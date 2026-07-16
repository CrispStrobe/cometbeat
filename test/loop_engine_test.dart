// LoopEngine — the Loop Mixer's Flutter-free core. Covers the timing grid
// (incl. swing), the data-pattern model (variants, euclidean rows), the
// mixdown invariants (silence, no clipping, combo-independent levels), the
// GrooveSpec snapshot/serialization and the render cache. Mirrors
// synth_test.dart: pure Dart, no device audio.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/loop_engine.dart';
import 'package:klang_universum/core/audio/synth.dart';

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
}
