// test/highway_grooves_test.dart
//
// The groove ladder. The point of these assertions is that the ladder is
// actually a ladder — the first cut of the Beat Highway shipped four presets
// that all ran hats on every eighth at 92 bpm, which is three hat taps a second
// on top of kick and snare before a beginner has played one bar.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/games/highway/highway_grooves.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';
import 'package:comet_beat/core/games/highway/highway_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits per bar of eighths — how busy a groove actually is to play.
int _density(HighwayGroove g) {
  var hits = 0;
  for (final row in g.rows.values) {
    hits += row.split('').where((c) => c == 'x').length;
  }
  return hits;
}

void main() {
  test('there are dozens of them, not four', () {
    expect(kHighwayGrooves.length, greaterThanOrEqualTo(24));
  });

  test('the first rung is two limbs and no hat at all', () {
    final first = kHighwayGrooves.where((g) => g.level == 1);
    expect(first, isNotEmpty);
    for (final g in first) {
      expect(
        g.rows.containsKey(Drum.hat),
        isFalse,
        reason: '${g.name}: a hat on the first rung is the mistake this ladder '
            'exists to fix',
      );
      expect(g.bpm, lessThanOrEqualTo(64));
    }
  });

  test('difficulty actually increases with level', () {
    double meanDensity(int level) {
      final at = kHighwayGrooves.where((g) => g.level == level).toList();
      if (at.isEmpty) return 0;
      return at.map(_density).reduce((a, b) => a + b) / at.length;
    }

    expect(meanDensity(1), lessThan(meanDensity(3)));
    expect(meanDensity(3), lessThan(meanDensity(5)));
  });

  test('nothing is authored faster than it can be learnt', () {
    for (final g in kHighwayGrooves) {
      expect(g.bpm, lessThanOrEqualTo(88), reason: g.name);
      // The busiest patterns must not ALSO be the fastest.
      if (_density(g) >= 30) {
        expect(g.bpm, lessThanOrEqualTo(84), reason: g.name);
      }
    }
  });

  test('every row is a whole number of bars on the eighth grid', () {
    for (final g in kHighwayGrooves) {
      final lengths = g.rows.values.map((r) => r.length).toSet();
      expect(lengths.length, 1, reason: '${g.name}: rows of different lengths');
      expect(lengths.first % 4, 0, reason: '${g.name}: ragged bar');
      for (final row in g.rows.values) {
        expect(
          RegExp(r'^[x.]+$').hasMatch(row),
          isTrue,
          reason: '${g.name}: a row is x and . only',
        );
      }
    }
  });

  test('the drum highway offers the whole ladder, easiest first', () {
    final pieces = HighwayLibrary.forInstrument(HighwayInstrument.drums);
    expect(pieces.length, kHighwayGrooves.length);
    expect(pieces.first.level, 1);
    for (var i = 1; i < pieces.length; i++) {
      expect(pieces[i].level, greaterThanOrEqualTo(pieces[i - 1].level));
    }
  });

  test('every groove becomes a playable chart', () {
    for (final piece in HighwayLibrary.forInstrument(HighwayInstrument.drums)) {
      expect(piece.chart.events, isNotEmpty, reason: piece.id);
      expect(
        piece.chart.events.every((e) => e.lane != null && e.midi == null),
        isTrue,
        reason: '${piece.id}: a drum hit is a lane, not a pitch',
      );
    }
  });
}
