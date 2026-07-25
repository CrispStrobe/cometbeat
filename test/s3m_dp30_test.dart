// test/s3m_dp30_test.dart
//
// Unit tests for the ST3 "DP30ADPCM" 4-bit ADPCM sample decoder in
// s3m_reader.dart (decodeDp30Adpcm), plus its integration through parseS3m and
// the degenerate-input preserve-only fallback.
//
// The decoder implements the well-known ST3 / libopenmpt ADPCM variant:
//   • the first 16 bytes are a signed-int8 delta table;
//   • the rest is a nibble stream (two per byte, LOW nibble first);
//   • an 8-bit accumulator (mod 256) is advanced by table[nibble] per sample,
//     reinterpreted as signed int8, then normalized by /128.
//
// These tests prove the decoder on a HAND-COMPUTED reference vector — there is
// no real packed `.s3m` in the corpus to validate against.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/s3m_dp30_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A signed 16-byte delta table (as unsigned on-disk bytes) exercising both
/// signs and later triggering an 8-bit accumulator wraparound.
///   index: 0  1  2  3  4   5   6   7   8   9   10   11  12   13   14   15
///   value: 0  1  2  3  4  -1  -2  -3  10  20  -10  -20  50  -50  100 -100
final _table = <int>[
  0,
  1,
  2,
  3,
  4,
  255,
  254,
  253,
  10,
  20,
  246,
  236,
  50,
  206,
  100,
  156,
];

/// A 0x50-byte type-1 instrument header with [length] samples and pack==1.
List<int> _packedHeader({required int length}) {
  final h = List<int>.filled(0x50, 0);
  h[0x00] = 1; // type: PCM sample
  h[0x10] = length & 0xFF;
  h[0x11] = (length >> 8) & 0xFF;
  h[0x12] = (length >> 16) & 0xFF;
  h[0x13] = (length >> 24) & 0xFF;
  h[0x1C] = 64; // volume
  h[0x1E] = 1; // pack = DP30 ADPCM
  h[0x4C] = 0x53; // "SCRS"
  h[0x4D] = 0x43;
  h[0x4E] = 0x52;
  h[0x4F] = 0x53;
  return h;
}

/// A single-channel, single-pattern module wrapping [sample].
S3mModule _module(S3mSample sample) => S3mModule(
      title: 'DP30',
      channelCount: 1,
      order: const [0],
      samples: [sample],
      patterns: [
        S3mPattern(
          List.generate(
            64,
            (_) => List<S3mCell>.filled(1, S3mCell.empty),
            growable: false,
          ),
        ),
      ],
    );

void main() {
  group('decodeDp30Adpcm (algorithm on a hand-computed vector)', () {
    // Nibble stream (LOW nibble first per byte):
    //   0x21 -> low 1, high 2
    //   0x08 -> low 8, high 0
    //   0x9E -> low 14, high 9
    // Sample-order nibbles: 1, 2, 8, 0, 14, 9
    //   table lookups:      1, 2, 10, 0, 100, 20
    // accumulator (mod 256): 1, 3, 13, 13, 113, 133->(-123 signed)
    final packed = Uint8List.fromList([..._table, 0x21, 0x08, 0x9E]);
    final expected = Float64List.fromList(
      [1, 3, 13, 13, 113, -123].map((v) => v / 128.0).toList(),
    );

    test('decodes the reference vector exactly (incl. 8-bit wraparound)', () {
      final out = decodeDp30Adpcm(packed, 6);
      expect(out.length, 6);
      expect(out, expected);
      // The last sample proves the accumulator wraps 133 -> -123 (signed int8).
      expect(out.last, closeTo(-123 / 128.0, 1e-12));
    });

    test('a truncated nibble stream stops early instead of throwing', () {
      // Only 2 nibble bytes present -> at most 4 samples decodable.
      final short = Uint8List.fromList([..._table, 0x21, 0x08]);
      final out = decodeDp30Adpcm(short, 6);
      expect(out.length, 4);
      expect(out, Float64List.fromList(expected.take(4).toList()));
    });

    test('fewer than 16 bytes (no table) yields an empty result', () {
      expect(decodeDp30Adpcm(Uint8List(15), 6), isEmpty);
      expect(decodeDp30Adpcm(Uint8List.fromList(_table), 0), isEmpty);
    });
  });

  group('parseS3m integration', () {
    test('a full packed (pack==1) sample decodes to non-empty pcm', () {
      final packed = Uint8List.fromList([..._table, 0x21, 0x08, 0x9E]);
      final expected = Float64List.fromList(
        [1, 3, 13, 13, 113, -123].map((v) => v / 128.0).toList(),
      );
      final src = _module(
        S3mSample(
          name: 'dp30',
          pcm: Float64List(0),
          packed: true,
          rawHeader: _packedHeader(length: 6),
          rawData: packed,
        ),
      );

      final s = parseS3m(writeS3m(src)).samples.single;
      expect(s.packed, isTrue);
      expect(s.isEmpty, isFalse);
      expect(s.pcm, isNotEmpty);
      expect(s.pcm, expected); // decoded via the ADPCM path, not raw bytes
      // Raw packed block preserved for byte-identical same-format re-export.
      expect(s.rawData, packed);
    });
  });

  group('degenerate-input preserve-only fallback', () {
    test('an all-zero delta table decodes to all-zero -> pcm left empty', () {
      // Table of all zeros => every delta is 0 => the decode is all-zero, which
      // the reader treats as degenerate and discards (preserve-only).
      final zeroTable = List<int>.filled(16, 0);
      final packed = Uint8List.fromList([...zeroTable, 0x11, 0x22, 0x33]);

      // The raw decoder still returns a (zero-filled) vector...
      final raw = decodeDp30Adpcm(packed, 6);
      expect(raw.length, 6);
      expect(raw.every((v) => v == 0.0), isTrue);

      // ...but parseS3m applies the fallback: pcm empty, packed + rawData kept.
      final src = _module(
        S3mSample(
          name: 'zero',
          pcm: Float64List(0),
          packed: true,
          rawHeader: _packedHeader(length: 6),
          rawData: packed,
        ),
      );
      final s = parseS3m(writeS3m(src)).samples.single;
      expect(s.packed, isTrue);
      expect(s.isEmpty, isFalse); // survives (not dropped as empty)
      expect(s.pcm, isEmpty); // degenerate decode discarded
      expect(s.rawData, packed); // raw block still preserved
    });

    test('a packed block with no nibble data does not crash', () {
      // Header claims 6 samples but only the 16-byte table is present.
      final packed = Uint8List.fromList(List<int>.filled(16, 0));
      final src = _module(
        S3mSample(
          name: 'notab',
          pcm: Float64List(0),
          packed: true,
          rawHeader: _packedHeader(length: 6),
          rawData: packed,
        ),
      );
      final s = parseS3m(writeS3m(src)).samples.single;
      expect(s.packed, isTrue);
      expect(s.pcm, isEmpty);
    });
  });
}
