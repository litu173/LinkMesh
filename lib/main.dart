import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'ble/ble_transport.dart';
import 'data/sqlite_message_store.dart';
import 'mesh/mesh_router.dart';
import 'services/alert_service.dart';
import 'services/identity_service.dart';
import 'services/location_service.dart';
import 'services/mesh_bridge.dart';
import 'services/mesh_controller.dart';
import 'services/sos_service.dart';
import 'state/providers.dart';

/// Runs both when the user opens the app and when Android starts the
/// background service with no UI (e.g. after a reboot). The mesh is started
/// here rather than from a widget so it works in both cases.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await SqliteMessageStore.open();
  final identity = await IdentityService.load(store);
  final transport = BleTransport(identity: () => identity.current);
  final router = MeshRouter(
    transport: transport,
    store: store,
    identity: identity.current,
  )..start();
  identity.changes.listen((id) => router.identity = id);
  final bridge = MeshBridge();
  final alerts = AlertService(router: router, bridge: bridge);
  final controller = MeshController(
    transport: transport,
    bridge: bridge,
    alerts: alerts,
  );
  final sos = SosService(router: router, location: LocationService());

  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        transportProvider.overrideWithValue(transport),
        routerProvider.overrideWithValue(router),
        identityServiceProvider.overrideWithValue(identity),
        sosServiceProvider.overrideWithValue(sos),
        bridgeProvider.overrideWithValue(bridge),
        alertServiceProvider.overrideWithValue(alerts),
        meshControllerProvider.overrideWithValue(controller),
      ],
      child: const LinkMeshApp(),
    ),
  );

  await controller.startIfPermitted();
}
