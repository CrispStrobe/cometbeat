// test/highway_grading_test.dart
//
// Grading. The rules that matter: a note is judged once, a tap claims the
// nearest one it matches, the window closes and the note is missed, the clock
// waits when it is asked to, and the hand you did NOT take on plays itself
// without ever counting for or against you.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:flutter_test/flutter_test.dart';

const _chart = HighwayChart(
  name: 'test',
  bpm: 60,
  events: [
    HighwayEvent(startBeat: 0, beats: 1, midi: 60),
    HighwayEvent(startBeat: 1, beats: 1, midi: 62),
    HighwayEvent(startBeat: 2, beats: 1, midi: 64, voice: 1),
  ],
);

final _map = KeyboardLaneMap(lowMidi: 48, highMidi: 84);

HighwayRailKey _key(int midi) =>
    _map.railKeys().firstWhere((k) => k.midi == midi);

HighwayGrader _grader({
  HighwayDifficulty difficulty = HighwayDifficulty.medium,
  Set<int>? voices,
}) =>
    HighwayGrader(
      chart: _chart,
      rules: HighwayRules.of(difficulty),
      laneMap: _map,
      gradedVoices: voices,
    );

void main() {
  group('difficulty presets', () {
    test('get strictly tighter, and only the easiest waits for you', () {
      final windows = [
        for (final d in HighwayDifficulty.values)
          HighwayRules.of(d).hitWindowBeats,
      ];
      for (var i = 1; i < windows.length; i++) {
        expect(windows[i], lessThan(windows[i - 1]));
      }
      expect(HighwayRules.of(HighwayDifficulty.relaxed).waitForMe, isTrue);
      expect(HighwayRules.of(HighwayDifficulty.easy).waitForMe, isFalse);
      // The perfect window is always inside the hit window.
      for (final d in HighwayDifficulty.values) {
        final r = HighwayRules.of(d);
        expect(r.perfectWindowBeats, lessThan(r.hitWindowBeats));
      }
    });

    test('scaffolds fall away as it gets harder', () {
      expect(HighwayRules.of(HighwayDifficulty.relaxed).showNoteNames, isTrue);
      expect(HighwayRules.of(HighwayDifficulty.expert).showNoteNames, isFalse);
      expect(HighwayRules.of(HighwayDifficulty.expert).showCaptions, isFalse);
      // Less warning, not a faster tempo, is what makes expert hard.
      expect(
        HighwayRules.of(HighwayDifficulty.expert).leadBeats,
        lessThan(HighwayRules.of(HighwayDifficulty.relaxed).leadBeats),
      );
    });
  });

  group('tapping', () {
    test('a tap inside the window hits, and dead-on is perfect', () {
      final g = _grader();
      final result = g.tap(_key(60), 0);
      expect(result.isHit, isTrue);
      expect(result.quality, HighwayHitQuality.perfect);
      expect(g.hits, 1);
      expect(g.streak, 1);
    });

    test('slightly late still counts, but is not perfect', () {
      final g = _grader();
      final result = g.tap(_key(60), 0.3);
      expect(result.isHit, isTrue);
      expect(result.quality, HighwayHitQuality.late);
      expect(result.note!.timingError, closeTo(0.3, 1e-9));
    });

    test('the wrong key scores nothing and breaks the streak', () {
      final g = _grader()..tap(_key(60), 0);
      final result = g.tap(_key(61), 0.05);
      expect(result.isHit, isFalse);
      expect(g.hits, 1);
      expect(g.streak, 0);
      // A wrong key must never consume a target: the note is still available.
      expect(g.notes.first.state, HighwayNoteState.hit);
      expect(g.notes[1].isPending, isTrue);
    });

    test('one note cannot be farmed by hammering the same key', () {
      final g = _grader();
      g.tap(_key(60), 0);
      g.tap(_key(60), 0.05);
      g.tap(_key(60), 0.1);
      expect(g.hits, 1);
    });

    test('a tap claims the CLOSEST matching note', () {
      const doubled = HighwayChart(
        name: 'd',
        bpm: 60,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 60),
          HighwayEvent(startBeat: 0.3, beats: 1, midi: 60),
        ],
      );
      final g = HighwayGrader(
        chart: doubled,
        rules: HighwayRules.of(HighwayDifficulty.easy),
        laneMap: _map,
      );
      g.tap(_key(60), 0.28);
      expect(g.notes[1].state, HighwayNoteState.hit); // the nearer one
      expect(g.notes[0].isPending, isTrue);
    });

    test('the streak multiplier grows with a clean run, and a miss resets it',
        () {
      final long = HighwayChart(
        name: 'long',
        bpm: 60,
        events: [
          for (var i = 0; i < 12; i++)
            HighwayEvent(startBeat: i.toDouble(), beats: 1, midi: 60),
        ],
      );
      final g = HighwayGrader(
        chart: long,
        rules: HighwayRules.of(HighwayDifficulty.medium),
        laneMap: _map,
      );
      expect(g.multiplier, 1);
      for (var i = 0; i < 8; i++) {
        g.tap(_key(60), i.toDouble());
      }
      expect(g.streak, 8);
      expect(g.multiplier, 2); // 8 clean in a row is worth double
      expect(g.score, greaterThan(800));

      g.tap(_key(61), 8); // a wrong key
      expect(g.streak, 0);
      expect(g.multiplier, 1);
    });
  });

  group('the clock', () {
    test('a note whose window closed is missed exactly once', () {
      final g = _grader()..advanceTo(1.0);
      expect(g.misses, 1);
      expect(g.notes.first.state, HighwayNoteState.missed);
      g.advanceTo(1.1);
      expect(g.misses, 1); // not re-counted every frame
    });

    test('wait-for-me holds at the next note you owe', () {
      final g = _grader(difficulty: HighwayDifficulty.relaxed);
      expect(g.holdBeat, 0);
      g.tap(_key(60), 0);
      expect(g.holdBeat, 1); // moves on to the next one
    });

    test('wait-for-me takes the EARLIEST note owed, not the first listed', () {
      // A hand-authored two-voice chart is not in time order.
      const unordered = HighwayChart(
        name: 'hands',
        bpm: 60,
        events: [
          HighwayEvent(startBeat: 2, beats: 1, midi: 72),
          HighwayEvent(startBeat: 0, beats: 1, midi: 60, voice: 1),
        ],
      );
      final g = HighwayGrader(
        chart: unordered,
        rules: HighwayRules.of(HighwayDifficulty.relaxed),
        laneMap: _map,
      );
      expect(g.holdBeat, 0, reason: 'the clock must wait for the LH note');
    });

    test('nothing holds the clock above the beginner tier', () {
      expect(_grader(difficulty: HighwayDifficulty.easy).holdBeat, isNull);
    });

    test('finished once every graded note is answered', () {
      final g = _grader(voices: {0});
      expect(g.total, 2);
      g.tap(_key(60), 0);
      g.tap(_key(62), 1);
      expect(g.finished, isTrue);
      expect(g.accuracy, 1.0);
    });
  });

  group('hands separate', () {
    test('the hand you did not take on plays itself and is never scored', () {
      final g = _grader(voices: {0});
      expect(g.total, 2); // only the two voice-0 notes are yours
      g.advanceTo(2.5);
      final other = g.notes.firstWhere((n) => n.event.voice == 1);
      expect(other.state, HighwayNoteState.hit); // played itself
      expect(g.hits, 0); // …but you get no credit for it
      expect(g.misses, 2); // and only YOUR notes can be missed
    });

    test('watch mode grades nothing at all', () {
      final g = _grader(voices: const {});
      expect(g.total, 0);
      g.advanceTo(5);
      expect(g.hits, 0);
      expect(g.misses, 0);
      expect(g.notes.every((n) => n.state == HighwayNoteState.hit), isTrue);
    });
  });
}
