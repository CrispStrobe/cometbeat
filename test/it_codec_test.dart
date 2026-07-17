// test/it_codec_test.dart
//
// Impulse Tracker `.it` reader suite:
//   • a hand-authored golden oracle (test/fixtures/golden.it, license-clean,
//     committed) whose every value is known — the byte-for-byte contract;
//   • a live test over a real module (test/fixtures/wild_local.it) — skipped when
//     absent, since copyrighted modules are NOT committed (gitignored). Drop any
//     `.it` in as wild_local.it to fuzz the reader against it.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/it_codec_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseIt — golden oracle (GOLDENIT)', () {
    late ItModule m;

    setUpAll(() {
      final f = File('test/fixtures/golden.it');
      expect(
        f.existsSync(),
        isTrue,
        reason: 'golden.it must be committed; regenerate via make_golden_it.py',
      );
      m = parseIt(f.readAsBytesSync());
    });

    test('header fields', () {
      expect(m.name, 'GOLDENIT');
      expect(m.channelCount, 1);
      expect(m.instrumentCount, 0);
      expect(m.samples.length, 3);
      expect(m.patterns.length, 1);
      expect(m.initialSpeed, 6);
      expect(m.initialTempo, 125);
      expect(m.order, [0]);
    });

    test('pattern 0: 4 rows, row0 ch0 = note 60 (C-5) + instrument 1', () {
      final p = m.patterns.first;
      expect(p.numRows, 4);
      expect(p.channelCount, 1);
      final cell = p.rows[0][0];
      expect(cell.note, 60);
      expect(cell.instrument, 1);
      expect(itNoteToMidi(cell.note), 60); // middle C
      for (var r = 1; r < 4; r++) {
        expect(p.rows[r][0].isEmpty, isTrue, reason: 'row $r should be empty');
      }
    });

    test('sample 0: 8-bit signed uncompressed, [0,10,20,-10,-20]/128', () {
      final s = m.samples[0];
      expect(s.sixteenBit, isFalse);
      expect(s.compressed, isFalse);
      expect(s.length, 5);
      expect(s.pcm.length, 5);
      final raw = [0, 10, 20, -10, -20];
      for (var i = 0; i < raw.length; i++) {
        expect(s.pcm[i], closeTo(raw[i] / 128, 1e-9));
      }
    });

    // Compressed blocks validated against libxmp itsex.c (44/44 round-trips).
    test(
        'sample 1: 8-bit IT215-compressed → [0,5,-5,40,-40,120,-120,0,0,3]/128',
        () {
      final s = m.samples[1];
      expect(s.sixteenBit, isFalse);
      expect(s.compressed, isTrue);
      expect(s.length, 10);
      expect(s.pcm.length, 10);
      final raw = [0, 5, -5, 40, -40, 120, -120, 0, 0, 3];
      for (var i = 0; i < raw.length; i++) {
        expect(s.pcm[i], closeTo(raw[i] / 128, 1e-9), reason: 'sample1[$i]');
      }
    });

    test(
        'sample 2: 16-bit IT215-compressed → '
        '[0,100,-100,5000,-5000,32000,-32000,0,1,-1]/32768', () {
      final s = m.samples[2];
      expect(s.sixteenBit, isTrue);
      expect(s.compressed, isTrue);
      expect(s.length, 10);
      expect(s.pcm.length, 10);
      final raw = [0, 100, -100, 5000, -5000, 32000, -32000, 0, 1, -1];
      for (var i = 0; i < raw.length; i++) {
        expect(s.pcm[i], closeTo(raw[i] / 32768, 1e-9), reason: 'sample2[$i]');
      }
    });
  });

  group('parseIt — malformed input', () {
    test('too short / bad signature throws ItFormatException', () {
      expect(
        () => parseIt(Uint8List.fromList(List.filled(8, 0))),
        throwsA(isA<ItFormatException>()),
      );
      expect(
        () => parseIt(Uint8List.fromList('NOT AN IT FILE!!'.codeUnits)),
        throwsA(isA<ItFormatException>()),
      );
    });
  });

  group('parseIt — live real module (skipped if absent)', () {
    final f = File('test/fixtures/wild_local.it');
    final present = f.existsSync();

    test(
      'parses "terrascape intro music" structure',
      () {
        final m = parseIt(f.readAsBytesSync());
        // verified out-of-band with Python:
        expect(m.name, 'terrascape intro music');
        expect(m.order.length, 19);
        expect(m.instrumentCount, 12);
        expect(m.samples.length, 12);
        expect(m.patterns.length, 17);
        expect(m.initialSpeed, 6);
        expect(m.initialTempo, 125);
        expect(m.channelCount, 8);
        // pattern 0 has 64 rows
        expect(m.patterns.first.numRows, 64);
        // sample 0: 16-bit uncompressed, 35584 samples
        final s0 = m.samples.first;
        expect(s0.sixteenBit, isTrue);
        expect(s0.compressed, isFalse);
        expect(s0.length, 35584);
        expect(s0.pcm.length, 35584);
        // every sample's PCM stays in range
        for (final s in m.samples) {
          for (final v in s.pcm) {
            expect(v, inInclusiveRange(-1.0, 1.0));
          }
        }
      },
      skip: present ? false : 'test/fixtures/wild_local.it not present',
    );
  });
}
