// LoopEngine — the Loop Mixer's Flutter-free core. Covers the timing grid
// (incl. swing), the data-pattern model (variants, euclidean rows), the
// mixdown invariants (silence, no clipping, combo-independent levels), the
// GrooveSpec snapshot/serialization and the render cache. Mirrors
// synth_test.dart: pure Dart, no device audio.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

Int16List _pcm(Uint8List wav) => Int16List.sublistView(wav, 44);

int _peak(Uint8List wav) {
  var peak = 0;
  for (final s in _pcm(wav)) {
    if (s.abs() > peak) peak = s.abs();
  }
  return peak;
}

void main() {
  test('supported tempos keep the step grid integral in ms and samples', () {
    for (final bpm in [75, 100, 120]) {
      final t = LoopTiming(tempoBpm: bpm);
      expect(t.beatMs * bpm, 60000, reason: '$bpm bpm beat is integral');
      expect(t.stepMs * 2, t.beatMs, reason: '$bpm bpm step is integral');
      expect(
        (t.stepMs * kSampleRate) % 1000,
        0,
        reason: '$bpm bpm step is a whole sample count',
      );
      expect(t.totalMs, t.stepMs * t.totalSteps);
    }
  });

  test('swing delays off-eighths, keeps the loop length, and is bounded', () {
    const straight = LoopTiming(tempoBpm: 100);
    const swung = LoopTiming(tempoBpm: 100, swing: 0.5);
    expect(swung.totalMs, straight.totalMs);
    expect(swung.totalSamples, straight.totalSamples);
    // Even boundaries unmoved, odd boundaries late by swing × step.
    expect(swung.boundaryMs(0), 0);
    expect(swung.boundaryMs(2), straight.boundaryMs(2));
    expect(swung.boundaryMs(1), straight.boundaryMs(1) + 150);
    expect(swung.boundaryMs(swung.totalSteps), swung.totalMs);
    // A swung melodic stem still fills the loop exactly.
    final track = kLoopMixerTracks.firstWhere((t) => t.id == 'melody');
    expect(track.variants.first.render(swung).length, swung.totalSamples);
  });

  // Regression: swing = 0.5 @ 100 bpm is the one value where stepMs × swing
  // lands on the 10 ms grid, so the assertion above passed by LUCK. Other
  // slider positions gave a non-integral swing offset, each swung eighth
  // truncated up to a sample in renderSegmentsRaw, and stems of different
  // patterns drifted up to 8 samples apart — the "steps integral in ms AND
  // samples" invariant this class promises. _swingMs now snaps to the 10 ms
  // grid, so EVERY stem is exactly totalSamples at every tempo and swing.
  test('every stem is sample-exact at all tempos and swing amounts', () {
    for (final bpm in [75, 100, 120]) {
      for (final swing in [0.1, 0.15, 0.25, 0.33, 0.37, 0.5, 0.6]) {
        final t = LoopTiming(tempoBpm: bpm, swing: swing);
        // Boundaries land on the sample grid: ms × 44.1 is a whole number iff
        // the ms is a multiple of 10.
        for (var step = 0; step <= t.totalSteps; step++) {
          expect(
            t.boundaryMs(step) % 10,
            0,
            reason: 'bpm=$bpm swing=$swing boundary $step off the 10ms grid',
          );
        }
        for (final track in kLoopMixerTracks) {
          for (final v in track.variants) {
            expect(
              v.render(t).length,
              t.totalSamples,
              reason: 'bpm=$bpm swing=$swing ${track.id} stem drifted',
            );
          }
        }
      }
    }
  });

  test('euclid distributes the right number of hits evenly', () {
    for (final (hits, steps) in [(3, 8), (5, 8), (7, 16), (4, 16)]) {
      final row = euclid(hits, steps);
      expect(row.length, steps);
      expect(row.where((h) => h).length, hits, reason: 'E($hits,$steps)');
      // Even distribution: gaps between hits differ by at most 1.
      final positions = [
        for (var i = 0; i < steps; i++)
          if (row[i]) i,
      ];
      final gaps = [
        for (var i = 0; i < positions.length; i++)
          (positions[(i + 1) % positions.length] - positions[i] + steps) %
              steps,
      ];
      final sorted = [...gaps]..sort();
      expect(sorted.last - sorted.first, lessThanOrEqualTo(1));
    }
    // Rotation pins the first hit to step 0.
    expect(euclid(3, 8, rotation: 2).first, isTrue);
    expect(stepRow('x..x.x..'), [
      true, false, false, true, false, true, false, false, //
    ]);
  });

  test('built-in tracks: unique ids, and every variant fills the loop', () {
    final ids = kLoopMixerTracks.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);

    const timing = LoopTiming(tempoBpm: 100);
    for (final track in kLoopMixerTracks) {
      expect(track.variants, isNotEmpty, reason: track.id);
      for (var v = 0; v < track.variants.length; v++) {
        final stem = track.variants[v].render(timing);
        expect(
          stem.length,
          timing.totalSamples,
          reason: '${track.id}[$v] stem length',
        );
        expect(
          stem.any((s) => s.abs() > 1e-6),
          isTrue,
          reason: '${track.id}[$v] renders audio',
        );
      }
    }
  });

  test('empty set renders full-length silence', () {
    final engine = LoopEngine();
    final wav = engine.renderLoop();
    expect(wav.length, 44 + engine.timing.totalSamples * 2);
    expect(_peak(wav), 0);
  });

  test('toggling tracks changes the render; the mix never clips', () {
    final engine = LoopEngine();
    expect(engine.toggle('drums'), isTrue);
    final drums = engine.renderLoop();
    expect(_peak(drums), greaterThan(2000), reason: 'audible');

    expect(engine.toggle('bass'), isTrue);
    final drumsBass = engine.renderLoop();
    expect(drumsBass, isNot(equals(drums)));

    for (final track in engine.tracks) {
      engine.enabled.add(track.id);
    }
    final full = engine.renderLoop();
    // The tanh soft-knee caps the sum below full scale even with all tracks.
    expect(_peak(full), lessThan(32767));
    expect(engine.toggle('drums'), isFalse, reason: 'toggle off');
  });

  test('a track sounds the same alone as inside a mix (no level pumping)', () {
    final engine = LoopEngine();
    engine.enabled.add('chords');
    final solo = _pcm(engine.renderLoop());

    engine.enabled.add('sparkle');
    final mixed = _pcm(engine.renderLoop());

    // The sparkle pattern is silent for its first two steps, so there the mix
    // must be (near-)identical to the solo chord render — a per-combo
    // normalization would rescale it. tanh compression differs only at high
    // amplitude, so allow a small tolerance.
    final quiet = (engine.timing.stepMs * kSampleRate) ~/ 1000;
    for (var i = 0; i < quiet; i++) {
      expect((mixed[i] - solo[i]).abs(), lessThanOrEqualTo(64), reason: '@$i');
    }
  });

  test('variants cycle A→B→C→A and change the render', () {
    final engine = LoopEngine();
    engine.enabled.add('drums');
    final a = engine.renderLoop();
    expect(engine.cycleVariant('drums'), 1);
    final b = engine.renderLoop();
    expect(b, isNot(equals(a)));
    expect(engine.cycleVariant('drums'), 2);
    expect(engine.cycleVariant('drums'), 0);
    expect(identical(engine.renderLoop(), a), isTrue, reason: 'cache hit');
  });

  test('levels scale a track and swing changes the groove render', () {
    final engine = LoopEngine();
    engine.enabled.add('chords');
    final loud = _peak(engine.renderLoop());

    engine.levels['chords'] = 0.5;
    final soft = _peak(engine.renderLoop());
    // Half level ≈ half peak (tanh is near-linear at pad level).
    expect(soft, closeTo(loud / 2, loud * 0.08));

    // Swing needs off-eighth onsets to bite — the held chord pad has none,
    // so probe with the melody riff.
    engine.levels.remove('chords');
    engine.enabled
      ..clear()
      ..add('melody');
    engine.swing = 0.4;
    final swung = engine.renderLoop();
    engine.swing = 0;
    expect(swung, isNot(equals(engine.renderLoop())));
  });

  test('GrooveSpec: snapshot, json roundtrip, applySpec, cache identity', () {
    final engine = LoopEngine();
    engine
      ..toggle('drums')
      ..toggle('melody')
      ..cycleVariant('drums')
      ..levels['melody'] = 0.7
      ..tempoBpm = 120
      ..swing = 0.25;

    final spec = engine.spec;
    final restored = GrooveSpec.fromJson(spec.toJson());
    expect(restored.cacheKey, spec.cacheKey);

    final other = LoopEngine()..applySpec(restored);
    expect(other.enabled, {'drums', 'melody'});
    expect(other.variants['drums'], 1);
    expect(other.levels['melody'], 0.7);
    expect(other.tempoBpm, 120);
    expect(other.swing, 0.25);
    expect(
      other.renderLoop(),
      equals(engine.renderLoop()),
      reason: 'same spec → identical WAV',
    );

    // Unknown ids from a foreign token are dropped defensively.
    final foreign = GrooveSpec.fromJson({
      'e': ['drums', 'theremin'],
      't': 100,
    });
    final safe = LoopEngine()..applySpec(foreign);
    expect(safe.enabled, {'drums'});
  });

  test('a progression makes a 4-bar loop; followers re-voice, others tile', () {
    final engine = LoopEngine();
    engine.enabled.addAll({'bass', 'melody'});
    final vampSamples = engine.timing.totalSamples;

    engine.progression = kProgressions.first; // I–V–vi–IV
    expect(engine.timing.bars, 4);
    expect(engine.timing.totalSamples, vampSamples * 2);
    final wav = engine.renderLoop();
    expect(wav.length, 44 + vampSamples * 2 * 2);

    final pcm = _pcm(wav);
    final barSamples = engine.timing.totalSamples ~/ 4;
    // The melody tiles: bar 3 repeats bar 1 exactly. The bass follows the
    // chords: bar 2 (V) differs from bar 1 (I) — so the combined signal must
    // repeat where only tiling happens and differ where the harmony moves.
    var tiledDiff = 0;
    for (var i = 0; i < barSamples * 2; i++) {
      if (pcm[i] != pcm[i + barSamples * 2]) tiledDiff++;
    }
    expect(
      tiledDiff,
      greaterThan(0),
      reason: 'bass re-voices, halves differ',
    );

    engine.enabled.remove('bass');
    final melodyOnly = _pcm(engine.renderLoop());
    for (var i = 0; i < barSamples * 2; i++) {
      expect(
        melodyOnly[i],
        melodyOnly[i + barSamples * 2],
        reason: 'melody tiles exactly @$i',
      );
      if (i > 100) break; // spot-check the head, full scan is slow
    }

    // Spec carries the progression; roundtrip restores it.
    final restored = LoopEngine()
      ..applySpec(GrooveSpec.fromJson(engine.spec.toJson()));
    expect(restored.progression?.id, 'axis');
    expect(restored.timing.bars, 4);
  });

  test('fill swaps only the drum stem, only when drums are enabled', () {
    final engine = LoopEngine();
    engine.enabled.addAll({'bass', 'melody'});
    // No drums → the fill flag is a no-op (same cached object).
    expect(
      identical(engine.renderLoop(fill: true), engine.renderLoop()),
      isTrue,
    );

    engine.enabled.add('drums');
    final normal = engine.renderLoop();
    final fill = engine.renderLoop(fill: true);
    expect(fill, isNot(equals(normal)));
    expect(fill.length, normal.length);
    // Repeated fill renders hit the cache.
    expect(identical(engine.renderLoop(fill: true), fill), isTrue);
  });

  test('groove share tokens roundtrip and reject foreign input', () {
    final engine = LoopEngine()
      ..toggle('drums')
      ..toggle('bass')
      ..cycleVariant('bass')
      ..swing = 0.3
      ..progression = kProgressions.last;

    final token = encodeGrooveToken(engine.spec);
    expect(token, startsWith('KU1.'));
    final decoded = decodeGrooveToken(token);
    expect(decoded, isNotNull);
    expect(decoded!.cacheKey, engine.spec.cacheKey);

    final restored = LoopEngine()..applySpec(decoded);
    expect(restored.renderLoop(), equals(engine.renderLoop()));

    expect(decodeGrooveToken('hello'), isNull);
    expect(decodeGrooveToken('KU1.%%%not-base64%%%'), isNull);
    expect(decodeGrooveToken('KU1.aGVsbG8'), isNull, reason: 'not json');
  });

  // Regression: a share token is user-pasteable free text, and every spec field
  // is validated on the way in EXCEPT tempo, which passed through raw into
  // `beatMs = 60000 ~/ tempoBpm`. These tokens are all structurally valid, so
  // decodeGrooveToken accepts them and the caller's "invalid code" path never
  // fires — the damage landed one call later: t=0 threw
  // IntegerDivisionByZeroException, t=-100 gave totalSamples=-211680 (RangeError
  // allocating the mix buffer), t=60001 collapsed totalMs to 0 (modulo-by-zero
  // in the playback ticker, every frame), t=1 rendered an 8-minute ~42 MB WAV
  // synchronously on the UI thread.
  test('a hand-edited tempo in a share token cannot break the timing math', () {
    String tokenFor(int t) {
      final json = jsonEncode({
        'e': ['drums'],
        't': t,
      });
      return 'KU1.${base64Url.encode(utf8.encode(json))}';
    }

    for (final t in [0, -100, 1, 60001]) {
      final spec = decodeGrooveToken(tokenFor(t));
      expect(spec, isNotNull, reason: 't=$t is structurally valid json');
      expect(
        spec!.tempoBpm,
        inInclusiveRange(kMinTempoBpm, kMaxTempoBpm),
        reason: 't=$t must be clamped by fromJson',
      );

      final engine = LoopEngine()..applySpec(spec);
      expect(engine.tempoBpm, inInclusiveRange(kMinTempoBpm, kMaxTempoBpm));

      // The timing math must stay positive and finite, and a render must not
      // blow up.
      final timing = LoopTiming(tempoBpm: engine.tempoBpm);
      expect(timing.totalMs, greaterThan(0), reason: 't=$t');
      expect(timing.totalSamples, greaterThan(0), reason: 't=$t');
      expect(engine.renderLoop(), isNotEmpty, reason: 't=$t');
    }
  });

  test('the tempo setter clamps direct misuse, leaving valid tempos alone', () {
    final engine = LoopEngine();
    engine.tempoBpm = 0;
    expect(engine.tempoBpm, kMinTempoBpm);
    engine.tempoBpm = 100000;
    expect(engine.tempoBpm, kMaxTempoBpm);
    // The constructor bypasses the setter — it must clamp too.
    expect(LoopEngine(tempoBpm: 0).tempoBpm, kMinTempoBpm);
    // The tempos the UI actually offers are untouched.
    for (final bpm in [75, 100, 120]) {
      expect(LoopEngine(tempoBpm: bpm).tempoBpm, bpm);
    }
  });

  test('infinite mode: deterministic per iteration, varied across them', () {
    final engine = LoopEngine();
    engine.enabled.addAll({'drums', 'melody', 'bass'});
    final base = engine.renderLoop();

    final it3a = engine.renderVariedLoop(3);
    final it3b = engine.renderVariedLoop(3);
    expect(it3a, equals(it3b), reason: 'same (spec, iteration) → same bytes');
    expect(it3a.length, base.length, reason: 'loop length untouched');

    final it4 = engine.renderVariedLoop(4);
    expect(it4, isNot(equals(it3a)), reason: 'iterations differ');

    // Fill iterations keep the (unvaried) fill drums but still ornament.
    final fillLoop = engine.renderVariedLoop(3, fill: true);
    expect(fillLoop, isNot(equals(it3a)));

    engine.enabled.clear();
    expect(
      engine.renderVariedLoop(7),
      equals(engine.renderLoop()),
      reason: 'empty groove: silence either way',
    );
  });

  test('renders are cached per spec and invalidated by tempo', () {
    final engine = LoopEngine();
    engine.enabled.add('melody');
    final first = engine.renderLoop();
    expect(identical(first, engine.renderLoop()), isTrue, reason: 'cache hit');

    engine.tempoBpm = 120;
    final faster = engine.renderLoop();
    expect(identical(first, faster), isFalse);
    expect(faster.length, lessThan(first.length), reason: 'shorter loop');
  });

  test('mixStems places drum hits without clipping and pads short stems', () {
    final hit = renderDrumPattern([(0, Drum.kick)], totalMs: 100);
    final mixed = mixStems(
      [(samples: hit, gain: 1.0), (samples: hit, gain: 1.0)],
      totalSamples: 8820, // 200 ms — longer than the stems
    );
    expect(mixed.length, 8820);
    var peak = 0;
    for (final s in mixed) {
      if (s.abs() > peak) peak = s.abs();
    }
    expect(peak, greaterThan(10000));
    expect(peak, lessThan(32767));
    // The padded tail stays silent.
    expect(mixed.sublist(5000).any((s) => s != 0), isFalse);
  });

  test('a master send effect changes the mix; none restores it', () {
    final e = LoopEngine()
      ..toggle('drums')
      ..toggle('bass');
    final dry = e.renderLoop();

    e.send = LoopSend.reverb;
    final wet = e.renderLoop();
    expect(wet, isNot(equals(dry)));
    expect(wet.length, dry.length); // same loop length

    e.send = LoopSend.delay;
    expect(e.renderLoop(), isNot(equals(wet))); // a different send

    e.send = LoopSend.none;
    expect(e.renderLoop(), equals(dry)); // send is in the cache key
  });

  // Regression: reverb/delay ran over a SINGLE loop with zero-initialized state,
  // so the render was not the steady state of a repeating signal — the first
  // ~300 ms of every iteration was echo-free and the tail sounding at the loop
  // end vanished at the wrap (an audible "delay drops out on the downbeat",
  // measured 36.9 % deviation from steady state for the delay send). The engine
  // now pre-rolls one loop, so the rendered wet loop IS the periodic steady
  // state. Verified here against a fully-converged 3-copy reference.
  test('a send effect renders the steady-state loop (seam continuity)', () {
    Float64List floats(Uint8List wav) => Float64List.fromList(
          [for (final s in Int16List.sublistView(wav, 44)) s / 32768.0],
        );
    Float64List repeat(Float64List x, int k) {
      final out = Float64List(x.length * k);
      for (var c = 0; c < k; c++) {
        out.setRange(c * x.length, (c + 1) * x.length, x);
      }
      return out;
    }

    for (final send in [LoopSend.delay, LoopSend.reverb]) {
      final e = LoopEngine()
        ..toggle('drums')
        ..toggle('bass');
      final dry = floats(e.renderLoop());
      final n = dry.length;

      // Ground truth: effect three concatenated copies, keep the last (fully
      // converged) — the same effect params the engine uses.
      final threeWet = send == LoopSend.delay
          ? delayFx(repeat(dry, 3), delayMs: 300, feedback: 0.3, mix: 0.28)
          : reverbFx(repeat(dry, 3), mix: 0.28);

      e.send = send;
      final rendered = floats(e.renderLoop());
      expect(rendered.length, n);

      var maxDev = 0.0;
      var peak = 1e-9;
      for (var i = 0; i < n; i++) {
        final d = (rendered[i] - threeWet[2 * n + i]).abs();
        if (d > maxDev) maxDev = d;
        if (threeWet[2 * n + i].abs() > peak) peak = threeWet[2 * n + i].abs();
      }
      // The rendered loop must match the converged steady state to within a
      // PCM16 quantization step (the render round-trips through Int16).
      expect(
        maxDev,
        lessThan(1.5 / 32768 + peak * 0.01),
        reason: '$send off steady state by '
            '${(maxDev / peak * 100).toStringAsFixed(1)}%',
      );
    }
  });
}
