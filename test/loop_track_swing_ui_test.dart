// Reaching per-track swing from the GUI.
//
// The engine could give one track its own swing since the previous commit, but
// nothing on screen could ask for it — which makes the feature worth exactly
// nothing to a player. It lives in the sound inspector directly under the
// global swing slider, as one badge per track: `–` means "follow the groove",
// a digit means this track has its own.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// The inspector is closed by default and this screen animates continuously —
/// bounded pumps only, never pumpAndSettle.
Future<LoopMixerTester> _withInspector(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester);
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every track starts by following the groove', (tester) async {
    final game = await _withInspector(tester);
    for (final id in ['drums', 'bass', 'melody']) {
      expect(game.hasOwnSwing(id), isFalse, reason: id);
      expect(game.trackSwingOf(id), game.swing, reason: id);
    }
  });

  testWidgets('a badge exists for each track and is tappable', (tester) async {
    final game = await _withInspector(tester);
    expect(find.byKey(const Key('loop-swing-drums')), findsOneWidget);

    await tester.tap(find.byKey(const Key('loop-swing-drums')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasOwnSwing('drums'), isTrue,
        reason: 'the tap should have given it its own swing');
  });

  testWidgets('the ladder walks the range and returns to following',
      (tester) async {
    final game = await _withInspector(tester);
    final seen = <double>[];
    for (var i = 0; i < 4; i++) {
      game.cycleTrackSwing('drums');
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.hasOwnSwing('drums'), isTrue);
      seen.add(game.trackSwingOf('drums'));
    }
    expect(seen, [0.0, 0.2, 0.4, 0.6], reason: 'straight → heavy');

    game.cycleTrackSwing('drums');
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasOwnSwing('drums'), isFalse,
        reason: 'it should come back round to following the groove');
  });

  testWidgets('one track keeps its own while the others follow',
      (tester) async {
    final game = await _withInspector(tester);
    game.cycleTrackSwing('drums');
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.hasOwnSwing('drums'), isTrue);
    expect(game.hasOwnSwing('bass'), isFalse);
    expect(game.trackSwingOf('bass'), game.swing);
  });
}
