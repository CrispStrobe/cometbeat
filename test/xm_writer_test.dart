// test/xm_writer_test.dart
//
// FastTracker 2 `.xm` writer: writeXm must be the inverse of parseXm. Verified by
// round-trips (write → re-read preserves the module), which is the robust
// acceptance for a format with packing freedom.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/xm_writer_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:comet_beat/core/audio/mod/xm_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('output starts with the XM signature', () {
    final m0 = parseXm(File('test/fixtures/golden.xm').readAsBytesSync());
    final bytes = writeXm(m0);
    expect(String.fromCharCodes(bytes.sublist(0, 17)), 'Extended Module: ');
  });

  group('golden.xm survives parse → write → parse', () {
    late XmModule m0, m1;
    setUpAll(() {
      m0 = parseXm(File('test/fixtures/golden.xm').readAsBytesSync());
      m1 = parseXm(writeXm(m0));
    });

    test('header + structure', () {
      expect(m1.name, m0.name);
      expect(m1.channelCount, m0.channelCount);
      expect(m1.patterns.length, m0.patterns.length);
      expect(m1.instruments.length, m0.instruments.length);
      expect(m1.defaultTempo, m0.defaultTempo);
      expect(m1.defaultBpm, m0.defaultBpm);
      expect(m1.order, m0.order);
    });

    test('pattern cells', () {
      final p0 = m0.patterns.first, p1 = m1.patterns.first;
      expect(p1.numRows, p0.numRows);
      expect(p1.rows[0][0].note, p0.rows[0][0].note); // 49 (C-4)
      expect(p1.rows[0][0].instrument, p0.rows[0][0].instrument); // 1
      for (var r = 1; r < p0.numRows; r++) {
        expect(p1.rows[r][0].isEmpty, isTrue);
      }
    });

    test('sample PCM', () {
      final s0 = m0.instruments.first.samples.first;
      final s1 = m1.instruments.first.samples.first;
      expect(s1.pcm.length, s0.pcm.length);
      for (var i = 0; i < s0.pcm.length; i++) {
        expect(s1.pcm[i], closeTo(s0.pcm[i], 1e-6));
      }
    });
  });

  group('hand-built module round-trips (multi-channel, empty cells, 16-bit)',
      () {
    late XmModule m1;
    setUpAll(() {
      final rows = <List<XmCell>>[
        [
          const XmCell(note: 49, instrument: 1), // ch0: C-4, instr 1
          const XmCell(note: 61, instrument: 2, volume: 0x30), // ch1 + vol col
        ],
        [
          XmCell.empty, // ch0 empty
          const XmCell(note: 97), // ch1 note-off
        ],
      ];
      final src = XmModule(
        name: 'HANDMADE',
        channelCount: 2,
        defaultTempo: 5,
        defaultBpm: 140,
        order: const [0],
        patterns: [XmPattern(rows)],
        instruments: [
          XmInstrument(
            name: 'eight',
            samples: [
              XmSample(
                pcm: Float64List.fromList([0, 0.5, -0.5]),
              ),
            ],
          ),
          XmInstrument(
            name: 'sixteen',
            samples: [
              XmSample(
                volume: 48,
                sixteenBit: true,
                pcm: Float64List.fromList([0, 0.25, -0.25, 0.9]),
              ),
            ],
          ),
        ],
      );
      m1 = parseXm(writeXm(src));
    });

    test('header + channels', () {
      expect(m1.name, 'HANDMADE');
      expect(m1.channelCount, 2);
      expect(m1.defaultTempo, 5);
      expect(m1.defaultBpm, 140);
      expect(m1.instruments.length, 2);
    });

    test('cells (notes, instrument, volume column, empty, note-off)', () {
      final rows = m1.patterns.first.rows;
      expect(rows[0][0].note, 49);
      expect(rows[0][0].instrument, 1);
      expect(rows[0][1].note, 61);
      expect(rows[0][1].instrument, 2);
      expect(rows[0][1].volume, 0x30);
      expect(rows[1][0].isEmpty, isTrue);
      expect(rows[1][1].note, 97);
    });

    test('8-bit and 16-bit sample PCM survive', () {
      final s8 = m1.instruments[0].samples.first;
      expect(s8.sixteenBit, isFalse);
      expect(s8.pcm.length, 3);
      expect(s8.pcm[1], closeTo(0.5, 1 / 128));
      expect(s8.pcm[2], closeTo(-0.5, 1 / 128));

      final s16 = m1.instruments[1].samples.first;
      expect(s16.sixteenBit, isTrue);
      expect(s16.pcm.length, 4);
      expect(s16.pcm[1], closeTo(0.25, 1e-4));
      expect(s16.pcm[3], closeTo(0.9, 1e-4));
    });
  });
}
