// ProTracker `.mod` codec — the authoritative round-trip suite. The golden
// fixture below is assembled BYTE-BY-BYTE independently of the codec (an
// oracle), so parseMod and writeMod are each checked against known-correct data,
// not just against each other. Also round-trips any real `.mod` files dropped in
// test/fixtures/.
//
// Pure Dart: no device, no Flutter widgets.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal but complete, spec-valid ProTracker `.mod`, assembled here by hand
/// (the oracle). One sample (8 bytes PCM, finetune −2, volume 48), one pattern
/// with two notes on channel 0, 4 channels, song length 1.
Uint8List _goldenBytes() {
  final b = BytesBuilder();
  void str(String s, int len) {
    final out = List<int>.filled(len, 0);
    for (var i = 0; i < s.length && i < len; i++) {
      out[i] = s.codeUnitAt(i);
    }
    b.add(out);
  }

  void u16(int v) {
    b
      ..addByte((v >> 8) & 0xFF)
      ..addByte(v & 0xFF); // big-endian
  }

  str('TESTMOD', 20); // title
  // Sample 1.
  str('sine', 22);
  u16(4); // length in words = 8 bytes
  b.addByte(0x0E); // finetune −2 (signed nibble)
  b.addByte(48); // volume
  u16(0); // repeat point (words)
  u16(0); // repeat length (words)
  // Samples 2..31 — empty descriptors (30 zero bytes each).
  for (var s = 2; s <= 31; s++) {
    b.add(List<int>.filled(30, 0));
  }
  b.addByte(1); // song length
  b.addByte(127); // restart
  b.add(List<int>.filled(128, 0)); // order table (all → pattern 0)
  str('M.K.', 4); // signature (4 channels)

  // Pattern 0: 64 rows × 4 channels × 4 bytes.
  final pat = List<int>.filled(64 * 4 * 4, 0);
  // Row 0, ch 0: sample 1, period 428 (C-2), no effect → 01 AC 10 00
  pat[0] = 0x01;
  pat[1] = 0xAC;
  pat[2] = 0x10;
  pat[3] = 0x00;
  // Row 4, ch 0: sample 1, period 214, effect C (set vol) param 20 → 00 D6 1C 20
  const o = (4 * 4 + 0) * 4;
  pat[o] = 0x00;
  pat[o + 1] = 0xD6;
  pat[o + 2] = 0x1C;
  pat[o + 3] = 0x20;
  b.add(pat);

  // Sample 1 PCM (signed 8-bit, written as bytes).
  b.add(
    const [0, 64, 127, 64, 0, -64, -128, -64].map((v) => v & 0xFF).toList(),
  );
  return b.toBytes();
}

void main() {
  group('parseMod (import)', () {
    test('decodes the golden module correctly', () {
      final m = parseMod(_goldenBytes());
      expect(m.title, 'TESTMOD');
      expect(m.channelCount, 4);
      expect(m.order, [0]);
      expect(m.samples.length, 31);

      final s = m.samples[0];
      expect(s.name, 'sine');
      expect(s.volume, 48);
      expect(s.finetune, -2); // signed nibble
      expect(s.pcm, Int8List.fromList([0, 64, 127, 64, 0, -64, -128, -64]));
      expect(m.samples[1].isEmpty, isTrue);

      expect(m.patterns.length, 1);
      final rows = m.patterns[0].rows;
      expect(rows.length, 64);
      expect(rows[0][0], const ModCell(sample: 1, period: 428));
      expect(
        rows[4][0],
        const ModCell(sample: 1, period: 214, effect: 12, effectParam: 32),
      );
      expect(rows[1][0].isEmpty, isTrue);
    });

    test('rejects too-short input', () {
      expect(
        () => parseMod(Uint8List(100)),
        throwsA(isA<ModFormatException>()),
      );
    });
  });

  group('writeMod (export)', () {
    test('reproduces the golden bytes exactly (byte-stable)', () {
      final golden = _goldenBytes();
      final written = writeMod(parseMod(golden));
      expect(written, equals(golden));
    });
  });

  group('round-trip', () {
    test('parse → write → parse is stable', () {
      final first = parseMod(_goldenBytes());
      final second = parseMod(writeMod(first));
      expect(second.title, first.title);
      expect(second.channelCount, first.channelCount);
      expect(second.order, first.order);
      expect(second.samples[0].pcm, first.samples[0].pcm);
      expect(second.samples[0].finetune, first.samples[0].finetune);
      expect(second.patterns[0].rows[0][0], first.patterns[0].rows[0][0]);
      expect(second.patterns[0].rows[4][0], first.patterns[0].rows[4][0]);
    });

    test('period ↔ MIDI helpers agree with the golden notes', () {
      expect(periodToMidi(428), modNoteBaseMidi + 12); // C-2
      expect(periodToMidi(214), modNoteBaseMidi + 24); // C-3
      expect(periodToMidi(0), -1);
      expect(midiToPeriod(periodToMidi(428)), 428);
    });
  });

  group('real fixtures (test/fixtures/*.mod)', () {
    final dir = Directory('test/fixtures');
    final files = dir.existsSync()
        ? dir.listSync().whereType<File>().where(
              (f) => f.path.toLowerCase().endsWith('.mod'),
            )
        : <File>[];

    if (files.isEmpty) {
      test(
        'no real .mod fixtures present (skipped)',
        () {
          // Drop real ProTracker .mod files into test/fixtures/ to exercise the
          // codec on wild data; each is parsed and round-tripped below.
        },
        skip: 'add .mod files to test/fixtures/',
      );
    }

    for (final file in files) {
      test('round-trips ${file.uri.pathSegments.last}', () {
        final bytes = file.readAsBytesSync();
        final a = parseMod(bytes);
        final b = parseMod(writeMod(a)); // write then re-read must be stable
        expect(b.title, a.title);
        expect(b.channelCount, a.channelCount);
        expect(b.order, a.order);
        expect(b.patterns.length, a.patterns.length);
        for (var p = 0; p < a.patterns.length; p++) {
          expect(b.patterns[p].rows, a.patterns[p].rows);
        }
        for (var s = 0; s < 31; s++) {
          expect(b.samples[s].pcm, a.samples[s].pcm);
        }
      });
    }
  });
}
