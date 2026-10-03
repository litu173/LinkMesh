import 'package:geolocator/geolocator.dart';

/// Best-effort GPS fix. Uses satellites only, so it works without internet;
/// returns null rather than throwing when no fix is available.
class LocationService {
  Position? _last;

  Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _last;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _last;
      }
      _last = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          // Plain GPS: Google's fused provider can stall without network.
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 10),
        ),
      );
    } catch (_) {
      try {
        _last = await Geolocator.getLastKnownPosition(
              forceAndroidLocationManager: true,
            ) ??
            _last;
      } catch (_) {}
    }
    return _last;
  }
}
