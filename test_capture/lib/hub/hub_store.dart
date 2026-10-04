import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/json_store.dart';
import '../core/models.dart';

/// Holds everything the PC hub knows: items, media on disk, pairing data.
class HubStore extends ChangeNotifier {
  late final Directory root;
  late final JsonFile _itemsFile;
  late final JsonFile _settingsFile;

  final Map<String, CaptureItem> _items = {};
  String pin = '';
  String hubName = 'PC';

  /// token -> device name
  final Map<String, String> devices = {};
  int _failedPairs = 0;

  List<CaptureItem> get items => _items.values.toList();
  CaptureItem? item(String id) => _items[id];

  Directory get mediaRoot => Directory(_join(root.path, 'media'));
  Directory get reportsRoot => Directory(_join(root.path, 'Reports'));

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    root = Directory(_join(docs.path, 'TestCapture'));
    await root.create(recursive: true);
    await mediaRoot.create(recursive: true);
    _itemsFile = JsonFile(_join(root.path, 'items.json'));
    _settingsFile = JsonFile(_join(root.path, 'hub_settings.json'));

    final rawItems = await _itemsFile.read();
    if (rawItems is List) {
      for (final e in rawItems) {
        try {
          final it = CaptureItem.fromJson(Map<String, dynamic>.from(e as Map));
          _items[it.id] = it;
        } catch (_) {/* skip bad entry */}
      }
    }

    final s = await _settingsFile.read();
    if (s is Map) {
      pin = s['pin'] as String? ?? '';
      final d = s['devices'];
      if (d is Map) {
        d.forEach((k, v) => devices[k.toString()] = v.toString());
      }
    }
    hubName = Platform.localHostname;
    if (pin.isEmpty) newPin(save: false);
    await _saveSettings();
    notifyListeners();
  }

  // ---------- pairing ----------

  void newPin({bool save = true}) {
    final r = Random.secure();
    pin = List.generate(6, (_) => r.nextInt(10)).join();
    _failedPairs = 0;
    if (save) {
      _saveSettings();
      notifyListeners();
    }
  }

  /// Returns a token when the PIN is right, otherwise null.
  String? pair(String givenPin, String deviceName) {
    if (givenPin.trim() != pin) {
      _failedPairs++;
      if (_failedPairs >= 5) newPin(); // stop brute forcing
      return null;
    }
    final r = Random.secure();
    final token = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    devices[token] = deviceName.isEmpty ? 'Phone' : deviceName;
    newPin(); // a PIN works once
    return token;
  }

  bool isAuthorized(String? token) => token != null && devices.containsKey(token);

  void unpair(String token) {
    devices.remove(token);
    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() =>
      _settingsFile.write({'pin': pin, 'devices': devices});

  // ---------- items ----------

  Future<void> _saveItems() =>
      _itemsFile.write(_items.values.map((e) => e.toJson()).toList());

  /// Called when a phone sends item metadata. Keeps PC-side edits (status).
  Future<CaptureItem> upsertFromPhone(Map<String, dynamic> json, String deviceName) async {
    final incoming = CaptureItem.fromJson(json);
    if (incoming.id.isEmpty || incoming.id.length > 64 ||
        incoming.id.contains(RegExp(r'[^A-Za-z0-9_-]'))) {
      throw const FormatException('bad id');
    }
    final existing = _items[incoming.id];
    if (existing == null) {
      incoming
        ..status = ItemStatus.open
        ..complete = false
        ..deviceName = deviceName
        ..media = incoming.media
            .map((m) => MediaFile(
                fileName: safeFileName(m.fileName),
                kind: m.kind,
                size: m.size,
                uploaded: false))
            .toList();
      _items[incoming.id] = incoming;
    } else {
      existing
        ..title = incoming.title
        ..note = incoming.note
        ..priority = incoming.priority
        ..project = incoming.project
        ..tags = incoming.tags
        ..updatedAt = DateTime.now();
      for (final m in incoming.media) {
        final name = safeFileName(m.fileName);
        if (!existing.media.any((e) => e.fileName == name)) {
          existing.media.add(MediaFile(fileName: name, kind: m.kind, size: m.size));
        }
      }
    }
    await _saveItems();
    notifyListeners();
    return _items[incoming.id]!;
  }

  File mediaFile(String id, String fileName) => File(
      _join(_join(mediaRoot.path, safeFileName(id)), safeFileName(fileName)));

  Future<void> mediaReceived(String id, String fileName, int size) async {
    final it = _items[id];
    if (it == null) return;
    for (final m in it.media) {
      if (m.fileName == safeFileName(fileName)) {
        m.uploaded = true;
        m.size = size;
      }
    }
    await _saveItems();
    notifyListeners();
  }

  Future<void> markComplete(String id) async {
    final it = _items[id];
    if (it == null) return;
    it.complete = true;
    await _saveItems();
    notifyListeners();
  }

  Future<void> update(CaptureItem it) async {
    it.updatedAt = DateTime.now();
    _items[it.id] = it;
    await _saveItems();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _items.remove(id);
    final dir = Directory(_join(mediaRoot.path, safeFileName(id)));
    if (await dir.exists()) await dir.delete(recursive: true);
    await _saveItems();
    notifyListeners();
  }

  List<String> get projects {
    final s = <String>{};
    for (final it in _items.values) {
      if (it.project.trim().isNotEmpty) s.add(it.project.trim());
    }
    return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
