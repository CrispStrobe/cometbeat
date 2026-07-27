// B1/B3 — the editor ops that are not same-length transforms.
//
// An FX chain maps N samples to N, which is why the rack can be a list of
// modules. These change the LENGTH or the structure — insert silence, repeat a
// take, find where the gaps are, join two takes — so they are not effects, and
// they are tested here as the pure functions the service, the CLI and these
// tests all share.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone({int ms = 1000, double amp = 0.4, double hz = 440}) {
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

Float64List _silence(int ms) => Float64List(ms * _sr ~/ 1000);

Float64List _concat(List<Float64List> parts) {
  final out = Float64List(parts.fold(0, (n, p) => n + p.length));
  var at = 0;
  for (final p in parts) {
    out.setRange(at, at + p.length, p);
    at += p.length;
  }
  return out;
}

double _ms(Float64List x) => x.length * 1000 / _sr;

double _rms(Float64List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

void main() {
  group('pad', () {
    test('adds silence at both ends', () {
      final take = padTake(
        _tone(),
        null,
        leadMs: 500,
        tailMs: 250,
        sampleRate: _sr,
      );
      expect(_ms(take.left), closeTo(1750, 0.1));
      // The lead really is silent, and the audio really is in the middle.
      expect(_rms(Float64List.sublistView(take.left, 0, 500 * _sr ~/ 1000)), 0);
      expect(
        _rms(
          Float64List.sublistView(
            take.left,
            600 * _sr ~/ 1000,
            1400 * _sr ~/ 1000,
          ),
        ),
        greaterThan(0.1),
      );
    });

    test('reports a NEGATIVE start shift so the audio keeps its place', () {
      // The lead pushes the audio later by exactly its own length, so a caller
      // placing this on a timeline slides the clip back by the same amount and
      // nothing moves in the arrangement.
      final take = padTake(_tone(), null, leadMs: 500, sampleRate: _sr);
      expect(take.startShiftMs, closeTo(-500, 0.1));
    });

    test('a negative pad is treated as zero, not as a trim', () {
      // Quietly reinterpreting a pad as a cut would be a surprising way to lose
      // audio; trimming has its own op.
      final take = padTake(_tone(), null, leadMs: -500, sampleRate: _sr);
      expect(_ms(take.left), closeTo(1000, 0.1));
    });

    test('stereo keeps both channels aligned', () {
      final take = padTake(
        _tone(),
        _tone(hz: 660),
        leadMs: 100,
        sampleRate: _sr,
      );
      expect(take.right, isNotNull);
      expect(take.right!.length, take.left.length);
    });
  });

  group('repeat', () {
    test('×3 is three times as long, and the copies are identical', () {
      final source = _tone(ms: 100);
      final take = repeatTake(source, null, 3);
      expect(take.left.length, source.length * 3);
      for (var i = 0; i < source.length; i++) {
        expect(take.left[i], source[i]);
        expect(take.left[i + source.length], source[i]);
        expect(take.left[i + source.length * 2], source[i]);
      }
    });

    test('×1 is unchanged and ×0 is empty', () {
      final source = _tone(ms: 50);
      expect(repeatTake(source, null, 1).left, orderedEquals(source));
      expect(repeatTake(source, null, 0).left, isEmpty);
    });
  });

  group('finding the gaps', () {
    // silence · tone · silence · tone · silence
    Float64List phrased() => _concat([
          _silence(500),
          _tone(),
          _silence(750),
          _tone(),
          _silence(250),
        ]);

    test('every silent stretch is found, with its bounds', () {
      final gaps = findSilences(phrased(), null, sampleRate: _sr);
      expect(gaps, hasLength(3));
      expect(gaps[0].startMs, closeTo(0, 1));
      expect(gaps[0].endMs, closeTo(500, 1));
      expect(gaps[1].startMs, closeTo(1500, 1));
      expect(gaps[1].endMs, closeTo(2250, 1));
      expect(gaps[2].endMs, closeTo(3500, 1));
    });

    test('the phrases between them are the complement', () {
      final phrases = findPhrases(phrased(), null, sampleRate: _sr);
      expect(phrases, hasLength(2));
      expect(phrases[0].startMs, closeTo(500, 1));
      expect(phrases[0].endMs, closeTo(1500, 1));
      expect(phrases[1].startMs, closeTo(2250, 1));
      expect(phrases[1].endMs, closeTo(3250, 1));
    });

    test('a gap shorter than the minimum is not a gap', () {
      // Without a minimum length every zero crossing of a quiet passage is a
      // "silence" and the answer is thousands of ranges that mean nothing.
      final brief = _concat([_tone(ms: 200), _silence(50), _tone(ms: 200)]);
      expect(
        findSilences(brief, null, sampleRate: _sr),
        isEmpty,
      );
      expect(
        findSilences(brief, null, minLengthMs: 20, sampleRate: _sr),
        hasLength(1),
      );
    });

    test('audio with no silence at all yields one phrase and no gaps', () {
      final solid = _tone();
      expect(findSilences(solid, null, sampleRate: _sr), isEmpty);
      final phrases = findPhrases(solid, null, sampleRate: _sr);
      expect(phrases, hasLength(1));
      expect(phrases.single.startMs, 0);
      expect(phrases.single.endMs, closeTo(1000, 1));
    });

    test('a stereo take is judged on BOTH channels', () {
      // A gap is only a gap when neither side has anything in it.
      final left = _concat([_tone(ms: 200), _silence(400), _tone(ms: 200)]);
      final right = _concat([_silence(200), _tone(ms: 400), _silence(200)]);
      expect(findSilences(left, right, sampleRate: _sr), isEmpty);
      expect(findSilences(left, null, sampleRate: _sr), hasLength(1));
    });
  });

  group('splice', () {
    test('the join is shorter than the sum by the crossfade', () {
      final a = _tone(ms: 500);
      final b = _tone(ms: 500);
      final take =
          spliceTakes(a, null, b, null, crossfadeMs: 100, sampleRate: _sr);
      expect(_ms(take.left), closeTo(900, 1));
    });

    test('equal-power holds the level joining UNRELATED takes', () {
      // Which is what a splice usually is. Equal-power keeps the total power
      // constant, so two unrelated signals cross without a dip.
      final a = _tone(ms: 500);
      final b = _tone(ms: 500, hz: 997); // unrelated pitch → uncorrelated
      final take =
          spliceTakes(a, null, b, null, crossfadeMs: 100, sampleRate: _sr);
      const joinAt = 450 * _sr ~/ 1000;
      final atJoin = _rms(
        Float64List.sublistView(take.left, joinAt, joinAt + 2000),
      );
      final before = _rms(Float64List.sublistView(take.left, 0, 2000));
      expect(atJoin, closeTo(before, before * 0.15));
    });

    test('…and on CORRELATED takes it reads +3 dB, which is why linear exists',
        () {
      // My first version of this test asserted the opposite and failed, which
      // was the test being wrong rather than the code: equal-power adds POWERS,
      // so two copies of the same tone sum to about ×1.41 at the join. Pinned
      // both ways so the trade-off cannot be mistaken for a bug.
      final a = _tone(ms: 500);
      final b = _tone(ms: 500); // the same tone — perfectly correlated
      const joinAt = 450 * _sr ~/ 1000;
      double levelAtJoin(SpliceCurve curve) {
        final take = spliceTakes(
          a,
          null,
          b,
          null,
          crossfadeMs: 100,
          curve: curve,
          sampleRate: _sr,
        );
        return _rms(Float64List.sublistView(take.left, joinAt, joinAt + 2000));
      }

      final before = _rms(Float64List.sublistView(a, 0, 2000));
      // Equal-power bulges…
      expect(levelAtJoin(SpliceCurve.equalPower), greaterThan(before * 1.2));
      // …and linear is the one that holds the level here.
      expect(
        levelAtJoin(SpliceCurve.linear),
        closeTo(before, before * 0.15),
      );
    });

    test('a zero crossfade is a hard butt join', () {
      final a = _tone(ms: 100);
      final b = _tone(ms: 100);
      final take =
          spliceTakes(a, null, b, null, crossfadeMs: 0, sampleRate: _sr);
      expect(take.left.length, a.length + b.length);
    });

    test('a crossfade longer than the takes is clamped, not crashed', () {
      final a = _tone(ms: 50);
      final b = _tone(ms: 50);
      final take =
          spliceTakes(a, null, b, null, crossfadeMs: 5000, sampleRate: _sr);
      expect(take.left, isNotEmpty);
      expect(take.left.length, lessThanOrEqualTo(a.length + b.length));
    });
  });

  group('full statistics', () {
    test('a clean sine reads as healthy', () {
      final stats = fullStatsOf(_tone(), null, sampleRate: _sr);
      expect(stats.basic.peak, closeTo(0.4, 0.01));
      // A sine has no DC and a crest factor of 3.01 dB by definition.
      expect(stats.dcOffset, closeTo(0, 1e-6));
      expect(stats.crestFactorDb, closeTo(3.01, 0.2));
      // 440 Hz for one second crosses zero 880 times.
      expect(stats.zeroCrossings, closeTo(880, 4));
    });

    test('DC offset is measured — it is invisible on a level meter', () {
      final shifted = Float64List.fromList(_tone());
      for (var i = 0; i < shifted.length; i++) {
        shifted[i] += 0.1;
      }
      expect(
        fullStatsOf(shifted, null, sampleRate: _sr).dcOffset,
        closeTo(0.1, 1e-3),
      );
    });

    test('crest factor collapses under heavy compression', () {
      // The measurement that says "over-compressed" when no loudness number
      // will: a square wave is peak == RMS, a crest factor of 0 dB.
      final square = Float64List(_sr);
      for (var i = 0; i < square.length; i++) {
        square[i] = (i ~/ 50).isEven ? 0.5 : -0.5;
      }
      expect(
        fullStatsOf(square, null, sampleRate: _sr).crestFactorDb,
        closeTo(0, 0.1),
      );
    });

    test('effective bit depth spots a converted file', () {
      // Every sample landing on a 16-bit boundary means this was converted,
      // not recorded at the depth it claims.
      final quantised = Float64List(1000);
      const step = 2.0 / (1 << 16);
      for (var i = 0; i < quantised.length; i++) {
        quantised[i] = (math.sin(i / 20) / step).roundToDouble() * step;
      }
      expect(
        fullStatsOf(quantised, null, sampleRate: _sr).effectiveBits,
        16,
      );
    });

    test('it still carries the basic stats, unchanged', () {
      final tone = _tone();
      final full = fullStatsOf(tone, null, sampleRate: _sr);
      final basic = clipStatsOf(tone, null, sampleRate: _sr);
      expect(full.basic.peak, basic.peak);
      expect(full.basic.rms, basic.rms);
      expect(full.basic.durationMs, basic.durationMs);
    });
  });
}
