import 'dart:async';

import '../core/constants.dart';
import '../mesh/mesh_router.dart';
import 'location_service.dart';

/// Repeats an SOS broadcast with the latest location until cancelled.
///
/// Each repeat is a new mesh message (new id), so nodes that already relayed
/// the previous one still forward it, and late arrivals in range receive it.
class SosService {
  SosService({
    required this.router,
    required this.location,
    this.interval = MeshConstants.sosInterval,
  });

  final MeshRouter router;
  final LocationService location;
  final Duration interval;

  Timer? _timer;
  String _text = '';
  final _active = StreamController<bool>.broadcast();

  bool get isActive => _timer != null;
  Stream<bool> get activeChanges => _active.stream;

  void start(String text) {
    if (isActive) return;
    _text = text.trim().isEmpty ? 'SOS — I need help' : text.trim();
    _timer = Timer.periodic(interval, (_) => _broadcast());
    _active.add(true);
    unawaited(_broadcast());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _active.add(false);
  }

  Future<void> _broadcast() async {
    final position = await location.currentPosition();
    if (!isActive) return;
    await router.sendSos(
      _text,
      lat: position?.latitude,
      lng: position?.longitude,
    );
  }
}
