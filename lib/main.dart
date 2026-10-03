import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'ble/ble_transport.dart';
import 'data/sqlite_message_store.dart';
import 'mesh/mesh_router.dart';
import 'services/identity_service.dart';
import 'services/location_service.dart';
import 'services/sos_service.dart';
import 'state/providers.dart';

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
  final sos = SosService(router: router, location: LocationService());

  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        transportProvider.overrideWithValue(transport),
        routerProvider.overrideWithValue(router),
        identityServiceProvider.overrideWithValue(identity),
        sosServiceProvider.overrideWithValue(sos),
      ],
      child: const LinkMeshApp(),
    ),
  );
}
