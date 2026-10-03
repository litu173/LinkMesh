import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/message_store.dart';
import '../models/mesh_message.dart';
import '../models/node_identity.dart';
import '../models/stored_message.dart';
import 'seen_cache.dart';
import 'transport.dart';

/// Flood-based mesh routing.
///
/// Every node rebroadcasts messages not addressed to it until `max_hops` is
/// spent, suppressing duplicates by message id. Recent messages are kept in a
/// relay buffer and replayed to newly linked peers, so a message survives a
/// broken chain and continues once a path reappears (store-and-forward).
///
/// Delivery status for our own messages:
/// * sent      – a neighbour accepted the frame
/// * relayed   – we heard a neighbour forward it (hop_count > 0 echo)
/// * delivered – the recipient's ack came back
class MeshRouter {
  MeshRouter({
    required this.transport,
    required this.store,
    required this.identity,
    DateTime Function()? clock,
  })  : _now = clock ?? DateTime.now,
        _seen = SeenCache(
          ttl: MeshConstants.seenTtl,
          maxEntries: MeshConstants.seenMaxEntries,
          clock: clock,
        );

  final MeshTransport transport;
  final MessageStore store;
  final DateTime Function() _now;
  final SeenCache _seen;
  final _uuid = const Uuid();

  /// Updated when the user renames themselves.
  NodeIdentity identity;

  // Insertion-ordered so the oldest entries are pruned first.
  final _buffer = <String, _Buffered>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _sosAlerts = StreamController<StoredMessage>.broadcast();
  final _incoming = StreamController<StoredMessage>.broadcast();

  /// Fires for each new SOS received from another node.
  Stream<StoredMessage> get sosAlerts => _sosAlerts.stream;

  /// Fires for each new chat message addressed to this node.
  Stream<StoredMessage> get incomingMessages => _incoming.stream;

  void start() {
    _subscriptions
      ..add(transport.incoming.listen(_onFrame))
      ..add(transport.peerLinked.listen(_flushTo));
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _sosAlerts.close();
    await _incoming.close();
  }

  Future<StoredMessage> sendText(String peerId, String text) =>
      _originate(MessageType.text, peerId, text);

  Future<StoredMessage> sendSos(String text, {double? lat, double? lng}) =>
      _originate(
        MessageType.sos,
        MeshConstants.broadcastId,
        text,
        lat: lat,
        lng: lng,
      );

  Future<StoredMessage> _originate(
    MessageType type,
    String receiverId,
    String content, {
    double? lat,
    double? lng,
  }) async {
    final message = MeshMessage(
      id: _uuid.v4(),
      type: type,
      senderId: identity.id,
      senderName: identity.name,
      receiverId: receiverId,
      timestamp: _now().millisecondsSinceEpoch,
      content: content,
      lat: lat,
      lng: lng,
    );
    _seen.add(message.id);
    await store.save(StoredMessage(message: message, outgoing: true));
    _remember(message);
    if (await transport.broadcast(message.encode()) > 0) {
      await _advance(message.id, DeliveryStatus.sent);
    }
    return (await store.get(message.id))!;
  }

  Future<void> _onFrame(Uint8List bytes) async {
    final message = MeshMessage.tryDecode(bytes);
    if (message == null) return;

    if (message.senderId == identity.id) {
      // Our own message coming back: proof a neighbour relayed it.
      if (message.hopCount > 0 && message.type != MessageType.ack) {
        await _advance(message.id, DeliveryStatus.relayed);
      }
      return;
    }

    // Must stay synchronous up to here so concurrent copies are deduped.
    if (!_seen.add(message.id)) return;
    // Survives restarts, when the in-memory cache is empty.
    if (await store.get(message.id) != null) return;

    final forMe = message.receiverId == identity.id;
    switch (message.type) {
      case MessageType.text:
        if (forMe) {
          final stored = StoredMessage(
            message: message,
            outgoing: false,
            relayHops: message.hopCount,
          );
          await store.save(stored);
          _incoming.add(stored);
          await _sendAck(message);
        } else {
          await _relay(message);
        }
      case MessageType.ack:
        if (forMe) {
          await _onAck(message);
        } else {
          // The original no longer needs replaying from our buffer.
          _buffer.remove(message.refId);
          await _relay(message);
        }
      case MessageType.sos:
        final stored = StoredMessage(
          message: message,
          outgoing: false,
          relayHops: message.hopCount,
        );
        await store.save(stored);
        _sosAlerts.add(stored);
        await _relay(message);
    }
  }

  Future<void> _relay(MeshMessage message) async {
    if (!message.canRelay) return;
    final forwarded = message.relayed();
    _remember(forwarded);
    await transport.broadcast(forwarded.encode());
  }

  Future<void> _sendAck(MeshMessage original) async {
    final ack = MeshMessage(
      id: _uuid.v4(),
      type: MessageType.ack,
      senderId: identity.id,
      senderName: identity.name,
      receiverId: original.senderId,
      timestamp: _now().millisecondsSinceEpoch,
      content: '${original.hopCount}',
      refId: original.id,
      maxHops: original.maxHops,
    );
    _seen.add(ack.id);
    _remember(ack);
    await transport.broadcast(ack.encode());
  }

  Future<void> _onAck(MeshMessage ack) async {
    final refId = ack.refId;
    if (refId == null) return;
    _buffer.remove(refId);
    final stored = await store.get(refId);
    if (stored == null || !stored.outgoing) return;
    await store.save(stored.copyWith(
      status: DeliveryStatus.delivered,
      relayHops: int.tryParse(ack.content) ?? 0,
    ));
  }

  /// Moves an outgoing message's status forward, never backward.
  Future<void> _advance(String id, DeliveryStatus status) async {
    final stored = await store.get(id);
    if (stored == null || !stored.outgoing) return;
    if (stored.status.index >= status.index) return;
    await store.save(stored.copyWith(status: status));
  }

  void _remember(MeshMessage message) {
    _prune();
    _buffer.remove(message.id);
    _buffer[message.id] = _Buffered(
      message,
      _now().add(MeshConstants.relayBufferTtl),
    );
    while (_buffer.length > MeshConstants.relayBufferMaxSize) {
      _buffer.remove(_buffer.keys.first);
    }
  }

  void _prune() {
    final now = _now();
    _buffer.removeWhere((_, b) => b.expiresAt.isBefore(now));
  }

  Future<void> _flushTo(String nodeId) async {
    _prune();
    for (final entry in _buffer.values.toList()) {
      final message = entry.message;
      if (message.senderId == nodeId) continue;
      final ok = await transport.sendTo(nodeId, message.encode());
      if (ok && message.senderId == identity.id) {
        await _advance(message.id, DeliveryStatus.sent);
      }
    }
  }
}

class _Buffered {
  _Buffered(this.message, this.expiresAt);
  final MeshMessage message;
  final DateTime expiresAt;
}
