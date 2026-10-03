import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/message_store.dart';
import '../mesh/mesh_router.dart';
import '../mesh/transport.dart';
import '../models/node_identity.dart';
import '../models/peer.dart';
import '../models/stored_message.dart';
import '../services/alert_service.dart';
import '../services/identity_service.dart';
import '../services/mesh_bridge.dart';
import '../services/mesh_controller.dart';
import '../services/sos_service.dart';

// Services are created in main() and injected via overrides.
final storeProvider = Provider<MessageStore>((_) => throw UnimplementedError());
final transportProvider =
    Provider<MeshTransport>((_) => throw UnimplementedError());
final routerProvider = Provider<MeshRouter>((_) => throw UnimplementedError());
final identityServiceProvider =
    Provider<IdentityService>((_) => throw UnimplementedError());
final sosServiceProvider =
    Provider<SosService>((_) => throw UnimplementedError());
final bridgeProvider = Provider<MeshBridge>((_) => throw UnimplementedError());
final alertServiceProvider =
    Provider<AlertService>((_) => throw UnimplementedError());
final meshControllerProvider =
    Provider<MeshController>((_) => throw UnimplementedError());

/// Emits the current value first, then every change.
Stream<T> _seeded<T>(T current, Stream<T> changes) async* {
  yield current;
  yield* changes;
}

/// Re-runs [query] whenever the store changes.
Stream<T> _watchStore<T>(MessageStore store, Future<T> Function() query) async* {
  yield await query();
  await for (final _ in store.changes) {
    yield await query();
  }
}

final identityProvider = StreamProvider<NodeIdentity>((ref) {
  final service = ref.watch(identityServiceProvider);
  return _seeded(service.current, service.changes);
});

final transportStatusProvider = StreamProvider<TransportStatus>((ref) {
  final transport = ref.watch(transportProvider);
  return _seeded(transport.status, transport.statusChanges);
});

final peersProvider = StreamProvider<List<Peer>>((ref) {
  final transport = ref.watch(transportProvider);
  return _seeded(transport.peers, transport.peerChanges);
});

final conversationsProvider = StreamProvider<List<ConversationSummary>>((ref) {
  final store = ref.watch(storeProvider);
  return _watchStore(store, store.conversations);
});

final conversationProvider =
    StreamProvider.family<List<StoredMessage>, String>((ref, peerId) {
  final store = ref.watch(storeProvider);
  return _watchStore(store, () => store.conversation(peerId));
});

final sosAlertsProvider = StreamProvider<List<StoredMessage>>((ref) {
  final store = ref.watch(storeProvider);
  return _watchStore(store, store.sosAlerts);
});

final sosActiveProvider = StreamProvider<bool>((ref) {
  final sos = ref.watch(sosServiceProvider);
  return _seeded(sos.isActive, sos.activeChanges);
});

/// Best display name for a node: live peer name, else the name it last used
/// in a message, else a short id.
String nameFor(String nodeId, List<Peer> peers, [String? fallback]) {
  for (final p in peers) {
    if (p.nodeId == nodeId && (p.name?.isNotEmpty ?? false)) return p.name!;
  }
  if (fallback != null && fallback.isNotEmpty) return fallback;
  return nodeId.length > 8 ? nodeId.substring(0, 8) : nodeId;
}
