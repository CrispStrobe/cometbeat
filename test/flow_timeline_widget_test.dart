// Widget test for the EDITABLE flow/order-command timeline sheet on the Advanced
// Tracker: open the sheet, author a pattern break through the real UI (edit
// button → command picker → number dialog → Apply), and assert the live song's
// model was updated. Also covers removing an authored command via its chip.
//
// The heavy correctness coverage of the authoring helpers themselves lives in
// test/flow_timeline_edit_test.dart; this test proves the sheet wires the UI to
// those helpers and mutates the live _song.

import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

/// The Advanced Tracker never fully settles (it drives a live scope/clock), so
/// advance a couple of fixed frames instead of [WidgetTester.pumpAndSettle] to
/// let a modal/dialog transition finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
    MelodyBridge.instance.clear();
  });

  testWidgets('authors a Dxx pattern break from the flow-timeline sheet',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(8); // pattern 0, last row index = 7
    game.setNote(0, 0, 60);
    await tester.pump();

    // Open the editable flow timeline; one entry (order 0) with an edit button.
    game.debugShowFlowTimeline();
    await _settle(tester);
    expect(find.byKey(const ValueKey('flowEdit_0')), findsOneWidget);

    // Edit → command picker → "Break to row…".
    await tester.tap(find.byKey(const ValueKey('flowEdit_0')));
    await _settle(tester);
    await tester.tap(find.text('Break to row…'));
    await _settle(tester);

    // Enter the target row in the number dialog and apply.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '5',
    );
    await tester.tap(find.text('Apply'));
    await _settle(tester);

    // The model updated: Dxx (0xD) with the decimal-encoded row 5 (=0x05) on
    // channel 0, the pattern's last row (7).
    expect(game.effectAt(0, 7), (0xD, 0x05));
  });

  testWidgets('removes an authored command via its chip', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setRows(8);
    game.setNote(0, 0, 60);
    // Author a break directly on the model, then confirm the sheet removes it.
    game.debugSetCommand(0, 7, 0xD, 0x05);
    await tester.pump();
    expect(game.effectAt(0, 7), (0xD, 0x05));

    game.debugShowFlowTimeline();
    await _settle(tester);

    // The command shows as a deletable chip; tapping its delete affordance clears
    // it from the model.
    // The InputChip's only icon is its delete affordance.
    final deleteIcon = find.descendant(
      of: find.byType(InputChip),
      matching: find.byType(Icon),
    );
    expect(deleteIcon, findsOneWidget);
    await tester.tap(deleteIcon);
    await _settle(tester);

    expect(game.effectAt(0, 7), (0, 0));
  });
}
