import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/json_store.dart';
import '../core/models.dart';
import '../core/protocol.dart';

enum HubConnection { notPaired, checking, online, offline }

/// Phone side: local library of captures + upload queue to the PC hub.
class PhoneStore extends ChangeNotifier {
  late final Directory root;
  late final JsonFile _itemsFile;
  late final JsonFile _settingsFile;

  final List<CaptureItem> items = [];
  HubInfo? hub;
  String? token;
  String deviceName = 'Android phone';
  List<String> recentProjects = [];
  String lastProject = '';

  HubConnection connection = HubConnection.notPaired;

  /// Upload progress of the item currently syncing (0..1).
  String? syncingId;
  double syncProgress = 0;

  bool _syncRunning = false;
  Timer? _timer;

  Directory get mediaRoot => Directory('${root.path}/media');
  File mediaFile(String id, String name) => File('${mediaRoot.path}/$id/$name');

  bool get isPaired => hub != null && token != null;
  int get pendingCount => items.where((i) => i.syncState != SyncState.synced).length;

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    root = Directory('${docs.path}/testcapture');
    await mediaRoot.create(recursive: true);
    _itemsFile = JsonFile('${root.path}/items.json');
    _settingsFile = JsonFile('${root.path}/settings.json');

    final raw = await _itemsFile.read();
    if (raw is List) {
      for (final e in raw) {
        try {
          final it = CaptureItem.fromJson(Map<String, dynamic>.from(e as Map));
          if (it.syncState == SyncState.syncing) it.syncState = SyncState.pending;
          items.add(it);
        } catch (_) {}
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final s = await _settingsFile.read();
    if (s is Map) {
      if (s['hub'] is Map) hub = HubInfo.fromJson(Map<String, dynamic>.from(s['hub'] as Map));
      token = s['token'] as String?;
      deviceName = s['deviceName'] as String? ?? deviceName;
      lastProject = s['lastProject'] as String? ?? '';
      recentProjects =
          (s['recentProjects'] as List?)?.map((e) => e.toString()).toList() ?? [];
    }
    connection = isPaired ? HubConnection.checking : HubConnection.notPaired;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (pendingCount > 0 || connection != HubConnection.online) syncNow();
    });
    unawaited(syncNow());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _saveItems() => _itemsFile.write(items.map((e) => e.toJson()).toList());
  Future<void> _saveSettings() => _settingsFile.write({
        'hub': hub?.toJson(),
        'token': token,
        'deviceName': deviceName,
        'lastProject': lastProject,
        'recentProjects': recentProjects,
      });

