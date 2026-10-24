import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_service.dart';

class DupFile {
  const DupFile(this.path, this.modified);
  final String path;
  final DateTime modified;
}

class DupGroup {
  const DupGroup(this.size, this.files);

  final int size;
  final List<DupFile> files; // purani file pehle

  /// Ek copy rakh kar baaki delete karne se kitni jagah bachegi
  int get wasted => size * (files.length - 1);
}

class ScanResult {
  const ScanResult({
    required this.large,
    required this.groups,
    required this.scanned,
  });

  final List<FileItem> large;
  final List<DupGroup> groups;
  final int scanned;

  int get wastedTotal => groups.fold(0, (s, g) => s + g.wasted);
}

class ScanProgress {
  const ScanProgress(this.phase, this.done, this.total);
  final String phase;
  final int done;
  final int total; // 0 = unknown
}

/// Storage Optimizer: badi files + duplicate files (size -> partial hash -> full hash).
/// Poora scan alag isolate mein hota hai, UI smooth rehta hai.
class OptimizerService {
  OptimizerService(this._fs);

  final FileService _fs;
  Isolate? _isolate;
  ReceivePort? _port;
  Completer<ScanResult>? _completer;

  static const largeMinBytes = 50 * 1024 * 1024; // 50 MB
  static const dupMinBytes = 100 * 1024; // 100 KB se chhoti files ignore

  bool get scanning => _completer != null && !_completer!.isCompleted;

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
    final c = _completer;
    if (c != null && !c.isCompleted) c.completeError(FileOpException('cancelled'));
  }

  Future<ScanResult> scan({
    required bool showHidden,
    void Function(ScanProgress)? onProgress,
  }) async {
    if (scanning) cancel();
    final port = ReceivePort();
    final done = Completer<ScanResult>();
    _port = port;
    _completer = done;

    port.listen((dynamic m) {
      if (done.isCompleted || m is! List || m.isEmpty) return;
      switch (m[0]) {
        case 'progress':
          onProgress?.call(ScanProgress(m[1] as String, m[2] as int, m[3] as int));
        case 'done':
          final large = <FileItem>[
            for (final r in (m[1] as List))
              FileItem(
                path: r[0] as String,
                isDir: false,
                size: r[1] as int,
                modified: DateTime.fromMillisecondsSinceEpoch(r[2] as int),
              ),
          ];
          final groups = <DupGroup>[
            for (final g in (m[2] as List))
              DupGroup(g[0] as int, [
                for (final f in (g[1] as List))
                  DupFile(
                    f[0] as String,
                    DateTime.fromMillisecondsSinceEpoch(f[1] as int),
                  ),
              ]),
          ];
          done.complete(ScanResult(large: large, groups: groups, scanned: m[3] as int));
        case 'error':
          done.completeError(FileOpException(m[1] as String));
        default:
          // Isolate crash (onError) => scan atke nahi, error dikhao
          done.completeError(FileOpException('Scan poora nahi ho saka'));
      }
    });

    try {
      _isolate = await Isolate.spawn(
        _scanWorker,
        <Object>[
          port.sendPort,
          _fs.root.path,
          _fs.trashDir.path,
          showHidden,
          largeMinBytes,
          dupMinBytes,
          Platform.isWindows,
        ],
        onError: port.sendPort,
      );
      return await done.future;
    } finally {
      port.close();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _port = null;
    }
  }
}

// -----------------------------------------------------------------------------
// Background isolate
// -----------------------------------------------------------------------------

