import 'dart:async';

import '../mesh/mesh_router.dart';
import '../models/stored_message.dart';
import '../ui/format.dart';
import 'mesh_bridge.dart';

/// Decides how to tell the user about incoming messages and SOS alerts:
/// a notification (with its channel sound) when they aren't looking at
/// the conversation, or just the sound when they are.
class AlertService {
  AlertService({required this.router, required this.bridge}) {
    _subs
      ..add(router.incomingMessages.listen(_onMessage))
      ..add(router.sosAlerts.listen(_onSos));
  }

  /// Re-alert for the same person's SOS at most this often; repeats in
  /// between update the notification silently.
  static const sosRealertAfter = Duration(minutes: 2);

  final MeshRouter router;
  final MeshBridge bridge;
  final _subs = <StreamSubscription<StoredMessage>>[];
  final _lastSosAlert = <String, DateTime>{};

  /// True while the app is on screen.
  bool appVisible = false;

  /// Peer whose chat is open, if any.
  String? openChatPeer;

  Future<void> _onMessage(StoredMessage stored) async {
    final m = stored.message;
    if (appVisible && openChatPeer == m.senderId) {
      await bridge.playSound(AlertSound.message);
      return;
    }
    final via = stored.relayHops > 0 ? ' (${relayLabel(stored.relayHops)})' : '';
    await bridge.notifyMessage(
      peerId: m.senderId,
      title: '${_name(m.senderName, m.senderId)}$via',
      body: m.content,
    );
  }

  Future<void> _onSos(StoredMessage stored) async {
    final m = stored.message;
    final now = DateTime.now();
    final last = _lastSosAlert[m.senderId];
    final alert = last == null || now.difference(last) > sosRealertAfter;
    if (alert) _lastSosAlert[m.senderId] = now;

    final where = m.hasLocation
        ? '📍 ${m.lat!.toStringAsFixed(5)}, ${m.lng!.toStringAsFixed(5)}'
        : 'Location unavailable';
    final hops =
        stored.relayHops == 0 ? 'nearby' : relayLabel(stored.relayHops);
    await bridge.notifySos(
      senderId: m.senderId,
      title: '🆘 SOS from ${_name(m.senderName, m.senderId)}',
      body: '${m.content}\n$where · $hops · ${formatTimestamp(m.timestamp)}',
      alert: alert,
    );
  }

  String _name(String name, String id) =>
      name.isNotEmpty ? name : (id.length > 8 ? id.substring(0, 8) : id);

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
