/// Bounded, time-limited set of message ids used for duplicate suppression.
class SeenCache {
  SeenCache({
    required this.ttl,
    required this.maxEntries,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;

  // Insertion-ordered, so the oldest entries are always first.
  final _entries = <String, DateTime>{};

  bool contains(String id) {
    _evict();
    return _entries.containsKey(id);
  }

  /// Records [id]. Returns true if it was not already present.
  bool add(String id) {
    _evict();
    if (_entries.containsKey(id)) return false;
    _entries[id] = _now();
    if (_entries.length > maxEntries) _entries.remove(_entries.keys.first);
    return true;
  }

  void _evict() {
    final cutoff = _now().subtract(ttl);
    while (_entries.isNotEmpty && _entries.values.first.isBefore(cutoff)) {
      _entries.remove(_entries.keys.first);
    }
  }
}
