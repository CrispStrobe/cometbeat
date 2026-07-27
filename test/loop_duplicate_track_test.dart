// Duplicating a track.
//
// The band was a fixed roster, and I had recorded that as right for a young
// audience. The maintainer corrected the premise: CometBeat scales up to
// students and hobbyists on the Scratch model, where adding another of
// something is the ordinary way to go further. Two bass lines an octave apart,
// or the same beat at two pattern lengths, are exactly the kind of thing this
// unlocks.
//
// The property worth pinning is that a copy is a COPY. One that arrived at
// default settings would have to be rebuilt before it could be varied, which
// defeats the purpose — so everything that shapes the sound comes with it.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  return e;
}

void main() {
  group('a copy joins the band', () {
    test('it gets a fresh id and starts playing', () {
      final e = _engine();
      final copy = e.duplicateTrack('bass');
      expect(copy, isNotNull);
      expect(copy, isNot('bass'));
      expect(e.tracks.map((t) => t.id), contains(copy));
      expect(e.enabled, contains(copy), reason: 'you duplicated it to hear it');
    });

    test('duplicating twice gives two distinct copies', () {
      final e = _engine();
      final a = e.duplicateTrack('bass');
      final b = e.duplicateTrack('bass');
      expect(a, isNot(b));
      expect(
        e.tracks.map((t) => t.id).toSet().length,
        e.tracks.length,
        reason: 'ids must stay unique',
      );
    });

    test('duplicating something that is not a track returns null', () {
      expect(_engine().duplicateTrack('nope'), isNull);
    });
  });

  group('a copy is a COPY', () {
    test('it carries level, pan and variant', () {
      final e = _engine();
      e.levels['bass'] = 0.4;
      e.setPan('bass', -0.7);
      e.variants['bass'] = 1;

      final copy = e.duplicateTrack('bass')!;
      expect(e.levels[copy], 0.4);
      expect(e.panOf(copy), -0.7);
      expect(e.variants[copy], 1);
    });

    test('it carries pattern length and swing', () {
      final e = _engine();
      e.setTrackSteps('bass', 3);
      e.setTrackSwing('bass', 0.4);

      final copy = e.duplicateTrack('bass')!;
      expect(e.trackSteps(copy), 3);
      expect(e.trackSwing(copy), 0.4);
    });

    test('it carries automation, and the two lanes are independent', () {
      // A shared lane map would make editing the copy edit the original —
      // the same aliasing trap section duplication had.
      final e = _engine();
      e.setAutomation('bass', AutomationParam.level, AutomationLane([1, 0]));

      final copy = e.duplicateTrack('bass')!;
      expect(e.automationFor(copy, AutomationParam.level), isNotNull);

      e.setAutomation(copy, AutomationParam.level, AutomationLane([0, 0, 1]));
      expect(
        e.automationFor('bass', AutomationParam.level)!.values,
        [1.0, 0.0],
        reason: 'editing the copy must not touch the original',
      );
    });

    test('it actually sounds — the render changes', () {
      final e = _engine();
      final before = e.renderLoop();
      e.duplicateTrack('bass');
      expect(e.renderLoop(), isNot(before));
    });
  });

  group('removing a copy', () {
    test('takes its settings with it', () {
      final e = _engine();
      final copy = e.duplicateTrack('bass')!;
      e.setTrackSteps(copy, 3);

      expect(e.removeExtraTrack(copy), isTrue);
      expect(e.tracks.map((t) => t.id), isNot(contains(copy)));
      expect(e.enabled, isNot(contains(copy)));
      expect(
        e.trackSteps(copy),
        kPatternSteps,
        reason: 'stale settings must not haunt a reused id',
      );
    });

    test('a base-band track is REFUSED, not hidden', () {
      // Losing the drums to a stray tap would be worse than refusing the tap.
      final e = _engine();
      expect(e.removeExtraTrack('drums'), isFalse);
      expect(e.tracks.map((t) => t.id), contains('drums'));
    });

    test('the original is untouched when its copy goes', () {
      final e = _engine();
      final before = e.renderLoop();
      final copy = e.duplicateTrack('bass')!;
      e.removeExtraTrack(copy);
      expect(e.renderLoop(), before, reason: 'back to exactly the old render');
    });
  });
}
