import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/protocol.dart';
import 'hub_store.dart';

/// HTTP API + UDP discovery responder that runs inside the PC app.
///
/// API (all JSON unless noted):
///   GET  /api/ping                          -> {app, name}            (no auth)
///   POST /api/pair       {pin, deviceName}  -> {token, name}          (no auth)
///   GET  /api/auth-check                    -> 200 / 401
///   POST /api/items      item json          -> {missing: [fileNames]}
///   PUT  /api/items/{id}/media/{fileName}   raw file bytes
///   POST /api/items/{id}/complete
class HubServer {
  HubServer(this.store);
  final HubStore store;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  String? error;

  bool get running => _http != null;

  Future<void> start() async {
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, Protocol.httpPort, shared: true);
      _http!.listen(_handle, onError: (_) {});
    } catch (e) {
      error = 'Could not open port ${Protocol.httpPort}: $e';
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, Protocol.discoveryPort,
          reuseAddress: true);
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udp!.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true).trim();
        if (msg == Protocol.discoverMessage) {
          final reply =
              '${Protocol.discoverReplyPrefix}|${store.hubName}|${Protocol.httpPort}';
          _udp!.send(utf8.encode(reply), dg.address, dg.port);
        }
      });
    } catch (e) {
      error ??= 'Discovery unavailable (port ${Protocol.discoveryPort}): $e';
    }
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _udp?.close();
    _http = null;
    _udp = null;
  }

  static Future<List<String>> localAddresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final out = <String>[];
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.address.startsWith('169.254')) out.add(a.address);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      if (seg.isEmpty || seg.first != 'api') return _send(res, 404, {'error': 'not found'});
      final path = seg.skip(1).toList();
      final method = req.method.toUpperCase();

      // ---- open endpoints
      if (method == 'GET' && path.length == 1 && path[0] == 'ping') {
        return _send(res, 200, {'app': 'testcapture', 'name': store.hubName});
      }
      if (method == 'POST' && path.length == 1 && path[0] == 'pair') {
        final body = await _readJson(req);
        final token = store.pair('${body['pin'] ?? ''}', '${body['deviceName'] ?? ''}');
        if (token == null) return _send(res, 403, {'error': 'Wrong PIN'});
        return _send(res, 200, {'token': token, 'name': store.hubName});
      }

      // ---- authenticated endpoints
      final token = req.headers.value(Protocol.tokenHeader);
      if (!store.isAuthorized(token)) return _send(res, 401, {'error': 'Not paired'});
      final deviceName = store.devices[token] ?? 'Phone';

      if (method == 'GET' && path.length == 1 && path[0] == 'auth-check') {
        return _send(res, 200, {'ok': true, 'name': store.hubName});
      }

      if (method == 'POST' && path.length == 1 && path[0] == 'items') {
        final body = await _readJson(req);
        final item = await store.upsertFromPhone(body, deviceName);
        final missing = <String>[];
        for (final m in item.media) {
          if (!m.uploaded || !await store.mediaFile(item.id, m.fileName).exists()) {
            missing.add(m.fileName);
          }
        }
        return _send(res, 200, {'missing': missing});
      }

      if (path.length >= 3 && path[0] == 'items') {
        final id = path[1];
        final item = store.item(id);
        if (item == null) return _send(res, 404, {'error': 'unknown item'});

        if (method == 'PUT' && path.length == 4 && path[2] == 'media') {
          final name = path[3];
          if (!item.media.any((m) => m.fileName == name)) {
            return _send(res, 400, {'error': 'media not declared'});
          }
          final target = store.mediaFile(id, name);
          await target.parent.create(recursive: true);
          final part = File('${target.path}.part');
          final sink = part.openWrite();
          var received = 0;
          try {
            await for (final chunk in req) {
              received += chunk.length;
              sink.add(chunk);
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          final expected = req.contentLength;
          if (expected >= 0 && expected != received) {
            await part.delete();
            return _send(res, 400, {'error': 'incomplete upload'});
          }
          await part.rename(target.path);
          await store.mediaReceived(id, name, received);
          return _send(res, 200, {'ok': true, 'size': received});
        }

        if (method == 'POST' && path.length == 3 && path[2] == 'complete') {
          await store.markComplete(id);
          return _send(res, 200, {'ok': true});
        }
      }

      return _send(res, 404, {'error': 'not found'});
    } catch (e) {
      try {
        await _send(res, 500, {'error': e.toString()});
      } catch (_) {}
    }
  }

  static Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) return {};
    final v = jsonDecode(text);
    if (v is Map) return Map<String, dynamic>.from(v);
    throw const FormatException('expected a JSON object');
  }

  static Future<void> _send(HttpResponse res, int code, Object body) async {
    res.statusCode = code;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }
}
