import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/file_item.dart';

class FileOpException implements Exception {
  FileOpException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TrashRecord {
  const TrashRecord(this.original, this.trashed);
  final String original;
  final String trashed;
}

class BatchOptions {
  const BatchOptions({
    this.prefix = '',
    this.suffix = '',
    this.numbering = false,
  });
  final String prefix;
  final String suffix;
  final bool numbering;
}

class BatchResult {
  const BatchResult(this.ok, this.failed);
  final int ok;
  final int failed;
}

class QuickLocation {
  const QuickLocation(this.label, this.path);
  final String label;
  final String path;
}

/// Saari file-system ka kaam yahin hota hai (UI ko yahan se koi lena dena nahi).
class FileService {
  // ---------- Locations ----------

  Directory get root {
    if (Platform.isAndroid) return Directory('/storage/emulated/0');
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory(home);
  }

  Directory get trashDir => Directory(p.join(root.path, '.swift_trash'));

  /// Wireless transfer isi folder mein files receive/share karta hai.
  Directory get transferDir => Platform.isAndroid
      ? Directory('/storage/emulated/0/Download/SwiftFiles')
      : Directory(p.join(root.path, 'Downloads', 'SwiftFiles'));

  List<QuickLocation> quickLocations() {
    final r = root.path;
    final names = Platform.isAndroid
        ? ['Download', 'DCIM', 'Pictures', 'Movies', 'Music', 'Documents']
        : ['Desktop', 'Downloads', 'Documents', 'Pictures', 'Videos', 'Music'];
    final out = <QuickLocation>[QuickLocation('Home', r)];
    for (final n in names) {
      final path = p.join(r, n);
      if (Directory(path).existsSync()) out.add(QuickLocation(n, path));
    }
    return out;
  }

  // ---------- Permission ----------

  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    final s = await Permission.manageExternalStorage.request();
    if (s.isGranted) return true;
    final s2 = await Permission.storage.request();
    return s2.isGranted;
  }

  // ---------- Reading ----------

  Future<FileItem> _toItem(FileSystemEntity e, {bool showHidden = false}) async {
    final s = await e.stat();
    final isDir = s.type == FileSystemEntityType.directory;
    return FileItem(
      path: e.path,
      isDir: isDir,
      size: isDir ? 0 : s.size,
      modified: s.modified,
      childCount: isDir ? await _countDir(e.path, showHidden) : -1,
    );
  }

