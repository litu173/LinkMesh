import 'dart:typed_data';

import '../models/peer.dart';

enum TransportStatus { idle, bluetoothOff, unsupported, running }

/// A link layer that moves opaque frames between neighbouring nodes.
///
/// The mesh router only talks to this interface, so BLE today and WiFi
/// Direct / LoRa later plug in without touching routing logic.
abstract class MeshTransport {
  TransportStatus get status;
  Stream<TransportStatus> get statusChanges;

  /// Complete frames received from any neighbour.
  Stream<Uint8List> get incoming;

  List<Peer> get peers;
  Stream<List<Peer>> get peerChanges;

  /// Emits a node id each time a link to that node becomes usable, so the
  /// router can flush buffered messages to it.
  Stream<String> get peerLinked;

  Future<void> start();
  Future<void> stop();

  /// Sends [frame] to every linked neighbour. Returns how many accepted it.
  Future<int> broadcast(Uint8List frame);

  /// Sends [frame] to one neighbour. Returns false if it isn't linked or the
  /// write failed.
  Future<bool> sendTo(String nodeId, Uint8List frame);
}
