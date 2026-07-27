// B4/B2 — trimming by where the VOICE is, and reducing bit depth honestly.
//
// Both are easy to fake a passing test for. A "VAD" that just trims silence
// passes any test written with a clean fixture, and a "dither" that only
// quantises passes anything that checks the bit depth. So the assertions here
// are the ones that separate the real thing from the cheap version: the trim
// survives a noise floor that a plain threshold cannot handle, and the dither's
// error is NOISE rather than distortion — measured in the spectrum.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_edits.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone({int ms = 500, double amp = 0.5, double hz = 440}) {
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

/// Room tone — quiet, but NOT silence, which is the case a fixed sample
/// threshold gets wrong.
Float64List _room({int ms = 500, double amp = 0.02, int seed = 3}) {
  final r = math.Random(seed);
  final n = ms * _sr ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (r.nextDouble() * 2 - 1) * amp;
  }
  return out;
}

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

/// Energy in a band, by summing Goertzel magnitudes across it.
double _bandEnergy(Float64List signal, double fromHz, double toHz) {
  var total = 0.0;
  for (var hz = fromHz; hz <= toHz; hz += (toHz - fromHz) / 12) {
    final w = 2 * math.pi * hz / _sr;
    final coeff = 2 * math.cos(w);
    var s1 = 0.0, s2 = 0.0;
    for (final x in signal) {
      final s0 = x + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final real = s1 - s2 * math.cos(w);
    final imag = s2 * math.sin(w);
    total += math.sqrt(real * real + imag * imag) / signal.length;
  }
  return total;
}

void main() {
  group('voice-activity trim', () {
    test('cuts the lead and tail, keeps the voice', () {
      final take = voiceActivityTrim(
        _concat([_room(ms: 800), _tone(ms: 1000), _room(ms: 600)]),
        null,
        sampleRate: _sr,
      );
      // 800 ms of room removed, less the 60 ms pad that protects the onset.
      expect(take.startShiftMs, closeTo(740, 40));
      // What is left is the tone plus the two pads, not the whole file.
      expect(_ms(take.left), closeTo(1120, 80));
    });

    test('works where a fixed sample threshold cannot', () {
      // The case VAD exists for: room tone LOUDER than the quietest part of the
      // speech. A single threshold either keeps the room or eats the word;
      // measuring the floor and working in frames handles both.
      final room = _room(amp: 0.05, ms: 700);
      final quietWord = _tone(ms: 600, amp: 0.12);
      final take = voiceActivityTrim(
        _concat([room, quietWord, _room(amp: 0.05, ms: 700, seed: 9)]),
        null,
        sampleRate: _sr,
      );
      // The word survived…
      expect(_ms(take.left), greaterThan(500));
      // …and most of the room did not.
      expect(_ms(take.left), lessThan(1200));
    });

    test('hysteresis: one isolated click does not open the gate', () {
      // A single loud frame in the middle of room tone is not speech starting.
      final noisy = _concat([_room(), _tone(ms: 1000), _room()]);
      noisy[100] = 0.9; // a click, very early, one sample
      final take = voiceActivityTrim(noisy, null, sampleRate: _sr);
      // The trim still starts near the TONE, not at the click.
      expect(take.startShiftMs, greaterThan(300));
    });

    test('a take with no voice comes back empty — the caller decides', () {
      // Same contract as trimSilenceTake: empty means "nothing to keep", and
      // callers already read that as leave-it-alone.
      //
      // The room here is ~−50 dBFS, which is what room tone in a real recording
      // measures. That matters: a file with NO dynamic contrast cannot be
      // judged by the relative test, so absolute level breaks the tie, and this
      // fixture has to sit on the unambiguous side of it.
      final take =
          voiceActivityTrim(_room(ms: 900, amp: 0.004), null, sampleRate: _sr);
      expect(take.left, isEmpty);
    });

    test('…but uniformly LOUD material is kept — where the line sits', () {
      // The other side of the same tiebreak, asserted so the judgment is
      // visible rather than buried in a constant: steady noise at −25 dBFS is
      // not a room, it is quiet content, and throwing it away would be the
      // worst outcome this function can produce.
      final loudRoom = _room(ms: 900, amp: 0.1);
      final take = voiceActivityTrim(loudRoom, null, sampleRate: _sr);
      expect(take.left.length, loudRoom.length);
    });

    test('a take that is voice throughout is returned untouched', () {
      final solid = _tone(ms: 800);
      final take = voiceActivityTrim(solid, null, sampleRate: _sr);
      expect(take.left.length, solid.length);
      expect(take.startShiftMs, 0);
    });

    test('stereo keeps both channels aligned', () {
      final take = voiceActivityTrim(
        _concat([_room(), _tone(), _room()]),
        _concat([_room(seed: 5), _tone(hz: 660), _room(seed: 6)]),
        sampleRate: _sr,
      );
      expect(take.right, isNotNull);
      expect(take.right!.length, take.left.length);
    });
  });

  group('dither', () {
    test('it really reduces the resolution', () {
      final take = ditherTake(_tone(), null, bits: 8);
      expect(
        fullStatsOf(take.left, null, sampleRate: _sr).effectiveBits,
        8,
      );
    });

    test('the same seed gives the same noise', () {
      // A render that cannot repeat its own dither is not reproducible, and a
      // test could not assert anything about it.
      final a = ditherTake(_tone(), null, bits: 8);
      final b = ditherTake(_tone(), null, bits: 8);
      expect(a.left, orderedEquals(b.left));
    });

    test('dither breaks up the quantisation DISTORTION', () {
      // The point of dithering, and the thing a plain quantiser gets wrong. A
      // quiet tone truncated to few bits produces harmonics locked to the
      // signal — audible as grit. Dither turns that into broadband noise, so
      // the harmonic that truncation creates should be weaker.
      final quiet = _tone(amp: 0.02, hz: 1000);
      final dithered = ditherTake(quiet, null, bits: 6).left;

      // Undithered quantisation, for comparison.
      const steps = 32.0;
      final truncated = Float64List(quiet.length);
      for (var i = 0; i < quiet.length; i++) {
        truncated[i] = (quiet[i] * steps).roundToDouble() / steps;
      }

      // The third harmonic is where truncation of a sine puts its energy.
      final harmonicTruncated = _bandEnergy(truncated, 2950, 3050);
      final harmonicDithered = _bandEnergy(dithered, 2950, 3050);
      expect(harmonicDithered, lessThan(harmonicTruncated));
    });

    test('noise shaping moves the noise UP, out of the sensitive band', () {
      // The trade: total noise power goes UP, audible noise goes down, because
      // the ear is far more sensitive at 3 kHz than at 15 kHz.
      final quiet = _tone(amp: 0.01, hz: 200, ms: 1000);
      final plain = ditherTake(quiet, null, bits: 8).left;
      final shaped = ditherTake(quiet, null, bits: 8, noiseShaping: true).left;

      final plainMid = _bandEnergy(plain, 2000, 4000);
      final shapedMid = _bandEnergy(shaped, 2000, 4000);
      final plainTop = _bandEnergy(plain, 15000, 20000);
      final shapedTop = _bandEnergy(shaped, 15000, 20000);

      // Less where the ear is sharp…
      expect(shapedMid, lessThan(plainMid));
      // …more where it is not. Both halves matter: only the first would also
      // pass for a shaper that simply removed noise, which is not what this is.
      expect(shapedTop, greaterThan(plainTop));
    });

    test('shaping is off by default — it is an end-of-chain choice', () {
      // Asserted as "the default is NOT the shaped result", because comparing
      // the default against an explicit `noiseShaping: false` would just be the
      // same call twice and prove nothing.
      final quiet = _tone(amp: 0.01, hz: 200);
      final byDefault = ditherTake(quiet, null, bits: 8).left;
      final shaped = ditherTake(quiet, null, bits: 8, noiseShaping: true).left;
      var differs = false;
      for (var i = 0; i < byDefault.length && !differs; i++) {
        if ((byDefault[i] - shaped[i]).abs() > 1e-12) differs = true;
      }
      expect(differs, isTrue, reason: 'the flag should change the output');
    });

    test('the result stays in range', () {
      final loud = _tone(amp: 0.999);
      final take = ditherTake(loud, null, bits: 8);
      for (final v in take.left) {
        expect(v.abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('stereo dithers both channels', () {
      final take = ditherTake(_tone(), _tone(hz: 660), bits: 8);
      expect(take.right, isNotNull);
      expect(
        fullStatsOf(take.left, take.right, sampleRate: _sr).effectiveBits,
        8,
      );
    });
  });
}
