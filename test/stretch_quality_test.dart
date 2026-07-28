// WS-A9 — the time-stretch quality setting.
//
// ⚠️ Read the enum's own doc comment first: this was scoped expecting a MATERIAL
// trade-off ("short frames keep drum hits sharp, long frames are smooth on held
// notes") and only half of that survived measurement. These tests pin the half
// that is real and deliberately do NOT assert the half that is not — a test
// written to the original story would have passed on noise and enshrined a
// claim the DSP does not make.
//
// What IS real: WSOLA aligns frames by correlating the overlap region, so a
// correlation window shorter than one period of the material cannot find the
// right alignment and the stretch locks onto a SUB-HARMONIC. The note comes out
// at the wrong pitch — not merely rougher. That failure is large, exactly
// predictable from the overlap length, and it is what the setting is for.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _note(double hz, {double seconds = 0.4}) {
  final n = (_sr * seconds).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

/// Pitch by zero-crossing rate — immune to the amplitude modulation WSOLA
/// introduces, which an FFT peak search is not, and it is precisely the
/// sub-harmonic drop this feature is about that it detects.
double _pitchHz(Float64List pcm) {
  var crossings = 0;
  for (var i = 1; i < pcm.length; i++) {
    if ((pcm[i - 1] < 0) != (pcm[i] < 0)) crossings++;
  }
  return crossings * _sr / (2 * pcm.length);
}

bool _holdsPitch(double hz, StretchQuality q, {double factor = 1.5}) {
  final out = timeStretch(_note(hz), factor, quality: q);
  return (_pitchHz(out) - hz).abs() < hz * 0.06;
}

