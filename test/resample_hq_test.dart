// A6 — band-limited rate conversion.
//
// The only claim worth testing here is the one that separates rate conversion
// from interpolation: content the destination rate cannot represent must be
// REMOVED, not folded. So the load-bearing tests feed a tone above the target
// Nyquist and measure what comes out at the frequency it would alias to. The
// same tests are run against the plain interpolator, which FAILS them — that
// side-by-side is the point, because "we resample" was already true before this
// and was already producing whistles on every downsampled export.
//
// Everything else here guards the things a resampler quietly gets wrong:
// length, gain, and the edges (a truncated kernel fades the first and last
// samples unless the taps are normalised per output sample).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _tone(double hz, double rate, {double seconds = 0.5}) {
  final n = (rate * seconds).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * hz * i / rate);
  }
  return out;
}

/// Magnitude at [hz] by direct correlation — a Goertzel-style probe, which is
/// all that is needed to ask "is this one frequency present".
double _magnitudeAt(Float64List pcm, double hz, double rate) {
  if (pcm.isEmpty) return 0;
  var re = 0.0;
  var im = 0.0;
  for (var i = 0; i < pcm.length; i++) {
    final phase = 2 * math.pi * hz * i / rate;
    re += pcm[i] * math.cos(phase);
    im += pcm[i] * math.sin(phase);
  }
  return 2 * math.sqrt(re * re + im * im) / pcm.length;
}

double _peak(Float64List pcm) {
  var peak = 0.0;
  for (final v in pcm) {
    peak = math.max(peak, v.abs());
  }
  return peak;
}

