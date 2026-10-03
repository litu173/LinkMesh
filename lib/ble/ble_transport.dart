import 'dart:async';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide CharacteristicProperties;

import '../core/constants.dart';
import '../mesh/chunker.dart';
import '../mesh/transport.dart';
import '../models/node_identity.dart';
import '../models/peer.dart';

/// BLE link layer. Every node plays both roles at once:
///
/// * **Peripheral** (ble_peripheral): advertises the LinkMesh service and runs
///   a GATT server with an *inbox* characteristic that neighbours write
///   frames into, plus an *identity* characteristic they read.
/// * **Central** (flutter_blue_plus): scans for the service on a duty cycle,
///   connects to the strongest peers and writes frames into their inbox.
///
/// So each direction of a link is a separate GATT connection: A sends to B
/// over A's connection to B. Frames larger than the MTU are chunked.
class BleTransport implements MeshTransport {
  BleTransport({required NodeIdentity Function() identity})
      : _identity = identity; // ignore: prefer_initializing_formals

  /// flutter_blue_plus requires a license declaration. `nonprofit` covers
  /// personal, nonprofit and educational use; for-profit use needs a paid
  /// commercial license (see the flutter_blue_plus LICENSE file).
  static const fbpLicense = License.nonprofit;

  final NodeIdentity Function() _identity;
  final _service = Guid(BleConstants.serviceUuid);
  final _inboxUuid = Guid(BleConstants.inboxCharUuid);
  final _identityUuid = Guid(BleConstants.identityCharUuid);

  final _links = <String, _Link>{};
  final _reassembler = Reassembler();

  final _statusCtrl = StreamController<TransportStatus>.broadcast();
  final _incomingCtrl = StreamController<Uint8List>.broadcast();
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _linkedCtrl = StreamController<String>.broadcast();

  TransportStatus _status = TransportStatus.idle;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _scanTimer;
  Timer? _maintenanceTimer;
  bool _peripheralConfigured = false;
  bool _online = false;

  @override
  TransportStatus get status => _status;

  @override
  Stream<TransportStatus> get statusChanges => _statusCtrl.stream;

  @override
  Stream<Uint8List> get incoming => _incomingCtrl.stream;

  @override
  Stream<List<Peer>> get peerChanges => _peersCtrl.stream;

  @override
  Stream<String> get peerLinked => _linkedCtrl.stream;

  @override
  List<Peer> get peers {
    final seen = <String>{};
    final result = <Peer>[];
    final ordered = _links.values.where((l) => !l.ignored).toList()
      ..sort((a, b) {
        final byState = _rank(a.state).compareTo(_rank(b.state));
        return byState != 0 ? byState : b.rssi.compareTo(a.rssi);
      });
    for (final link in ordered) {
      // A peer may show up under several addresses (MAC rotation); keep the
      // best-ranked one per node id.
      final nodeId = link.nodeId;
      if (nodeId != null && !seen.add(nodeId)) continue;
      result.add(link.toPeer());
    }
    return result;
  }

  static int _rank(PeerLinkState s) => switch (s) {
        PeerLinkState.connected => 0,
        PeerLinkState.connecting => 1,
        PeerLinkState.discovered => 2,
        PeerLinkState.disconnected => 3,
      };

