@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/stem_files_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stems written in blocks map back exactly, and release deletes them',
      () {
    if (!stemFilesSupported) {
      markTestSkipped('no mmap here');
      return;
    }
    const n = 10007;
    final rnd = math.Random(3);
    final want = {
      for (final name in ['vocals', 'drums'])
        name: (
          Float32List.fromList([for (var i = 0; i < n; i++) rnd.nextDouble()]),
          Float32List.fromList([for (var i = 0; i < n; i++) -rnd.nextDouble()]),
        ),
    };
    final writer = StemFileWriter(newStemFolder(), n);
    // Out of order and in uneven blocks, through views with offsets.
    for (final (a, b) in [(4000, n), (0, 1234), (1234, 4000)]) {
      for (final e in want.entries) {
        writer.write(
          e.key,
          a,
          Float32List.sublistView(e.value.$1, a, b),
          Float32List.sublistView(e.value.$2, a, b),
        );
      }
    }
    final files = writer.close();
    expect(files.map((f) => f.name), ['vocals', 'drums']);
    final mapped = mapStemFiles(files, n, 44100);
    for (final s in mapped.stems) {
      expect(s.frames, n);
      expect(s.sampleRate, 44100);
      expect(s.left, want[s.name]!.$1);
      expect(s.right, want[s.name]!.$2);
    }
    mapped.release();
    for (final f in files) {
      expect(File(f.path).existsSync(), isFalse);
    }
    mapped.release(); // idempotent
  });

  test('a new folder clears the previous split', () {
    if (!stemFilesSupported) {
      markTestSkipped('no mmap here');
      return;
    }
    final a = newStemFolder();
    File('${a.path}/x.f32').writeAsBytesSync([1, 2, 3, 4]);
    final b = newStemFolder();
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
  });
}
