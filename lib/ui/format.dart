String _two(int n) => n.toString().padLeft(2, '0');

/// `14:05` today, `3/10 14:05` otherwise.
String formatTimestamp(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final time = '${_two(t.hour)}:${_two(t.minute)}';
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? time : '${t.day}/${t.month} $time';
}

String relayLabel(int hops) =>
    hops == 1 ? 'via 1 device' : 'via $hops devices';
