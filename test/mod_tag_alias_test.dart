// The 4-byte signature at offset 0x438 (1080) both selects a module's channel
// count AND is metadata a same-format read→write roundtrip must preserve.
// Several distinct tags map to the same channel count (8ch: OCTA/CD81/FLT8/8CHN;
// 4ch: M.K./M!K!/FLT4/4CHN), so the writer must NOT force one canonical tag when
// the module was read from disk — it must reproduce the source bytes verbatim.
// A synthetically-built module (no stored signature) still gets the computed
// canonical tag (M.K./M!K!/%dCHN).
//
// Pure Dart: no device, no Flutter widgets.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal spec-valid `.mod` carrying [sig], with pattern data sized for
/// [channels] and [patternCount] patterns (order references each so parseMod
/// reconstructs the full count). Layout: 20-byte title, 31×30-byte sample
/// descriptors, song length, restart, 128-byte order table, the 4-byte
/// signature at 1080, then the patterns from 1084 (no PCM: all samples empty).
Uint8List _modWith(
  String sig, {
  required int channels,
  int patternCount = 1,
}) {
  final b = BytesBuilder();
  void str(String s, int len) {
    final out = List<int>.filled(len, 0);
    for (var i = 0; i < s.length && i < len; i++) {
      out[i] = s.codeUnitAt(i);
    }
    b.add(out);
  }

  str('ALIASTEST', 20); // title
  for (var s = 1; s <= 31; s++) {
    b.add(List<int>.filled(30, 0)); // empty sample descriptors (length 0)
  }
  b.addByte(patternCount); // song length (offset 950)
  b.addByte(127); // restart (offset 951)
  final order = List<int>.filled(128, 0);
  for (var i = 0; i < patternCount && i < 128; i++) {
    order[i] = i; // reference every pattern
  }
  b.add(order); // order table (952..1079)
  str(sig, 4); // signature (1080..1083)
  b.add(List<int>.filled(patternCount * 64 * channels * 4, 0)); // patterns
  return b.toBytes();
}

/// The 4 signature bytes writeMod emitted at offset 0x438 (1080).
String _sigOf(Uint8List bytes) =>
    String.fromCharCodes(bytes.sublist(0x438, 0x43C));

void main() {
  group('signature-tag aliases: parse channel count + roundtrip preservation',
      () {
    const aliases = {
      'OCTA': 8,
      'CD81': 8,
      'FLT8': 8,
      '8CHN': 8,
      'FLT4': 4,
      'M!K!': 4,
      'M.K.': 4,
    };

    aliases.forEach((sig, channels) {
      test('"$sig" parses as $channels channels and roundtrips verbatim', () {
        final bytes = _modWith(sig, channels: channels);

        final parsed = parseMod(bytes);
        expect(
          parsed.channelCount,
          channels,
          reason: 'channel count for "$sig"',
        );
        expect(parsed.signature, sig, reason: 'captured signature for "$sig"');

        // A same-format read→write roundtrip reproduces the SAME tag bytes,
        // instead of forcing M.K./%dCHN.
        final written = writeMod(parsed);
        expect(_sigOf(written), sig, reason: 'roundtrip tag for "$sig"');
      });
    });
  });

  group('synthetic modules (no stored signature) get the computed tag', () {
    ModModule synthetic({
      required int channels,
      required int patternCount,
    }) =>
        ModModule(
          channelCount: channels,
          restart: 0,
          samples: [for (var i = 0; i < 31; i++) ModSample.empty()],
          order: [for (var i = 0; i < patternCount; i++) i],
          patterns: [
            for (var i = 0; i < patternCount; i++) const ModPattern([]),
          ],
        );

    test('4 channels, ≤64 patterns → "M.K."', () {
      final bytes = writeMod(synthetic(channels: 4, patternCount: 64));
      expect(_sigOf(bytes), 'M.K.');
    });

    test('4 channels, >64 patterns → "M!K!"', () {
      final bytes = writeMod(synthetic(channels: 4, patternCount: 65));
      expect(_sigOf(bytes), 'M!K!');
    });

    test('6 channels → "6CHN"', () {
      final bytes = writeMod(synthetic(channels: 6, patternCount: 1));
      expect(_sigOf(bytes), '6CHN');
    });
  });
}