class _Entry {
  _Entry(this.path, this.size, this.modifiedMs);
  final String path;
  final int size;
  final int modifiedMs;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// limit = null => poori file; warna sirf shuru ke `limit` bytes
String? _hash(String path, {int? limit}) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final sink = _DigestSink();
    final conv = sha1.startChunkedConversion(sink);
    var remaining = limit ?? raf.lengthSync();
    while (remaining > 0) {
      final chunk = raf.readSync(min(1 << 20, remaining));
      if (chunk.isEmpty) break;
      conv.add(chunk);
      remaining -= chunk.length;
    }
    conv.close();
    return sink.value?.toString();
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

void _scanWorker(List<Object> a) {
  final send = a[0] as SendPort;
  final root = a[1] as String;
  final trash = a[2] as String;
  final hidden = a[3] as bool;
  final largeMin = a[4] as int;
  final dupMin = a[5] as int;
  final windows = a[6] as bool;

  try {
    // System / app-data folders ko kabhi scan nahi karte: yahan duplicate hata dena
    // apps ya system ko kharab kar sakta hai.
    bool skipDir(String name, String parent) {
      final lower = name.toLowerCase();
      if (lower == 'node_modules') return true;
      if (windows) {
        return lower == 'appdata' ||
            lower == r'$recycle.bin' ||
            lower == 'system volume information';
      }
      return lower == 'android' && p.equals(parent, root);
    }

    final all = <_Entry>[];
    final stack = <Directory>[Directory(root)];
    var seen = 0;

    while (stack.isNotEmpty) {
      final d = stack.removeLast();
      List<FileSystemEntity> kids;
      try {
        kids = d.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in kids) {
        final name = p.basename(e.path);
        if (p.equals(e.path, trash)) continue;
        if (!hidden && name.startsWith('.')) continue;
        if (e is Directory) {
          if (skipDir(name, d.path)) continue;
          stack.add(e);
        } else if (e is File) {
          try {
            final st = e.statSync();
            all.add(_Entry(e.path, st.size, st.modified.millisecondsSinceEpoch));
          } catch (_) {}
          seen++;
          if (seen % 400 == 0) send.send(<Object>['progress', 'Files gin rahe hain', seen, 0]);
        }
      }
    }

    // ---- badi files ----
    final large = all.where((e) => e.size >= largeMin).toList()
      ..sort((x, y) => y.size.compareTo(x.size));
    final largeOut = <List<Object>>[
      for (final e in large.take(200)) <Object>[e.path, e.size, e.modifiedMs],
    ];

    // ---- duplicates ----
    final bySize = <int, List<_Entry>>{};
    for (final e in all) {
      if (e.size >= dupMin) (bySize[e.size] ??= []).add(e);
    }
    final candidates = bySize.values.where((l) => l.length > 1).toList();
    final totalCandidates = candidates.fold<int>(0, (s, l) => s + l.length);
    var hashed = 0;
    final groupsOut = <List<Object>>[];

    for (final sameSize in candidates) {
      // 1) sirf shuru ke 64 KB ka hash (tez)
      final byPartial = <String, List<_Entry>>{};
      for (final e in sameSize) {
        final h = _hash(e.path, limit: 64 * 1024);
        hashed++;
        if (hashed % 10 == 0) {
          send.send(<Object>['progress', 'Duplicates check ho rahe hain', hashed, totalCandidates]);
        }
        if (h != null) (byPartial[h] ??= []).add(e);
      }
      // 2) bache hue par poora hash
      for (final part in byPartial.values) {
        if (part.length < 2) continue;
        final byFull = <String, List<_Entry>>{};
        for (final e in part) {
          final h = _hash(e.path);
          if (h != null) (byFull[h] ??= []).add(e);
        }
        for (final same in byFull.values) {
          if (same.length < 2) continue;
          same.sort((x, y) => x.modifiedMs.compareTo(y.modifiedMs));
          groupsOut.add(<Object>[
            same.first.size,
            [
              for (final e in same) <Object>[e.path, e.modifiedMs],
            ],
          ]);
        }
      }
    }
    // sabse zyada jagah barbad karne wale groups pehle
    groupsOut.sort((x, y) {
      final wx = (x[0] as int) * ((x[1] as List).length - 1);
      final wy = (y[0] as int) * ((y[1] as List).length - 1);
      return wy.compareTo(wx);
    });

    send.send(<Object>['done', largeOut, groupsOut, seen]);
  } catch (_) {
    send.send(<Object>['error', 'Scan poora nahi ho saka']);
  }
}
