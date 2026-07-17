// test/xm_codec_test.dart
//
// FastTracker 2 `.xm` reader suite:
//   • a hand-authored golden oracle (test/fixtures/golden.xm, license-clean,
//     committed) whose every value is known — the byte-for-byte contract;
//   • a live test over a real module (test/fixtures/wild_local.xm) — skipped when
//     absent, since copyrighted modules are NOT committed (gitignored). Drop any
//     `.xm` in as wild_local.xm to fuzz the reader against it.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/xm_codec_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/xm_module.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseXm — golden oracle (GOLDENXM)', () {
    late XmModule m;

    setUpAll(() {
      final f = File('test/fixtures/golden.xm');
      expect(
        f.existsSync(),
        isTrue,
        reason: 'golden.xm must be committed; regenerate via make_golden_xm.py',
      );
      m = parseXm(f.readAsBytesSync());
    });

    test('header fields', () {
      expect(m.name, 'GOLDENXM');
      expect(m.channelCount, 1);
      expect(m.patterns.length, 1);
      expect(m.instruments.length, 1);
      expect(m.defaultTempo, 6);
      expect(m.defaultBpm, 125);
      expect(m.order, [0]);
    });

    test('pattern 0: 4 rows, row0 = note 49 (C-4) + instrument 1', () {
      final p = m.patterns.first;
      expect(p.numRows, 4);
      expect(p.channelCount, 1);
      final cell = p.rows[0][0];
      expect(cell.note, 49);
      expect(cell.instrument, 1);
      expect(xmNoteToMidi(cell.note), 60); // C-4
      // rows 1..3 are empty
      for (var r = 1; r < 4; r++) {
        expect(p.rows[r][0].isEmpty, isTrue, reason: 'row $r should be empty');
      }
    });

    test('instrument 0: one 8-bit sample, delta-decoded to [0,10,20,10,0]/128',
        () {
      final ins = m.instruments.first;
      expect(ins.samples.length, 1);
      final s = ins.samples.first;
      expect(s.sixteenBit, isFalse);
      expect(s.pcm.length, 5);
      // raw decoded = [0,10,20,10,0]; normalized by /128
      expect(s.pcm[0], closeTo(0 / 128, 1e-9));
      expect(s.pcm[1], closeTo(10 / 128, 1e-9));
      expect(s.pcm[2], closeTo(20 / 128, 1e-9));
      expect(s.pcm[3], closeTo(10 / 128, 1e-9));
      expect(s.pcm[4], closeTo(0 / 128, 1e-9));
    });
  });

  group('parseXm — malformed input', () {
    test('too short / bad signature throws XmFormatException', () {
      expect(
        () => parseXm(Uint8List.fromList(List.filled(8, 0))),
        throwsA(isA<XmFormatException>()),
      );
      expect(
        () => parseXm(Uint8List.fromList('NOT AN XM FILE!!!'.codeUnits)),
        throwsA(isA<XmFormatException>()),
      );
    });
  });

  group('parseXm — live real module (skipped if absent)', () {
    final f = File('test/fixtures/wild_local.xm');
    final present = f.existsSync();

    test(
      'parses "The final support" structure',
      () {
        final m = parseXm(f.readAsBytesSync());
        // verified out-of-band with Python:
        expect(m.name, 'The final support');
        expect(m.channelCount, 24);
        expect(m.patterns.length, 20);
        expect(m.instruments.length, 77);
        expect(m.defaultTempo, 4);
        expect(m.defaultBpm, 125);
        // structural sanity: every pattern is rows × 24 cells
        for (final p in m.patterns) {
          if (p.numRows > 0) expect(p.channelCount, 24);
        }
        expect(m.order, isNotEmpty);
      },
      skip: present ? false : 'test/fixtures/wild_local.xm not present',
    );
  });
}
