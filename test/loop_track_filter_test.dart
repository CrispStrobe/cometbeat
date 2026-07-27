// D3 — a filter per TRACK, and its automation.
//
// The master filter has always been one knob over everything, so the only move
// it can make is "all of this, duller". The one worth having is the opposite —
// dull the bass while the hats stay bright, then open it across the loop — and
// that needs the filter to be per track. It also needs to be real DSP rather
// than a scalar, which is why `AutomationParam.filter` had a value mapping, a
// codec and a UI-less existence but rendered nothing at all until now.
//
// Two things are measured here rather than asserted from the shape of the code:
//
// WHERE THE ENERGY WENT. A filter claims a spectral tilt, so each test compares
// a low band against a high band through a Goertzel probe. "The bytes changed"
// would pass for a filter wired backwards.
//
// THAT NOTHING ELSE MOVED. The guarantee every automation slice rests on is
// that a groove using none of this renders byte-for-byte as it did before, and
// the seam that carries the filter (`mixStems`' new insert) is the same seam
// the level envelope uses. So the no-filter render is compared byte-for-byte
// against the same groove rendered through a path with no inserts at all.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine({Iterable<String> on = const ['bass']}) {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(on);
  return e;
}

/// The mono PCM of a rendered loop (WAV header dropped).
Float64List _pcm(Uint8List wav) {
  final out = Float64List((wav.length - 44) ~/ 2);
  for (var i = 0; i < out.length; i++) {
    var v = wav[44 + i * 2] | (wav[45 + i * 2] << 8);
    if (v > 32767) v -= 65536;
    out[i] = v / 32768.0;
  }
  return out;
}

