import 'dart:async';
import 'dart:typed_data';

import 'package:linkmesh/data/message_store.dart';
import 'package:linkmesh/mesh/mesh_router.dart';
import 'package:linkmesh/mesh/transport.dart';
import 'package:linkmesh/models/node_identity.dart';
import 'package:linkmesh/models/peer.dart';
import 'package:linkmesh/models/stored_message.dart';

/// Simulated radio neighbourhood: nodes only hear nodes they're linked to.
class FakeNetwork {
  FakeNetwork({this.latency = Duration.zero});

  final Duration latency;
  final nodes = <String, TestNode>{};
  final _links = <String>{};
  int framesDelivered = 0;

  TestNode addNode(String id) {
    final transport = FakeTransport(id, this);
    final store = CountingStore();
    final router = MeshRouter(
      transport: transport,
      store: store,
      identity: NodeIdentity(id: id, name: id),
    )..start();
    return nodes[id] = TestNode(id, transport, store, router);
  }

  static String _key(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  bool linked(String a, String b) => _links.contains(_key(a, b));

  void link(String a, String b) {
    if (!_links.add(_key(a, b))) return;
    nodes[a]!.transport._linked.add(b);
    nodes[b]!.transport._linked.add(a);
  }

  void unlink(String a, String b) => _links.remove(_key(a, b));

  /// Links consecutive ids into a line: a - b - c ...
  void chain(List<String> ids) {
    for (var i = 0; i + 1 < ids.length; i++) {
      link(ids[i], ids[i + 1]);
    }
  }

  Iterable<String> neighbours(String id) =>
      nodes.keys.where((other) => other != id && linked(id, other));

  void _deliver(String from, String to, Uint8List frame) {
    Future<void>.delayed(latency, () {
      if (!linked(from, to)) return; // link dropped while in flight
      framesDelivered++;
      nodes[to]!.transport._incoming.add(frame);
    });
  }
}

class TestNode {
  TestNode(this.id, this.transport, this.store, this.router);

  final String id;
  final FakeTransport transport;
  final CountingStore store;
  final MeshRouter router;
}

class CountingStore extends InMemoryMessageStore {
  final saves = <String, int>{};

  @override
  Future<void> save(StoredMessage message) {
    saves.update(message.id, (n) => n + 1, ifAbsent: () => 1);
    return super.save(message);
  }
}

class FakeTransport implements MeshTransport {
  FakeTransport(this.id, this.network);

  final String id;
  final FakeNetwork network;
  final _incoming = StreamController<Uint8List>.broadcast();
  final _linked = StreamController<String>.broadcast();

  @override
  TransportStatus get status => TransportStatus.running;

  @override
  Stream<TransportStatus> get statusChanges => const Stream.empty();

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  List<Peer> get peers => const [];

  @override
  Stream<List<Peer>> get peerChanges => const Stream.empty();

  @override
  Stream<String> get peerLinked => _linked.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<int> broadcast(Uint8List frame) async {
    final targets = network.neighbours(id).toList();
    for (final t in targets) {
      network._deliver(id, t, frame);
    }
    return targets.length;
  }

  @override
  Future<bool> sendTo(String nodeId, Uint8List frame) async {
    if (!network.linked(id, nodeId)) return false;
    network._deliver(id, nodeId, frame);
    return true;
  }
}

/// Lets queued deliveries and async handlers run.
Future<void> settle([Duration d = const Duration(milliseconds: 50)]) =>
    Future<void>.delayed(d);
