import 'package:permission_handler/permission_handler.dart';

class MeshPermissions {
  const MeshPermissions({required this.bluetooth, required this.location});

  /// Scan, connect and advertise. Without these the mesh can't run.
  final bool bluetooth;

  /// Needed for BLE scanning on Android 11 and below, and for SOS
  /// coordinates everywhere. The mesh still starts without it.
  final bool location;
}

Future<MeshPermissions> requestMeshPermissions() async {
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
  ].request();

  // On Android 11 and below the Bluetooth permissions report granted.
  bool ok(Permission p) => statuses[p]?.isGranted ?? false;
  return MeshPermissions(
    bluetooth: ok(Permission.bluetoothScan) &&
        ok(Permission.bluetoothConnect) &&
        ok(Permission.bluetoothAdvertise),
    location: ok(Permission.locationWhenInUse),
  );
}
