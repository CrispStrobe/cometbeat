// The measuring instruments for the OpenMPT A/B, verified on synthesised
// signals with known differences.
//
// The A/B harness itself is opt-in (it needs a Homebrew openmpt123 and
// licence-restricted modules that cannot be committed), so it never runs on CI.
// These do. A metric that only ever executes on one developer's machine is a
// metric nobody can rely on, and the headline case below is precisely the one
// the old duration+RMS comparison could not see.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/audio_compare.dart';

const _sr = 44100;

Float64List _tone(double hz, {int n = 32768, double amp = 0.5}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

/// A tone that fades in and out, so it has an envelope to correlate.
Float64List _swell(double hz, {int n = 32768, double amp = 0.5}) {
  final out = _tone(hz, n: n, amp: amp);
  for (var i = 0; i < n; i++) {
    out[i] *= math.sin(math.pi * i / n);
  }
  return out;
}

/// A sequence of [hz] notes, each swelling, spread evenly over [n] samples —
/// material whose SPECTRUM changes with time, which a steady tone's does not.
Float64List _melody(List<num> hz, {int n = 131072}) {
  final out = Float64List(n);
  final per = n ~/ hz.length;
  for (var k = 0; k < hz.length; k++) {
    final note = _swell(hz[k].toDouble(), n: per);
    out.setRange(k * per, k * per + per, note);
  }
  return out;
}

/// [pcm] delayed by [samples] (zero-padded at the front, same length).
Float64List _delayed(Float64List pcm, int samples) {
  final out = Float64List(pcm.length);
  for (var i = samples; i < pcm.length; i++) {
    out[i] = pcm[i - samples];
  }
  return out;
}

void main() {
  group('the case that motivated this: RMS and duration cannot see tuning', () {
    test('a semitone-sharp render matches on level but not on spectrum', () {
      // We render Amiga periods through periodToMidi at A440 rather than from
      // the Paula clock, so a systematic TUNING error is a live possibility.
      // Its signature is: same length, same loudness, different pitches. The
      // old comparison checked only the first two.
      final reference = _tone(440);
      final sharp = _tone(440 * 1.05946); // +1 semitone

      // Indistinguishable to the metrics we had.
      expect(reference.length, sharp.length);
      expect(
        levelDeltaDb(reference, sharp).abs(),
        lessThan(0.5),
        reason: 'RMS is blind to transposition — that is the whole problem',
      );

      // Obvious to the metric we now have.
      expect(
        spectralSimilarity(reference, sharp),
        lessThan(0.5),
        reason: 'a semitone shift must collapse spectral similarity',
      );
    });

    test('even a quarter-tone is caught, given the resolution for it', () {
      // Bin width is sampleRate/frame and a Hann lobe spans ~4 bins, so the
      // detectable offset is a property of the frame size, not of the metric.
      // A quarter-tone at A440 is ~13 Hz: 16384 samples (2.7 Hz bins) resolves
      // it; the default 8192 (5.4 Hz) is marginal and 1024 cannot see a whole
      // semitone. This is why the frame is a parameter and is documented.
      final quarterTone = _tone(440 * 1.0293, n: 65536);
      final reference = _tone(440, n: 65536);
      expect(
        spectralSimilarity(reference, quarterTone, frame: 16384, hop: 8192),
        lessThan(0.7),
        reason: 'quarter-tone, ~29 cents',
      );
    });

    test('a merely LATE render is not mistaken for a wrong-notes render', () {
      // Found by running the real A/B: our renders sit up to ~0.6 s from
      // OpenMPT's (start-up priming and trailing silence differ), and comparing
      // frame i against frame i dragged every spectral score toward zero. A
      // timing offset must be reported by the LAG, not disguised as a pitch
      // fault — the two need different fixes.
      // A MELODY, not a steady tone: a shifted steady tone still has the same
      // spectrum in every frame, so it cannot show the problem (my first
      // attempt scored 0.997 unaligned and proved nothing). Real modules
      // change note, which is where a shift starts comparing one note against
      // the next.
      final a = _melody(const [392, 523, 659, 440]);
      final late = _delayed(a, 16384);

      // Unaligned, the same tune looks like a different one...
      final unaligned = spectralSimilarity(a, late);
      expect(unaligned, lessThan(0.9));

      // ...and AudioComparison aligns first, so it sees them for what they are.
      final c = AudioComparison.of(a, late);
      expect(
        c.lagSamples,
        closeTo(16384, 1024),
        reason: 'the lag IS the fault',
      );
      expect(
        c.spectral,
        greaterThan(unaligned),
        reason: 'aligning must improve the spectral verdict, not worsen it',
      );
      expect(
        c.spectral,
        greaterThan(0.9),
        reason: 'after alignment these are plainly the same notes',
      );
    });

    test('detuneCents says HOW FAR out of tune, not merely that it is', () {
      // spectralSimilarity can tell you two renders disagree; only this says by
      // how much, which is what decides whether a difference is worth changing
      // anything for. Signed: positive means the SECOND render is sharp.
      final reference = _melody(const [220, 330, 440, 550]);

      for (final cents in [0, 5, -5, 25, -25, 100, -100]) {
        final ratio = math.pow(2, cents / 1200).toDouble();
        final shifted = _melody(
          const [220, 330, 440, 550].map((hz) => hz * ratio).toList(),
        );
        expect(
          detuneCents(reference, shifted),
          closeTo(cents, 3),
          reason: 'asked for $cents cents',
        );
      }
    });

    test('detune resolves finer than its bin spacing', () {
      // 240 bins/octave is 5 cents per bin, so without the parabolic
      // interpolation across the correlation peak the answer would quantise to
      // multiples of 5 and a 2-cent drift would read as 0.
      final a = _melody(const [220, 330, 440, 550]);
      final ratio = math.pow(2, 2 / 1200).toDouble();
      final b =
          _melody(const [220, 330, 440, 550].map((hz) => hz * ratio).toList());
      expect(detuneCents(a, b), closeTo(2, 1.5));
    });

    test('detune reports NaN, not a number, when it cannot tell', () {
      // Silence has no spectrum to align. Returning 0 would read as "perfectly
      // in tune"; returning the search rail (-600) would read as a finding.
      // Both are lies a caller would print. NaN is not.
      expect(detuneCents(Float64List(65536), Float64List(65536)).isNaN, isTrue);
    });

    test('an identical render scores ~1 on every metric', () {
      final a = _swell(330);
      final b = _swell(330);
      final c = AudioComparison.of(a, b);
      expect(c.levelDb.abs(), lessThan(1e-9));
      expect(c.envelope, greaterThan(0.999));
      expect(c.lagSamples, 0);
      expect(c.spectral, greaterThan(0.999));
      expect(c.toString(), contains('spectral'));
    });
  });

  group('levelDeltaDb', () {
    test('reports how much louder, with the sign pointing at the loud one', () {
      final loud = _tone(440);
      final quiet = _tone(440, amp: 0.25);
      expect(levelDeltaDb(loud, quiet), closeTo(6.02, 0.05));
      expect(levelDeltaDb(quiet, loud), closeTo(-6.02, 0.05));
    });

    test('silence floors instead of returning infinity', () {
      final silence = Float64List(1024);
      expect(levelDeltaDb(_tone(440), silence), 120);
      expect(levelDeltaDb(silence, _tone(440)), -120);
      // Two silences agree rather than producing NaN.
      expect(levelDeltaDb(silence, Float64List(1024)), 0);
    });
  });

  group('envelopeCorrelation', () {
    test('is about SHAPE, so a uniformly quieter render still scores 1', () {
      // Deliberate division of labour: gain is levelDeltaDb's job. If this
      // metric also punished gain, one fault would trip two metrics and the
      // diagnostic would stop localising anything.
      final loud = _swell(440);
      final quiet = _swell(440, amp: 0.1);
      expect(envelopeCorrelation(loud, quiet), greaterThan(0.999));
      expect(levelDeltaDb(loud, quiet).abs(), greaterThan(10));
    });

    test('a swell and a steady tone do not agree', () {
      expect(
        envelopeCorrelation(_swell(440), _tone(440)),
        lessThan(0.5),
        reason: 'one moves, the other does not',
      );
    });

    test('silence has no shape to agree about, and says so with 0', () {
      expect(envelopeCorrelation(Float64List(8192), Float64List(8192)), 0);
    });
  });

  group('bestLagSamples', () {
    test('finds a delay, and the sign says which render is late', () {
      final a = _swell(440, n: 65536);
      final late = _delayed(a, 4096);
      // Convention: POSITIVE means the second argument is late. Envelope-block
      // resolution, so allow a block either way.
      expect(bestLagSamples(a, late), closeTo(4096, 512));
      expect(bestLagSamples(late, a), closeTo(-4096, 512));
    });

    test('refuses to guess when there is no peak to find', () {
      // Noise against noise has no shared onsets. The argmax of a flat
      // correlation is still SOME number, and a caller that shifts by it
      // discards real overlap — on the actual A/B this turned a comparable
      // pair into an empty one and scored the spectrum 0. Unknown must read
      // as 0, not as a confident answer.
      final rng = math.Random(7);
      Float64List noise() => Float64List.fromList(
            [for (var i = 0; i < 65536; i++) rng.nextDouble() - 0.5],
          );
      expect(bestLagSamples(noise(), noise()), 0);
    });

    test('never searches further than the material allows', () {
      // The window used to be a fixed ±0.74 s, which is longer than these
      // renders — so it could "align" past the end of the signal entirely.
      final short = _swell(440, n: 8192);
      final lag = bestLagSamples(short, _delayed(short, 1024));
      expect(lag.abs(), lessThanOrEqualTo(8192 ~/ 4));
    });

    test('aligned renders report no lag', () {
      final a = _swell(440, n: 65536);
      expect(bestLagSamples(a, Float64List.fromList(a)), 0);
    });

    test('works on envelopes, so phase differences do not fool it', () {
      // Two renders of the same notes can differ in waveform phase (different
      // interpolation, different start-up) while sharing every onset. Lag must
      // track the onsets, not the samples.
      final a = _swell(440, n: 65536);
      final phaseFlipped = Float64List.fromList([for (final v in a) -v]);
      expect(bestLagSamples(a, phaseFlipped), 0);
    });
  });

  group('spectralSimilarity', () {
    test('ignores gain — it is about content, not level', () {
      expect(
        spectralSimilarity(_tone(440), _tone(440, amp: 0.05)),
        greaterThan(0.99),
      );
    });

    test('a different note scores low even at the same loudness', () {
      final a = _tone(440);
      final b = _tone(660); // a fifth up
      expect(levelDeltaDb(a, b).abs(), lessThan(0.5));
      expect(spectralSimilarity(a, b), lessThan(0.3));
    });

    test('two silences report 0, not a vacuous 1', () {
      // Nothing audible in common is not agreement. Scoring it 1 would let a
      // render that fell silent pass the strictest metric we have.
      expect(spectralSimilarity(Float64List(32768), Float64List(32768)), 0);
    });

    test('a buffer shorter than one frame reports 0 rather than throwing', () {
      expect(spectralSimilarity(Float64List(128), Float64List(128)), 0);
    });

    test('sparse material is not inflated by its silent frames', () {
      // Half silence, half a tone — versus the same layout at another pitch.
      // If silent frames counted as agreement the score would be dragged up
      // toward 1 and a real difference would slip through.
      Float64List halfSilent(double hz) {
        final out = Float64List(65536);
        final tone = _tone(hz);
        out.setRange(32768, 65536, tone);
        return out;
      }

      expect(
        spectralSimilarity(halfSilent(440), halfSilent(660)),
        lessThan(0.3),
      );
    });
  });
}
