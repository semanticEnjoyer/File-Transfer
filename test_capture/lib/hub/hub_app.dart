import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/protocol.dart';
import '../core/theme.dart';
import 'desktop_utils.dart';
import 'hub_server.dart';
import 'hub_store.dart';

class HubApp extends StatelessWidget {
  const HubApp({super.key, required this.store, required this.server});
  final HubStore store;
  final HubServer server;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TestCapture',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Dashboard(store: store, server: server),
    );
  }
}

enum SortMode { newest, oldest, priority }

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.store, required this.server});
  final HubStore store;
  final HubServer server;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  HubStore get store => widget.store;

  ItemStatus? _status; // null = all
  final Set<Priority> _priorities = {};
  String? _project;
  String _search = '';
  SortMode _sort = SortMode.newest;
  String? _selectedId;
  List<String> _addresses = [];

  @override
  void initState() {
    super.initState();
    HubServer.localAddresses().then((a) {
      if (mounted) setState(() => _addresses = a);
    });
  }

  List<CaptureItem> _filtered() {
    final q = _search.trim().toLowerCase();
    final list = store.items.where((it) {
      if (_status != null && it.status != _status) return false;
      if (_priorities.isNotEmpty && !_priorities.contains(it.priority)) return false;
      if (_project != null && it.project.trim() != _project) return false;
      if (q.isNotEmpty &&
          !('${it.title} ${it.note} ${it.project} ${it.tags.join(' ')}')
              .toLowerCase()
              .contains(q)) {
        return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case SortMode.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.priority:
        list.sort((a, b) {
          final p = b.priority.index.compareTo(a.priority.index);
          return p != 0 ? p : b.createdAt.compareTo(a.createdAt);
        });
    }
    return list;
  }

  Future<void> _export(List<CaptureItem> items, {String? title}) async {
    if (items.isEmpty) return;
    final reportTitle = title ??
        (_project != null ? '$_project – test report' : 'Test report');
    try {
      final path = await exportReport(store, items, reportTitle);
      await openWithSystem(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Report created with ${items.length} item(s)'),
        action: SnackBarAction(label: 'Show folder', onPressed: () => revealInFolder(path)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _filtered();
        final selected = _selectedId == null ? null : store.item(_selectedId!);
        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 270, child: _buildSidebar(context)),
              const VerticalDivider(width: 1),
              Expanded(child: _buildList(context, items)),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 460,
                child: selected == null
                    ? const _EmptyDetail()
                    : DetailPanel(
                        key: ValueKey(selected.id),
                        item: selected,
                        store: store,
                        onClose: () => setState(() => _selectedId = null),
                        onExport: () => _export([selected], title: selected.title),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- sidebar

  Widget _buildSidebar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = store.items;
    int countStatus(ItemStatus? s) =>
        s == null ? all.length : all.where((i) => i.status == s).length;
    int countPriority(Priority p) => all.where((i) => i.priority == p).length;

    return Container(
      color: cs.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.bug_report, color: cs.onPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TestCapture',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('Hub · ${store.hubName}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          _PairCard(store: store, server: widget.server, addresses: _addresses),
          const SizedBox(height: 18),
          const _SectionLabel('Status'),
          _NavTile(
              icon: Icons.inbox,
              label: 'All captures',
              count: countStatus(null),
              selected: _status == null,
              onTap: () => setState(() => _status = null)),
          for (final s in ItemStatus.values)
            _NavTile(
                icon: s.icon,
                label: s.label,
                count: countStatus(s),
                selected: _status == s,
                onTap: () => setState(() => _status = s)),
          const SizedBox(height: 14),
          const _SectionLabel('Priority'),
          for (final p in Priority.values.reversed)
            _NavTile(
                icon: p.icon,
                iconColor: p.color,
                label: p.label,
                count: countPriority(p),
                selected: _priorities.contains(p),
                onTap: () => setState(() =>
                    _priorities.contains(p) ? _priorities.remove(p) : _priorities.add(p))),
          if (store.projects.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel('Projects'),
            _NavTile(
                icon: Icons.folder_open,
                label: 'All projects',
                selected: _project == null,
                onTap: () => setState(() => _project = null)),
            for (final pr in store.projects)
              _NavTile(
                  icon: Icons.folder,
                  label: pr,
                  count: all.where((i) => i.project.trim() == pr).length,
                  selected: _project == pr,
                  onTap: () => setState(() => _project = pr)),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- list

  Widget _buildList(BuildContext context, List<CaptureItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search title, notes, project, tags…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<SortMode>(
              tooltip: 'Sort',
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: SortMode.newest, child: Text('Newest first')),
                PopupMenuItem(value: SortMode.oldest, child: Text('Oldest first')),
                PopupMenuItem(value: SortMode.priority, child: Text('Priority')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Row(children: [Icon(Icons.sort), SizedBox(width: 4), Text('Sort')]),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: items.isEmpty ? null : () => _export(items),
              icon: const Icon(Icons.description_outlined),
              label: Text('Export report (${items.length})'),
            ),
          ]),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyList(hasAny: store.items.isNotEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return _ItemCard(
                      item: it,
                      store: store,
                      selected: it.id == _selectedId,
                      onTap: () => setState(() => _selectedId = it.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================== widgets

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.iconColor,
  });
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 18, color: iconColor ?? cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (count != null)
                Text('$count', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.store, required this.server, required this.addresses});
  final HubStore store;
  final HubServer server;
  final List<String> addresses;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pinText = '${store.pin.substring(0, 3)} ${store.pin.substring(3)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle,
                size: 10, color: server.running ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            Text(server.running ? 'Ready on Wi-Fi' : 'Server not running',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          if (server.error != null) ...[
            const SizedBox(height: 6),
            Text(server.error!, style: TextStyle(color: cs.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Text('Pairing PIN', style: Theme.of(context).textTheme.bodySmall),
          Row(children: [
            Expanded(
              child: SelectableText(pinText,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            IconButton(
              tooltip: 'New PIN',
              onPressed: store.newPin,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          if (addresses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('PC address (for manual connect)',
                style: Theme.of(context).textTheme.bodySmall),
            for (final a in addresses)
              InkWell(
                onTap: () => Clipboard.setData(ClipboardData(text: a)),
                child: Text('$a:${Protocol.httpPort}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
          ],
          const SizedBox(height: 10),
          Text(
              store.devices.isEmpty
                  ? 'No phones paired yet'
                  : '${store.devices.length} phone(s) paired',
              style: Theme.of(context).textTheme.bodySmall),
          for (final e in store.devices.entries)
            Row(children: [
              const Icon(Icons.phone_android, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(e.value, overflow: TextOverflow.ellipsis)),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Unpair',
                iconSize: 16,
                onPressed: () => store.unpair(e.key),
                icon: const Icon(Icons.link_off),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.store, this.size = 76});
  final CaptureItem item;
  final HubStore store;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = item.firstImage;
    Widget child;
    if (img != null && img.uploaded) {
      child = Image.file(
        store.mediaFile(item.id, img.fileName),
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: cs.outline),
      );
    } else if (item.hasVideo) {
      child = Icon(Icons.movie, color: cs.primary, size: 30);
    } else if (item.media.isEmpty) {
      child = Icon(Icons.notes, color: cs.outline, size: 28);
    } else {
      child = const Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Stack(fit: StackFit.expand, children: [
          child,
          if (item.media.length > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text('${item.media.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard(
      {required this.item, required this.store, required this.selected, required this.onTap});
  final CaptureItem item;
  final HubStore store;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(width: 4, height: 60, decoration: BoxDecoration(
                color: item.priority.color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            _Thumb(item: item, store: store),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            item.status == ItemStatus.done ? TextDecoration.lineThrough : null)),
                if (item.note.isNotEmpty)
                  Text(item.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  PriorityChip(item.priority, dense: true),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(item.status.icon, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(item.status.label, style: tt.bodySmall),
                  ]),
                  if (item.project.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(item.project, style: tt.bodySmall),
                    ]),
                  if (!item.complete && item.media.isNotEmpty)
                    Text('receiving…', style: tt.bodySmall?.copyWith(color: cs.primary)),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Text(timeAgo(item.createdAt), style: tt.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasAny});
  final bool hasAny;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(hasAny ? Icons.filter_alt_off : Icons.phone_android, size: 56, color: cs.outline),
        const SizedBox(height: 12),
        Text(hasAny ? 'Nothing matches these filters' : 'No captures yet',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
            hasAny
                ? 'Try clearing a filter or the search.'
                : 'Open TestCapture on your phone, pair it with the PIN on the left,\nand send your first screenshot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLowest,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined, size: 48, color: cs.outline),
          const SizedBox(height: 10),
          Text('Select a capture to see details', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// =============================================================== detail

class DetailPanel extends StatefulWidget {
  const DetailPanel({
    super.key,
    required this.item,
    required this.store,
    required this.onClose,
    required this.onExport,
  });
  final CaptureItem item;
  final HubStore store;
  final VoidCallback onClose;
  final VoidCallback onExport;

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  int _mediaIndex = 0;

  CaptureItem get it => widget.item;

  Future<void> _edit() async {
    final title = TextEditingController(text: it.title);
    final project = TextEditingController(text: it.project);
    final note = TextEditingController(text: it.note);
    final tags = TextEditingController(text: it.tags.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit capture'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
                controller: project, decoration: const InputDecoration(labelText: 'Project')),
            const SizedBox(height: 12),
            TextField(
                controller: tags,
                decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
            const SizedBox(height: 12),
            TextField(
                controller: note,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      it
        ..title = title.text.trim().isEmpty ? it.title : title.text.trim()
        ..project = project.text.trim()
        ..note = note.text
        ..tags = tags.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      await widget.store.update(it);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete capture?'),
        content: Text('"${it.title}" and its ${it.media.length} file(s) will be removed from this PC.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      widget.onClose();
      await widget.store.delete(it.id);
    }
  }

  void _openFullscreen(File f) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(child: Image.file(f)),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filled(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _mediaViewer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (it.media.isEmpty) {
      return const SizedBox.shrink();
    }
    final int idx = _mediaIndex < it.media.length ? _mediaIndex : 0;
    final m = it.media[idx];
    final f = widget.store.mediaFile(it.id, m.fileName);

    Widget content;
    if (!m.uploaded) {
      content = const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text('Receiving from phone…', style: TextStyle(color: Colors.white70)),
        ]),
      );
    } else if (m.kind == MediaKind.image) {
      content = GestureDetector(
        onTap: () => _openFullscreen(f),
        child: MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: Image.file(f, fit: BoxFit.contain),
        ),
      );
    } else {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filled(
            iconSize: 40,
            onPressed: () => openWithSystem(f.path),
            icon: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 10),
          Text(m.fileName, style: const TextStyle(color: Colors.white)),
          Text(formatBytes(m.size), style: const TextStyle(color: Colors.white60)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 300,
          color: Colors.black,
          child: content,
        ),
      ),
      if (it.media.length > 1) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: it.media.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final mm = it.media[i];
              final ff = widget.store.mediaFile(it.id, mm.fileName);
              return InkWell(
                onTap: () => setState(() => _mediaIndex = i),
                child: Container(
                  width: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: i == idx ? cs.primary : cs.outlineVariant, width: i == idx ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: mm.kind == MediaKind.image && mm.uploaded
                      ? Image.file(ff, fit: BoxFit.cover, cacheWidth: 120)
                      : Icon(mm.kind == MediaKind.video ? Icons.movie : Icons.hourglass_top,
                          color: cs.primary),
                ),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 6),
      Row(children: [
        Text('${idx + 1}/${it.media.length} · ${m.fileName}',
            style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        if (m.uploaded)
          TextButton.icon(
            onPressed: () => revealInFolder(f.path),
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Show file'),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SelectableText(it.title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _meta(context, Icons.schedule, timeAgo(it.createdAt)),
          if (it.deviceName.isNotEmpty) _meta(context, Icons.phone_android, it.deviceName),
          if (it.project.isNotEmpty) _meta(context, Icons.folder, it.project),
        ]),
        if (it.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in it.tags)
              Chip(label: Text('#$t'), visualDensity: VisualDensity.compact),
          ]),
        ],
        const SizedBox(height: 16),
        _mediaViewer(context),
        const SizedBox(height: 18),
        Text('Priority', style: tt.labelLarge),
        const SizedBox(height: 8),
        PriorityPicker(
          value: it.priority,
          onChanged: (p) {
            it.priority = p;
            widget.store.update(it);
          },
        ),
        const SizedBox(height: 18),
        Text('Status', style: tt.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<ItemStatus>(
          showSelectedIcon: false,
          segments: [
            for (final s in ItemStatus.values)
              ButtonSegment(value: s, label: Text(s.label), icon: Icon(s.icon, size: 16)),
          ],
          selected: {it.status},
          onSelectionChanged: (v) {
            it.status = v.first;
            widget.store.update(it);
          },
        ),
        const SizedBox(height: 18),
        Row(children: [
          Text('Notes', style: tt.labelLarge),
          const Spacer(),
          TextButton(onPressed: _edit, child: const Text('Edit')),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(it.note.isEmpty ? 'No notes' : it.note,
              style: it.note.isEmpty ? TextStyle(color: cs.outline) : null),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onExport,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Export'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
    ]);
  }
}
