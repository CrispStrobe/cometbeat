// The Score Workshop joins the interop set — the last surface to.
//
// An audit of the five surfaces showed Score with neither a drop target nor a
// clipboard host: every other mode could receive music from every other mode,
// and the one built for writing music could not. That is the sort of gap a
// matrix finds and a feature list does not.
//
// ⚠️ Its drop lands as NEW PARTS rather than replacing the document — the
// opposite call to the Tracker's and the Tab Workshop's, and particular to this
// surface: a score IS its parts, so arriving beside the existing ones is both
// the natural reading and the non-destructive one.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, Score, TimeSignature;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

CompositionWorkshopTester _workshop(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

MultiPartScore _twoParts() => MultiPartScore([
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4',
      ),
      Score.simple(timeSignature: TimeSignature.fourFour, notes: 'g3:h a3'),
    ]);

void main() {
  testWidgets('a dropped score lands as NEW parts, keeping what was there', (
    tester,
  ) async {
    await pumpGame(tester, const CompositionWorkshopScreen());
    final workshop = _workshop(tester);
    final before = workshop.partCount;
    final notesBefore = workshop.noteCount;

    workshop.addDroppedParts(_twoParts());
    await tester.pump();

    expect(workshop.partCount, before + 2);
    expect(
      workshop.noteCount,
      greaterThanOrEqualTo(notesBefore),
      reason: 'nothing that was here was taken away',
    );
  });

  testWidgets('the dropped parts carry their music, not empty staves', (
    tester,
  ) async {
    // "It added parts" is not enough — two empty staves would satisfy a count.
    await pumpGame(tester, const CompositionWorkshopScreen());
    final workshop = _workshop(tester);
    workshop.addDroppedParts(_twoParts());
    await tester.pump();

    final (_, xml) = await workshop.debugGenerateExport('musicxml');
    expect(xml, isNotNull);
    // Six notes across the two dropped parts.
    expect(RegExp('<note').allMatches(xml!).length, greaterThanOrEqualTo(6));
  });

  testWidgets('the clipboard: put a score on, and it is there', (tester) async {
    final tray = TrayService();
    await pumpGame(
      tester,
      const CompositionWorkshopScreen(),
      extraProviders: [Provider<TrayService>.value(value: tray)],
    );
    final workshop = _workshop(tester);

    workshop.putOnTray();
    await tester.pump();

    expect(tray.items, hasLength(1));
    expect(tray.items.single.kind, AppMode.score);
    expect(tray.items.single.payload, isNotNull);
  });

  testWidgets('⚠️ cross-editor: a score put on here lands in another editor', (
    tester,
  ) async {
    // The acceptance clause, from this side.
    final tray = TrayService();
    await pumpGame(
      tester,
      const CompositionWorkshopScreen(),
      extraProviders: [Provider<TrayService>.value(value: tray)],
    );
    _workshop(tester).putOnTray();
    await tester.pump();

    final payload = tray.items.single.payload!;
    final decision = dropDecisionFor(payload, AppMode.tracker);
    expect(decision.canDrop, isTrue, reason: 'it can go to the Tracker');
    expect(decision.document, isNotNull);
  });

  test('a score dropped ON a score is exact — no round trip', () {
    // The WS-X1 rule, checked for this surface: a same-kind drop must not go
    // through the bridge at all, or opening your own music would cost something.
    final score = _twoParts();
    final decision = dropDecisionFor(
      MusicDragPayload(kind: AppMode.score, document: score),
      AppMode.score,
    );
    expect(decision.outcome, DropOutcome.exact);
    expect(identical(decision.document, score), isTrue);
  });
}