void main() {
  group('the pitch floor is the whole feature', () {
    test('a longer frame holds lower notes — strictly', () {
      // Measured floors are roughly 85 / 67 / 39 Hz, so 75 Hz separates the
      // shortest frame from the other two. (Written first against 110 Hz, from
      // an earlier 512-sample `light`; 768 holds 110 fine. The floors move when
      // the frame does — read them off, do not remember them.)
      expect(
        _holdsPitch(75, StretchQuality.light),
        isFalse,
        reason: 'light should not survive 75 Hz',
      );
      expect(_holdsPitch(75, StretchQuality.balanced), isTrue);
      expect(_holdsPitch(75, StretchQuality.deep), isTrue);
    });

    test('only DEEP survives a bass low E', () {
      // 41.2 Hz — the open E of a bass guitar, and the case that justifies
      // carrying a 2048-sample setting at all.
      expect(_holdsPitch(41.2, StretchQuality.light), isFalse);
      expect(_holdsPitch(41.2, StretchQuality.balanced), isFalse);
      expect(_holdsPitch(41.2, StretchQuality.deep), isTrue);
    });

    test('⚠️ the DEFAULT cannot hold bass — a pre-existing limit, now named',
        () {
      // This is NOT a regression introduced by the setting: 1024/256 were the
      // hardcoded constants before it existed, so every stretch of deep
      // material the app has ever done had this flaw. It was invisible because
      // nothing measured pitch after stretching. Pinned so it stays visible,
      // and so the fix (choose `deep`) is discoverable.
      final stretched = timeStretch(_note(41.2, seconds: 0.6), 1.5);
      expect(
        _pitchHz(stretched),
        lessThan(35),
        reason: 'the default drops a 41.2 Hz note to a sub-harmonic',
      );
    });

    test('every setting holds ordinary musical material', () {
      // The floors only bite in the bass; nothing here should be fragile in the
      // range most material lives in.
      for (final q in StretchQuality.values) {
        for (final hz in [220.0, 440.0, 880.0]) {
          expect(_holdsPitch(hz, q), isTrue, reason: '${q.name} at $hz Hz');
        }
      }
    });
  });

  group('the advertised floor is a promise, not a guess', () {
    test('lowestReliableHz is never optimistic', () {
      // The number is shown to a person choosing a setting, so it has to be
      // conservative: the real floor must sit BELOW what is advertised.
      for (final q in StretchQuality.values) {
        final advertised = q.lowestReliableHz();
        expect(
          _holdsPitch(advertised, q),
          isTrue,
          reason: '${q.name} fails at its own advertised '
              '${advertised.toStringAsFixed(0)} Hz',
        );
      }
    });

    test('it follows the overlap, which is what actually sets the floor', () {
      for (final q in StretchQuality.values) {
        expect(q.overlap, q.frameSize - q.frameSize ~/ 4);
        expect(q.lowestReliableHz(), closeTo(1.5 * _sr / q.overlap, 1e-9));
      }
      // And it scales with the sample rate, since the floor is about SAMPLES
      // per period, not Hz.
      expect(
        StretchQuality.deep.lowestReliableHz(22050),
        closeTo(StretchQuality.deep.lowestReliableHz() / 2, 1e-9),
      );
    });
  });

  group('the transient story that did NOT survive measurement', () {
    test('every setting doubles hits equally at a factor of 2', () {
      // Recorded as a fact, not a defect. WSOLA repeats material at large
      // factors and frame length does not fix that — which is exactly why the
      // setting is NOT named "percussive vs tonal". If this ever starts
      // discriminating, the naming should be revisited.
      Float64List hits() {
        const n = _sr;
        final out = Float64List(n);
        for (var h = 0; h < 8; h++) {
          final at = h * (n ~/ 8);
          for (var i = 0; i < 200 && at + i < n; i++) {
            out[at + i] =
                math.exp(-i / 40) * math.sin(2 * math.pi * 1800 * i / _sr);
          }
        }
        return out;
      }

      int onsets(Float64List p) {
        const w = 64;
        final env = <double>[];
        for (var i = 0; i + w < p.length; i += w) {
          var s = 0.0;
          for (var j = 0; j < w; j++) {
            s += p[i + j] * p[i + j];
          }
          env.add(math.sqrt(s / w));
        }
        final thr = env.reduce(math.max) * 0.25;
        var n = 0;
        var armed = true;
        for (final e in env) {
          if (armed && e > thr) {
            n++;
            armed = false;
          }
          if (e < thr * 0.5) armed = true;
        }
        return n;
      }

      final counts = <int>[
        for (final q in StretchQuality.values)
          onsets(timeStretch(hits(), 2, quality: q)),
      ];
      expect(
        counts.toSet(),
        hasLength(1),
        reason: 'frame length was expected NOT to change this: $counts',
      );
      expect(
        counts.first,
        greaterThan(8),
        reason: 'WSOLA does repeat material at a factor of 2',
      );
    });
  });

  group('the default is exactly the old behaviour', () {
    test('BALANCED is byte-identical to the previous hardcoded settings', () {
      final note = _note(220, seconds: 0.35);
      final byDefault = timeStretch(note, 1.3);
      // Looked up by index rather than named: passing the default explicitly
      // is the POINT of this test and the analyzer const-folds a named
      // constant into "redundant". The index also matters in its own right —
      // the FX registry stores this param as a number and defaults it to 1, so
      // `balanced` being values[1] is load-bearing, not incidental.
      final balanced = StretchQuality.values[1];
      expect(balanced, StretchQuality.balanced);
      final explicit = timeStretch(note, 1.3, quality: balanced);
      expect(byDefault, orderedEquals(explicit));
      expect(StretchQuality.balanced.frameSize, 1024);
      expect(StretchQuality.balanced.hop, 256);
      expect(StretchQuality.balanced.tolerance, 256);
    });

    test('every setting preserves LENGTH', () {
      // The contract clip warp rests on: a quality knob that changed the
      // duration would silently break the arrangement.
      final note = _note(220, seconds: 0.5);
      for (final q in StretchQuality.values) {
        final out = timeStretch(note, 1.5, quality: q);
        expect(
          out.length,
          closeTo((note.length * 1.5).round(), q.frameSize),
          reason: q.name,
        );
      }
    });

    test('the stereo twin applies the SAME setting to both channels', () {
      // Different settings per channel would decorrelate them — the one thing
      // a stereo stretch must never do.
      final note = _note(220, seconds: 0.3);
      final out =
          timeStretchStereo(note, note, 1.4, quality: StretchQuality.deep);
      expect(out.left, orderedEquals(out.right));
    });
  });

  group('degenerate inputs', () {
    test('every setting survives a buffer shorter than its own frame', () {
      // Not hypothetical: clip warp hands this exactly that on a short one-shot.
      final tiny = Float64List(500);
      for (var i = 0; i < tiny.length; i++) {
        tiny[i] = math.sin(2 * math.pi * 440 * i / _sr);
      }
      for (final q in StretchQuality.values) {
        final out = timeStretch(tiny, 1.5, quality: q);
        expect(out, isNotEmpty, reason: q.name);
        expect(out.every((v) => v.isFinite), isTrue, reason: q.name);
      }
    });

    test('an empty buffer stays empty at every setting', () {
      for (final q in StretchQuality.values) {
        expect(timeStretch(Float64List(0), 1.5, quality: q), isEmpty);
      }
    });
  });
}
