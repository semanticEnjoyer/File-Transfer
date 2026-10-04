import 'package:flutter/material.dart';

import '../core/protocol.dart';
import 'phone_store.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.store});
  final PhoneStore store;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  PhoneStore get store => widget.store;
  List<HubInfo> _found = [];
  bool _searching = false;
  late final TextEditingController _name =
      TextEditingController(text: widget.store.deviceName);
  final _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!store.isPaired) _search();
  }

  @override
  void dispose() {
    _name.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final res = await PhoneStore.discover();
    if (!mounted) return;
    setState(() {
      _found = res;
      _searching = false;
    });
  }

  Future<void> _connectManual() async {
    FocusScope.of(context).unfocus();
    final hub = await PhoneStore.probe(_manual.text);
    if (!mounted) return;
    if (hub == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No TestCapture PC found at that address')));
      return;
    }
    _askPin(hub);
  }

  Future<void> _askPin(HubInfo hub) async {
    await store.setDeviceName(_name.text);
    if (!mounted) return;
    final pinCtrl = TextEditingController();
    String? error;
    var busy = false;
    final paired = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Pair with ${hub.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Enter the 6-digit PIN shown in the PC app.'),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 7,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: InputDecoration(counterText: '', errorText: error),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() {
                        busy = true;
                        error = null;
                      });
                      final err = await store.pair(hub, pinCtrl.text);
                      if (err == null) {
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } else {
                        setD(() {
                          busy = false;
                          error = err;
                        });
                      }
                    },
              child: const Text('Pair'),
            ),
          ],
        ),
      ),
    );
    if (paired == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Paired with ${hub.name}')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('PC connection')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (store.isPaired) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.computer, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(store.hub!.name, style: tt.titleMedium),
                          Text('${store.hub!.host}:${store.hub!.port}', style: tt.bodySmall),
                        ]),
                      ),
                      Icon(Icons.circle,
                          size: 12,
                          color: store.connection == HubConnection.online
                              ? Colors.green
                              : Colors.red),
                    ]),
                    const SizedBox(height: 8),
                    Text(store.connection == HubConnection.online
                        ? 'Connected. ${store.pendingCount} capture(s) waiting to send.'
                        : 'PC not reachable. Make sure the PC app is open and both devices are on the same Wi-Fi.'),
                    const SizedBox(height: 10),
                    Row(children: [
                      OutlinedButton.icon(
                          onPressed: store.syncNow,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: store.unpair, child: const Text('Forget this PC')),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'This phone’s name',
                helperText: 'Shown on the PC next to each capture',
                prefixIcon: Icon(Icons.phone_android),
              ),
              onSubmitted: store.setDeviceName,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Text(store.isPaired ? 'Pair with another PC' : 'PCs on this Wi-Fi',
                  style: tt.titleSmall),
              const Spacer(),
              if (_searching)
                const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(
                    onPressed: _search, icon: const Icon(Icons.search), label: const Text('Search')),
            ]),
            const SizedBox(height: 6),
            if (!_searching && _found.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'No PC found yet. Open TestCapture on your PC, then tap Search. '
                    'If Windows asks about the firewall, allow private networks.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final h in _found)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.computer),
                  title: Text(h.name),
                  subtitle: Text(h.host),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _askPin(h),
                ),
              ),
            const SizedBox(height: 24),
            Text('Or enter the address manually', style: tt.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: '192.168.1.20:${Protocol.httpPort}',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _connectManual(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _connectManual, child: const Text('Connect')),
            ]),
          ],
        ),
      ),
    );
  }
}
