import 'dart:convert';
import 'dart:io';

/// Tiny crash-safe JSON file store: writes to a temp file, then renames.
class JsonFile {
  JsonFile(this.path);
  final String path;

  Future<void> _chain = Future.value();

  Future<dynamic> read() async {
    for (final p in [path, '$path.tmp']) {
      final f = File(p);
      if (!await f.exists()) continue;
      try {
        return jsonDecode(await f.readAsString());
      } catch (_) {
        // Corrupt file: keep a copy for recovery and try the next candidate.
        await f.copy('$p.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    return null;
  }

  /// Writes are queued so two writes never touch the file at the same time.
  Future<void> write(dynamic data) {
    final text = const JsonEncoder.withIndent(' ').convert(data);
    final next = _chain.then((_) => _write(text));
    _chain = next.catchError((_) {});
    return next;
  }

  Future<void> _write(String text) async {
    final tmp = File('$path.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(text, flush: true);
    // rename() replaces an existing target file on all platforms.
    await tmp.rename(path);
  }
}
