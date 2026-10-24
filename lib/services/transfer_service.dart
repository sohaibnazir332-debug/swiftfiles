import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'file_service.dart';
import 'web_page.dart';

/// Wireless transfer: app ke andar chhota sa local web server chalta hai.
/// Dusra device (PC/mobile) browser mein address kholta hai, PIN daalta hai,
/// aur files upload/download kar leta hai. Data sirf Wi-Fi ke andar rehta hai.
class TransferService extends ChangeNotifier {
  TransferService(this._fs);

  final FileService _fs;
  HttpServer? _server;
  int _failedPins = 0;

  String? url;
  String pin = '';
  String? error;
  final List<String> received = [];

  bool get running => _server != null;
  Directory get dir => _fs.transferDir;

  Future<void> start() async {
    if (running) return;
    error = null;
    try {
      await dir.create(recursive: true);
      pin = (1000 + Random.secure().nextInt(9000)).toString();
      _failedPins = 0;
      try {
        _server = await io.serve(_handle, InternetAddress.anyIPv4, 8080);
      } on SocketException {
        // 8080 busy ho to koi bhi khali port le lo
        _server = await io.serve(_handle, InternetAddress.anyIPv4, 0);
      }
      final ip = await _localIp();
      url = 'http://${ip ?? 'localhost'}:${_server!.port}';
    } catch (e) {
      error = 'Server start nahi hua. Wi-Fi check karein.';
      _server = null;
      url = null;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    url = null;
    notifyListeners();
    await s?.close(force: true);
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  // ---------- request handling ----------

  Future<Response> _handle(Request req) async {
    final path = req.url.path;

    // Page load ke liye PIN nahi chahiye (page khud PIN maangta hai)
    if (req.method == 'GET' && path.isEmpty) {
      return Response.ok(
        kWebPage,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }

    if (_failedPins >= 10) {
      return Response(
        429,
        body: 'Bohat zyada galat PIN. Server band karke dobara chalayein.',
      );
    }
    final given = req.headers['x-pin'] ?? req.url.queryParameters['pin'];
    if (given != pin) {
      _failedPins++;
      return Response.forbidden('Wrong PIN');
    }
    _failedPins = 0;

    try {
      if (req.method == 'GET' && path == 'api/files') return await _list();
      if (req.method == 'GET' && path == 'download') return await _download(req);
      if (req.method == 'PUT' && path == 'upload') return await _upload(req);
    } catch (e) {
      return Response.internalServerError(body: 'Error: $e');
    }
    return Response.notFound('Not found');
  }

  Future<Response> _list() async {
    final out = <Map<String, Object>>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        out.add({'name': name, 'size': await e.length()});
      }
    }
    out.sort((a, b) =>
        (a['name']! as String).toLowerCase().compareTo((b['name']! as String).toLowerCase()));
    return Response.ok(
      jsonEncode(out),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _download(Request req) async {
    final name = p.basename(req.url.queryParameters['name'] ?? '');
    if (name.isEmpty || name == '.' || name == '..') {
      return Response.badRequest(body: 'Bad name');
    }
    final file = File(p.join(dir.path, name));
    if (!await file.exists()) return Response.notFound('File not found');
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${await file.length()}',
        'content-disposition':
            "attachment; filename*=UTF-8''${Uri.encodeComponent(name)}",
      },
    );
  }

  Future<Response> _upload(Request req) async {
    final name = p.basename(req.url.queryParameters['name'] ?? '');
    if (name.isEmpty || name == '.' || name == '..') {
      return Response.badRequest(body: 'Bad name');
    }
    await dir.create(recursive: true);
    final target = File(_fs.uniquePath(p.join(dir.path, name)));
    final sink = target.openWrite();
    try {
      await sink.addStream(req.read());
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await target.exists()) await target.delete();
      rethrow;
    }
    received.insert(0, p.basename(target.path));
    notifyListeners();
    return Response.ok('ok');
  }

  Future<String?> _localIp() async {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    String? fallback;
    for (final i in ifaces) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (ip.startsWith('169.254')) continue;
        if (ip.startsWith('192.168.')) return ip;
        fallback ??= ip;
      }
    }
    return fallback;
  }
}
