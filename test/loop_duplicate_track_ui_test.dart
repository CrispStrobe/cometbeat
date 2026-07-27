// Reaching track duplication from the GUI.
//
// The engine could copy a track already; nothing on screen could ask for it,
// which makes it worth nothing to a player. The chips live in the inspector
// rather than on the track card because that card's row is a pixel from
// RenderFlex overflow and its long-press belongs to voice-picking — adding a
// control there broke fourteen tests once already.
//
// Removing a copy reuses the card's existing delete button, which captured
// layers already have; the base band still has none, so the drums cannot be
// lost to a stray tap.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The inspector is closed by default; this screen animates continuously, so
/// bounded pumps only — pumpAndSettle never settles here.
Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('there is a chip per track', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('loop-dup-bass')), findsOneWidget);
    expect(find.byKey(const Key('loop-dup-drums')), findsOneWidget);
  });

  testWidgets('tapping a chip adds a copy to the band', (tester) async {
    final game = await _open(tester);
    final before = game.trackIds.length;

    await tester.tap(find.byKey(const Key('loop-dup-bass')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.trackIds.length, before + 1);
    expect(game.trackIds, contains('bass-2'));
    expect(
      game.enabledTracks,
      contains('bass-2'),
      reason: 'you duplicated it to hear it',
    );
  });

  testWidgets('the copy gets its own chip, so copies can be copied',
      (tester) async {
    final game = await _open(tester);
    game.duplicateTrack('bass');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('loop-dup-bass-2')), findsOneWidget);

    game.duplicateTrack('bass-2');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.trackIds, contains('bass-2-2'));
  });

  testWidgets('removing a copy takes it off the band', (tester) async {
    final game = await _open(tester);
    game.duplicateTrack('bass');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.trackIds, contains('bass-2'));

    game.removeCopy('bass-2');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.trackIds, isNot(contains('bass-2')));
    expect(game.enabledTracks, isNot(contains('bass-2')));
  });

  testWidgets('a base-band track cannot be removed this way', (tester) async {
    final game = await _open(tester);
    game.removeCopy('drums');
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      game.trackIds,
      contains('drums'),
      reason: 'the engine refuses, and the UI must not pretend otherwise',
    );
  });
}
