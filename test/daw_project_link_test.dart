// WS-X1's FIFTH surface — the Audio Editor holds a live link.
//
// ⚠️ The card said this was impossible: "`AppMode.audio` has no project codec at
// all… there is no audio project track for a link to point at", and the screen
// "holds a timeline of clips rather than one document". Both were true when
// written. `WS-W1c` then registered a codec for `AppMode.audio` — which makes
// **the timeline the document**, since a `.cbdaw` is exactly one — and the
// objection expired without anyone noticing, because a note that says "not
// possible" is not something people re-check.
//
// So these tests are mostly about the property the card doubted: an edit made
// here reaches the project TRACK, and a track of another kind is refused rather
// than quietly converted.

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DawTester _game(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

Future<(DawTester, ProjectService)> _open(WidgetTester tester) async {
  final projects = ProjectService();
  await pumpGame(
    tester,
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProjectService>.value(value: projects),
        ChangeNotifierProvider(create: (_) => DawService()),
      ],
      child: const DawScreen(),
    ),
  );
  return (_game(tester), projects);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a track added from here can be opened LIVE', (tester) async {
    final (game, projects) = await _open(tester);
    final id = game.addToProject(name: 'Take 1');
    expect(id, isNotNull);

    expect(game.hasLiveProjectLink, isFalse, reason: 'adding is not opening');
    expect(game.openProjectTrack(id!), isTrue);
    await tester.pump();
    expect(game.hasLiveProjectLink, isTrue);
  });

  testWidgets('⚠️ an edit made here reaches the project TRACK', (tester) async {
    // The property the card doubted, and the only one that matters: a link that
    // never writes is an inert link.
    final (game, projects) = await _open(tester);
    final id = game.addToProject(name: 'Take 1')!;
    game.openProjectTrack(id);
    await tester.pump();

    final before = (projects.track(id)!.document as DawTimeline)
        .tracks
        .fold<int>(0, (sum, t) => sum + t.clips.length);

    game.addDemoBeat();
    await tester.pump();
    expect(game.writeBackToProject(), isTrue);

    final after = (projects.track(id)!.document as DawTimeline)
        .tracks
        .fold<int>(0, (sum, t) => sum + t.clips.length);
    expect(
      after,
      greaterThan(before),
      reason: 'the project track has the edit',
    );
  });

  testWidgets('a track of ANOTHER kind is refused, not converted', (
    tester,
  ) async {
    // A conversion belongs behind the "Open in…" menu, where its cost is shown
    // before the user commits — not inside a project-track open.
    final (game, projects) = await _open(tester);
    final id = projects.addTrack(
      kind: AppMode.score,
      document: 'not a timeline',
      name: 'Melody',
    );

    expect(game.openProjectTrack(id), isFalse);
    expect(game.hasLiveProjectLink, isFalse);
  });

  testWidgets('with no project in scope, nothing pretends to be linked', (
    tester,
  ) async {
    // Every existing test mounts this screen without a project tree, so this is
    // the common path, not an edge case.
    await pumpGame(
      tester,
      ChangeNotifierProvider(
        create: (_) => DawService(),
        child: const DawScreen(),
      ),
    );
    final game = _game(tester);

    expect(game.addToProject(), isNull);
    expect(game.openProjectTrack('anything'), isFalse);
    expect(game.hasLiveProjectLink, isFalse);
    expect(game.writeBackToProject(), isFalse);
  });

  testWidgets('writing back without a link is refused, not a crash', (
    tester,
  ) async {
    final (game, _) = await _open(tester);
    expect(game.writeBackToProject(), isFalse);
  });
}
