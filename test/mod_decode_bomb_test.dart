// Decode-bomb regression guards for the tracker module importers.
//
// The S3M / IT / XM readers size allocations from counts declared in the file
// header (pattern count, rows-per-pattern, channels). Those are u16 fields, so
// a tiny crafted module can declare 65535 of each and drive the parser into
// billions of cell allocations — a multi-second hang / OOM from a ~1 KB file.
// These tests craft such modules and assert the parser stays fast and produces
// bounded output (the readers clamp to each format's real addressable maxima).
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tracker parsers reject decode-bomb headers cheaply', () {
    test('S3M patNum=65535 does not allocate 65535 patterns', () {
      final b = Uint8List(96);
      b[0x2C] = 0x53;
      b[0x2D] = 0x43;
      b[0x2E] = 0x52;
      b[0x2F] = 0x4D; // "SCRM"
      final d = ByteData.sublistView(b);
      d.setUint16(0x24, 65535, Endian.little); // patNum
      for (var i = 0; i < 32; i++) {
        b[0x40 + i] = 0; // all channels enabled (max grid width)
      }
      final sw = Stopwatch()..start();
      final m = parseS3m(b);
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'clamped pattern count must keep parse fast',
      );
      expect(m.patterns.length, lessThanOrEqualTo(256));
    });

    test('IT patNum×numRows bomb stays bounded', () {
      // patNum pattern-offset u32s @0xC0, all pointing at a header declaring
      // numRows=65535.
      const patNum = 256;
      const hdrAt = 0xC0 + patNum * 4;
      final b = Uint8List(hdrAt + 16);
      b[0] = 0x49;
      b[1] = 0x4D;
      b[2] = 0x50;
      b[3] = 0x4D; // "IMPM"
      final d = ByteData.sublistView(b);
      d.setUint16(0x26, patNum, Endian.little);
      for (var i = 0; i < patNum; i++) {
        d.setUint32(0xC0 + i * 4, hdrAt, Endian.little);
      }
      d.setUint16(hdrAt + 0, 4, Endian.little); // packedLen
      d.setUint16(hdrAt + 2, 65535, Endian.little); // numRows (bomb)
      final sw = Stopwatch()..start();
      final m = parseIt(b);
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(m.patterns.length, lessThanOrEqualTo(256));
      for (final p in m.patterns) {
        expect(p.rows.length, lessThanOrEqualTo(256));
      }
    });

    test('XM numChannels×numRows bomb stays bounded', () {
      final sig = 'Extended Module: '.codeUnits;
      const hdrSize = 0x114;
      const patAt = 0x3C + hdrSize;
      final b = Uint8List(patAt + 9);
      for (var i = 0; i < sig.length; i++) {
        b[i] = sig[i];
      }
      final d = ByteData.sublistView(b);
      d.setUint32(0x3C, hdrSize, Endian.little);
      d.setUint16(0x44, 65535, Endian.little); // numChannels (bomb)
      d.setUint16(0x46, 1, Endian.little); // numPatterns
      d.setUint32(patAt, 9, Endian.little); // patternHeaderLength
      d.setUint16(patAt + 5, 65535, Endian.little); // numRows (bomb)
      d.setUint16(patAt + 7, 0, Endian.little); // packedSize
      final sw = Stopwatch()..start();
      final m = parseXm(b);
      expect(sw.elapsedMilliseconds, lessThan(2000));
      for (final p in m.patterns) {
        expect(p.rows.length, lessThanOrEqualTo(256));
        for (final row in p.rows) {
          expect(row.length, lessThanOrEqualTo(64));
        }
      }
    });
  });
}
