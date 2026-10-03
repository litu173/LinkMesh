/// Shared protocol and tuning constants.
///
/// Changing any UUID breaks compatibility with devices running older builds.
library;

class MeshConstants {
  MeshConstants._();

  /// Receiver id used for messages addressed to every node (SOS).
  static const broadcastId = '*';

  /// Default relay budget for a new message.
  static const defaultMaxHops = 5;

  /// How long a node keeps a message to re-send to peers it meets later
  /// (store-and-forward for intermittent links).
  static const relayBufferTtl = Duration(minutes: 15);
  static const relayBufferMaxSize = 200;

  /// How long a message id is remembered for duplicate suppression.
  static const seenTtl = Duration(hours: 1);
  static const seenMaxEntries = 5000;

  static const sosInterval = Duration(seconds: 20);
}

class BleConstants {
  BleConstants._();

  static const serviceUuid = '6e4c0001-8f3a-4b7e-9c1d-1a2b3c4d5e6f';

  /// Centrals write mesh frames (chunked) here.
  static const inboxCharUuid = '6e4c0002-8f3a-4b7e-9c1d-1a2b3c4d5e6f';

  /// Centrals read the node's identity JSON `{"id":..,"name":..}` here.
  static const identityCharUuid = '6e4c0003-8f3a-4b7e-9c1d-1a2b3c4d5e6f';

  /// Android caps concurrent GATT connections (~7); stay below it.
  static const maxOutboundLinks = 5;

  /// Ignore peers weaker than this; links that far out mostly fail.
  static const minConnectRssi = -95;

  /// RSSI below which a connected link is shown as "weak".
  static const weakRssi = -85;

  /// Scan duty cycle: scan for [scanWindow] every [scanPeriod] to save battery.
  static const scanWindow = Duration(seconds: 8);
  static const scanPeriod = Duration(seconds: 20);

  /// A discovered (not connected) peer is dropped after this long unseen.
  static const peerStaleAfter = Duration(seconds: 60);

  static const connectTimeout = Duration(seconds: 12);
  static const reconnectBackoff = Duration(seconds: 15);

  static const requestedMtu = 512;
}
