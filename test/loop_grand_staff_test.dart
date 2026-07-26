// Loop Studio score panel: a mixed-range track is engraved on a GRAND staff.
//
// The panel used to pick ONE clef per track via `clefForGrooveCells`, so a
// two-handed part or a bassline with a high fill was forced onto a single staff
// and its far end disappeared under ledger lines. PLAN.md's retirement map lists
// "hard-coded clef choices" under Replace.
//
// `groove_staff_test.dart` covers the range classifier itself; this covers the
// wiring — that the panel actually reaches for GrandStaffView when the range
// calls for it, and keeps a single StaffView when it does not.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show GrandStaffView, StaffView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

/// One cell per pitch, each an eighth.
List<PatternCell> _cells(List<int> midis) => [
      for (final m in midis) PatternCell(midis: [m], steps: 1),
    ];

Future<LoopMixerTester> _openScore(WidgetTester tester) async {
  await pumpGame(tester, const LoopMixerScreen());
  final game = _game(tester);
  game.toggleScorePanel();
  await tester.pump();
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a track using both ranges gets a grand staff', (tester) async {
    final game = await _openScore(tester);
    game.toggleTrack('bass');
    await tester.pump();

    // Left hand around C3, right hand around C5 — no single clef holds it.
    game.debugSetTrackCells('bass', _cells([48, 52, 55, 72, 76, 79]));
    await tester.pump();

    expect(find.byKey(const ValueKey('loop-grand-staff')), findsOneWidget);
    expect(find.byType(GrandStaffView), findsOneWidget);
  });

  testWidgets('a single-range track keeps one staff', (tester) async {
    final game = await _openScore(tester);
    game.toggleTrack('bass');
    await tester.pump();

    // Squarely below middle C — one bass staff is the right answer.
    game.debugSetTrackCells('bass', _cells([40, 43, 45, 47, 48]));
    await tester.pump();

    expect(find.byKey(const ValueKey('loop-grand-staff')), findsNothing);
    expect(find.byType(StaffView), findsOneWidget);
  });

  testWidgets('one stray note does not split the staff', (tester) async {
    // The classifier's incidental-note guard, seen through the UI: a treble
    // line with a single low pickup must stay on one staff.
    final game = await _openScore(tester);
    game.toggleTrack('bass');
    await tester.pump();

    game.debugSetTrackCells('bass', _cells([72, 74, 76, 77, 50]));
    await tester.pump();

    expect(find.byKey(const ValueKey('loop-grand-staff')), findsNothing);
    expect(find.byType(StaffView), findsOneWidget);
  });

  testWidgets('switching a track from wide to narrow drops back to one staff',
      (tester) async {
    // The choice is derived per build, not latched — editing a track's notes has
    // to be able to take the second staff away again.
    final game = await _openScore(tester);
    game.toggleTrack('bass');
    await tester.pump();

    game.debugSetTrackCells('bass', _cells([48, 52, 55, 72, 76, 79]));
    await tester.pump();
    expect(find.byType(GrandStaffView), findsOneWidget);

    game.debugSetTrackCells('bass', _cells([40, 43, 45, 47, 48]));
    await tester.pump();
    expect(find.byType(GrandStaffView), findsNothing);
    expect(find.byType(StaffView), findsOneWidget);
  });

  testWidgets('a grand staff coexists with normal staves in a band',
      (tester) async {
    // Mixed band: the wide track gets two staves, the others keep one each, and
    // the panel still renders them together.
    final game = await _openScore(tester);
    game.toggleTrack('bass');
    game.toggleTrack('melody');
    await tester.pump();

    game.debugSetTrackCells('bass', _cells([48, 52, 55, 72, 76, 79]));
    await tester.pump();

    expect(find.byType(GrandStaffView), findsOneWidget);
    expect(find.byType(StaffView), findsAtLeastNWidgets(1));
  });
}
