// Sf2SoundFont.parse must be robust to MALFORMED input — users load arbitrary
// .sf2 files (showSoundFontSheet, bin/sfont.dart), and the app catches only
// SoundFontLoadException, so an uncaught RangeError/IndexError would crash the
// picker. Contract locked here: for ANY bytes, parse returns a font or throws a
// plain Exception (FormatException) — never a RangeError/other Error, no hang.
// Valid fonts still parse intact.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

Uint8List _validFont() {
  const n = 4410;
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (0.5 * 32767 * math.sin(2 * math.pi * 220 * i / 22050)).round();
  }
  return oneSampleSf2(
    pcm: pcm,
    sampleRate: 22050,
    rootKey: 57,
    loopStart: 100,
    loopEnd: n - 100,
  );
}

void main() {
  test('a valid font still parses intact (no regression)', () {
    final sf = Sf2SoundFont.parse(_validFont());
    expect(sf.presets.length, 1);
    expect(sf.sampleAt(0)?.pcm.length, 4410);
  });

  test('a chunk claiming a huge size no longer throws IndexError', () {
    // RIFF/sfbk + a LIST whose size (0x7FFFFFFF) far exceeds the buffer — this
    // used to walk getUint32 past the end and throw an uncaught IndexError.
    final bytes = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0xFF, 0xFF, 0xFF, 0x7F, 0x73, 0x66, 0x62, 0x6b, //
      0x4C, 0x49, 0x53, 0x54, 0xFF, 0xFF, 0xFF, 0x7F,
      ...List<int>.filled(64, 0),
    ]);
    // Clean Exception (missing smpl/shdr), not an Error.
    expect(() => Sf2SoundFont.parse(bytes), throwsFormatException);
  });

  test('sub-header-length inputs fail cleanly (bounds-safe tag)', () {
    for (final b in [
      Uint8List(0),
      Uint8List.fromList([0x52, 0x49, 0x46]), // 3 bytes, "RIF"
      Uint8List.fromList('RIFF'.codeUnits), // 4 bytes, no sfbk
    ]) {
      expect(() => Sf2SoundFont.parse(b), throwsFormatException);
    }
  });

  test('fuzz: no malformed input throws a non-Exception Error', () {
    for (var seed = 0; seed < 120; seed++) {
      final len = 1 + (seed * 131) % 12000;
      final b = Uint8List(len);
      var x = seed * 2654435761 + 1;
      for (var i = 0; i < len; i++) {
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        b[i] = x & 0xff;
      }
      // Half the inputs get a real RIFF/sfbk + oversized LIST header.
      if (seed.isEven && len >= 20) {
        final riff = [...'RIFF'.codeUnits, 0xFF, 0xFF, 0xFF, 0x7F];
        b.setRange(0, 12, [...riff, ...'sfbk'.codeUnits]);
        b.setRange(12, 20, [...'LIST'.codeUnits, 0xFF, 0xFF, 0xFF, 0x7F]);
      }
      try {
        Sf2SoundFont.parse(b);
      } on Exception {
        // clean — acceptable
      } catch (e) {
        fail('seed $seed threw a non-Exception: ${e.runtimeType}: $e');
      }
    }
  });
}