void main() {
  group('the anti-aliasing is the whole feature', () {
    // 44100 → 22050: the destination Nyquist is 11025 Hz. A 15 kHz tone cannot
    // survive, and if it is not filtered out first it comes back mirrored
    // around 11025 — at 22050 − 15000 = 7050 Hz, right in the middle of the
    // music, where nothing can remove it afterwards.
    const from = 44100.0;
    const to = 22050.0;
    const doomed = 15000.0;
    const aliasesTo = 7050.0;

    test('a tone above the target Nyquist does NOT come back as an alias', () {
      final out = resampleHq(
        _tone(doomed, from),
        fromRate: from,
        toRate: to,
      );
      final alias = _magnitudeAt(out, aliasesTo, to);
      expect(alias, lessThan(0.01), reason: 'alias at $aliasesTo Hz');
    });

    test('the plain interpolator FAILS that — which is why this exists', () {
      // Not a test of the old code so much as a record of the bug: exporting a
      // bright mix at half rate through resampleCubic put a loud whistle in it.
      final out = resampleCubic(_tone(doomed, from), from / to);
      final alias = _magnitudeAt(out, aliasesTo, to);
      expect(alias, greaterThan(0.3), reason: 'the fold this feature removes');
    });

    test('music BELOW the target Nyquist survives at full level', () {
      // The other half of every filter test: the damage went away AND the
      // signal that should have survived did. A resampler that returned silence
      // would pass the test above.
      final out = resampleHq(_tone(1000, from), fromRate: from, toRate: to);
      expect(_magnitudeAt(out, 1000, to), closeTo(1.0, 0.05));
    });

    test('every quality tier is alias-free; they differ in how MUCH', () {
      // The tiers are a cost/depth trade, not a correctness trade — the worst
      // of them must still be usable, or it should not be offered.
      var previous = double.infinity;
      for (final q in ResampleQuality.values) {
        final out = resampleHq(
          _tone(doomed, from),
          fromRate: from,
          toRate: to,
          quality: q,
        );
        final alias = _magnitudeAt(out, aliasesTo, to);
        expect(alias, lessThan(0.02), reason: '${q.name} alias');
        expect(alias, lessThanOrEqualTo(previous + 1e-6), reason: q.name);
        previous = alias;
      }
    });

    test('a tone just under the cutoff still passes', () {
      // The transition band has to be narrow enough to be useful. 10 kHz is
      // under the 11025 Hz cutoff and is ordinary programme material.
      final out = resampleHq(_tone(10000, from), fromRate: from, toRate: to);
      expect(_magnitudeAt(out, 10000, to), greaterThan(0.5));
    });
  });

  group('upsampling', () {
    test('it invents no content above the SOURCE Nyquist', () {
      // Upsampling cannot add detail; a bad interpolator adds harmonic hash
      // instead. 22050 → 44100 of a 5 kHz tone must stay one tone.
      final out = resampleHq(
        _tone(5000, 22050),
        fromRate: 22050,
        toRate: 44100,
      );
      expect(_magnitudeAt(out, 5000, 44100), closeTo(1.0, 0.05));
      // Nothing meaningful where the source could not have had anything.
      expect(_magnitudeAt(out, 15000, 44100), lessThan(0.02));
    });

    test('it does not dull what was already there', () {
      // The cutoff must stay at the source Nyquist when going up; pulling it
      // down would quietly low-pass every upsample.
      final out = resampleHq(
        _tone(9000, 22050),
        fromRate: 22050,
        toRate: 44100,
      );
      expect(_magnitudeAt(out, 9000, 44100), greaterThan(0.9));
    });
  });

  group('the things a resampler quietly gets wrong', () {
    test('the length follows the ratio', () {
      final src = Float64List(44100);
      expect(
        resampleHq(src, fromRate: 44100, toRate: 22050).length,
        22050,
      );
      expect(
        resampleHq(src, fromRate: 44100, toRate: 48000).length,
        48000,
      );
    });

    test('the ENDS keep their level', () {
      // The kernel is truncated by the buffer edges, so an un-normalised
      // version fades the first and last samples — audible as a click or a
      // gap at every clip boundary.
      final flat = Float64List(4410)..fillRange(0, 4410, 0.5);
      final out = resampleHq(flat, fromRate: 44100, toRate: 22050);
      expect(out.first, closeTo(0.5, 0.01));
      expect(out.last, closeTo(0.5, 0.01));
      expect(_peak(out), closeTo(0.5, 0.01));
    });

    test('equal rates return the input untouched', () {
      // A no-op that costs a rounding error is still not a no-op, and this is
      // the overwhelmingly common case on export.
      final src = _tone(440, 44100, seconds: 0.05);
      expect(
        resampleHq(src, fromRate: 44100, toRate: 44100),
        same(src),
      );
    });

    test('degenerate arguments give an empty buffer, not a crash', () {
      for (final call in [
        () => resampleHq(Float64List(0), fromRate: 44100, toRate: 22050),
        () => resampleHq(Float64List(10), fromRate: 0, toRate: 22050),
        () => resampleHq(Float64List(10), fromRate: 44100, toRate: -1),
      ]) {
        expect(call(), isEmpty);
      }
    });
  });

  group('the raw converter is a different thing on purpose', () {
    test('it aliases — that IS the effect', () {
      // Offered because the aliasing is sometimes wanted (it is how early
      // samplers sounded), and named so nobody reaches for it expecting
      // quality. A test that asserted it was clean would be asserting it had
      // been silently replaced by the good one.
      final out = resampleRaw(
        _tone(15000, 44100),
        fromRate: 44100,
        toRate: 22050,
      );
      expect(_magnitudeAt(out, 7050, 22050), greaterThan(0.3));
    });

    test('it still gets the length and the equal-rate case right', () {
      expect(
        resampleRaw(Float64List(44100), fromRate: 44100, toRate: 22050).length,
        22050,
      );
      final src = Float64List(10);
      expect(resampleRaw(src, fromRate: 8000, toRate: 8000), same(src));
    });
  });

  group('the EXPORT path uses it — where the bug actually bit', () {
    /// Decode a 16-bit PCM WAV body back to floats, so the assertion is about
    /// what lands on disk rather than about an intermediate buffer.
    Float64List pcmOf(Uint8List wav) {
      final bd = ByteData.sublistView(wav);
      // Walk the chunks rather than assuming a 44-byte header.
      var pos = 12;
      while (pos + 8 <= wav.length) {
        final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
        final size = bd.getUint32(pos + 4, Endian.little);
        if (id == 'data') {
          final n = size ~/ 2;
          final out = Float64List(n);
          for (var i = 0; i < n; i++) {
            out[i] = bd.getInt16(pos + 8 + i * 2, Endian.little) / 32768.0;
          }
          return out;
        }
        pos += 8 + size + (size.isOdd ? 1 : 0);
      }
      return Float64List(0);
    }

    test('exporting at half rate no longer folds the top octave in', () {
      // The actual user-visible bug: a bright mix exported at 22.05 kHz came
      // back with a whistle in it. This is the regression that keeps it fixed.
      final wav = pcmFloatToWav(
        _tone(15000, 44100),
        sampleRate: 22050,
        sourceSampleRate: 44100,
      );
      expect(_magnitudeAt(pcmOf(wav), 7050, 22050), lessThan(0.02));
    });

    test('the quality choice is not decorative', () {
      // The picker threads through four call layers, and a dropped argument at
      // any one of them leaves a control that silently does nothing. Asserted
      // by OUTPUT: the tiers must not all produce identical bytes.
      Uint8List at(ResampleQuality q) => pcmFloatToWav(
            _tone(10500, 44100),
            sampleRate: 22050,
            sourceSampleRate: 44100,
            resampleQuality: q,
          );
      expect(at(ResampleQuality.fast), isNot(at(ResampleQuality.best)));
    });

    test('an export at the SAME rate is untouched', () {
      // The overwhelmingly common case. Rate conversion must not become
      // something every ordinary export pays for.
      // 48 k both sides — same-rate, and not the default, so the assertion
      // cannot pass by accident on a build that ignores the arguments.
      final src = _tone(1000, 48000, seconds: 0.05);
      final wav =
          pcmFloatToWav(src, sampleRate: 48000, sourceSampleRate: 48000);
      final back = pcmOf(wav);
      expect(back, hasLength(src.length));
      for (var i = 0; i < src.length; i++) {
        expect(back[i], closeTo(src[i], 1 / 32768 * 1.5), reason: 'sample $i');
      }
    });
  });
}
