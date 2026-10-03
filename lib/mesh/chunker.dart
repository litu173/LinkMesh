import 'dart:math';
import 'dart:typed_data';

/// Splits frames into link-sized chunks and reassembles them.
///
/// Chunk layout: `[frameId: 4 bytes BE][index: 1][count: 1][payload...]`.
/// Up to 255 chunks per frame, which at the minimum BLE MTU (20-byte
/// payload) still allows ~3.5 KB frames — far above a text message.
class Chunker {
  Chunker._();

  static const headerSize = 6;
  static const maxChunks = 255;
  static final _random = Random.secure();

  static List<Uint8List> split(Uint8List frame, int maxChunkSize) {
    final payloadSize = maxChunkSize - headerSize;
    if (payloadSize <= 0) {
      throw ArgumentError.value(maxChunkSize, 'maxChunkSize', 'too small');
    }
    final count = max(1, (frame.length / payloadSize).ceil());
    if (count > maxChunks) {
      throw ArgumentError('Frame of ${frame.length} bytes needs $count chunks');
    }
    final frameId = _random.nextInt(1 << 32);
    return List.generate(count, (i) {
      final start = i * payloadSize;
      final end = min(start + payloadSize, frame.length);
      final chunk = Uint8List(headerSize + end - start);
      ByteData.sublistView(chunk).setUint32(0, frameId);
      chunk[4] = i;
      chunk[5] = count;
      chunk.setRange(headerSize, chunk.length, frame, start);
      return chunk;
    });
  }
}

/// Collects chunks per sender and yields complete frames.
class Reassembler {
  Reassembler({
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration timeout;
  final DateTime Function() _now;
  final _pending = <String, _PartialFrame>{};

  /// Feeds one chunk from [source]. Returns the frame once complete.
  Uint8List? add(String source, Uint8List chunk) {
    _evictStale();
    if (chunk.length < Chunker.headerSize) return null;
    final frameId = ByteData.sublistView(chunk).getUint32(0);
    final index = chunk[4];
    final count = chunk[5];
    if (count == 0 || index >= count) return null;
    final payload = Uint8List.sublistView(chunk, Chunker.headerSize);
    if (count == 1) return Uint8List.fromList(payload);

    final key = '$source/$frameId';
    final partial = _pending.putIfAbsent(
      key,
      () => _PartialFrame(count, _now()),
    );
    if (partial.parts.length != count) return null; // inconsistent header
    partial.parts[index] = Uint8List.fromList(payload);
    if (partial.parts.any((p) => p == null)) return null;

    _pending.remove(key);
    final builder = BytesBuilder(copy: false);
    for (final p in partial.parts) {
      builder.add(p!);
    }
    return builder.takeBytes();
  }

  void _evictStale() {
    final cutoff = _now().subtract(timeout);
    _pending.removeWhere((_, p) => p.startedAt.isBefore(cutoff));
  }
}

class _PartialFrame {
  _PartialFrame(int count, this.startedAt)
      : parts = List<Uint8List?>.filled(count, null);

  final List<Uint8List?> parts;
  final DateTime startedAt;
}
