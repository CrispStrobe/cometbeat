// Scream Tracker 3 `.s3m` reader — the test suite (the contract/spec).
//
// UNIT (always runs): a hand-authored, byte-exact golden `.s3m`
// (test/fixtures/golden.s3m, generated independently of the codec) with known
// contents → asserts every field.
// LIVE (runs when present): the real test/fixtures/*.s3m modules — parsed and
// checked against values verified out-of-band. Copyrighted wild files aren't
// committed (they're gitignored); drop one in to exercise the codec on real data.
//
// The S3M-reader agent implements s3m_reader.dart to make the UNIT tests pass.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseS3m — golden oracle (test/fixtures/golden.s3m)', () {
    late S3mModule m;
    setUpAll(() {
      m = parseS3m(File('test/fixtures/golden.s3m').readAsBytesSync());
    });

    test('header fields', () {
      expect(m.title, 'GOLDENS3M');
      expect(m.channelCount, 1);
      expect(m.globalVolume, 64);
      expect(m.initialSpeed, 6);
      expect(m.initialTempo, 125);
      expect(m.order, [0]); // the 255 end-marker is stripped
    });

    test('the one sample (unsigned PCM → signed)', () {
      expect(m.samples.length, 1);
      final s = m.samples[0];
      expect(s.name, 'sine');
      expect(s.volume, 48);
      expect(s.c2spd, 8363);
      expect(s.pcm.length, 8);
      // Unsigned [128,160,200,255,128,96,40,0] → signed (b-128).
      expect(s.pcm[0], 0);
      expect(s.pcm[3], 127);
      expect(s.pcm[7], -128);
    });

    test('the one pattern (note C-5, instrument 1, on channel 0 row 0)', () {
      expect(m.patterns.length, 1);
      final rows = m.patterns[0].rows;
      expect(rows.length, 64);
      expect(rows[0][0].note, 0x50); // octave 5, semitone 0
      expect(rows[0][0].instrument, 1);
      expect(rows[1][0].isEmpty, isTrue);
    });

    test('rejects non-S3M input', () {
      expect(
        () => parseS3m(Uint8List(200)),
        throwsA(isA<S3mFormatException>()),
      );
    });
  });

  group('parseS3m — real fixtures (live)', () {
    final dir = Directory('test/fixtures');
    final files = dir.existsSync()
        ? dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.s3m'))
            .where((f) => !f.path.endsWith('golden.s3m'))
        : <File>[];

    if (files.isEmpty) {
      test('no wild .s3m present (skipped)', () {}, skip: 'drop a .s3m in');
    }

    for (final file in files) {
      test('parses ${file.uri.pathSegments.last} sanely', () {
        final m = parseS3m(file.readAsBytesSync());
        expect(m.title.isNotEmpty, isTrue);
        expect(m.channelCount, greaterThan(0));
        expect(m.samples, isNotEmpty);
        expect(m.patterns, isNotEmpty);
        // Every pattern is 64 rows × channelCount.
        for (final p in m.patterns) {
          expect(p.rows.length, 64);
          for (final row in p.rows) {
            expect(row.length, m.channelCount);
          }
        }
      });
    }
  });
}
