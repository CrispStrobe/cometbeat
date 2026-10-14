import 'package:comet_beat/features/workshop/workshop_playhead.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const schedule = <ScheduledElement>[
    (id: 'a', start: 0, end: 1),
    (id: 'b', start: 0.5, end: 2),
    (id: 'c', start: 2, end: 3),
  ];

  group('WorkshopPlayhead.step', () {
    test('reports the ids sounding at each moment', () {
      final p = WorkshopPlayhead()..start(schedule, endSeconds: 3);
      expect(p.step(0.2), (action: PlayheadAction.play, changed: true));
      expect(p.sounding, {'a'});
      expect(p.step(0.7).changed, isTrue);
      expect(p.sounding, {'a', 'b'});
      expect(p.step(0.8).changed, isFalse, reason: 'same set, no repaint');
      p.step(2.5);
      expect(p.sounding, {'c'});
    });

    test('nothing sounds during the count-in', () {
      final p = WorkshopPlayhead()
        ..start(schedule, endSeconds: 3, countInSeconds: 2);
      p.step(1.5);
      expect(p.sounding, isEmpty);
      p.step(2.2);
      expect(p.sounding, {'a'});
      // The end is music time: 3s of music after the 2s lead-in.
      expect(p.step(4.9).action, PlayheadAction.play);
      expect(p.step(5).action, PlayheadAction.stop);
    });

    test('a loop restarts without the count-in', () {
      final p = WorkshopPlayhead()
        ..start(schedule, endSeconds: 3, countInSeconds: 2, loop: true);
      expect(p.step(5).action, PlayheadAction.restartLoop);
      // The next cycle's clock starts at music zero.
      p.step(0.2);
      expect(p.sounding, {'a'});
    });

    test('stop clears the loop and the sounding set', () {
      final p = WorkshopPlayhead()
        ..start(schedule, endSeconds: 3, loop: true)
        ..step(0.2)
        ..stop();
      expect(p.sounding, isEmpty);
      expect(p.looping, isFalse);
    });
  });

  group('WorkshopPlayhead.countInLength', () {
    test('one bar of the meter at the tempo', () {
      // 4/4 at 120: four half-second beats.
      expect(
        WorkshopPlayhead.countInLength(quarterBpm: 120, beats: 4, beatUnit: 4),
        2,
      );
      // 6/8 at quarter = 120: six quarter-second eighths.
      expect(
        WorkshopPlayhead.countInLength(quarterBpm: 120, beats: 6, beatUnit: 8),
        1.5,
      );
    });

    test('slow practice stretches it; odd input falls back', () {
      expect(
        WorkshopPlayhead.countInLength(
          quarterBpm: 120,
          beats: 4,
          beatUnit: 4,
          speed: 0.5,
        ),
        4,
      );
      // No tempo → 100 bpm; 1 beat clamps up to 2.
      expect(
        WorkshopPlayhead.countInLength(quarterBpm: null, beats: 1, beatUnit: 4),
        1.2,
      );
    });
  });
}
