// WS-L10 — audio tracks in the Loop Studio.
//
// A Loop Studio track was symbolic only, so a recorded loop had nowhere to live
// except a bounce. The card's own framing is the design: after WS-W1 this is "a
// track-kind admission plus tempo-matching, not a new model" — and the reason
// that is true is that `_renderMix` only ever asked a track for a Float64List.
// A recording already IS one.
//
// So the tests below are mostly about what does NOT need to be rebuilt: level,
// pan, the D3 per-track filter and every automation lane have to apply to audio
// without a line of audio-specific mixing code, because they all live after the
// stem in `mixStems`. If any of those needed special-casing, the design would be
// wrong.
//
// And one thing that DOES need care, which the card flags: the engine renders
// one buffer and repeats it gaplessly, so an audio stem must be EXACTLY the
// loop's sample count. Not close. A stem 30 ms short is 30 ms of silence every
// time round.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_audio_fit.dart';
import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine({Iterable<String> on = const ['drums']}) {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(on);
  return e;
}

/// A sine of [samples] length — recognisable after a resample, unlike noise.
Float64List _tone(int samples, {double hz = 220}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = math.sin(2 * math.pi * hz * i / kSampleRate) * 0.5;
  }
  return out;
}

/// Mono PCM of a rendered loop (WAV header dropped).
Float64List _pcm(Uint8List wav) {
  final out = Float64List((wav.length - 44) ~/ 2);
  for (var i = 0; i < out.length; i++) {
    var v = wav[44 + i * 2] | (wav[45 + i * 2] << 8);
    if (v > 32767) v -= 65536;
    out[i] = v / 32768.0;
  }
  return out;
}

double _rms(Float64List x, [int from = 0, int? to]) {
  final end = to ?? x.length;
  var sum = 0.0;
  for (var i = from; i < end; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / math.max(1, end - from));
}

