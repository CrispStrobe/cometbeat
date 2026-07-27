// The badge that reaches per-track loop length.
//
// The engine work is only worth anything if a child can get to it, and the
// thing to pin is not that a circle is drawn — it is that tapping the circle
// changes what actually plays: this track's length AND, when the new length
// does not divide the grid, the length of the whole rendered loop.

import 'package:comet_beat/core/audio/loop_engine.dart' show kPatternSteps;
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The length badge on the first track card that has one.
Finder _anyStepsBadge() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('loop-steps-'),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every track starts at the full grid', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    for (final id in ['drums', 'bass', 'melody']) {
      expect(game.trackSteps(id), kPatternSteps, reason: id);
    }
    expect(game.loopSteps, kPatternSteps, reason: 'a 2-bar loop, as before');
  });

  testWidgets('tapping the badge shortens the track and lengthens the loop',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    final badges = _anyStepsBadge();
    expect(badges, findsWidgets, reason: 'the control must be reachable');

    // Cycle the first badge until it lands on a length that does not divide
    // the grid; that is the case where the whole loop has to grow.
    var found = false;
    for (var i = 0; i < kLoopTrackLengths.length; i++) {
      await tester.tap(badges.first, warnIfMissed: false);
      await tester.pump();
      if (game.loopSteps > kPatternSteps) {
        found = true;
        break;
      }
    }
    expect(
      found,
      isTrue,
      reason: 'cycling should reach a length that lengthens the loop',
    );
    expect(game.loopSteps % kPatternSteps, 0,
        reason: 'the grid must still land whole');
  });

  testWidgets('cycling all the way round returns to the full grid',
      (tester) async {
    // The child's undo is another tap, so the cycle has to close.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    for (var i = 0; i < kLoopTrackLengths.length; i++) {
      await tester.tap(_anyStepsBadge().first, warnIfMissed: false);
      await tester.pump();
    }
    expect(game.loopSteps, kPatternSteps);
  });
}
