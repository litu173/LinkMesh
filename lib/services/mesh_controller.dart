import 'dart:async';

import 'package:flutter/widgets.dart';

import '../mesh/transport.dart';
import '../models/peer.dart';
import 'alert_service.dart';
import 'mesh_bridge.dart';
import 'permissions.dart';

/// Starts the mesh and keeps it running in the right mode for whether the
/// app is on screen, and keeps the background-service notification current.
class MeshController {
  MeshController({
    required this.transport,
    required this.bridge,
    required this.alerts,
  }) {
    _peerSub = transport.peerChanges.listen(_updateStatus);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _onLifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached,
    );
  }

  final MeshTransport transport;
  final MeshBridge bridge;
  final AlertService alerts;

  late final StreamSubscription<List<Peer>> _peerSub;
  late final AppLifecycleListener _lifecycle;
  MeshPermissions? _permissions;
  bool _visible = false;
  int _lastConnected = -1;

  MeshPermissions? get permissions => _permissions;

  /// No prompts: used at process start, which may be a reboot with no UI.
  Future<void> startIfPermitted() async {
    final permissions = await checkMeshPermissions();
    _permissions = permissions;
    if (permissions.canRunHeadless(await bridge.sdkInt())) {
      await _start(permissions);
    }
  }

  /// Prompts for permissions, then starts. Called from the UI.
  Future<MeshPermissions> requestAndStart() async {
    final permissions = await requestMeshPermissions();
    _permissions = permissions;
    if (permissions.bluetooth) await _start(permissions);
    return permissions;
  }

  Future<void> _start(MeshPermissions permissions) async {
    await transport.start();
    if (await bridge.isBackgroundEnabled()) {
      // GPS in the background (for SOS) is only granted to a service
      // started while the app is visible.
      await bridge.startService(
        withLocation: permissions.location && _visible,
      );
    }
  }

  Future<bool> isBackgroundEnabled() => bridge.isBackgroundEnabled();

  Future<void> setBackgroundEnabled(bool enabled) async {
    if (enabled) {
      await bridge.startService(withLocation: _permissions?.location ?? false);
    } else {
      await bridge.stopService();
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    // `inactive` covers brief interruptions like the notification shade.
    _visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    alerts.appVisible = state == AppLifecycleState.resumed;
    transport.setBackground(!_visible);
  }

  void _updateStatus(List<Peer> peers) {
    final connected =
        peers.where((p) => p.state == PeerLinkState.connected).length;
    if (connected == _lastConnected) return;
    _lastConnected = connected;
    unawaited(bridge.setStatus(switch (connected) {
      0 => 'Listening for nearby devices',
      1 => '1 device connected · receiving and relaying',
      _ => '$connected devices connected · receiving and relaying',
    }));
  }

  Future<void> dispose() async {
    _lifecycle.dispose();
    await _peerSub.cancel();
  }
}
