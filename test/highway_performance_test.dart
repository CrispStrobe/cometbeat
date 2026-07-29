// test/highway_performance_test.dart
//
// The highway's one real scaling risk: a dense piece is thousands of notes, and
// both the painter and the grader see every note every frame unless they are
// careful. A phone has ~16 ms to draw a frame AND run the audio engine.
//
// These are RELATIVE assertions, not wall-clock budgets — an absolute
// millisecond bar would be a flake on a loaded CI box and would say nothing
// about the algorithm. What actually matters is that cost tracks what is ON
// SCREEN, not how long the piece is: a four-minute sonata and a sixteen-bar
// exercise show the same number of blocks at any instant, so they must cost
// about the same per frame. That is the property that breaks if someone removes
// the cull, and it is the property this file pins.

import 'dart:ui' as ui;

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/features/games/highway/highway_theme.dart';
import 'package:comet_beat/features/games/highway/highway_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chart of [bars] bars, four notes to the bar in both hands — the density of
/// a real two-hand piano piece.
HighwayChart _piece(int bars) => HighwayChart(
      name: '$bars bars',
      bpm: 120,
      events: [
        for (var b = 0; b < bars; b++)
          for (var q = 0; q < 4; q++) ...[
            HighwayEvent(
              startBeat: b * 4.0 + q,
              beats: 1,
              midi: 60 + ((b * 4 + q) % 12),
            ),
            HighwayEvent(
              startBeat: b * 4.0 + q,
              beats: 1,
              midi: 48 + ((b * 3 + q) % 12),
              voice: 1,
            ),
          ],
      ],
    );

/// Paints [frames] frames of [chart] and returns the elapsed microseconds.
int _paintCost(HighwayChart chart, {required int frames}) {
  final laneMap = KeyboardLaneMap.forRange(
    chart.lowMidi ?? 60,
    chart.highMidi ?? 72,
  );
  final rules = HighwayRules.of(HighwayDifficulty.medium);
  final grader = HighwayGrader(chart: chart, rules: rules, laneMap: laneMap);
  final palette = HighwayPalette.of(HighwaySkin.midnight);
  const size = Size(400, 800);

  // Warm the text cache and any lazy geometry, so the first frame's one-off
  // costs are not charged to the measurement.
  for (var i = 0; i < 3; i++) {
    _paintOnce(chart, laneMap, grader, rules, palette, size, i.toDouble());
  }

  final total = chart.totalBeats; // O(n) — never inside a timed loop
  final watch = Stopwatch()..start();
  for (var f = 0; f < frames; f++) {
    // Sweep across the whole piece, so no run gets to sit in one cheap spot.
    final beat = total * f / frames;
    _paintOnce(chart, laneMap, grader, rules, palette, size, beat);
  }
  watch.stop();
  return watch.elapsedMicroseconds;
}

void _paintOnce(
  HighwayChart chart,
  HighwayLaneMap laneMap,
  HighwayGrader grader,
  HighwayRules rules,
  HighwayPalette palette,
  Size size,
  double beat,
) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = highwayPainterForTest(
    chart: chart,
    laneMap: laneMap,
    notes: grader.notes,
    beat: beat,
    rules: rules,
    palette: palette,
    geometry: HighwayGeometry(
      size: size,
      railHeight: 120,
      leadBeats: rules.leadBeats,
      projection: HighwayProjection.flat,
    ),
  );
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}

void main() {
  test('paint cost tracks what is on screen, not how long the piece is', () {
    // 16 bars (128 notes) vs 500 bars (4,000 notes) — a four-minute piece.
    const frames = 40;
    // Whichever chart is measured first otherwise pays the JIT bill for the
    // whole paint path and reads several times slower than it is.
    _paintCost(_piece(16), frames: 5);
    _paintCost(_piece(500), frames: 5);
    final small = _paintCost(_piece(16), frames: frames);
    final large = _paintCost(_piece(500), frames: frames);
    // ignore: avoid_print
    print(
      'paint: 128 notes ${(small / frames / 1000).toStringAsFixed(2)} ms/frame · '
      '4000 notes ${(large / frames / 1000).toStringAsFixed(2)} ms/frame',
    );
    expect(
      large,
      lessThan(small * 4),
      reason: 'a 31× longer piece must not cost 31× a frame — the cull is what '
          'keeps this playable, and this is the test that notices it going',
    );
  });

  test('advancing the clock scans the active window, not the whole piece', () {
    const frames = 600; // ten seconds at 60 fps
    int cost(int bars) {
      final chart = _piece(bars);
      final grader = HighwayGrader(
        chart: chart,
        rules: HighwayRules.of(HighwayDifficulty.medium),
        laneMap: KeyboardLaneMap.forRange(48, 84),
      );
      // Hoisted: `totalBeats` walks every event, so leaving it in the loop
      // measures the getter instead of the thing under test. (That is not a
      // hypothetical — it read 289 µs/frame here and sent me looking for a bug
      // in the grader that was not there.)
      final total = chart.totalBeats;
      final watch = Stopwatch()..start();
      for (var f = 0; f < frames; f++) {
        grader.advanceTo(total * f / frames);
      }
      watch.stop();
      return watch.elapsedMicroseconds;
    }

    final small = cost(16);
    final large = cost(500);
    // ignore: avoid_print
    print(
      'advanceTo: 128 notes ${(small / frames).toStringAsFixed(1)} µs/frame · '
      '4000 notes ${(large / frames).toStringAsFixed(1)} µs/frame',
    );
    expect(
      large,
      lessThan(small * 6),
      reason: 'a per-frame scan of every note in the piece is what makes a long '
          'song stutter; the grader must only look at notes that are live',
    );
  });

  test('a tap is answered without walking the whole piece', () {
    final chart = _piece(500);
    final laneMap = KeyboardLaneMap.forRange(48, 84);
    final grader = HighwayGrader(
      chart: chart,
      rules: HighwayRules.of(HighwayDifficulty.medium),
      laneMap: laneMap,
    );
    final key = laneMap.railKeys().firstWhere((k) => k.midi == 60);
    // Late in the piece: a naive implementation rescans thousands of resolved
    // notes for every tap.
    grader.advanceTo(1800);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      grader.tap(key, 1800 + i * 0.001);
    }
    watch.stop();
    // ignore: avoid_print
    print('tap: ${(watch.elapsedMicroseconds / 200).toStringAsFixed(1)} µs');
    expect(watch.elapsedMicroseconds / 200, lessThan(400));
  });
}