/// Energy at [hz], by Goertzel — enough to hear a pitch shift.
double _at(Float64List x, double hz) {
  final w = 2 * math.pi * hz / kSampleRate;
  final coeff = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (final v in x) {
    final s0 = v + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final real = s1 - s2 * math.cos(w);
  final imag = s2 * math.sin(w);
  return math.sqrt(real * real + imag * imag) / x.length;
}

void main() {
  group('the fit lands EXACTLY on the grid', () {
    test('a take a little long is pulled to the sample', () {
      // The case this exists for: a two-bar take that is 2.03 bars because a
      // person stopped it late.
      final e = _engine();
      final target = e.timing.totalSamples;
      final id = e.addAudioTrack(_tone((target * 1.03).round()));
      expect(e.audioPcm(id)!.length, isNot(target));
      expect(
        AudioPattern(e.audioPcm(id)!).render(e.timing).length,
        target,
        reason: 'a stem that is not exactly the loop is a gap every cycle',
      );
    });

    test('every length lands exactly, short or long', () {
      final e = _engine();
      final target = e.timing.totalSamples;
      final lengths = [1, 100, target ~/ 3, target - 1, target, target * 2 + 7];
      for (final n in lengths) {
        expect(fitAudioToLoop(_tone(n), target).length, target, reason: 'n=$n');
      }
    });

    test('an empty take is silence of the right length, not an empty stem', () {
      final e = _engine();
      final fitted = fitAudioToLoop(Float64List(0), e.timing.totalSamples);
      expect(fitted.length, e.timing.totalSamples);
      expect(fitted.every((v) => v == 0), isTrue);
    });

    test('an exact take is passed through untouched', () {
      // Resampling at unity is not a no-op — it costs a rounding error — so the
      // exact case must not go through the filter at all.
      final e = _engine();
      final pcm = _tone(e.timing.totalSamples);
      expect(
        identical(fitAudioToLoop(pcm, e.timing.totalSamples), pcm),
        isTrue,
      );
    });

    test('the stretch is reported, so a caller can refuse it', () {
      expect(audioFitRatio(100, 100), 1.0);
      expect(audioFitRatio(200, 100), 0.5);
      expect(audioFitIsSubtle(1.02), isTrue);
      expect(audioFitIsSubtle(0.97), isTrue);
      expect(audioFitIsSubtle(2), isFalse, reason: 'twice as fast IS audible');

      final e = _engine();
      final id = e.addAudioTrack(_tone(e.timing.totalSamples ~/ 2));
      expect(e.audioStretchOf(id), closeTo(2, 0.01));
    });
  });

  group('it is an ORDINARY track from there on', () {
    test('it joins enabled and is audible', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      expect(e.enabled, contains(id));
      expect(e.isAudioTrack(id), isTrue);
      expect(_rms(_pcm(e.renderLoop())), greaterThan(0.01));
    });

    test('the audio actually reaches the mix at its own pitch', () {
      final e = _engine(on: const []);
      e.addAudioTrack(_tone(e.timing.totalSamples, hz: 440));
      final mix = _pcm(e.renderLoop());
      expect(_at(mix, 440), greaterThan(_at(mix, 300) * 4));
    });

    test('LEVEL applies with no audio-specific code', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      final loud = _rms(_pcm(e.renderLoop()));
      e.levels[id] = 0.25;
      expect(_rms(_pcm(e.renderLoop())), lessThan(loud * 0.5));
    });

    test('PAN applies, and switches the mix to stereo', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      e.setPan(id, -1);
      final wav = e.renderLoop();
      // Channel count lives at byte 22 of the WAV header.
      expect(wav[22], 2, reason: 'a panned track renders stereo');
      final inter = _pcm(wav);
      var left = 0.0, right = 0.0;
      for (var i = 0; i + 1 < inter.length; i += 2) {
        left += inter[i].abs();
        right += inter[i + 1].abs();
      }
      expect(left, greaterThan(right * 10), reason: 'hard left');
    });

    test('the D3 per-track FILTER applies', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples, hz: 6000));
      final open = _at(_pcm(e.renderLoop()), 6000);
      e.setTrackFilter(id, -0.95);
      expect(_at(_pcm(e.renderLoop()), 6000), lessThan(open * 0.5));
    });

    test('an automation LANE applies', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      e.setAutomation(
        id,
        AutomationParam.level,
        AutomationLane([
          for (var s = 0; s < kPatternSteps; s++)
            s < kPatternSteps ~/ 2 ? 1.0 : 0.0,
        ]),
      );
      final mix = _pcm(e.renderLoop());
      final mid = mix.length ~/ 2;
      expect(_rms(mix, 0, mid), greaterThan(0.01));
      expect(
        _rms(mix, mid + 2000),
        lessThan(0.001),
        reason: 'the lane silences the second half of the audio too',
      );
    });

    test('it mixes WITH the synthesised band', () {
      final e = _engine();
      final drumsOnly = _rms(_pcm(e.renderLoop()));
      e.addAudioTrack(_tone(e.timing.totalSamples));
      expect(_rms(_pcm(e.renderLoop())), greaterThan(drumsOnly));
    });

    test('it can be muted, removed, and duplicated', () {
      final e = _engine(on: const []);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      e.toggle(id);
      expect(_rms(_pcm(e.renderLoop())), lessThan(1e-6));
      e.toggle(id);

      final copy = e.duplicateTrack(id)!;
      expect(e.isAudioTrack(copy), isTrue);
      expect(e.audioPcm(copy), same(e.audioPcm(id)));

      expect(e.removeExtraTrack(copy), isTrue);
      expect(e.tracks.map((t) => t.id), isNot(contains(copy)));
    });
  });

  group('what it deliberately does NOT do', () {
    test('a groove with no audio track renders byte-for-byte as before', () {
      // The guard every slice in this arc has carried.
      final a = _engine(on: const ['drums', 'bass']).renderLoop();
      final e = _engine(on: const ['drums', 'bass']);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      expect(e.renderLoop(), isNot(orderedEquals(a)));
      e.removeExtraTrack(id);
      expect(e.renderLoop(), orderedEquals(a));
    });

    test('it stays OUT of the share token', () {
      // The PCM cannot travel in a paste-able string, so the roster must not
      // claim the track either — a token that promised it and restored it empty
      // would be worse than one that never mentioned it.
      final e = _engine();
      final plain = encodeGrooveToken(e.spec);
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      expect(e.spec.extraTracks.containsKey(id), isFalse);
      expect(encodeGrooveToken(e.spec), plain);
    });

    test('and it does not come back from one', () {
      final e = _engine();
      final id = e.addAudioTrack(_tone(e.timing.totalSamples));
      final restored = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);
      expect(restored.tracks.map((t) => t.id), isNot(contains(id)));
      expect(restored.isAudioTrack(id), isFalse);
    });

    test('the groove key does not repitch it', () {
      // Transposing a recording is a different, destructive feature; the key
      // moving must not silently apply it.
      final e = _engine(on: const []);
      e.addAudioTrack(_tone(e.timing.totalSamples, hz: 440));
      final atC = _pcm(e.renderLoop());
      e.key = 7;
      expect(_pcm(e.renderLoop()), orderedEquals(atC));
    });
  });

  test('the render cache is keyed on MORE than the share token', () {
    // A real bug, caught by the LEVEL test above and pinned here. Audio tracks
    // are excluded from the spec because their PCM cannot travel in a token —
    // and the render cache used to be keyed on `spec.cacheKey`, so the moment
    // they left the spec, changing an audio track's level, pan, filter or lane
    // produced an identical key and the stale WAV came straight back.
    final e = _engine(on: const []);
    final id = e.addAudioTrack(_tone(e.timing.totalSamples));
    final token = encodeGrooveToken(e.spec);
    final identity = e.renderIdentity;

    e.levels[id] = 0.25;
    expect(
      encodeGrooveToken(e.spec),
      token,
      reason: 'the SHARE token is rightly unchanged — the track is not in it',
    );
    expect(
      e.renderIdentity,
      isNot(identity),
      reason: 'but the RENDER identity must move, or the cache lies',
    );
  });

  test('the fitted stem is cached, and follows the audio', () {
    final e = _engine(on: const []);
    final id = e.addAudioTrack(_tone(e.timing.totalSamples * 2));
    final first = e.renderLoop();
    expect(e.renderLoop(), orderedEquals(first), reason: 'stable');

    // A second track with different audio must not read the first one's fit.
    final other = e.addAudioTrack(_tone(e.timing.totalSamples, hz: 880));
    expect(e.audioPcm(other), isNot(same(e.audioPcm(id))));
    expect(e.renderLoop(), isNot(orderedEquals(first)));
  });
}
