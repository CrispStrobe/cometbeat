// L2 — the session grid.
//
// Each section has always stored an enabled set AND a variant per track, which
// is a real session-view scene. It was only ever drawn as four lettered pads,
// so you could launch a section but never see what was in it — let alone change
// one thing about it, which is the whole reason people use a session view.
//
// The behaviour worth pinning is that a cell edits the SECTION, not the live
// mix: toggling a track in the section you are not playing must not change what
// you hear, and must be there when you launch it.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

Future<LoopMixerTester> _withSectionA(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester);
  game.toggleTrack('drums');
  game.toggleTrack('bass');
  await tester.pump();
  game.captureScene(0);
  await tester.pump();
  game.launchScene(0);
  await tester.pump();
  // The grid lives in the sound inspector, which is closed by default.
  if (!game.inspectorVisible) {
    game.toggleInspector();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the grid appears only once a section exists', (tester) async {
    // An empty 7x4 grid of nothing is noise on a child's screen.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    game.toggleInspector();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const Key('loop-cell-drums-0')),
      findsNothing,
      reason: 'no sections captured yet',
    );

    game.toggleTrack('drums');
    await tester.pump();
    game.captureScene(0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('loop-cell-drums-0')), findsOneWidget);
  });

  testWidgets('a cell reports what the section actually holds', (tester) async {
    final game = await _withSectionA(tester);
    expect(game.sceneHasTrack(0, 'drums'), isTrue);
    expect(game.sceneHasTrack(0, 'bass'), isTrue);
    expect(game.sceneHasTrack(0, 'melody'), isFalse);
  });

  testWidgets('tapping a cell edits that section', (tester) async {
    final game = await _withSectionA(tester);
    await tester.tap(find.byKey(const Key('loop-cell-melody-0')));
    await tester.pump();
    expect(game.sceneHasTrack(0, 'melody'), isTrue);

    await tester.tap(find.byKey(const Key('loop-cell-melody-0')));
    await tester.pump();
    expect(game.sceneHasTrack(0, 'melody'), isFalse, reason: 'it toggles');
  });

  testWidgets('editing the PLAYING section is heard immediately',
      (tester) async {
    final game = await _withSectionA(tester);
    game.toggleSceneTrack(0, 'melody');
    await tester.pump();
    expect(game.enabledTracks, contains('melody'));
  });

  testWidgets('editing an OTHER section does not disturb what is playing',
      (tester) async {
    // The point of a session grid: you prepare the next section while the
    // current one keeps going.
    final game = await _withSectionA(tester);
    game.captureScene(1);
    await tester.pump();
    game.launchScene(0);
    await tester.pump();
    final playing = {...game.enabledTracks};

    game.toggleSceneTrack(1, 'melody');
    await tester.pump();
    expect(game.enabledTracks, playing, reason: 'the live mix moved');
    expect(game.sceneHasTrack(1, 'melody'), isTrue);

    game.launchScene(1);
    await tester.pump();
    expect(
      game.enabledTracks,
      contains('melody'),
      reason: 'the prepared change should arrive on launch',
    );
  });

  testWidgets('an empty section has no editable cells', (tester) async {
    final game = await _withSectionA(tester);
    expect(game.sceneIsEmpty(3), isTrue);
    game.toggleSceneTrack(3, 'drums');
    await tester.pump();
    expect(game.sceneIsEmpty(3), isTrue, reason: 'no accidental creation');
  });
}
