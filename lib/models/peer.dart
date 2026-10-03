import '../core/constants.dart';

enum PeerLinkState { discovered, connecting, connected, disconnected }

/// What the UI shows for a peer, per the spec's three connection states.
enum SignalQuality { connected, weak, disconnected }

class Peer {
  const Peer({
    required this.address,
    required this.state,
    required this.rssi,
    required this.lastSeen,
    this.nodeId,
    this.name,
  });

  /// Transport-level address (BLE MAC on Android).
  final String address;

  /// Mesh node id, known once the peer's identity has been read.
  final String? nodeId;
  final String? name;
  final PeerLinkState state;
  final int rssi;
  final DateTime lastSeen;

  String get displayName => name ?? nodeId?.substring(0, 8) ?? address;

  SignalQuality get quality {
    if (state != PeerLinkState.connected) return SignalQuality.disconnected;
    return rssi < BleConstants.weakRssi
        ? SignalQuality.weak
        : SignalQuality.connected;
  }

  /// 0–4 bars, for signal strength indicators.
  int get bars {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }
}
