// WS-X1 for Loop Studio — the two halves the live link was missing.
//
// The link itself is @workstation-parity's (`62447430`), and this file does not
// re-test it: `loop_mixer_test` already does. What it covers is the two things
// that shipped without a caller, which is a failure mode this codebase keeps
// producing and which is invisible from the outside —
//
//   `addToProject` was reachable only from the TEST interface, so no player
//   could create the link the rest of the feature depends on;
//
//   `writeBackToProject` had no call site at all, so a live link existed and
//   edits made here never reached the project track. A link that never writes
//   is an inert link.
//
// Both are now wired, and both are asserted from the outside — through a tap
// and through an ordinary edit — rather than by calling the methods directly,
// because "the method works" was already true when the feature did not.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// Mounts the screen WITH a project in scope.
Future<(LoopMixerTester, ProjectService)> _open(
  WidgetTester tester, {
  ProjectService? projects,
}) async {
  final service = projects ?? ProjectService();
  await pumpGame(
    tester,
    ChangeNotifierProvider<ProjectService>.value(
      value: service,
      child: const LoopMixerScreen(),
    ),
  );
  final game = _game(tester)..debugFreezeSeams();
  if (!game.inspectorVisible) game.toggleInspector();
  await tester.pump(const Duration(milliseconds: 50));
  return (game, service);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('putting the groove in the project', () {
    testWidgets('the button adds a loop track carrying the whole groove',
        (tester) async {
      final (game, projects) = await _open(tester);
      expect(projects.tracks, isEmpty);

      await tester.tap(find.byKey(const Key('loop-add-to-project')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(projects.tracks, hasLength(1));
      final track = projects.tracks.single;
      expect(track.kind, AppMode.loop);
      // The WHOLE groove, not one melody line — that is the WS-W1 choice this
      // depends on, and the reason a project track can be reopened as a band.
      expect(track.document, isA<GrooveSpec>());
      expect(game.hasLiveProjectLink, isTrue);
    });

    testWidgets('once linked, the button stops offering to add it again',
        (tester) async {
      final (game, _) = await _open(tester);
      await tester.tap(find.byKey(const Key('loop-add-to-project')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.hasLiveProjectLink, isTrue);

      // The key is on the button itself (FilledButton.tonalIcon IS one).
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('loop-add-to-project')),
      );
      expect(button.onPressed, isNull, reason: 'already in the project');
    });
  });

  group('edits travel back', () {
    testWidgets('changing the groove updates the project track',
        (tester) async {
      final (game, projects) = await _open(tester);
      game.addToProject();
      await tester.pump(const Duration(milliseconds: 50));
      final before = (projects.tracks.single.document! as GrooveSpec).cacheKey;

      // Any ordinary edit: the write-back is hooked to the same place every
      // edit already goes through.
      game.cycleAutomationStep('drums', 0);
      await tester.pump(const Duration(milliseconds: 50));

      final after = (projects.tracks.single.document! as GrooveSpec).cacheKey;
      expect(after, isNot(before));
    });

    testWidgets('with no link, an edit changes no project track',
        (tester) async {
      final (game, projects) = await _open(tester);
      game.cycleAutomationStep('drums', 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(projects.tracks, isEmpty);
      expect(game.writeBackToProject(), isFalse);
    });
  });

  group('opening a project track here', () {
    testWidgets('a LOOP track opens live, and its groove is applied',
        (tester) async {
      final projects = ProjectService();
      final id = projects.addTrack(
        kind: AppMode.loop,
        name: 'Saved groove',
        document: const GrooveSpec(enabled: {'bass'}, tempoBpm: 75),
      );
      final (game, _) = await _open(tester, projects: projects);

      expect(game.openProjectTrack(id), isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.hasLiveProjectLink, isTrue);
      expect(game.tempoBpm, 75);
    });

    testWidgets('a NON-loop document is refused, not silently converted',
        (tester) async {
      // Their call, and the right one: a conversion belongs behind the
      // "Open in…" menu where its cost is shown, not as a side effect of
      // opening a track. Pinned so it stays deliberate.
      final projects = ProjectService();
      final id = projects.addTrack(
        kind: AppMode.loop,
        name: 'Cells',
        document: const [
          PatternCell(midis: [60], steps: 16),
        ],
      );
      final (game, _) = await _open(tester, projects: projects);
      expect(game.openProjectTrack(id), isFalse);
      expect(game.hasLiveProjectLink, isFalse);
    });

    testWidgets('an unknown track id is refused, not crashed on',
        (tester) async {
      final (game, _) = await _open(tester);
      expect(game.openProjectTrack('nope'), isFalse);
    });
  });

  testWidgets('with NO project in scope the surface still works',
      (tester) async {
    // Every test that mounts this screen alone, and the games registry, supply
    // no ProjectService. The feature degrades to nothing rather than the
    // surface refusing to exist.
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester)..debugFreezeSeams();
    if (!game.inspectorVisible) game.toggleInspector();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('loop-add-to-project')), findsNothing);
    expect(game.addToProject(), isNull);
    expect(game.hasLiveProjectLink, isFalse);
    expect(game.writeBackToProject(), isFalse);
    // And it still does its actual job.
    game.cycleAutomationStep('drums', 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.hasAutomationFor('drums'), isTrue);
  });
}
