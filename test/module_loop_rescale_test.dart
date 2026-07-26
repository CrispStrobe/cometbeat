// Loop points must survive the resample onto the engine rate.
//
// A module sample is stored at its own c5speed and is resampled on import. The
// LOOP POINTS are stored in original-sample units and have to be rescaled to
// match. They were rescaled by the same ratio but rounded INDEPENDENTLY of the
// resampled buffer, so `loopStart + loopLength` could land one sample past the
// end — and `SampleInstrument.loops` requires `loopStart + loopLength <=
// sample.length`, so a one-sample rounding error switched looping off entirely.
//
// The note then plays the sample once and stops instead of sustaining. It is
// silent in the sense that matters: no error, no warning, just a click where a
// held note should be. And `loopStart = 0, loopLength = sampleLength` — "loop
// the whole sample" — is the most common layout there is, so this hit ordinary
// modules rather than an exotic corner.
//
// Found by A/B-ing a purpose-built musical fixture against OpenMPT: our render
// came out 14 dB quieter with an envelope correlation of 0.10, because our
// notes were ~30 ms clicks where OpenMPT sustained them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:flutter_test/flutter_test.dart';

/// A sample whose loop covers the WHOLE buffer — the common case.
/// `loopStart` defaults to 0, so only the length needs stating.
DocSample _wholeLoop(int length, {required int c5speed}) {
  final pcm = Float64List(length);
  for (var i = 0; i < length; i++) {
    pcm[i] = math.sin(2 * math.pi * i / length);
  }
  return DocSample(pcm: pcm, c5speed: c5speed, loopLength: length);
}

void main() {
  group('loop points survive the resample', () {
    test('a whole-sample loop still loops after resampling UP', () {
      // 8363 -> 44100 is the ordinary MOD case and the one that broke: 256
      // samples become 1349 while the loop length rounded to 1350.
      final inst = sampleInstrumentFromDoc('x', _wholeLoop(256, c5speed: 8363));
      expect(
        inst.loops,
        isTrue,
        reason: 'loopStart ${inst.loopStart} + loopLength ${inst.loopLength} '
            'must fit inside ${inst.sample.length} samples, or the note plays '
            'once and stops instead of sustaining',
      );
      expect(
        inst.loopStart + inst.loopLength,
        lessThanOrEqualTo(inst.sample.length),
      );
    });

    test('and after resampling DOWN', () {
      final inst =
          sampleInstrumentFromDoc('x', _wholeLoop(1024, c5speed: 96000));
      expect(inst.loops, isTrue);
      expect(
        inst.loopStart + inst.loopLength,
        lessThanOrEqualTo(inst.sample.length),
      );
    });

    test('across many rates, no ratio rounds the loop out of bounds', () {
      // The failure is a rounding edge, so one rate proves little. Sweep the
      // rates real modules actually use plus awkward ones.
      const rates = [
        4000, 8000, 8363, 11025, 16000, 22050, 32000,
        43999, 44100, 44101, 48000, 64000, 96000, //
      ];
      for (final rate in rates) {
        for (final len in [7, 64, 255, 256, 257, 1000]) {
          final inst =
              sampleInstrumentFromDoc('x', _wholeLoop(len, c5speed: rate));
          expect(
            inst.loopStart + inst.loopLength,
            lessThanOrEqualTo(inst.sample.length),
            reason: 'rate $rate, length $len: loop runs past the buffer',
          );
          // A loop that existed before the resample must still exist after it.
          if (inst.sample.isNotEmpty) {
            expect(inst.loops, isTrue, reason: 'rate $rate, length $len');
          }
        }
      }
    });

    test('a partial loop keeps its position, not just its validity', () {
      // Clamping must not be a blunt "shrink to fit" that moves the loop: a
      // sample looping its second half should still loop its second half.
      // 8363 is DocSample's default c5speed — the ordinary MOD rate.
      final sample = DocSample(
        pcm: Float64List(1000),
        loopStart: 500,
        loopLength: 500,
      );
      final inst = sampleInstrumentFromDoc('x', sample);
      expect(inst.loops, isTrue);
      const ratio = kSampleRate / 8363;
      expect(inst.loopStart, closeTo(500 * ratio, 2));
    });

    test('a sample with no loop still has none', () {
      final sample = DocSample(pcm: Float64List(256));
      final inst = sampleInstrumentFromDoc('x', sample);
      expect(inst.loops, isFalse, reason: 'clamping must not invent a loop');
    });
  });
}
