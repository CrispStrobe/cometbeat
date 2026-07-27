// Sections wait for the beat, like everything else on this screen.
//
// Quantized launch has existed since it shipped, but only for track cards: arm
// one and it waits for the loop seam, with an amber border saying so. Tapping a
// SECTION fired instantly. Same screen, same quantize switch, two behaviours —
// and the inconsistent one was the destructive direction, since a section
// replaces the entire mix mid-bar.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// Two captured sections, A playing, quantize on, clock running.
Future<LoopMixerTester> _twoSections(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester);

  game.toggleTrack('drums');
  await tester.pump();
  game.captureScene(0);
  await tester.pump();

  game.toggleTrack('bass');
  await tester.pump();
  game.captureScene(1);
  await tester.pump();

  game.launchScene(0);
  await tester.pump();
  if (!game.quantizeLaunch) game.toggleQuantize();
  await tester.pump();
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with quantize ON a section arms instead of jumping',
      (tester) async {
    final game = await _twoSections(tester);
    expect(
      game.isPlaying,
      isTrue,
      reason: 'quantize only applies while running',
    );
    final before = {...game.enabledTracks};

    game.launchScene(1);
    await tester.pump();
    expect(game.pendingScene, 1, reason: 'armed, not fired');
    expect(game.enabledTracks, before, reason: 'the mix must not move yet');

    game.debugLoopWrap();
    await tester.pump();
    expect(game.pendingScene, isNull);
    expect(
      game.enabledTracks,
      {'drums', 'bass'},
      reason: 'it landed on the beat',
    );
  });

  testWidgets('tapping the armed section again disarms it', (tester) async {
    // The child's undo, before the beat arrives.
    final game = await _twoSections(tester);
    final before = {...game.enabledTracks};

    game.launchScene(1);
    await tester.pump();
    game.launchScene(1);
    await tester.pump();
    expect(game.pendingScene, isNull);

    game.debugLoopWrap();
    await tester.pump();
    expect(game.enabledTracks, before, reason: 'nothing should have landed');
  });

  testWidgets('with quantize OFF a section still fires immediately',
      (tester) async {
    // The behaviour everyone already has must not change.
    final game = await _twoSections(tester);
    game.toggleQuantize();
    await tester.pump();
    expect(game.quantizeLaunch, isFalse);

    game.launchScene(1);
    await tester.pump();
    expect(game.pendingScene, isNull);
    expect(game.enabledTracks, {'drums', 'bass'});
  });

  testWidgets('turning quantize off drops an armed section', (tester) async {
    // It matches what turning it off already does to armed card toggles;
    // leaving one armed with no quantize would fire at a seam nobody expects.
    final game = await _twoSections(tester);
    game.launchScene(1);
    await tester.pump();
    expect(game.pendingScene, 1);

    game.toggleQuantize();
    await tester.pump();
    expect(game.pendingScene, isNull);
  });

  testWidgets('an armed section wins over armed card toggles', (tester) async {
    // A section defines the WHOLE mix, so applying it after the card toggles
    // would silently throw those away.
    final game = await _twoSections(tester);
    game.launchScene(1);
    await tester.pump();
    game.toggleTrack('melody');
    await tester.pump();
    expect(game.pendingScene, 1);
    expect(game.pendingLaunches, contains('melody'));

    game.debugLoopWrap();
    await tester.pump();
    expect(
      game.enabledTracks,
      {'drums', 'bass', 'melody'},
      reason: 'the section landed first, then the card toggle on top',
    );
  });
}
