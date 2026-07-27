// D6 — the tempo map: where the beat actually falls when the tempo is not one
// number.
//
// The two questions are inverses — which beat is this moment, and when does
// this beat happen — so the load-bearing test is that they round-trip ACROSS a
// tempo change. A map that gets one direction right and the other wrong looks
// fine on a constant tempo and desynchronises the moment anything changes,
// which is precisely the case it exists for.

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a constant tempo behaves exactly as one number did', () {
    test('120 BPM is 500 ms a beat, both ways', () {
      final map = TempoMap.constant(120);
      expect(map.isConstant, isTrue);
      expect(map.beatAtMs(500), closeTo(1, 1e-9));
      expect(map.beatAtMs(2000), closeTo(4, 1e-9));
      expect(map.msAtBeat(4), closeTo(2000, 1e-9));
    });

    test('an empty or headless map still starts somewhere', () {
      // Every caller would otherwise need a fallback for "before the first
      // change", which is a bug waiting to be written once per caller.
      expect(TempoMap().changes.first.ms, 0);
      expect(
        TempoMap([const TempoChange(ms: 5000, bpm: 90)]).changes.first.ms,
        0,
      );
    });
  });

  group('across a tempo change', () {
    // 120 BPM for the first 2 s (4 beats), then 60 BPM (1000 ms a beat).
    TempoMap map() => TempoMap([
          const TempoChange(ms: 0, bpm: 120),
          const TempoChange(ms: 2000, bpm: 60),
        ]);

    test('beats stop scaling linearly with time — the whole point', () {
      expect(map().beatAtMs(2000), closeTo(4, 1e-9));
      // One second later is only ONE more beat now, not two.
      expect(map().beatAtMs(3000), closeTo(5, 1e-9));
      expect(map().beatAtMs(4000), closeTo(6, 1e-9));
    });

    test('and the inverse agrees', () {
      expect(map().msAtBeat(4), closeTo(2000, 1e-9));
      expect(map().msAtBeat(5), closeTo(3000, 1e-9));
      expect(map().msAtBeat(6), closeTo(4000, 1e-9));
    });

    test('ms → beat → ms round-trips across the change', () {
      // The load-bearing property. Getting one direction right and the other
      // wrong looks fine at a constant tempo and desyncs the moment it varies.
      final m = map();
      for (final ms in [0.0, 500.0, 1999.0, 2000.0, 2001.0, 5000.0, 12345.0]) {
        expect(m.msAtBeat(m.beatAtMs(ms)), closeTo(ms, 1e-6), reason: '$ms ms');
      }
    });

    test('bpmAt reports the tempo in force, not the nearest one', () {
      final m = map();
      expect(m.bpmAt(0), 120);
      expect(m.bpmAt(1999), 120);
      expect(m.bpmAt(2000), 60);
      expect(m.bpmAt(9999), 60);
    });

    test('the beat grid spaces out after the change', () {
      final times = map().beatTimes(5000);
      // 0, 500, 1000, 1500, 2000 at 120 … then 3000, 4000, 5000 at 60.
      expect(times.take(5), [0, 500, 1000, 1500, 2000]);
      expect(times.skip(5).take(3), [3000, 4000, 5000]);
    });

    test('snapping lands on a beat, wherever the beat now is', () {
      final m = map();
      expect(m.snapToBeat(2400), closeTo(2000, 1e-6)); // nearer beat 4
      expect(m.snapToBeat(2600), closeTo(3000, 1e-6)); // nearer beat 5
    });
  });

  group('editing the map', () {
    test('a change at the same instant replaces rather than duplicates', () {
      final map = TempoMap.constant(120)
          .withChange(const TempoChange(ms: 1000, bpm: 90))
          .withChange(const TempoChange(ms: 1000, bpm: 100));
      expect(map.changes, hasLength(2));
      expect(map.changes.last.bpm, 100);
    });

    test('changes stay sorted however they are added', () {
      final map = TempoMap.constant(120)
          .withChange(const TempoChange(ms: 4000, bpm: 80))
          .withChange(const TempoChange(ms: 2000, bpm: 90));
      expect(map.changes.map((c) => c.ms), [0, 2000, 4000]);
    });

    test('the opening tempo cannot be removed', () {
      // The piece has to start at some tempo; allowing this would leave the
      // opening bars undefined.
      final map = TempoMap.constant(120).withoutChangeAt(0);
      expect(map.changes, hasLength(1));
      expect(map.changes.first.ms, 0);
    });

    test('json round-trips', () {
      final map = TempoMap([
        const TempoChange(ms: 0, bpm: 128),
        const TempoChange(ms: 8000, bpm: 96),
      ]);
      final back = TempoMap.fromJson(map.toJson());
      expect(back.changes.map((c) => c.ms), [0, 8000]);
      expect(back.changes.map((c) => c.bpm), [128, 96]);
    });

    test('malformed json degrades to a usable map, not a crash', () {
      for (final raw in [
        null,
        42,
        'nope',
        <Object?>[],
        [null, 'x', 7],
      ]) {
        final map = TempoMap.fromJson(raw);
        expect(map.changes, isNotEmpty, reason: '$raw');
        expect(map.changes.first.ms, 0);
      }
    });
  });

  group('the service', () {
    test('bpm still means the opening tempo', () {
      final daw = DawService();
      daw.setBpm(140);
      expect(daw.bpm, 140);
      expect(daw.beatMs, closeTo(60000 / 140, 1e-9));
    });

    test('setting the opening tempo leaves later changes where they are', () {
      final daw = DawService()..setTempoAt(4000, 90);
      daw.setBpm(150);
      expect(daw.tempoMap.changes.map((c) => c.ms), [0, 4000]);
      expect(daw.bpm, 150);
      expect(daw.tempoMap.bpmAt(4000), 90);
    });

    test('a mid-arrangement tempo change is UNDOABLE', () {
      // Unlike the opening tempo, which is a setting: putting a change in the
      // middle of an arrangement is an edit to the piece.
      final daw = DawService();
      daw.setTempoAt(2000, 90);
      expect(daw.tempoMap.changes, hasLength(2));
      daw.undo();
      expect(daw.tempoMap.isConstant, isTrue);
    });

    test('snapping uses the map where the tempo varies', () {
      final daw = DawService()
        ..setBpm(120)
        ..toggleSnap()
        ..setTempoAt(2000, 60);
      // Beat 5 is at 3000 ms once the tempo halves — a fixed 500 ms grid would
      // have said 2500.
      expect(daw.snapPosition(2900), closeTo(3000, 1e-6));
    });

    test('a constant-tempo project keeps the plain millisecond grid', () {
      final daw = DawService()
        ..setBpm(120)
        ..toggleSnap();
      expect(daw.snapPosition(1240), closeTo(1000, 1e-9));
      expect(daw.snapPosition(1260), closeTo(1500, 1e-9));
    });

    test('snapping off leaves a position alone', () {
      final daw = DawService()..setBpm(120);
      expect(daw.snapOn, isFalse);
      expect(daw.snapPosition(1234), 1234);
    });

    test('the map survives save and reload', () {
      final daw = DawService()..setTempoAt(3000, 75);
      final saved = daw.saveProject();

      final reopened = DawService()..loadProject(saved);
      expect(reopened.tempoMap.changes.map((c) => c.ms), [0, 3000]);
      expect(reopened.tempoMap.bpmAt(3000), 75);
    });

    test('a project with a constant tempo writes no tempo block', () {
      // Nothing to say that the default does not already cover, and an absent
      // key reads identically on a build that predates D6.
      final daw = DawService()..setBpm(128);
      expect(daw.saveProject().contains('"tempo"'), isFalse);
    });
  });
}
