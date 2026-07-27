// D2 + D3 from the GUI — one lane strip with a parameter switch, and a tone
// control per track.
//
// The pan lane has RENDERED since A3 and there was no way to draw one; the
// filter lane had a value mapping, a codec and a share-token slot and rendered
// nothing at all. D2 gives the one strip a Volume / Pan / Tone switch rather
// than stacking three grids per track, and D3 puts a real per-track filter
// underneath the third of them.
//
// The property every automation slice rests on, restated per parameter: a lane
// that is cycled back to neutral everywhere is DROPPED, not stored flat. "No
// lane" has to stay distinguishable from "a flat lane", because that is what
// keeps a groove using none of this byte-for-byte identical to one from before
// automation existed. Each parameter has its own neutral (1.0 volume, centre
// pan, no filtering), so each ladder has to wrap back to its own.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart' show kPatternSteps;
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

Future<LoopMixerTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  if (tester.any(target)) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the parameter switch', () {
    testWidgets('there is one chip per parameter, volume first',
        (tester) async {
      final game = await _open(tester);
      for (final p in AutomationParam.values) {
        expect(find.byKey(Key('loop-auto-param-${p.name}')), findsOneWidget);
      }
      expect(game.automationParam, AutomationParam.level);
    });

    testWidgets('there is still exactly ONE strip', (tester) async {
      // The decision was a switch, not a second strip: three stacked grids per
      // track turns the inspector into a matrix.
      await _open(tester);
      expect(find.byKey(const Key('loop-auto-drums-0')), findsOneWidget);
    });

    testWidgets('switching changes which lane the cells edit', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-auto-param-pan'));
      expect(game.automationParam, AutomationParam.pan);

      await _tap(tester, const Key('loop-auto-drums-0'));
      expect(game.hasAutomationForParam('drums', AutomationParam.pan), isTrue);
      expect(
        game.hasAutomationForParam('drums', AutomationParam.level),
        isFalse,
        reason: 'tapping a cell under Pan must not touch the volume lane',
      );
    });

    testWidgets('each parameter keeps its own lane', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-auto-bass-2'));
      await _tap(tester, const Key('loop-auto-param-pan'));
      await _tap(tester, const Key('loop-auto-bass-5'));

      expect(game.hasAutomationForParam('bass', AutomationParam.level), isTrue);
      expect(game.hasAutomationForParam('bass', AutomationParam.pan), isTrue);
      expect(
        game.automationAtParam('bass', AutomationParam.level, 5),
        1.0,
        reason: 'the pan edit landed at step 5 of the PAN lane only',
      );
      expect(game.automationAtParam('bass', AutomationParam.pan, 2), 0.5);
    });
  });

  group('cycling back to neutral drops the lane — per parameter', () {
    testWidgets('pan', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-auto-param-pan'));
      // Round the whole ladder and back to centre.
      for (var i = 0; i < 12; i++) {
        await _tap(tester, const Key('loop-auto-drums-0'));
        if (!game.hasAutomationForParam('drums', AutomationParam.pan)) break;
      }
      expect(
        game.hasAutomationForParam('drums', AutomationParam.pan),
        isFalse,
        reason: 'a pan lane back at centre everywhere must be dropped',
      );
      expect(game.automationAtParam('drums', AutomationParam.pan, 0), 0.5);
    });

    testWidgets('tone', (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-auto-param-filter'));
      for (var i = 0; i < 12; i++) {
        await _tap(tester, const Key('loop-auto-drums-0'));
        if (!game.hasAutomationForParam('drums', AutomationParam.filter)) break;
      }
      expect(
        game.hasAutomationForParam('drums', AutomationParam.filter),
        isFalse,
      );
    });

    testWidgets('a drawn lane really moves off neutral first', (tester) async {
      // Otherwise "it drops back to nothing" would also pass for a ladder that
      // never left neutral at all.
      final game = await _open(tester);
      await _tap(tester, const Key('loop-auto-param-pan'));
      await _tap(tester, const Key('loop-auto-drums-0'));
      expect(
        game.automationAtParam('drums', AutomationParam.pan, 0),
        isNot(0.5),
      );
      expect(
        game.automationAtParam('drums', AutomationParam.pan, 1),
        0.5,
        reason: 'only the tapped step moved',
      );
    });
  });

  group('the tone control per track', () {
    testWidgets('there is a badge per track, starting at –', (tester) async {
      final game = await _open(tester);
      expect(find.byKey(const Key('loop-filter-bass')), findsOneWidget);
      expect(game.trackFilterOf('bass'), 0.0);
    });

    testWidgets('tapping it darkens, then thins, then comes back',
        (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-filter-bass'));
      expect(game.trackFilterOf('bass'), lessThan(0), reason: 'darker first');

      final seen = <double>{game.trackFilterOf('bass')};
      for (var i = 0; i < 4; i++) {
        await _tap(tester, const Key('loop-filter-bass'));
        seen.add(game.trackFilterOf('bass'));
      }
      expect(seen, contains(0.0), reason: 'the ladder must wrap back to off');
      expect(seen.any((v) => v > 0), isTrue, reason: 'and offer thinner too');
    });

    testWidgets('it is per track — one badge does not move another',
        (tester) async {
      final game = await _open(tester);
      await _tap(tester, const Key('loop-filter-bass'));
      expect(game.trackFilterOf('bass'), isNot(0.0));
      expect(game.trackFilterOf('drums'), 0.0);
    });

    testWidgets('a tone LANE takes the badge over, and says so',
        (tester) async {
      // The lane replaces the knob at render time, so a badge still reading
      // "-9" under a lane that ignores it would be a lie.
      final game = await _open(tester);
      await _tap(tester, const Key('loop-filter-bass'));
      await _tap(tester, const Key('loop-auto-param-filter'));
      await _tap(tester, const Key('loop-auto-bass-0'));
      expect(
        game.hasAutomationForParam('bass', AutomationParam.filter),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('loop-filter-bass')),
          matching: find.text('~'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('an added track gets a strip and a badge of its own',
      (tester) async {
    final game = await _open(tester);
    await _tap(tester, const Key('loop-add-empty'));
    final added = game.trackIds.last;
    expect(find.byKey(Key('loop-filter-$added')), findsOneWidget);
    expect(find.byKey(Key('loop-auto-$added-0')), findsOneWidget);
    expect(
      find.byKey(Key('loop-auto-$added-${kPatternSteps - 1}')),
      findsOneWidget,
    );
  });
}
