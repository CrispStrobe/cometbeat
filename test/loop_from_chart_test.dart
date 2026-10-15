import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chart_to_groove.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// BB-U5(c) — a chord chart opens in Loop Studio as a band to drive.

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens on the chart\'s harmony, key and tempo', (tester) async {
    // A G-major chart: G C D Em is I IV V vi in G.
    final chart =
        parseChartText('key: G\ntempo: 132\n| G | C | D | Em |').chart;
    final projection = chartToProgression(chart);
    expect(projection.isExact, isTrue);

    await pumpGame(
      tester,
      LoopMixerScreen(
        initialSpec: GrooveSpec(tempoBpm: 132, key: grooveKeyOf(chart)),
        initialProgression: projection.progression,
      ),
    );
    final game = _game(tester);
    expect(game.tempoBpm, 132);
    expect(game.key, 7, reason: 'G');
    expect(game.customHarmonyCount, 1, reason: 'kept with the player\'s own');
    expect(game.progressionId, startsWith('custom-new-'));
  });

  test('a minor chart is keyed to its relative major', () {
    final am = parseChartText('key: Am\n| Am | Dm | E | Am |').chart;
    expect(grooveKeyOf(am), 0, reason: 'A minor → C, the engine has no minor');
  });
}