  Future<void> setDeviceName(String name) async {
    deviceName = name.trim().isEmpty ? 'Android phone' : name.trim();
    await _saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------ captures

  Future<CaptureItem> addCapture({
    required String title,
    required String note,
    required Priority priority,
    required String project,
    required List<String> tags,
    required List<String> sourcePaths,
  }) async {
    final id = newId();
    final dir = Directory('${mediaRoot.path}/$id');
    await dir.create(recursive: true);
    final media = <MediaFile>[];
    final used = <String>{};
    for (var i = 0; i < sourcePaths.length; i++) {
      final src = File(sourcePaths[i]);
      var name = safeFileName(src.uri.pathSegments.isEmpty ? 'file' : src.uri.pathSegments.last);
      // Prefix with index to keep order and avoid name clashes.
      name = '${(i + 1).toString().padLeft(2, '0')}_$name';
      while (used.contains(name)) {
        name = '0$name';
      }
      used.add(name);
      final dest = await src.copy('${dir.path}/$name');
      media.add(MediaFile(fileName: name, kind: mediaKindFor(name), size: await dest.length()));
    }
    final it = CaptureItem(
      id: id,
      title: title.trim().isEmpty ? _defaultTitle() : title.trim(),
      note: note,
      priority: priority,
      project: project.trim(),
      tags: tags,
      media: media,
      deviceName: deviceName,
    );
    items.insert(0, it);
    if (it.project.isNotEmpty) {
      lastProject = it.project;
      recentProjects.remove(it.project);
      recentProjects.insert(0, it.project);
      if (recentProjects.length > 8) recentProjects = recentProjects.sublist(0, 8);
    }
    await _saveItems();
    await _saveSettings();
    notifyListeners();
    unawaited(syncNow());
    return it;
  }

  String _defaultTitle() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Capture ${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> deleteLocal(CaptureItem it) async {
    items.removeWhere((e) => e.id == it.id);
    final dir = Directory('${mediaRoot.path}/${it.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    await _saveItems();
    notifyListeners();
  }

  /// Frees phone storage: removes local copies of items already on the PC.
  Future<int> clearSynced() async {
    final done = items.where((i) => i.syncState == SyncState.synced).toList();
    for (final it in done) {
      final dir = Directory('${mediaRoot.path}/${it.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    items.removeWhere((i) => i.syncState == SyncState.synced);
    await _saveItems();
    notifyListeners();
    return done.length;
  }

  void retry(CaptureItem it) {
    it.syncState = SyncState.pending;
    it.syncError = null;
    notifyListeners();
    syncNow();
  }

  // ------------------------------------------------------------ discovery & pairing

  /// Broadcasts on the Wi-Fi network and collects PC hubs that answer.
  static Future<List<HubInfo>> discover({Duration wait = const Duration(seconds: 2)}) async {
    final found = <String, HubInfo>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final s = sock;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        final parts = msg.split('|');
        if (parts.length >= 3 && parts[0] == Protocol.discoverReplyPrefix) {
          final host = dg.address.address;
          found[host] = HubInfo(
              name: parts[1], host: host, port: int.tryParse(parts[2]) ?? Protocol.httpPort);
        }
      });
      final data = utf8.encode(Protocol.discoverMessage);
      for (var i = 0; i < 3; i++) {
        s.send(data, InternetAddress('255.255.255.255'), Protocol.discoveryPort);
        await Future.delayed(Duration(milliseconds: wait.inMilliseconds ~/ 3));
      }
    } catch (_) {
      // Ignore: return whatever we found.
    } finally {
      sock?.close();
    }
    return found.values.toList();
  }

  /// Checks a manually typed address. Returns the hub if it answers.
  static Future<HubInfo?> probe(String input) async {
    var text = input.trim();
    if (text.isEmpty) return null;
    text = text.replaceFirst(RegExp(r'^https?://'), '');
    final parts = text.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? Protocol.httpPort : Protocol.httpPort;
    try {
      final res = await _request('GET', 'http://$host:$port/api/ping', null,
          timeout: const Duration(seconds: 4));
      if (res.status == 200 && res.json['app'] == 'testcapture') {
        return HubInfo(name: '${res.json['name'] ?? host}', host: host, port: port);
      }
    } catch (_) {}
    return null;
  }

  /// Returns null on success, or an error message.
  Future<String?> pair(HubInfo h, String pin) async {
    try {
      final res = await _request('POST', '${h.baseUrl}/api/pair',
          {'pin': pin.replaceAll(' ', ''), 'deviceName': deviceName},
          timeout: const Duration(seconds: 6));
      if (res.status == 200) {
        hub = HubInfo(name: '${res.json['name'] ?? h.name}', host: h.host, port: h.port);
        token = res.json['token'] as String?;
        connection = HubConnection.online;
        await _saveSettings();
        notifyListeners();
        // Items that failed before pairing get another chance.
        for (final it in items) {
          if (it.syncState == SyncState.failed) it.syncState = SyncState.pending;
        }
        unawaited(syncNow());
        return null;
      }
      return '${res.json['error'] ?? 'Pairing failed (${res.status})'}';
    } catch (e) {
      return 'Could not reach ${h.name}. Is the PC app open and on the same Wi-Fi?';
    }
  }

  Future<void> unpair() async {
    hub = null;
    token = null;
    connection = HubConnection.notPaired;
    await _saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------ sync

  Map<String, String> get _auth => {Protocol.tokenHeader: token ?? ''};

  Future<void> syncNow() async {
    if (_syncRunning || !isPaired) return;
    _syncRunning = true;
    try {
      // Are we reachable at all?
      try {
        final res = await _request('GET', '${hub!.baseUrl}/api/auth-check', null,
            headers: _auth, timeout: const Duration(seconds: 4));
        if (res.status == 401) {
          // PC forgot us (unpaired there).
          token = null;
          connection = HubConnection.notPaired;
          await _saveSettings();
          notifyListeners();
          return;
        }
        connection = res.status == 200 ? HubConnection.online : HubConnection.offline;
      } catch (_) {
        connection = HubConnection.offline;
        notifyListeners();
        return;
      }
      notifyListeners();

      // Oldest first so the PC receives captures in order.
      final queue = items
          .where((i) => i.syncState == SyncState.pending || i.syncState == SyncState.failed)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final it in queue) {
        if (!isPaired) break;
        await _syncItem(it);
      }
    } finally {
      _syncRunning = false;
      syncingId = null;
      notifyListeners();
    }
  }

  Future<void> _syncItem(CaptureItem it) async {
    syncingId = it.id;
    syncProgress = 0;
    it.syncState = SyncState.syncing;
    it.syncError = null;
    notifyListeners();
    try {
      final res = await _request('POST', '${hub!.baseUrl}/api/items', it.toWireJson(),
          headers: _auth, timeout: const Duration(seconds: 15));
      if (res.status != 200) throw HttpException('PC answered ${res.status}: ${res.json['error']}');
      final missing = ((res.json['missing'] as List?) ?? []).map((e) => e.toString()).toSet();

      final toSend = it.media.where((m) => missing.contains(m.fileName)).toList();
      final total = toSend.fold<int>(0, (s, m) => s + m.size);
      var sentBefore = 0;
      for (final m in toSend) {
        await _upload(it, m, (sent) {
          syncProgress = total == 0 ? 1 : (sentBefore + sent) / total;
          notifyListeners();
        });
        sentBefore += m.size;
        m.uploaded = true;
      }
      for (final m in it.media) {
        if (!missing.contains(m.fileName)) m.uploaded = true;
      }

      final done = await _request('POST', '${hub!.baseUrl}/api/items/${it.id}/complete', null,
          headers: _auth, timeout: const Duration(seconds: 10));
      if (done.status != 200) throw HttpException('PC answered ${done.status}');
      it.syncState = SyncState.synced;
    } catch (e) {
      it.syncState = SyncState.failed;
      it.syncError = e is HttpException ? e.message : 'Connection lost – will retry';
      connection = HubConnection.offline;
    }
    await _saveItems();
    notifyListeners();
  }

  Future<void> _upload(CaptureItem it, MediaFile m, void Function(int sent) onProgress) async {
    final file = mediaFile(it.id, m.fileName);
    final length = await file.length();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
          '${hub!.baseUrl}/api/items/${Uri.encodeComponent(it.id)}/media/${Uri.encodeComponent(m.fileName)}');
      final req = await client.putUrl(uri);
      req.headers.set(Protocol.tokenHeader, token ?? '');
      req.headers.contentType = ContentType.binary;
      req.contentLength = length;
      var sent = 0;
      var lastReport = DateTime.now();
      await req.addStream(file.openRead().map((chunk) {
        sent += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 150) {
          lastReport = now;
          onProgress(sent);
        }
        return chunk;
      }));
      final res = await req.close().timeout(const Duration(minutes: 2));
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) {
        throw HttpException('Upload failed (${res.statusCode}): $body');
      }
      onProgress(length);
    } finally {
      client.close(force: true);
    }
  }
}

class _Res {
  _Res(this.status, this.json);
  final int status;
  final Map<String, dynamic> json;
}

Future<_Res> _request(String method, String url, Map<String, dynamic>? body,
    {Map<String, String> headers = const {}, Duration timeout = const Duration(seconds: 10)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.openUrl(method, Uri.parse(url)).timeout(timeout);
    headers.forEach(req.headers.set);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(timeout);
    final text = await utf8.decoder.bind(res).join().timeout(timeout);
    Map<String, dynamic> json = {};
    try {
      final v = jsonDecode(text);
      if (v is Map) json = Map<String, dynamic>.from(v);
    } catch (_) {}
    return _Res(res.statusCode, json);
  } finally {
    client.close(force: true);
  }
}
