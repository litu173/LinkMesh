import 'dart:async';

import 'package:flutter/services.dart';

/// Dart side of the `linkmesh/service` channel: the Android foreground
/// service, notifications and sounds. Every call is best-effort: on
/// platforms without the native side (tests, iOS) it quietly does nothing.
class MeshBridge {
  MeshBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'serviceStopped') _stopped.add(null);
    });
  }

  static const _channel = MethodChannel('linkmesh/service');
  final _stopped = StreamController<void>.broadcast();

  /// Fires when the user stops background relay from the notification.
  Stream<void> get serviceStopped => _stopped.stream;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> startService({required bool withLocation}) =>
      _call('start', {'withLocation': withLocation});
  Future<void> stopService() => _call('stop');
  Future<bool> isBackgroundEnabled() async =>
      await _call<bool>('isEnabled') ?? false;
  Future<void> setStatus(String text) => _call('setStatus', {'text': text});

  Future<void> notifyMessage({
    required String peerId,
    required String title,
    required String body,
  }) =>
      _call('notifyMessage', {'peerId': peerId, 'title': title, 'body': body});

  Future<void> notifySos({
    required String senderId,
    required String title,
    required String body,
    required bool alert,
  }) =>
      _call('notifySos', {
        'senderId': senderId,
        'title': title,
        'body': body,
        'alert': alert,
      });

  Future<void> cancelMessageNotification(String peerId) =>
      _call('cancel', {'key': 'msg:$peerId'});

  Future<void> playSound(AlertSound sound) =>
      _call('playSound', {'kind': sound.name});

  /// Chat to open because the user tapped a notification, if any.
  Future<String?> takePendingChat() => _call<String>('takePendingChat');

  Future<int> sdkInt() async => await _call<int>('sdkInt') ?? 0;

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _call<bool>('isIgnoringBatteryOptimizations') ?? true;
  Future<void> requestBatteryExemption() => _call('requestBatteryExemption');
}

enum AlertSound { message, sos }
