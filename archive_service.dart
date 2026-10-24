import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'file_service.dart';

class ExtractResult {
  const ExtractResult({
    required this.dest,
    required this.extracted,
    required this.failed,
    required this.bytes,
  });

  /// Naya folder jahan files extract hui
  final String dest;
  final int extracted;
  final int failed;
  final int bytes;
}

/// ZIP / TAR / TAR.GZ / TGZ extract karta hai.
/// Kaam alag isolate mein hota hai, is liye UI kabhi atakta nahi,
/// aur badi files bhi smoothly extract hoti hain.
class ArchiveService {
  ArchiveService(this._fs);

  final FileService _fs;

  static const supportedHint = 'ZIP, TAR, TAR.GZ, TGZ';

  static bool supports(String fileName) {
    final n = fileName.toLowerCase();
    return n.endsWith('.zip') ||
        n.endsWith('.tar') ||
        n.endsWith('.tar.gz') ||
        n.endsWith('.tgz');
  }

  /// "photos.tar.gz" -> "photos"
  static String baseName(String fileName) {
    final lower = fileName.toLowerCase();
    for (final e in const ['.tar.gz', '.tgz', '.tar', '.zip']) {
      if (lower.endsWith(e)) return fileName.substring(0, fileName.length - e.length);
    }
    return p.basenameWithoutExtension(fileName);
  }

  /// Archive ko uske bagal mein naye folder (archive ke naam se) mein extract karta hai.
  Future<ExtractResult> extract(
    String archivePath, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (!supports(archivePath)) {
      throw FileOpException('Ye archive format support nahi ($supportedHint chalte hain)');
    }
    final parent = p.dirname(archivePath);
    var name = baseName(p.basename(archivePath)).trim();
    if (name.isEmpty) name = 'extracted';
    final dest = _fs.uniquePath(p.join(parent, name));

    final port = ReceivePort();
    final done = Completer<ExtractResult>();
    Isolate? isolate;

    port.listen((dynamic m) {
      if (done.isCompleted) return;
      if (m is List && m.isNotEmpty && m[0] == 'progress') {
        onProgress?.call(m[1] as int, m[2] as int);
      } else if (m is List && m.isNotEmpty && m[0] == 'done') {
        done.complete(ExtractResult(
          dest: dest,
          extracted: m[1] as int,
          failed: m[2] as int,
          bytes: m[3] as int,
        ));
      } else if (m is List && m.isNotEmpty && m[0] == 'error') {
        done.completeError(FileOpException(m[1] as String));
      } else if (m is List) {
        // Isolate ka onError: [error, stackTrace]
        done.completeError(FileOpException('Archive kharab ya adhoora hai'));
      }
    });

    try {
      isolate = await Isolate.spawn(
        _worker,
        <Object>[port.sendPort, archivePath, dest],
        onError: port.sendPort,
      );
      final r = await done.future;
      return r;
    } catch (e) {
      // aadha bana folder saaf kar do
      try {
        final d = Directory(dest);
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
      if (e is FileOpException) rethrow;
      throw FileOpException('Extract nahi ho saka');
    } finally {
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

// -----------------------------------------------------------------------------
// Background isolate
// -----------------------------------------------------------------------------

Future<void> _worker(List<Object> args) async {
  final send = args[0] as SendPort;
  final src = args[1] as String;
  final dest = args[2] as String;

  InputFileStream? input;
  try {
    input = InputFileStream(src);
    final lower = src.toLowerCase();
    final Archive archive;
    if (lower.endsWith('.zip')) {
      archive = ZipDecoder().decodeBuffer(input);
    } else if (lower.endsWith('.tar')) {
      archive = TarDecoder().decodeBuffer(input);
    } else {
      // .tar.gz / .tgz
      final tarBytes = GZipDecoder().decodeBuffer(input);
      archive = TarDecoder().decodeBytes(tarBytes);
    }

    await Directory(dest).create(recursive: true);

    final entries = archive.files.toList();
    final total = entries.length;
    var ok = 0, failed = 0, bytes = 0;

    for (var i = 0; i < total; i++) {
      final f = entries[i];
      try {
        // Zip-slip se bachav: archive ke andar "../" wala path bahar nahi ja sakta
        final rel = f.name.replaceAll('\\', '/');
        final target = p.normalize(p.join(dest, rel));
        if (!p.isWithin(dest, target) && !p.equals(dest, target)) {
          failed++;
          continue;
        }
        if (f.isFile) {
          await Directory(p.dirname(target)).create(recursive: true);
          final out = OutputFileStream(target);
          try {
            f.writeContent(out);
          } finally {
            await out.close();
          }
          bytes += f.size;
          ok++;
        } else {
          await Directory(target).create(recursive: true);
        }
      } catch (_) {
        failed++; // ek file na bane to baaki extract hoti rahein
      }
      if (i % 4 == 0 || i == total - 1) {
        send.send(<Object>['progress', i + 1, total]);
      }
    }

    if (ok == 0 && failed > 0) {
      send.send(<Object>[
        'error',
        'Koi file extract nahi hui (archive password-protected ho sakta hai)',
      ]);
    } else {
      send.send(<Object>['done', ok, failed, bytes]);
    }
  } catch (_) {
    send.send(<Object>['error', 'Archive kharab ya adhoora hai']);
  } finally {
    try {
      await input?.close();
    } catch (_) {}
  }
}