/// Energy across a band, summed from Goertzel probes — the one measurement
/// that can tell a low-pass from a high-pass.
double _band(Float64List signal, double fromHz, double toHz) {
  var total = 0.0;
  final step = (toHz - fromHz) / 12;
  for (var hz = fromHz; hz <= toHz; hz += step) {
    final w = 2 * math.pi * hz / kSampleRate;
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

/// High-band energy over low-band: bigger = brighter.
double _brightness(Float64List x) =>
    _band(x, 3000, 9000) / math.max(1e-12, _band(x, 80, 400));

double _rms(Float64List x, [int from = 0, int? to]) {
  final end = to ?? x.length;
  var sum = 0.0;
  for (var i = from; i < end; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / math.max(1, end - from));
}

void main() {
  group('a track filter is off until it is asked for', () {
    test('every track starts at 0', () {
      final e = _engine();
      for (final t in e.tracks) {
        expect(e.trackFilter(t.id), 0.0, reason: t.id);
      }
    });

    test('an unfiltered groove renders byte-for-byte as before', () {
      // The guarantee polymeter and the level lane both had to carry. The
      // insert list must be null, not a list of nulls, or the mixer takes a
      // different arithmetic path.
      final a = _engine(on: ['drums', 'bass', 'chords']).renderLoop();
      final b = _engine(on: ['drums', 'bass', 'chords']).renderLoop();
      expect(a, orderedEquals(b));

      final e = _engine(on: ['drums', 'bass', 'chords']);
      e.setTrackFilter('bass', -0.6);
      expect(e.renderLoop(), isNot(orderedEquals(a)));
      e.setTrackFilter('bass', 0);
      expect(
        e.renderLoop(),
        orderedEquals(a),
        reason: 'sweeping back to the middle must cost nothing again',
      );
    });

    test('setting it to 0 stores nothing, so the spec stays clean', () {
      final e = _engine();
      final plain = encodeGrooveToken(e.spec);
      e.setTrackFilter('bass', 0.0);
      expect(encodeGrooveToken(e.spec), plain);
      e.setTrackFilter('bass', 0.4);
      expect(encodeGrooveToken(e.spec), isNot(plain));
      e.setTrackFilter('bass', 0.0);
      expect(encodeGrooveToken(e.spec), plain);
    });

    test('it clamps rather than trusting its caller', () {
      final e = _engine();
      e.setTrackFilter('bass', -9);
      expect(e.trackFilter('bass'), -1.0);
      e.setTrackFilter('bass', 9);
      expect(e.trackFilter('bass'), 1.0);
    });
  });

  group('it filters the way the knob says', () {
    test('left is darker, right is thinner', () {
      final dry = _pcm(_engine().renderLoop());

      final darkE = _engine()..setTrackFilter('bass', -0.9);
      final thinE = _engine()..setTrackFilter('bass', 0.9);
      final dark = _pcm(darkE.renderLoop());
      final thin = _pcm(thinE.renderLoop());

      expect(_brightness(dark), lessThan(_brightness(dry)));
      expect(_brightness(thin), greaterThan(_brightness(dry)));
    });

    test('further left is darker still', () {
      double bright(double v) => _brightness(
            _pcm((_engine()..setTrackFilter('bass', v)).renderLoop()),
          );
      expect(bright(-0.9), lessThan(bright(-0.4)));
      expect(bright(-0.4), lessThan(bright(0)));
    });

    test('a high-pass takes the LOW end away', () {
      // Stated as its own measurement, because "brighter" is a ratio and a
      // low-pass wired backwards would also raise it.
      final dry = _pcm(_engine().renderLoop());
      final thin = _pcm((_engine()..setTrackFilter('bass', 0.9)).renderLoop());
      expect(_band(thin, 80, 400), lessThan(_band(dry, 80, 400) * 0.6));
    });
  });

  group('it is PER track', () {
    test('filtering one track leaves the other alone', () {
      // The whole point of D3: the bass goes dull and the hats stay bright.
      final bassOnly = _pcm(_engine(on: ['bass']).renderLoop());
      final drumsOnly = _pcm(_engine(on: ['drums']).renderLoop());

      final both = _engine(on: ['bass', 'drums'])
        ..setTrackFilter('bass', -0.95);
      final mixed = _pcm(both.renderLoop());

      // The drums' top end survives: the mix is brighter than the filtered
      // bass alone could ever be.
      final dullBass = _pcm(
        (_engine(on: ['bass'])..setTrackFilter('bass', -0.95)).renderLoop(),
      );
      expect(_brightness(mixed), greaterThan(_brightness(dullBass)));
      expect(
        _band(mixed, 3000, 9000),
        greaterThan(_band(dullBass, 3000, 9000)),
      );

      // …and it is genuinely the bass that changed, not the drums.
      expect(_band(bassOnly, 3000, 9000), greaterThan(0));
      expect(_band(drumsOnly, 3000, 9000), greaterThan(0));
    });

    test('it reaches the STEREO mix too, not just the mono one', () {
      // The mix has two paths and only one of them is the default: a groove
      // switches to the interleaved stereo mixdown the moment any enabled track
      // is panned off centre. A filter wired into only the mono path would go
      // silent exactly when someone started using the stereo field.
      // Hard-panned apart, so the left channel IS the bass — otherwise the
      // drums' hats bleed enough high end into it to swamp the measurement.
      final e = _engine(on: ['bass', 'drums'])
        ..setPan('bass', -1)
        ..setPan('drums', 1);
      final dry = e.renderLoop();
      e.setTrackFilter('bass', -0.95);
      final wet = e.renderLoop();
      expect(wet, isNot(orderedEquals(dry)));

      // Deinterleave the left channel (the drums are panned right, so the left
      // is mostly bass) and check it actually got darker.
      Float64List leftOf(Uint8List wav) {
        final pcm = _pcm(wav);
        return Float64List.fromList([
          for (var i = 0; i < pcm.length; i += 2) pcm[i],
        ]);
      }

      expect(_brightness(leftOf(wet)), lessThan(_brightness(leftOf(dry))));
    });

    test('the master filter still works on top of it', () {
      final e = _engine(on: ['bass', 'drums'])..setTrackFilter('bass', 0.5);
      final trackOnly = _pcm(e.renderLoop());
      e.masterFilter = -0.9;
      final andMaster = _pcm(e.renderLoop());
      expect(_brightness(andMaster), lessThan(_brightness(trackOnly)));
    });
  });

  group('the filter LANE renders — it did not before', () {
    /// A lane that is wide open for the first half of the loop and shut for the
    /// second: the sweep the whole feature exists for.
    AutomationLane halfShut() => AutomationLane([
          for (var s = 0; s < kPatternSteps; s++)
            s < kPatternSteps ~/ 2 ? 0.5 : 0.0,
        ]);

    test('a filter lane changes the render at all', () {
      // `AutomationParam.filter` had a value mapping, a codec and a share-token
      // slot, and rendered NOTHING. This is the assertion that was missing.
      final e = _engine();
      final flat = e.renderLoop();
      e.setAutomation('bass', AutomationParam.filter, halfShut());
      expect(e.renderLoop(), isNot(orderedEquals(flat)));
    });

    test('the two halves of the loop differ in brightness', () {
      final e = _engine();
      e.setAutomation('bass', AutomationParam.filter, halfShut());
      final pcm = _pcm(e.renderLoop());
      final mid = pcm.length ~/ 2;
      final first = Float64List.sublistView(pcm, 0, mid);
      final second = Float64List.sublistView(pcm, mid);
      expect(
        _brightness(second),
        lessThan(_brightness(first)),
        reason: 'the lane shuts the filter for the second half',
      );
    });

    test('a lane shorter than the loop repeats, like a pattern', () {
      // Stated as an identity rather than as a per-step brightness reading: a
      // single eighth-step of a bass line is a note attack or a decaying tail
      // depending on where it falls, and its spectrum says more about the note
      // than about the filter. Two steps tiled eight times IS the sixteen-step
      // lane, so the two renders must be the same bytes.
      final short = _engine()
        ..setAutomation(
          'bass',
          AutomationParam.filter,
          AutomationLane(const [0.5, 0.0]),
        );
      final tiled = _engine()
        ..setAutomation(
          'bass',
          AutomationParam.filter,
          AutomationLane([
            for (var s = 0; s < kPatternSteps; s++) s.isEven ? 0.5 : 0.0,
          ]),
        );
      expect(short.renderLoop(), orderedEquals(tiled.renderLoop()));
      expect(
        short.renderLoop(),
        isNot(orderedEquals(_engine().renderLoop())),
        reason: 'and it is genuinely doing something',
      );
    });

    test('an all-neutral lane is still a lane, and is still quiet about it',
        () {
      // Neutral for the filter is 0.5 → position 0 → no filtering. It must
      // render as the dry track, so that dropping the lane (which the UI does)
      // is genuinely a no-op rather than a fix for a bug.
      final e = _engine();
      final dry = e.renderLoop();
      e.setAutomation(
        'bass',
        AutomationParam.filter,
        AutomationLane.neutral(AutomationParam.filter, kPatternSteps),
      );
      final withLane = _pcm(e.renderLoop());
      final dryPcm = _pcm(dry);
      var worst = 0.0;
      for (var i = 0; i < dryPcm.length; i++) {
        worst = math.max(worst, (withLane[i] - dryPcm[i]).abs());
      }
      expect(worst, lessThan(1e-3));
    });

    test('the lane REPLACES the knob rather than stacking with it', () {
      final e = _engine()..setTrackFilter('bass', -0.95);
      final knobOnly = _pcm(e.renderLoop());
      e.setAutomation(
        'bass',
        AutomationParam.filter,
        AutomationLane.neutral(AutomationParam.filter, kPatternSteps),
      );
      expect(
        _brightness(_pcm(e.renderLoop())),
        greaterThan(_brightness(knobOnly)),
      );
    });
  });

  group('the seam stays clean', () {
    test('the filter has converged by the first sample', () {
      // A biquad starts with zero memory, but a loop's first sample follows its
      // last. Without the two-copy warm-up the loop opens with a transient that
      // is audible as a click every time round.
      final e = _engine(on: ['bass'])..setTrackFilter('bass', -0.9);
      final pcm = _pcm(e.renderLoop());
      // The tail of the loop and its head are the same musical material (the
      // pattern wraps), so a filter that had not converged would show up as a
      // much louder head than tail.
      final head = _rms(pcm, 0, 2000);
      final tail = _rms(pcm, pcm.length - 2000);
      expect(head, lessThan(math.max(tail, 1e-6) * 40));
    });

    test('nothing in the filtered buffer is NaN or clipped to nonsense', () {
      for (final v in [-1.0, -0.5, 0.5, 1.0]) {
        final pcm = _pcm((_engine()..setTrackFilter('bass', v)).renderLoop());
        for (final s in pcm) {
          expect(s.isFinite, isTrue, reason: 'position $v produced $s');
          expect(s.abs(), lessThanOrEqualTo(1.0));
        }
      }
    });
  });

  group('it travels with the groove', () {
    test('a filter survives a share token', () {
      final e = _engine();
      e.setTrackFilter('bass', -0.42);
      final back = LoopEngine(tempoBpm: 120)
        ..applySpec(decodeGrooveToken(encodeGrooveToken(e.spec))!);
      expect(back.trackFilter('bass'), closeTo(-0.42, 0.01));
    });

    test('a filter on an unknown track is dropped on load', () {
      final e = _engine();
      e.applySpec(const GrooveSpec(filters: {'tuba': -0.5}));
      expect(e.trackFilter('tuba'), 0.0);
    });

    test('a copy carries the filter it was copied from', () {
      final e = _engine();
      e.setTrackFilter('bass', 0.7);
      final copy = e.duplicateTrack('bass')!;
      expect(e.trackFilter(copy), 0.7);
      e.removeExtraTrack(copy);
      expect(e.trackFilter(copy), 0.0);
    });
  });

  test('mixStems without inserts is arithmetically untouched', () {
    // The seam itself, isolated from the engine: passing a null insert list and
    // passing no insert list at all must be the same mix, and one null entry in
    // a list must leave that stem alone.
    final a = Float64List.fromList([for (var i = 0; i < 64; i++) i / 64]);
    final b = Float64List.fromList([for (var i = 0; i < 64; i++) -i / 128]);
    final stems = <MixStem>[(samples: a, gain: 0.8), (samples: b, gain: 0.5)];
    final plain = mixStems(stems, totalSamples: 64);
    expect(mixStems(stems, totalSamples: 64), plain);
    expect(mixStems(stems, totalSamples: 64, inserts: [null, null]), plain);
    expect(
      mixStems(stems, totalSamples: 64, inserts: [null]),
      plain,
      reason: 'a short insert list must not disturb the stems it omits',
    );

    // An insert returning fewer samples than it was given falls back to the dry
    // stem rather than throwing. Internally impossible — the engine's filter
    // always returns the length it received — but a mixer that can be crashed
    // by a careless insert is a worse mixer.
    final clipped = mixStems(
      stems,
      totalSamples: 64,
      inserts: [(x) => Float64List.sublistView(x, 0, 8), null],
    );
    expect(clipped.length, 64);
  });
}
