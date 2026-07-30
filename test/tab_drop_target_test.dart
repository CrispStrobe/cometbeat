// WS-X2 — the Tab Workshop as a drop target: the FOURTH and last surface.
//
// The protocol has its own suite and so does each earlier target. What only
// wiring a real surface shows is that surface's own constraints, and this one has
// a constraint none of the others did: **a fret number is not a pitch.** It means
// a pitch only together with a tuning, so the same columns sound different here
// than where they came from, and frets on strings this instrument does not have
// cannot sound at all — which used to CRASH (see tab_tuning_change_test) and is
// now a warning instead.
//
// ⚠️ Never `pumpAndSettle` here: the screen runs a playhead ticker.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

TabWorkshopTester _tab(WidgetTester tester) =>
    tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

TabDocument _dropped({
  Tuning? tuning,
  Map<int, int> frets = const {0: 5},
}) {
  final doc =
      TabDocument.blank(tuning ?? Tuning.standardGuitar, initialColumns: 4);
  frets.forEach((string, fret) => doc.setFret(0, string, fret));
  doc.setFret(2, 1, 7);
  return doc;
}

MusicDragPayload _payload(TabDocument doc) =>
    MusicDragPayload(kind: AppMode.tab, document: doc);

void main() {
  testWidgets('a dropped tab lands in the document', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    final landed = tab.debugDrop(_payload(_dropped()));
    await tester.pump();

    expect(landed, isTrue);
    expect(tab.fretAt(0, 0), 5);
    expect(tab.fretAt(2, 1), 7);
  });

  testWidgets('⚠️ the drop is ONE undoable edit — the reason it lands here', (
    tester,
  ) async {
    // Replacing the document would go through the adopt path, which calls
    // _clearHistory() — an unrecoverable drop, which is worse than a partial one.
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 3);
    tab.enterFret(9);
    await tester.pump();

    tab.debugDrop(_payload(_dropped()));
    await tester.pump();
    expect(tab.fretAt(0, 0), 5);

    tab.undo();
    await tester.pump();
    expect(tab.fretAt(0, 3), 9, reason: 'the work that was here came back');
    expect(tab.fretAt(0, 0), isNull);
  });

  testWidgets('the dropped columns are COPIED, not shared', (tester) async {
    // Two surfaces holding the same column objects would be fine while they are
    // immutable — but the history holds them too, and a document that shares
    // structure with its source is a surprise waiting for the first refactor.
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    final source = _dropped();
    tab.debugDrop(_payload(source));
    await tester.pump();

    source.setFret(0, 0, 1); // edit the SOURCE afterwards
    expect(tab.fretAt(0, 0), 5, reason: 'the landed copy is unaffected');
  });

  group('what a drop warns about — this surface\'s own arithmetic', () {
    testWidgets('a same-tuning tab that fits warns about nothing', (
      tester,
    ) async {
      await pumpGame(tester, const TabWorkshopScreen());
      final tab = _tab(tester);
      expect(tab.debugDropWarnings(_payload(_dropped())), isEmpty);
    });

    testWidgets('frets on strings we do not have are counted, not deleted', (
      tester,
    ) async {
      // The case that used to crash. "You will not hear them" rather than "they
      // are gone" — the two have different remedies, and only one is fixable by
      // changing the tuning.
      await pumpGame(tester, const TabWorkshopScreen());
      final tab = _tab(tester);
      tab.setTuning(Tuning.standardBass);
      await tester.pump();

      final warnings = tab.debugDropWarnings(
        _payload(_dropped(frets: const {0: 5, 4: 3, 5: 2})),
      );
      expect(warnings.join(' '), contains('2 frets'));

      // And it still lands, without throwing.
      expect(tab.debugDrop(_payload(_dropped(frets: const {5: 2}))), isTrue);
      await tester.pump();
    });

    testWidgets('a different tuning is called out', (tester) async {
      // A fret number is only a pitch together with a tuning, so the same
      // columns genuinely sound different here.
      await pumpGame(tester, const TabWorkshopScreen());
      final tab = _tab(tester);
      final warnings = tab.debugDropWarnings(
        _payload(_dropped(tuning: Tuning.dropDGuitar)),
      );
      expect(warnings.join(' '), contains('YOUR tuning'));
    });
  });

  testWidgets('an unsupported kind is refused, and changes nothing', (
    tester,
  ) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    tab.enterFret(4);
    await tester.pump();

    final landed = tab.debugDrop(
      // A bounce is one-way, and the bridge says so.
      const MusicDragPayload(kind: AppMode.audio, document: 'not a document'),
    );
    await tester.pump();

    expect(landed, isFalse);
    expect(tab.fretAt(0, 0), 4);
  });

  test('the drag-over summary is short and never empty', () {
    for (final kind in AppMode.values) {
      final summary = dropSummary(
        dropDecisionFor(
          MusicDragPayload(kind: kind, document: _dropped()),
          AppMode.tab,
        ),
      );
      expect(summary, isNotEmpty, reason: kind.name);
      expect(summary.length, lessThan(60), reason: '${kind.name}: $summary');
    }
  });
}
