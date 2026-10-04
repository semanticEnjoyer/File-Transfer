import 'dart:io';

import 'package:flutter/material.dart';

import 'hub/hub_app.dart';
import 'hub/hub_server.dart';
import 'hub/hub_store.dart';
import 'phone/phone_app.dart';
import 'phone/phone_store.dart';

/// One codebase, two roles:
///  * Android / iOS  -> capture app (pick media, add notes + priority, send)
///  * Windows / macOS / Linux -> hub (receives captures, dashboard, reports)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    final store = PhoneStore();
    await store.load();
    runApp(PhoneApp(store: store));
  } else {
    final store = HubStore();
    await store.load();
    final server = HubServer(store);
    await server.start();
    runApp(HubApp(store: store, server: server));
  }
}