  /// Folder ke andar jhanke bina dikhne wali cheezein ginta hai (hidden tabhi jab ON ho).
  /// 1000 par ruk jata hai. Na khulne wala folder -1 (pata nahi) deta hai, "khali" nahi.
  Future<int> _countDir(String path, bool showHidden) async {
    var n = 0;
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        if (showHidden || !p.basename(e.path).startsWith('.')) {
          if (++n > 999) break;
        }
      }
      return n;
    } catch (_) {
      return -1;
    }
  }

  /// Favorites: diye gaye paths ke items (jo ab maujood nahi unhe chhod deta hai)
  Future<List<FileItem>> statPaths(Iterable<String> paths) async {
    final out = <FileItem>[];
    for (final path in paths) {
      try {
        if (await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        out.add(await _toItem(File(path), showHidden: true));
      } catch (_) {}
    }
    return out;
  }

  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async {
    final out = <FileItem>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      if (!showHidden && p.basename(e.path).startsWith('.')) continue;
      try {
        out.add(await _toItem(e, showHidden: showHidden));
      } catch (_) {
        // koi ek file na khule to baaki list rukni nahi chahiye
      }
    }
    return out;
  }

  /// Poore storage mein name + category se dhundta hai (hidden folders skip).
  Future<List<FileItem>> search(
    String rootPath, {
    String query = '',
    FileCategory category = FileCategory.all,
    int limit = 1500,
    bool showHidden = false,
  }) async {
    final q = query.trim().toLowerCase();
    final out = <FileItem>[];
    final stream = Directory(rootPath)
        .list(recursive: true, followLinks: false)
        .handleError((_) {});
    await for (final e in stream) {
      // Trash ki files search mein kabhi nahi aati
      if (p.equals(e.path, trashDir.path) || p.isWithin(trashDir.path, e.path)) {
        continue;
      }
      if (!showHidden && e.path.contains('${p.separator}.')) continue;
      final name = p.basename(e.path).toLowerCase();
      if (e is Directory) {
        if (category == FileCategory.all && q.isNotEmpty && name.contains(q)) {
          out.add(await _toItem(e, showHidden: showHidden));
        }
        continue;
      }
      if (e is! File) continue;
      if (q.isNotEmpty && !name.contains(q)) continue;
      if (category != FileCategory.all) {
        final ext = p.extension(name).replaceFirst('.', '');
        if (categoryOfExt(ext) != category) continue;
      }
      try {
        out.add(await _toItem(e));
      } catch (_) {}
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---------- Name helpers ----------

  static String? validateName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Naam khali nahi ho sakta';
    if (n.length > 200) return 'Naam bohat lamba hai';
    if (n == '.' || n == '..') return 'Ye naam durust nahi';
    if (RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(n)) {
      return 'Ye characters allowed nahi: < > : " / \\ | ? *';
    }
    if (Platform.isWindows && (n.endsWith('.') || n.endsWith(' '))) {
      return 'Naam dot ya space par khatam nahi ho sakta';
    }
    return null;
  }

  /// Batch rename ka naya naam: prefix + purana naam + suffix (+ _01) + extension
  static String buildBatchName(
    String original,
    BatchOptions o,
    int index, {
    bool isDir = false,
  }) {
    final ext = isDir ? '' : p.extension(original);
    final base = isDir ? original : p.basenameWithoutExtension(original);
    final n =
        o.numbering ? '_${(index + 1).toString().padLeft(2, '0')}' : '';
    return '${o.prefix}$base${o.suffix}$n$ext';
  }

  String uniquePath(String path) {
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return path;
    }
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    for (var i = 1; i < 10000; i++) {
      final c = p.join(dir, '$base ($i)$ext');
      if (FileSystemEntity.typeSync(c) == FileSystemEntityType.notFound) {
        return c;
      }
    }
    return p.join(dir, '$base (${DateTime.now().millisecondsSinceEpoch})$ext');
  }

  // ---------- Actions ----------

  Future<String> rename(String path, String newName) async {
    final name = newName.trim();
    final err = validateName(name);
    if (err != null) throw FileOpException(err);

    final target = p.join(p.dirname(path), name);
    if (target == path) return path;

    final onlyCaseChange =
        Platform.isWindows && target.toLowerCase() == path.toLowerCase();
    if (!onlyCaseChange &&
        await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      throw FileOpException('"$name" pehle se maujood hai');
    }
    await _move(path, target);
    return target;
  }

  Future<BatchResult> batchRename(
    List<FileItem> items,
    BatchOptions o,
  ) async {
    var ok = 0, failed = 0;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final newName = buildBatchName(it.name, o, i, isDir: it.isDir);
      if (newName == it.name) continue;
      try {
        await rename(it.path, newName);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    return BatchResult(ok, failed);
  }

  Future<BatchResult> moveTo(List<String> paths, String destDir) async {
    var ok = 0, failed = 0;
    for (final src in paths) {
      try {
        if (p.equals(p.dirname(src), destDir)) continue; // pehle se yahin hai
        if (p.equals(src, destDir) || p.isWithin(src, destDir)) {
          failed++; // folder ko apne andar nahi daal sakte
          continue;
        }
        await _move(src, uniquePath(p.join(destDir, p.basename(src))));
        ok++;
      } catch (_) {
        failed++;
      }
    }
    return BatchResult(ok, failed);
  }

  Future<void> createFolder(String parent, String name) async {
    final n = name.trim();
    final err = validateName(n);
    if (err != null) throw FileOpException(err);
    final path = p.join(parent, n);
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw FileOpException('"$n" pehle se maujood hai');
    }
    await Directory(path).create();
  }

  // ---------- Trash (safe delete with Undo) ----------

  Future<TrashRecord> trash(String path) async {
    await trashDir.create(recursive: true);
    final dest = p.join(
      trashDir.path,
      '${DateTime.now().microsecondsSinceEpoch}_${p.basename(path)}',
    );
    await _move(path, dest);
    return TrashRecord(path, dest);
  }

  Future<void> restore(TrashRecord r) async {
    await _move(r.trashed, uniquePath(r.original));
  }

  /// Trash mein padi ek item ko hamesha ke liye delete karta hai
  /// (ZIP auto-delete mein Undo ka waqt khatam hone par jagah foran khali hoti hai).
  Future<void> purge(TrashRecord r) async {
    final type = await FileSystemEntity.type(r.trashed);
    if (type == FileSystemEntityType.directory) {
      await Directory(r.trashed).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(r.trashed).delete();
    }
  }

  Future<int> trashSize() async {
    var total = 0;
    if (!await trashDir.exists()) return 0;
    await for (final e in trashDir
        .list(recursive: true, followLinks: false)
        .handleError((_) {})) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Trash khali karta hai, aur kitni jagah khali hui wo wapas deta hai.
  Future<int> emptyTrash() async {
    final size = await trashSize();
    if (await trashDir.exists()) await trashDir.delete(recursive: true);
    return size;
  }

  // ---------- internal ----------

  Future<void> _move(String src, String dest) async {
    final isDir =
        await FileSystemEntity.type(src) == FileSystemEntityType.directory;
    try {
      if (isDir) {
        await Directory(src).rename(dest);
      } else {
        await File(src).rename(dest);
      }
    } on FileSystemException {
      if (isDir) rethrow;
      await File(src).copy(dest);
      await File(src).delete();
    }
  }
}
