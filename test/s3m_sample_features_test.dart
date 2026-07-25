// test/s3m_sample_features_test.dart
//
// Exercises the extended S3M sample-header support in s3m_reader.dart /
// s3m_writer.dart: STEREO (flag 0x02), AdLib (type 2), and PACKED (pack==1)
// samples, plus a plain-mono regression pin. Each case is driven through the
// writer → reader roundtrip so both directions are covered.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/s3m_sample_features_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/mod/s3m_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signed 8-bit ints → normalized float (÷128), matching S3mSample.pcm.
Float64List _i8(List<int> v) =>
    Float64List.fromList([for (final b in v) b / 128]);

/// A minimal single-channel, single-pattern module wrapping [samples].
S3mModule _module(List<S3mSample> samples) => S3mModule(
      title: 'FEAT',
      channelCount: 1,
      order: const [0],
      samples: samples,
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

/// A hand-built 0x50-byte instrument header with [type] at 0x00, "SCRS" at
/// 0x4C, and the given fields patched in. memseg is left 0 (writer patches it).
List<int> _header({
  required int type,
  int length = 0,
  int volume = 64,
  int pack = 0,
  int flags = 0,
  List<int> opl = const [],
}) {
  final h = List<int>.filled(0x50, 0);
  h[0x00] = type;
  // 0x10 u32 length
  h[0x10] = length & 0xFF;
  h[0x11] = (length >> 8) & 0xFF;
  h[0x12] = (length >> 16) & 0xFF;
  h[0x13] = (length >> 24) & 0xFF;
  // OPL register bytes for AdLib live at 0x10..0x1B (overwrite length region).
  for (var i = 0; i < opl.length && i < 12; i++) {
    h[0x10 + i] = opl[i] & 0xFF;
  }
  h[0x1C] = volume & 0xFF;
  h[0x1E] = pack & 0xFF;
  h[0x1F] = flags & 0xFF;
  // "SCRS" marker at 0x4C.
  h[0x4C] = 0x53;
  h[0x4D] = 0x43;
  h[0x4E] = 0x52;
  h[0x4F] = 0x53;
  return h;
}

void main() {
  group('stereo 8-bit PCM sample', () {
    // Left and right channels of equal length with DISTINCT values.
    final left = _i8([0, 40, -40, 80]);
    final right = _i8([10, -10, 20, -20]);

    late S3mModule parsed;
    setUpAll(() {
      final src = _module([
        S3mSample(name: 'st', volume: 55, pcm: left, pcmRight: right),
      ]);
      parsed = parseS3m(writeS3m(src));
    });

    test('parseS3m yields a non-null right channel with the expected values',
        () {
      final s = parsed.samples.single;
      expect(s.pcmRight, isNotNull);
      expect(s.pcm, left);
      expect(s.pcmRight, right);
      // The two channels really are distinct.
      expect(s.pcmRight, isNot(equals(s.pcm)));
    });

    test('write → read preserves BOTH channels (roundtrip)', () {
      final s = parseS3m(writeS3m(parsed)).samples.single;
      expect(s.pcm, left);
      expect(s.pcmRight, right);
    });

    test('a truncated right channel degrades gracefully', () {
      // Build bytes directly then chop the trailing right-channel bytes off.
      final full = writeS3m(
        _module([
          S3mSample(name: 'st', volume: 55, pcm: left, pcmRight: right),
        ]),
      );
      // Drop the final 2 right-channel samples; the reader must not throw and
      // must return at most `length` right samples (here fewer, or null).
      final chopped = Uint8List.sublistView(full, 0, full.length - 2);
      final s = parseS3m(chopped).samples.single;
      expect(s.pcm, left); // left channel is intact
      if (s.pcmRight != null) {
        expect(s.pcmRight!.length, lessThanOrEqualTo(left.length));
      }
    });
  });

  group('AdLib (type 2) instrument', () {
    final opl = List<int>.generate(12, (i) => 0x40 + i); // distinct OPL bytes

    late S3mModule parsed;
    setUpAll(() {
      final adlib = S3mSample(
        name: 'opl',
        volume: 48,
        pcm: Float64List(0),
        adlib: true,
        adlibData: opl,
        rawHeader: _header(type: 2, volume: 48, opl: opl),
      );
      parsed = parseS3m(writeS3m(_module([adlib])));
    });

    test('is recognised as AdLib and NOT dropped as empty', () {
      final s = parsed.samples.single;
      expect(s.adlib, isTrue);
      expect(s.isEmpty, isFalse); // survives instead of being S3mSample.empty()
      // The OPL patch is now rendered to an audible FM approximation, so pcm is
      // populated (playback-only; the header still re-exports byte-identically).
      expect(s.pcm, isNotEmpty);
      expect(s.pcm.every((v) => v.isFinite && v.abs() <= 1.0), isTrue);
    });

    test('preserves the 12 OPL register bytes', () {
      final s = parsed.samples.single;
      expect(s.adlibData, isNotEmpty);
      expect(s.adlibData.length, 12);
      expect(s.adlibData, opl);
    });
  });

  group('packed (pack==1 / DP30 ADPCM) sample', () {
    // packedLen the reader captures = 16 + (length+1)/2. Pick length so that
    // equals our rawData size (24 bytes) for an exact roundtrip check.
    const length = 16; // 16 + (16+1)/2 = 16 + 8 = 24
    final rawPacked =
        Uint8List.fromList(List<int>.generate(24, (i) => i * 7 & 0xFF));

    late S3mModule parsed;
    setUpAll(() {
      final packedSample = S3mSample(
        name: 'dp30',
        volume: 40,
        pcm: Float64List(0),
        packed: true,
        rawHeader: _header(type: 1, length: length, volume: 40, pack: 1),
        rawData: rawPacked,
      );
      parsed = parseS3m(writeS3m(_module([packedSample])));
    });

    test('flags packed and is not dropped', () {
      final s = parsed.samples.single;
      expect(s.packed, isTrue);
      expect(s.isEmpty, isFalse);
    });

    test('decodes pcm and preserves the raw packed bytes', () {
      final s = parsed.samples.single;
      // Since the DP30 ADPCM decoder landed, a non-degenerate packed block now
      // decodes to PCM (previously asserted empty). The raw packed bytes are
      // still preserved verbatim for byte-identical same-format re-export.
      expect(s.pcm, isNotEmpty);
      expect(s.rawData, isNotNull);
      expect(s.rawData, rawPacked);
    });
  });

  test('plain mono 8-bit PCM sample parses + roundtrips exactly (regression)',
      () {
    final mono = _i8([0, 10, -10, 60, -60, 120, -120, 30]);
    final src = _module([S3mSample(name: 'mono', volume: 62, pcm: mono)]);

    final once = parseS3m(writeS3m(src)).samples.single;
    expect(once.name, 'mono');
    expect(once.volume, 62);
    expect(once.pcm, mono);
    expect(once.pcmRight, isNull);
    expect(once.adlib, isFalse);
    expect(once.packed, isFalse);

    // Second cycle is byte-identical (no drift).
    final firstBytes = writeS3m(src);
    final secondBytes = writeS3m(parseS3m(firstBytes));
    expect(secondBytes, firstBytes);
  });
}
