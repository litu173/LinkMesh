import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class MeshPermissions {
  const MeshPermissions({required this.bluetooth, required this.location});

  /// Scan, connect and advertise. Without these the mesh can't run.
  final bool bluetooth;

  /// Needed for BLE scanning on Android 11 and below, and for SOS
  /// coordinates everywhere. The mesh still starts without it.
  final bool location;

  /// Whether the mesh can run with no UI to ask for anything. On Android 11
  /// and below scanning also needs location.
  bool canRunHeadless(int sdkInt) => bluetooth && (sdkInt >= 31 || location);
}

const _bluetooth = [
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
  Permission.bluetoothAdvertise,
];

// macOS (used as a desktop test node) prompts for Bluetooth itself on
// first use and has no permission_handler implementation.
const _desktop = MeshPermissions(bluetooth: true, location: true);

/// Asks for everything LinkMesh uses. Notifications are requested too but
/// don't gate the mesh.
Future<MeshPermissions> requestMeshPermissions() async {
  if (!Platform.isAndroid) return _desktop;
  final statuses = await [
    ..._bluetooth,
    Permission.locationWhenInUse,
    Permission.notification,
  ].request();

  // On Android 11 and below the Bluetooth permissions report granted.
  bool ok(Permission p) => statuses[p]?.isGranted ?? false;
  return MeshPermissions(
    bluetooth: _bluetooth.every(ok),
    location: ok(Permission.locationWhenInUse),
  );
}

/// Current permission state, without prompting. Safe to call with no UI.
Future<MeshPermissions> checkMeshPermissions() async {
  if (!Platform.isAndroid) return _desktop;
  var bluetooth = true;
  for (final p in _bluetooth) {
    bluetooth = bluetooth && await p.status.isGranted;
  }
  return MeshPermissions(
    bluetooth: bluetooth,
    location: await Permission.locationWhenInUse.status.isGranted,
  );
}