  @override
  Future<void> start() async {
    if (_adapterSub != null) return;
    if (!await FlutterBluePlus.isSupported) {
      _setStatus(TransportStatus.unsupported);
      return;
    }
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _goOnline();
      } else if (state == BluetoothAdapterState.off) {
        _goOffline();
        _setStatus(TransportStatus.bluetoothOff);
      }
    });
  }

  @override
  Future<void> stop() async {
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _goOffline();
    _setStatus(TransportStatus.idle);
  }

  Future<void> _goOnline() async {
    if (_online) return;
    _online = true;
    try {
      await _startPeripheral();
    } catch (e) {
      // Some phones can't advertise. We can still send, but nobody can
      // write to us, so this node is send-only.
      debugPrint('LinkMesh: peripheral role unavailable: $e');
    }
    _scanSub = FlutterBluePlus.onScanResults.listen(_onScanResults);
    _scanTimer = Timer.periodic(BleConstants.scanPeriod, (_) => _scanOnce());
    _maintenanceTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _maintain());
    unawaited(_scanOnce());
    _setStatus(TransportStatus.running);
  }

  Future<void> _goOffline() async {
    if (!_online) return;
    _online = false;
    _scanTimer?.cancel();
    _maintenanceTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
      await BlePeripheral.stopAdvertising();
    } catch (_) {}
    for (final link in _links.values) {
      await link.connectionSub?.cancel();
      try {
        await link.device.disconnect();
      } catch (_) {}
    }
    _links.clear();
    _emitPeers();
  }

  // ---------------------------------------------------------------------------
  // Peripheral role

  Future<void> _startPeripheral() async {
    if (!_peripheralConfigured) {
      await BlePeripheral.initialize();
      BlePeripheral.setWriteRequestCallback(_onWriteRequest);
      BlePeripheral.setReadRequestCallback(_onReadRequest);
      await BlePeripheral.addService(
        BleService(
          uuid: BleConstants.serviceUuid,
          primary: true,
          characteristics: [
            BleCharacteristic(
              uuid: BleConstants.inboxCharUuid,
              properties: [CharacteristicProperties.write.index],
              permissions: [AttributePermissions.writeable.index],
              value: null,
            ),
            BleCharacteristic(
              uuid: BleConstants.identityCharUuid,
              properties: [CharacteristicProperties.read.index],
              permissions: [AttributePermissions.readable.index],
              value: null,
            ),
          ],
        ),
      );
      _peripheralConfigured = true;
    }
    // No localName: a 128-bit UUID plus a name overflows the 31-byte legacy
    // advertisement. Peers read our name from the identity characteristic.
    await BlePeripheral.startAdvertising(services: [BleConstants.serviceUuid]);
  }

  WriteRequestResult? _onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    if (value == null || !_sameUuid(characteristicId, _inboxUuid)) return null;
    final frame = _reassembler.add(deviceId, value);
    if (frame != null) _incomingCtrl.add(frame);
    return null;
  }

  ReadRequestResult? _onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    if (!_sameUuid(characteristicId, _identityUuid)) return null;
    final bytes = _identity().encode();
    return ReadRequestResult(
      value: offset < bytes.length ? bytes.sublist(offset) : Uint8List(0),
    );
  }

  bool _sameUuid(String raw, Guid guid) {
    try {
      return Guid(raw) == guid;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Central role

  Future<void> _scanOnce() async {
    if (!_online || FlutterBluePlus.isScanningNow) return;
    try {
      await FlutterBluePlus.startScan(
        withServices: [_service],
        timeout: BleConstants.scanWindow,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      debugPrint('LinkMesh: scan failed: $e');
    }
  }

  void _onScanResults(List<ScanResult> results) {
    final now = DateTime.now();
    final sorted = [...results]..sort((a, b) => b.rssi.compareTo(a.rssi));
    for (final r in sorted) {
      final link = _links.putIfAbsent(
        r.device.remoteId.str,
        () => _Link(r.device),
      );
      link
        ..rssi = r.rssi
        ..lastSeen = now;
      unawaited(_maybeConnect(link));
    }
    _emitPeers();
  }

  Future<void> _maybeConnect(_Link link) async {
    if (!_online || link.ignored) return;
    if (link.state == PeerLinkState.connected ||
        link.state == PeerLinkState.connecting) {
      return;
    }
    if (link.rssi < BleConstants.minConnectRssi) return;
    if (DateTime.now().isBefore(link.nextAttempt)) return;
    final active = _links.values.where((l) =>
        l.state == PeerLinkState.connected ||
        l.state == PeerLinkState.connecting);
    if (active.length >= BleConstants.maxOutboundLinks) return;

    // Claim the slot synchronously so concurrent scan callbacks don't race.
    link.state = PeerLinkState.connecting;
    _emitPeers();
    try {
      await link.device.connect(
        license: fbpLicense,
        timeout: BleConstants.connectTimeout,
        mtu: BleConstants.requestedMtu,
      );
      final services = await link.device.discoverServices();
      final service = services.where((s) => s.uuid == _service).firstOrNull;
      final inbox = service?.characteristics
          .where((c) => c.uuid == _inboxUuid)
          .firstOrNull;
      final identityChar = service?.characteristics
          .where((c) => c.uuid == _identityUuid)
          .firstOrNull;
      if (inbox == null || identityChar == null) {
        throw StateError('LinkMesh service incomplete');
      }
      final identity = NodeIdentity.tryDecode(await identityChar.read());
      if (identity == null) throw StateError('Unreadable identity');

      final isSelf = identity.id == _identity().id;
      final isDuplicate = _links.values.any((l) =>
          l != link &&
          l.nodeId == identity.id &&
          l.state == PeerLinkState.connected);
      if (isSelf || isDuplicate) {
        await link.device.disconnect();
        link
          ..ignored = isSelf
          ..nodeId = identity.id
          ..state = PeerLinkState.disconnected
          // A duplicate address may become the live one if the other drops.
          ..nextAttempt = DateTime.now().add(BleConstants.peerStaleAfter);
        _emitPeers();
        return;
      }

      link
        ..nodeId = identity.id
        ..name = identity.name
        ..inbox = inbox
        ..state = PeerLinkState.connected;
      link.connectionSub = link.device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onDisconnected(link);
      });
      _emitPeers();
      _linkedCtrl.add(identity.id);
    } catch (e) {
      debugPrint('LinkMesh: connect to ${link.device.remoteId} failed: $e');
      link
        ..state = PeerLinkState.disconnected
        ..inbox = null
        ..nextAttempt = DateTime.now().add(BleConstants.reconnectBackoff);
      try {
        await link.device.disconnect();
      } catch (_) {}
      _emitPeers();
    }
  }

  void _onDisconnected(_Link link) {
    link.connectionSub?.cancel();
    link
      ..connectionSub = null
      ..inbox = null
      ..state = PeerLinkState.disconnected
      // Brief pause, then let the next scan reconnect if it's still around.
      ..nextAttempt = DateTime.now().add(const Duration(seconds: 3));
    _emitPeers();
  }

  Future<void> _maintain() async {
    final cutoff = DateTime.now().subtract(BleConstants.peerStaleAfter);
    _links.removeWhere((_, l) =>
        l.state != PeerLinkState.connected &&
        l.state != PeerLinkState.connecting &&
        l.lastSeen.isBefore(cutoff));
    for (final link in _links.values.toList()) {
      if (link.state != PeerLinkState.connected) continue;
      try {
        link
          ..rssi = await link.device.readRssi()
          ..lastSeen = DateTime.now();
      } catch (_) {}
    }
    _emitPeers();
  }

  // ---------------------------------------------------------------------------
  // Sending

  @override
  Future<int> broadcast(Uint8List frame) async {
    final targets = _links.values.where((l) => l.inbox != null).toList();
    final results = await Future.wait(targets.map((l) => _write(l, frame)));
    return results.where((ok) => ok).length;
  }

  @override
  Future<bool> sendTo(String nodeId, Uint8List frame) async {
    final link = _links.values
        .where((l) => l.nodeId == nodeId && l.inbox != null)
        .firstOrNull;
    return link == null ? false : _write(link, frame);
  }

  /// Writes are queued per link so chunks of different frames never interleave.
  Future<bool> _write(_Link link, Uint8List frame) {
    final result = link.writeQueue.then((_) => _writeNow(link, frame));
    link.writeQueue = result.then((_) {});
    return result;
  }

  Future<bool> _writeNow(_Link link, Uint8List frame) async {
    final inbox = link.inbox;
    if (inbox == null) return false;
    try {
      final chunkSize = link.device.mtuNow - 3;
      for (final chunk in Chunker.split(frame, chunkSize)) {
        await inbox.write(chunk, timeout: 5);
      }
      return true;
    } catch (e) {
      debugPrint('LinkMesh: write to ${link.nodeId} failed: $e');
      return false;
    }
  }

  void _setStatus(TransportStatus status) {
    _status = status;
    _statusCtrl.add(status);
  }

  void _emitPeers() => _peersCtrl.add(peers);
}

class _Link {
  _Link(this.device);

  final BluetoothDevice device;
  String? nodeId;
  String? name;
  int rssi = -100;
  DateTime lastSeen = DateTime.now();
  PeerLinkState state = PeerLinkState.discovered;
  DateTime nextAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  BluetoothCharacteristic? inbox;
  StreamSubscription<BluetoothConnectionState>? connectionSub;
  Future<void> writeQueue = Future.value();

  /// Our own advertisement, seen through the scanner.
  bool ignored = false;

  Peer toPeer() => Peer(
        address: device.remoteId.str,
        nodeId: nodeId,
        name: name,
        state: state,
        rssi: rssi,
        lastSeen: lastSeen,
      );
}
