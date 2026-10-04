import 'dart:io';

import '../core/models.dart';
import 'hub_store.dart';

/// Opens a file or folder with the system's default app.
Future<void> openWithSystem(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

/// Opens the file manager with the file selected.
Future<void> revealInFolder(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    await Process.run('xdg-open', [File(path).parent.path]);
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// Builds a self-contained report folder (index.html + report.md + media)
/// and returns the path of index.html.
Future<String> exportReport(HubStore store, List<CaptureItem> items, String title) async {
  final now = DateTime.now();
  final folderName =
      'report-${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
  final sep = Platform.pathSeparator;
  final dir = Directory('${store.reportsRoot.path}$sep$folderName');
  final mediaDir = Directory('${dir.path}${sep}media');
  await mediaDir.create(recursive: true);

  final sorted = [...items]
    ..sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
    });

  final html = StringBuffer()
    ..writeln('<!doctype html><html><head><meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>${_esc(title)}</title><style>')
    ..writeln('body{font-family:Segoe UI,Roboto,Arial,sans-serif;max-width:980px;margin:32px auto;padding:0 16px;color:#1d1d29}')
    ..writeln('h1{margin-bottom:4px}.meta{color:#666;margin-bottom:24px}')
    ..writeln('.item{border:1px solid #ddd;border-radius:12px;padding:16px 20px;margin:18px 0;page-break-inside:avoid}')
    ..writeln('.pill{display:inline-block;padding:2px 10px;border-radius:20px;font-size:12px;font-weight:600;color:#fff;margin-right:6px}')
    ..writeln('.tag{display:inline-block;padding:2px 8px;border-radius:20px;font-size:12px;background:#eee;margin-right:6px}')
    ..writeln('.note{white-space:pre-wrap;margin:10px 0}')
    ..writeln('.media img{max-width:100%;max-height:520px;border-radius:8px;border:1px solid #ddd;margin:6px 6px 0 0}')
    ..writeln('.media a.video{display:inline-block;padding:10px 14px;border:1px solid #ccc;border-radius:8px;margin:6px 6px 0 0;text-decoration:none}')
    ..writeln('table{border-collapse:collapse;margin-bottom:12px}td{padding:2px 12px 2px 0}')
    ..writeln('</style></head><body>')
    ..writeln('<h1>${_esc(title)}</h1>')
    ..writeln('<div class="meta">Generated ${_stamp(now)} · ${sorted.length} item(s)</div>');

  final md = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('Generated ${_stamp(now)} · ${sorted.length} item(s)')
    ..writeln();

  var n = 0;
  for (final it in sorted) {
    n++;
    final color = switch (it.priority) {
      Priority.low => '#4CAF50',
      Priority.medium => '#2196F3',
      Priority.high => '#FF9800',
      Priority.critical => '#E53935',
    };
    html
      ..writeln('<div class="item">')
      ..writeln('<h2>$n. ${_esc(it.title)}</h2>')
      ..writeln('<span class="pill" style="background:$color">${it.priority.label}</span>'
          '<span class="tag">${it.status.label}</span>'
          '${it.project.isNotEmpty ? '<span class="tag">${_esc(it.project)}</span>' : ''}'
          '${it.tags.map((t) => '<span class="tag">#${_esc(t)}</span>').join()}')
      ..writeln('<table><tr><td>Captured</td><td>${_stamp(it.createdAt)}</td></tr>'
          '<tr><td>Device</td><td>${_esc(it.deviceName)}</td></tr></table>');
    if (it.note.trim().isNotEmpty) {
      html.writeln('<div class="note">${_esc(it.note)}</div>');
    }
    md
      ..writeln('## $n. ${it.title}')
      ..writeln()
      ..writeln('- **Priority:** ${it.priority.label}')
      ..writeln('- **Status:** ${it.status.label}')
      ..writeln(it.project.isNotEmpty ? '- **Project:** ${it.project}' : '')
      ..writeln('- **Captured:** ${_stamp(it.createdAt)} on ${it.deviceName}')
      ..writeln();
    if (it.note.trim().isNotEmpty) md..writeln(it.note)..writeln();

    html.writeln('<div class="media">');
    for (final m in it.media) {
      final src = store.mediaFile(it.id, m.fileName);
      if (!await src.exists()) continue;
      final outName = '${safeFileName(it.id)}_${m.fileName}';
      await src.copy('${mediaDir.path}$sep$outName');
      if (m.kind == MediaKind.image) {
        html.writeln('<a href="media/$outName"><img src="media/$outName" alt=""></a>');
        md..writeln('![](media/$outName)')..writeln();
      } else {
        html.writeln('<a class="video" href="media/$outName">▶ ${_esc(m.fileName)}</a>');
        md..writeln('[Video: ${m.fileName}](media/$outName)')..writeln();
      }
    }
    html
      ..writeln('</div>')
      ..writeln('</div>');
  }
  html.writeln('</body></html>');

  final index = File('${dir.path}${sep}index.html');
  await index.writeAsString(html.toString());
  await File('${dir.path}${sep}report.md').writeAsString(md.toString());
  return index.path;
}
