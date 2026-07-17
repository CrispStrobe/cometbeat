// test/it_writer_test.dart
//
// Impulse Tracker `.it` writer: writeIt must be the inverse of parseIt (for the
// uncompressed sample path). Verified by round-trips (write → re-read preserves
// the module). Compressed source samples are written back UNCOMPRESSED — their
// PCM survives, the `compressed` flag does not.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/it_writer_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/it_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('output has the "IMPM" signature', () {
    final m0 = parseIt(File('test/fixtures/golden.it').readAsBytesSync());
    final bytes = writeIt(m0);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'IMPM');
  });

  group('golden.it survives parse → write → parse', () {
    late ItModule m0, m1;
    setUpAll(() {
      m0 = parseIt(File('test/fixtures/golden.it').readAsBytesSync());
      m1 = parseIt(writeIt(m0));
    });

    test('header + structure', () {
      expect(m1.name, m0.name);
      expect(m1.channelCount, m0.channelCount);
      expect(m1.samples.length, m0.samples.length);
      expect(m1.patterns.length, m0.patterns.length);
      expect(m1.order, m0.order);
      expect(m1.initialSpeed, m0.initialSpeed);
      expect(m1.initialTempo, m0.initialTempo);
    });

    test('pattern cells', () {
      final p0 = m0.patterns.first, p1 = m1.patterns.first;
      expect(p1.numRows, p0.numRows);
      expect(p1.rows[0][0].note, p0.rows[0][0].note); // 60 (C-5)
      expect(p1.rows[0][0].instrument, p0.rows[0][0].instrument); // 1
      for (var r = 1; r < p0.numRows; r++) {
        expect(p1.rows[r][0].isEmpty, isTrue);
      }
    });

    test('sample PCM survives (incl. compressed sources → uncompressed)', () {
      for (var i = 0; i < m0.samples.length; i++) {
        final s0 = m0.samples[i], s1 = m1.samples[i];
        expect(
          s1.compressed,
          isFalse,
          reason: 'sample $i written uncompressed',
        );
        expect(s1.sixteenBit, s0.sixteenBit, reason: 'sample $i bit depth');
        expect(s1.pcm.length, s0.pcm.length, reason: 'sample $i length');
        final tol = s0.sixteenBit ? 1e-4 : 1 / 128;
        for (var k = 0; k < s0.pcm.length; k++) {
          expect(s1.pcm[k], closeTo(s0.pcm[k], tol), reason: 'sample $i[$k]');
        }
      }
    });
  });

  group('hand-built module round-trips (multi-channel, note-off, 8/16-bit)',
      () {
    late ItModule m1;
    setUpAll(() {
      final rows = <List<ItCell>>[
        [
          const ItCell(note: 60, instrument: 1, volpan: 40), // ch0
          const ItCell(note: 72, instrument: 2), // ch1
        ],
        [
          ItCell.empty, // ch0
          const ItCell(note: ItCell.noteOff), // ch1 (255)
        ],
      ];
      final src = ItModule(
        name: 'HANDIT',
        channelCount: 2,
        initialTempo: 135,
        order: const [0],
        patterns: [ItPattern(rows, 2)],
        samples: [
          ItSample(
            name: 'eight',
            length: 3,
            pcm: Float64List.fromList([0, 0.5, -0.5]),
          ),
          ItSample(
            name: 'sixteen',
            defaultVolume: 48,
            sixteenBit: true,
            length: 4,
            pcm: Float64List.fromList([0, 0.25, -0.25, 0.9]),
          ),
        ],
      );
      m1 = parseIt(writeIt(src));
    });

    test('header + channels', () {
      expect(m1.name, 'HANDIT');
      expect(m1.channelCount, 2);
      expect(m1.initialTempo, 135);
      expect(m1.samples.length, 2);
    });

    test('cells (note, instrument, volpan, empty, note-off)', () {
      final rows = m1.patterns.first.rows;
      expect(rows[0][0].note, 60);
      expect(rows[0][0].instrument, 1);
      expect(rows[0][0].volpan, 40);
      expect(rows[0][1].note, 72);
      expect(rows[0][1].instrument, 2);
      expect(rows[1][0].isEmpty, isTrue);
      expect(rows[1][1].note, ItCell.noteOff);
    });

    test('8-bit and 16-bit sample PCM survive', () {
      final s8 = m1.samples[0];
      expect(s8.sixteenBit, isFalse);
      expect(s8.pcm.length, 3);
      expect(s8.pcm[1], closeTo(0.5, 1 / 128));
      expect(s8.pcm[2], closeTo(-0.5, 1 / 128));

      final s16 = m1.samples[1];
      expect(s16.sixteenBit, isTrue);
      expect(s16.pcm.length, 4);
      expect(s16.pcm[1], closeTo(0.25, 1e-4));
      expect(s16.pcm[3], closeTo(0.9, 1e-4));
    });
  });
}
