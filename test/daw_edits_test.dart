// The destructive edit maths, headless — the same functions DawService bakes
// with and `bin/dawedit.dart` runs on a WAV. Pure Dart: no Flutter, no service,
// no timeline. (The service-level behaviour — undo, clip placement, the range
// ops on a real arrangement — is covered in daw_service_test.dart.)

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart'
    show Clip, SampleSource;
import 'package:flutter_test/flutter_test.dart';

const _rate = 44100;

Float64List _level(double value, int samples) =>
    Float64List(samples)..fillRange(0, samples, value);

double _peak(Float64List pcm) {
  var m = 0.0;
  for (final v in pcm) {
    if (v.abs() > m) m = v.abs();
  }
  return m;
}

void main() {
  group('bake takes', () {
    test('normalize uses ONE gain across both channels', () {
      // The right channel is the loud one; a per-channel normalize would raise
      // the left to full scale too and destroy the image.
      final take = normalizeTake(_level(0.2, 64), _level(0.4, 64));
      expect(_peak(take.right!), closeTo(0.98, 1e-9));
      expect(_peak(take.left), closeTo(0.49, 1e-9)); // half, as before
      expect(take.startShiftMs, 0);
    });

    test('normalize leaves silence alone', () {
      final take = normalizeTake(_level(0, 32), null);
      expect(_peak(take.left), 0);
    });

    test('amplify is the dB→linear law, and round-trips', () {
      expect(
        _peak(amplifyTake(_level(0.1, 8), null, 6).left),
        closeTo(0.1 * 1.9952623, 1e-7),
      );
      expect(
        _peak(amplifyTake(_level(0.1, 8), null, -6).left),
        closeTo(0.1 * 0.5011872, 1e-7),
      );
      final up = amplifyTake(_level(0.3, 8), null, 9);
      final back = amplifyTake(up.left, null, -9);
      expect(back.left.first, closeTo(0.3, 1e-12));
    });

    test('invert twice is the identity', () {
      final once = invertTake(_level(0.3, 8), _level(-0.2, 8));
      expect(once.left.first, closeTo(-0.3, 1e-12));
      expect(once.right!.first, closeTo(0.2, 1e-12));
      final twice = invertTake(once.left, once.right);
      expect(twice.left.first, closeTo(0.3, 1e-12));
      expect(twice.right!.first, closeTo(-0.2, 1e-12));
    });

    test('remove-DC centres each channel independently', () {
      final take = removeDcTake(_level(0.3, 16), _level(-0.5, 16));
      expect(_peak(take.left), lessThan(1e-12));
      expect(_peak(take.right!), lessThan(1e-12));
    });

    test('trim-silence reports the leading cut and keeps channels aligned', () {
      // Left is loud in the middle; right is loud slightly LATER. The window
      // must be the union, or the two sides would drift apart.
      final left = Float64List(1000)..fillRange(100, 400, 0.5);
      final right = Float64List(1000)..fillRange(300, 600, 0.5);
      final take = trimSilenceTake(left, right, sampleRate: _rate);

      expect(take.left.length, 500); // samples 100..600
      expect(take.right!.length, 500);
      expect(take.startShiftMs, closeTo(100 * 1000 / _rate, 1e-9));
      // Alignment survived: the right channel's onset is still 200 samples
      // after the left's.
      expect(take.left[0], closeTo(0.5, 1e-12));
      expect(take.right![0], 0);
      expect(take.right![200], closeTo(0.5, 1e-12));
    });

    test('trim-silence on an all-silent take yields an empty left', () {
      expect(
        trimSilenceTake(_level(0, 100), null, sampleRate: _rate).left,
        isEmpty,
      );
    });
  });

  group('clip stats', () {
    test('a full-scale square reads 0 dBFS peak and 0 dBFS RMS', () {
      final s = clipStatsOf(_level(1.0, 100), null, sampleRate: _rate);
      expect(s.peakDb, closeTo(0, 1e-9));
      expect(s.rmsDb, closeTo(0, 1e-9));
      expect(s.clippedSamples, 100); // |x| >= 1.0 counts as clipped
      expect(s.channels, 1);
    });

    test('a sine reads peak −0 dBFS and RMS −3 dBFS (1/sqrt2)', () {
      final sine = generateWave(
        shape: GeneratorShape.sine,
        samples: _rate,
        sampleRate: _rate,
        freq: 100,
        amp: 1,
      );
      final s = clipStatsOf(sine, null, sampleRate: _rate);
      expect(s.peak, closeTo(1, 1e-3));
      expect(s.rms, closeTo(0.7071, 1e-3));
      expect(s.rmsDb, closeTo(-3.01, 0.02));
      expect(s.durationMs, closeTo(1000, 1e-9));
      expect(s.clippedSamples, lessThanOrEqualTo(2));
    });

    test('silence floors at silenceDb instead of -infinity', () {
      final s = clipStatsOf(_level(0, 50), null, sampleRate: _rate);
      expect(s.peakDb, silenceDb);
      expect(s.rmsDb, silenceDb);
      expect(s.peakDb.isFinite, isTrue);
    });

    test('RMS spans both channels', () {
      // One side full, one side silent → RMS is 1/sqrt(2) of the loud side.
      final s =
          clipStatsOf(_level(1.0, 100), _level(0, 100), sampleRate: _rate);
      expect(s.channels, 2);
      expect(s.rms, closeTo(0.7071, 1e-4));
    });
  });

  group('generator', () {
    test('a tone hits the requested frequency (zero crossings)', () {
      const freq = 220.0;
      final pcm = generateWave(
        shape: GeneratorShape.sine,
        samples: _rate,
        sampleRate: _rate,
        freq: freq,
      );
      var crossings = 0;
      for (var i = 1; i < pcm.length; i++) {
        if (pcm[i - 1] < 0 && pcm[i] >= 0) crossings++;
      }
      expect(crossings, closeTo(freq, 1)); // one rising crossing per cycle
    });

    test('every shape respects the amplitude, silence is silent', () {
      for (final shape in GeneratorShape.values) {
        final pcm = generateWave(
          shape: shape,
          samples: 4410,
          sampleRate: _rate,
          amp: 0.4,
        );
        expect(pcm, hasLength(4410), reason: shape.name);
        if (shape == GeneratorShape.silence) {
          expect(_peak(pcm), 0, reason: shape.name);
        } else {
          // Nothing overshoots the requested amplitude — the noises are scaled
          // by their realised peak precisely so they can't.
          expect(_peak(pcm), greaterThan(0.3), reason: shape.name);
          expect(
            _peak(pcm),
            lessThanOrEqualTo(0.4 + 1e-12),
            reason: shape.name,
          );
        }
      }
    });

    test('noise is reproducible per seed and differs across seeds', () {
      Float64List noise(int seed) => generateWave(
            shape: GeneratorShape.pinkNoise,
            samples: 256,
            sampleRate: _rate,
            seed: seed,
          );
      expect(noise(7), noise(7));
      expect(noise(7), isNot(noise(8)));
    });

    test('pink noise has more low-frequency energy than white', () {
      // Cheap proxy: pink drifts, so successive samples are more alike.
      double meanAbsDelta(GeneratorShape shape) {
        final pcm = generateWave(
          shape: shape,
          samples: 20000,
          sampleRate: _rate,
          seed: 3,
        );
        var sum = 0.0;
        for (var i = 1; i < pcm.length; i++) {
          sum += (pcm[i] - pcm[i - 1]).abs();
        }
        return sum / (pcm.length - 1);
      }

      expect(
        meanAbsDelta(GeneratorShape.pinkNoise),
        lessThan(meanAbsDelta(GeneratorShape.whiteNoise)),
      );
    });
  });

  group('range surgery', () {
    // A 1000 ms clip at 0 on a 1-clip lane, measured by its declared duration.
    List<Clip> lane() => [Clip(source: SampleSource(Float64List(_rate)))];
    double duration(Clip c) =>
        (c.trimEndMs == 0 ? 1000.0 : c.trimEndMs) - c.trimStartMs;

    test('silence cuts the middle out and leaves the tail in place', () {
      final clips = lane();
      final removed = editClipsAroundRange(
        clips,
        250,
        750,
        removeInside: true,
        durationOf: duration,
        minSplitMs: 5,
      );
      expect(removed, 1);
      expect(clips, hasLength(2));
      expect(clips[0].startMs, 0);
      expect(duration(clips[0]), closeTo(250, 1e-9));
      expect(clips[1].startMs, closeTo(750, 1e-9)); // no ripple left
      expect(duration(clips[1]), closeTo(250, 1e-9));
    });

    test('crop keeps only the marked segment', () {
      final clips = lane();
      final removed = editClipsAroundRange(
        clips,
        250,
        750,
        removeInside: false,
        durationOf: duration,
        minSplitMs: 5,
      );
      expect(removed, 2);
      expect(clips, hasLength(1));
      expect(clips.single.startMs, closeTo(250, 1e-9));
      expect(duration(clips.single), closeTo(500, 1e-9));
    });

    test('a sliver too short to split is decided by its midpoint', () {
      // The range ends 2 ms into the clip — below minSplitMs, so no split is
      // possible; the clip's midpoint (500) is outside, so silence keeps it.
      final clips = lane();
      final removed = editClipsAroundRange(
        clips,
        -100,
        2,
        removeInside: true,
        durationOf: duration,
        minSplitMs: 5,
      );
      expect(removed, 0);
      expect(clips, hasLength(1));
    });

    test('a range that misses the clip changes nothing', () {
      final clips = lane();
      expect(
        editClipsAroundRange(
          clips,
          2000,
          3000,
          removeInside: true,
          durationOf: duration,
          minSplitMs: 5,
        ),
        0,
      );
      expect(clips, hasLength(1));
    });
  });
}
