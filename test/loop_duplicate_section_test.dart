// "Copy A to B, then change one thing."
//
// It is how sequencer users actually build an arrangement, and Loop Studio had
// no way to do it: every section had to be assembled from nothing, even when it
// differed from the last one by a single track.
//
// The property that matters most here is not that a copy appears — it is that
// the copy is INDEPENDENT. A shallow copy would share the enabled-set and the
// variant map, so editing B would silently edit A, and the user would only
// discover it after building the whole arrangement.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('duplicating copies the section into the next free slot',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    game.captureScene(0);
    await tester.pump();
    game.launchScene(0);
    await tester.pump();

    expect(game.sceneIsEmpty(1), isTrue, reason: 'slot B starts empty');
    expect(game.duplicateSection(), isTrue);
    await tester.pump();

    expect(game.sceneIsEmpty(1), isFalse, reason: 'the copy landed in B');
    expect(
      game.enabledTracks,
      {'drums', 'bass'},
      reason: 'the copy plays what the original played',
    );
  });

  testWidgets('editing the copy does NOT edit the original', (tester) async {
    // The shallow-copy trap: sharing the Set/Map would make B an alias of A.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    game.captureScene(0);
    await tester.pump();
    game.launchScene(0);
    await tester.pump();

    game.duplicateSection();
    await tester.pump();

    // Change the copy, then re-capture it into its own slot.
    game.toggleTrack('melody');
    await tester.pump();
    game.captureScene(1);
    await tester.pump();

    // Going back to A must still be the original two tracks.
    game.launchScene(0);
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums', 'bass'},
      reason: 'section A was altered by editing its copy',
    );

    game.launchScene(1);
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass', 'melody'});
  });

  testWidgets('it lands you ON the copy, not the original', (tester) async {
    // Otherwise the next edit silently changes the wrong section.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    game.captureScene(0);
    await tester.pump();
    game.launchScene(0);
    await tester.pump();

    game.duplicateSection();
    await tester.pump();

    game.toggleTrack('chords');
    await tester.pump();
    game.captureScene(1);
    await tester.pump();

    game.launchScene(0);
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums'},
      reason: 'the edit after duplicating went into A',
    );
  });

  testWidgets('duplicating an empty section does nothing', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.duplicateSection(), isFalse);
    for (var i = 0; i < 4; i++) {
      expect(game.sceneIsEmpty(i), isTrue);
    }
  });

  testWidgets('with every slot taken it refuses rather than overwriting',
      (tester) async {
    // Silently clobbering someone's section would be far worse than refusing.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      game.captureScene(i);
      await tester.pump();
    }
    game.launchScene(0);
    await tester.pump();

    expect(game.duplicateSection(), isFalse);
    for (var i = 0; i < 4; i++) {
      expect(game.sceneIsEmpty(i), isFalse);
    }
  });
}
