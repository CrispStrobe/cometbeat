// §3.3 block editing in the Advanced Tracker grid — interpolate, copy/paste and
// transpose over a marked rectangle. Drives the real State through the
// AdvancedTrackerTester seam (block anchor + cell read/write seams added for
// this coverage); assertions read back cell midi/volume.

import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('interpolate ramps note volumes across the marked block',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final g = _game(tester);

    // Notes on channel 0, rows 0..4; endpoints loud→silent, middles filled in.
    for (var r = 0; r <= 4; r++) {
      g.setNote(0, r, 60);
    }
    g.debugSetCellVolume(0, 0, 1.0);
    g.debugSetCellVolume(0, 4, 0.0);
    await tester.pump();

    // Mark the block (cursor at one corner, anchor at the other).
    g.moveCursor(0, 4);
    g.debugMarkBlock(0, 0);
    await tester.pump();

    g.interpolateBlock();
    await tester.pump();

    // Row 2 is the midpoint → ~0.5.
    expect(g.debugCellVolume(0, 2), closeTo(0.5, 0.05));
    expect(g.debugCellVolume(0, 1), closeTo(0.75, 0.05));
    expect(g.debugCellVolume(0, 3), closeTo(0.25, 0.05));
  });

  testWidgets('copy a cell and paste it elsewhere', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final g = _game(tester);

    g.setNote(0, 0, 60);
    await tester.pump();

    // Mark the single cell (0,0), copy it.
    g.moveCursor(0, 0);
    g.debugMarkBlock(0, 0);
    await tester.pump();
    g.copyBlock();

    // Paste at the cursor's new position.
    g.moveCursor(0, 4);
    await tester.pump();
    g.pasteBlock();
    await tester.pump();

    expect(g.debugCellMidi(0, 4), 60);
  });

  testWidgets('transpose shifts the marked block by semitones', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final g = _game(tester);

    g.setNote(0, 0, 60);
    await tester.pump();
    g.moveCursor(0, 0);
    g.debugMarkBlock(0, 0);
    await tester.pump();

    g.transposeBlock(2);
    await tester.pump();

    expect(g.debugCellMidi(0, 0), 62);
  });
}
