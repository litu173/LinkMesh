import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkmesh/mesh/chunker.dart';
import 'package:linkmesh/mesh/seen_cache.dart';

void main() {
  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (i) => i % 251));

  group('Chunker', () {
    test('small frame is a single chunk', () {
      final chunks = Chunker.split(bytes(10), 20);
      expect(chunks, hasLength(1));
      expect(Reassembler().add('dev', chunks.single), bytes(10));
    });

    test('large frame splits and reassembles in any order', () {
      final frame = bytes(1000);
      final chunks = Chunker.split(frame, 20); // minimum BLE payload
      expect(chunks.length, (1000 / 14).ceil());
      expect(chunks.every((c) => c.length <= 20), isTrue);

      final r = Reassembler();
      final shuffled = [...chunks.reversed];
      Uint8List? result;
      for (final c in shuffled) {
        result = r.add('dev', c) ?? result;
      }
      expect(result, frame);
    });

    test('interleaved frames from different senders stay separate', () {
      final f1 = bytes(100);
      final f2 = Uint8List.fromList(List.filled(100, 7));
      final c1 = Chunker.split(f1, 30);
      final c2 = Chunker.split(f2, 30);
      final r = Reassembler();
      final done = <Uint8List>[];
      for (var i = 0; i < c1.length; i++) {
        final a = r.add('one', c1[i]);
        final b = r.add('two', c2[i]);
        if (a != null) done.add(a);
        if (b != null) done.add(b);
      }
      expect(done, [f1, f2]);
    });

    test('incomplete frames expire', () {
      var now = DateTime(2026);
      final r = Reassembler(
        timeout: const Duration(seconds: 5),
        clock: () => now,
      );
      final chunks = Chunker.split(bytes(100), 30);
      r.add('dev', chunks.first);
      now = now.add(const Duration(seconds: 10));
      for (final c in chunks.skip(1)) {
        expect(r.add('dev', c), isNull);
      }
    });

    test('garbage chunks are rejected', () {
      final r = Reassembler();
      expect(r.add('dev', Uint8List(3)), isNull);
      expect(r.add('dev', Uint8List.fromList([0, 0, 0, 1, 5, 2, 9])), isNull);
    });
  });

  group('SeenCache', () {
    test('dedupes and expires', () {
      var now = DateTime(2026);
      final cache = SeenCache(
        ttl: const Duration(minutes: 1),
        maxEntries: 10,
        clock: () => now,
      );
      expect(cache.add('a'), isTrue);
      expect(cache.add('a'), isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(cache.contains('a'), isFalse);
      expect(cache.add('a'), isTrue);
    });

    test('caps size by evicting oldest', () {
      final cache = SeenCache(ttl: const Duration(hours: 1), maxEntries: 2);
      cache
        ..add('a')
        ..add('b')
        ..add('c');
      expect(cache.contains('a'), isFalse);
      expect(cache.contains('c'), isTrue);
    });
  });
}
