// Colour Melody — the pre-reader composing grid. A sandbox: tapping cells places
// notes, tapping the same cell clears it, and the grid renders to a real Score
// (two 4/4 bars) that plays back. Drives taps via the GridComposerTester seam.

import 'package:comet_beat/features/games/composition/grid_composer_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

GridComposerTester _game(WidgetTester tester) =>
    tester.state<State<GridComposerScreen>>(find.byType(GridComposerScreen))
        as GridComposerTester;

int _noteCount(Score s) =>
    s.measures.expand((m) => m.elements).whereType<NoteElement>().length;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a cell places a note; tapping it again clears it',
      (tester) async {
    await pumpGame(tester, const GridComposerScreen());
    final game = _game(tester);

    // Fresh grid: all rests, still two 4/4 bars.
    expect(game.columns.length, GridComposerScreen.columns);
    expect(game.columns.every((c) => c == null), isTrue);
    expect(game.score.measures.length, 2);
    expect(_noteCount(game.score), 0);

    game.tapCell(0, 2);
    await tester.pump();
    expect(game.columns[0], 2);
    expect(_noteCount(game.score), 1);

    // Tapping the same cell clears that beat.
    game.tapCell(0, 2);
    await tester.pump();
    expect(game.columns[0], isNull);
    expect(_noteCount(game.score), 0);
  });

  testWidgets('a built tune renders as notes and plays without error',
      (tester) async {
    await pumpGame(tester, const GridComposerScreen());
    final game = _game(tester);

    game.tapCell(0, 0);
    game.tapCell(2, 3);
    game.tapCell(7, 4);
    await tester.pump();

    expect(_noteCount(game.score), 3);

    // The Play button is enabled once there are notes; tapping it is a no-op in
    // the headless audio stub but must not throw.
    await tester.tap(find.text('Play'));
    await tester.pump();
  });
}
