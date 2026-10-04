import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'connect_screen.dart';
import 'new_capture_screen.dart';
import 'phone_store.dart';

class PhoneApp extends StatelessWidget {
  const PhoneApp({super.key, required this.store});
  final PhoneStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TestCapture',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(store: store),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final PhoneStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  PhoneStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.syncNow();
  }

  void _openConnect() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ConnectScreen(store: store)));

  void _newCapture() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => NewCaptureScreen(store: store)));

  Future<void> _clearSynced() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Free up space?'),
        content: const Text(
            'Removes the phone copies of captures that are already on your PC. The PC keeps everything.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await store.clearSynced();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Removed $n synced capture(s) from this phone')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('TestCapture', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              _ConnectionPill(store: store, onTap: _openConnect),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'connect') _openConnect();
                  if (v == 'clear') _clearSynced();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'connect', child: Text('PC connection')),
                  PopupMenuItem(value: 'clear', child: Text('Free up space')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _newCapture,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('New capture'),
          ),
          body: RefreshIndicator(
            onRefresh: store.syncNow,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (!store.isPaired)
                  SliverToBoxAdapter(child: _PairBanner(onTap: _openConnect)),
                if (store.items.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyPhone())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    sliver: SliverList.separated(
                      itemCount: store.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _PhoneItemCard(
                        item: store.items[i],
                        store: store,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                PhoneItemScreen(store: store, item: store.items[i]))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.store, required this.onTap});
  final PhoneStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color c, String label) = switch (store.connection) {
      HubConnection.online => (Colors.green, store.hub?.name ?? 'PC'),
      HubConnection.checking => (Colors.amber, 'Connecting'),
      HubConnection.offline => (Colors.red, 'PC offline'),
      HubConnection.notPaired => (Colors.grey, 'Not paired'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ActionChip(
        onPressed: onTap,
        avatar: Icon(Icons.circle, size: 10, color: c),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _PairBanner extends StatelessWidget {
  const _PairBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        color: cs.primaryContainer,
        child: ListTile(
          leading: Icon(Icons.computer, color: cs.onPrimaryContainer),
          title: const Text('Connect to your PC'),
          subtitle: const Text('Captures are kept here and sent once you pair.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _EmptyPhone extends StatelessWidget {
  const _EmptyPhone();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.photo_library_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 12),
          Text('No captures yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Tap “New capture”, pick screenshots or recordings,\nadd a note and a priority.',
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.item, required this.store});
  final CaptureItem item;
  final PhoneStore store;

  @override
  Widget build(BuildContext context) {
    switch (item.syncState) {
      case SyncState.synced:
        return const Tooltip(
            message: 'On your PC', child: Icon(Icons.cloud_done, color: Colors.green, size: 20));
      case SyncState.syncing:
        final p = store.syncingId == item.id ? store.syncProgress : 0.0;
        return SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, value: p > 0 ? p : null),
        );
      case SyncState.failed:
        return const Tooltip(
            message: 'Will retry', child: Icon(Icons.sync_problem, color: Colors.orange, size: 20));
      case SyncState.pending:
        return const Tooltip(
            message: 'Waiting for PC', child: Icon(Icons.schedule, color: Colors.grey, size: 20));
    }
  }
}

class _PhoneItemCard extends StatelessWidget {
  const _PhoneItemCard({required this.item, required this.store, required this.onTap});
  final CaptureItem item;
  final PhoneStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final img = item.firstImage;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 64,
                color: cs.surfaceContainerHighest,
                child: img != null
                    ? Image.file(store.mediaFile(item.id, img.fileName),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, __, ___) => Icon(Icons.cloud_done, color: cs.outline))
                    : Icon(item.hasVideo ? Icons.movie : Icons.notes, color: cs.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  PriorityChip(item.priority, dense: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      [
                        if (item.project.isNotEmpty) item.project,
                        '${item.media.length} file(s)',
                        timeAgo(item.createdAt),
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall,
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            _SyncBadge(item: item, store: store),
          ]),
        ),
      ),
    );
  }
}

/// Read-only view of a capture on the phone.
class PhoneItemScreen extends StatelessWidget {
  const PhoneItemScreen({super.key, required this.store, required this.item});
  final PhoneStore store;
  final CaptureItem item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(item.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Delete from phone',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete from phone?'),
                    content: Text(item.syncState == SyncState.synced
                        ? 'The copy on your PC is kept.'
                        : 'This capture has not reached your PC yet and will be lost.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await store.deleteLocal(item);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              PriorityChip(item.priority),
              const SizedBox(width: 8),
              if (item.project.isNotEmpty) Chip(label: Text(item.project)),
              const Spacer(),
              _SyncBadge(item: item, store: store),
            ]),
            if (item.syncState == SyncState.failed) ...[
              const SizedBox(height: 8),
              Card(
                color: cs.errorContainer,
                child: ListTile(
                  title: Text(item.syncError ?? 'Sending failed'),
                  trailing: TextButton(
                      onPressed: () => store.retry(item), child: const Text('Retry')),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (item.note.isNotEmpty) ...[
              Text('Notes', style: tt.labelLarge),
              const SizedBox(height: 4),
              SelectableText(item.note),
              const SizedBox(height: 16),
            ],
            for (final m in item.media) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: m.kind == MediaKind.image
                    ? Image.file(store.mediaFile(item.id, m.fileName),
                        errorBuilder: (_, __, ___) => _missing(context))
                    : Container(
                        height: 120,
                        color: Colors.black,
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.movie, color: Colors.white, size: 36),
                            Text('${m.fileName} · ${formatBytes(m.size)}',
                                style: const TextStyle(color: Colors.white70)),
                          ]),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _missing(BuildContext context) => Container(
        height: 80,
        alignment: Alignment.center,
        child: Text('File not on this phone', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
}
