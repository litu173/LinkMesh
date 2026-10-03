import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkmesh/models/mesh_message.dart';
import 'package:linkmesh/models/stored_message.dart';

import 'fake_network.dart';

void main() {
  Future<StoredMessage> statusOf(TestNode node, String id) async =>
      (await node.store.get(id))!;

  test('1. two devices communicate directly', () async {
    final net = FakeNetwork();
    final a = net.addNode('A');
    final b = net.addNode('B');
    net.link('A', 'B');

    final sent = await a.router.sendText('B', 'hello');
    await settle();

    final received = await b.store.conversation('A');
    expect(received, hasLength(1));
    expect(received.single.message.content, 'hello');
    expect(received.single.relayHops, 0);

    final status = await statusOf(a, sent.id);
    expect(status.status, DeliveryStatus.delivered);
    expect(status.relayHops, 0);
  });

  test('2. three devices relay through the middle node', () async {
    final net = FakeNetwork();
    final a = net.addNode('A');
    final b = net.addNode('B');
    final c = net.addNode('C');
    net.chain(['A', 'B', 'C']);

    final sent = await a.router.sendText('C', 'over the hill');
    await settle();

    final received = await c.store.conversation('A');
    expect(received.single.message.content, 'over the hill');
    expect(received.single.relayHops, 1);

    final status = await statusOf(a, sent.id);
    expect(status.status, DeliveryStatus.delivered);
    expect(status.relayHops, 1, reason: 'shown as "via 1 device"');

    // The relay doesn't keep other people's chats.
    expect(await b.store.conversations(), isEmpty);
  });

  test('3. middle device drops, message continues when link returns',
      () async {
    final net = FakeNetwork();
    final a = net.addNode('A');
    net.addNode('B');
    final c = net.addNode('C');
    net.chain(['A', 'B', 'C']);
    net.unlink('B', 'C');

    final sent = await a.router.sendText('C', 'are you there?');
    await settle();

    expect(await c.store.conversation('A'), isEmpty);
    expect(
      (await statusOf(a, sent.id)).status,
      DeliveryStatus.relayed,
      reason: 'A heard B forward it',
    );

    net.link('B', 'C'); // B replays its relay buffer to C
    await settle();

    expect(await c.store.conversation('A'), hasLength(1));
    expect((await statusOf(a, sent.id)).status, DeliveryStatus.delivered);
  });

  test('3b. sender with no peers queues, then sends on first link', () async {
    final net = FakeNetwork();
    final a = net.addNode('A');
    final b = net.addNode('B');

    final sent = await a.router.sendText('B', 'queued');
    expect(sent.status, DeliveryStatus.pending);

    net.link('A', 'B');
    await settle();

    expect(await b.store.conversation('A'), hasLength(1));
    expect((await statusOf(a, sent.id)).status, DeliveryStatus.delivered);
  });

  test('4. dense mesh delivers exactly once, no broadcast storm', () async {
    final net = FakeNetwork();
    final ids = ['A', 'B', 'C', 'D', 'E'];
    for (final id in ids) {
      net.addNode(id);
    }
    for (final x in ids) {
      for (final y in ids) {
        if (x != y) net.link(x, y);
      }
    }
    final sent = await net.nodes['A']!.router.sendText('E', 'once');
    await settle();

    final e = net.nodes['E']!;
    expect(e.store.saves[sent.id], 1, reason: 'stored once despite 4 copies');
    // Each node forwards a given message at most once.
    expect(net.framesDelivered, lessThan(ids.length * ids.length * 2));
    expect(
      (await statusOf(net.nodes['A']!, sent.id)).status,
      DeliveryStatus.delivered,
    );
  });

  test('5. high latency links still deliver', () async {
    final net = FakeNetwork(latency: const Duration(milliseconds: 150));
    final a = net.addNode('A');
    net.addNode('B');
    net.addNode('C');
    final d = net.addNode('D');
    net.chain(['A', 'B', 'C', 'D']);

    final sent = await a.router.sendText('D', 'slow');
    await settle(const Duration(milliseconds: 300));
    expect(await d.store.conversation('A'), isEmpty, reason: 'still in flight');

    await settle(const Duration(seconds: 1));
    expect((await d.store.conversation('A')).single.relayHops, 2);
    expect((await statusOf(a, sent.id)).status, DeliveryStatus.delivered);
  });

  test('max_hops bounds how far a message travels', () async {
    final net = FakeNetwork();
    final ids = List.generate(8, (i) => 'N$i');
    for (final id in ids) {
      net.addNode(id);
    }
    net.chain(ids);
    final origin = net.nodes['N0']!;

    // N0 -> N6 takes 5 relays (N1..N5): exactly the default budget.
    final reachable = await origin.router.sendText('N6', 'edge');
    // N0 -> N7 would take 6.
    final tooFar = await origin.router.sendText('N7', 'beyond');
    await settle(const Duration(milliseconds: 200));

    expect((await net.nodes['N6']!.store.conversation('N0')).single.relayHops,
        5);
    expect(await net.nodes['N7']!.store.conversation('N0'), isEmpty);
    expect((await statusOf(origin, reachable.id)).status,
        DeliveryStatus.delivered);
    expect((await statusOf(origin, tooFar.id)).status,
        isNot(DeliveryStatus.delivered));
  });

  test('SOS reaches every node and raises an alert', () async {
    final net = FakeNetwork();
    for (final id in ['A', 'B', 'C']) {
      net.addNode(id);
    }
    net.chain(['A', 'B', 'C']);
    final alerts = <String>[];
    net.nodes['C']!.router.sosAlerts.listen((m) => alerts.add(m.message.id));

    final sos = await net.nodes['A']!.router
        .sendSos('help', lat: 12.5, lng: 77.25);
    await settle();

    for (final id in ['B', 'C']) {
      final list = await net.nodes[id]!.store.sosAlerts();
      expect(list.single.message.content, 'help');
      expect(list.single.message.lat, 12.5);
    }
    expect(alerts, [sos.id]);
    expect(await net.nodes['A']!.store.sosAlerts(), isEmpty,
        reason: 'own SOS is not an alert');
  });

  test('malformed frames are ignored', () async {
    final net = FakeNetwork();
    final a = net.addNode('A');
    final b = net.addNode('B');
    net.link('A', 'B');

    await a.transport.broadcast(Uint8List.fromList([1, 2, 3]));
    await a.transport.broadcast(
      Uint8List.fromList(utf8.encode('{"id":"x","type":"bogus"}')),
    );
    await settle();

    expect(await b.store.conversations(), isEmpty);
  });

  test('message JSON round-trips with spec field names', () {
    const m = MeshMessage(
      id: 'm1',
      type: MessageType.text,
      senderId: 'A',
      senderName: 'Alice',
      receiverId: 'B',
      timestamp: 1234567890,
      content: 'hi',
    );
    final json = m.toJson();
    expect(json.keys, containsAll([
      'id', 'sender_id', 'receiver_id', 'timestamp', 'content', //
      'hop_count', 'max_hops',
    ]));
    final decoded = MeshMessage.tryDecode(m.encode())!;
    expect(decoded.toJson(), json);
  });
}
