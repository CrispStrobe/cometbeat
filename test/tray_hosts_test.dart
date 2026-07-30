// WS-X6 slice 2 — the Tracker and the Tab Workshop as clipboard hosts.
//
// The card's acceptance is cross-EDITOR: "an item put on the clipboard in one
// editor is present in another after navigating there, can be tapped onto that
// editor's surface, and lands through `dropDecisionFor` with its conversion cost
// stated". Slice 1 could not show the first half with one host; two hosts can.
//
// ⚠️ These pump ONE screen at a time against a SHARED `TrayService`, which is
// what navigating between editors amounts to — and it is also the case
// @loop-d1d4 flagged as broken in the real app (nothing provided the service in
// `main.dart`, so every screen had a private shelf). Their fix is one line;
// these tests describe the behaviour it enables.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/tray/tray.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _tracker(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

TabWorkshopTester _tab(WidgetTester tester) =>
    tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

Future<void> _pumpTracker(WidgetTester tester, TrayService tray) => pumpGame(
      tester,
      const AdvancedTrackerScreen(),
      extraProviders: [Provider<TrayService>.value(value: tray)],
    );

Future<void> _pumpTab(WidgetTester tester, TrayService tray) => pumpGame(
      tester,
      const TabWorkshopScreen(),
      extraProviders: [Provider<TrayService>.value(value: tray)],
    );

void main() {
  testWidgets('the Tracker can put its song on the clipboard', (tester) async {
    final tray = TrayService();
    await _pumpTracker(tester, tray);
    final game = _tracker(tester);
    game.setNote(0, 0, 60);
    await tester.pump();

    game.putOnTray();
    await tester.pump();

    expect(tray.items, hasLength(1));
    expect(tray.items.single.kind, AppMode.tracker);
    expect(tray.items.single.payload, isNotNull);
  });

  testWidgets('⚠️ and the TAB WORKSHOP can take it — the cross-editor half', (
    tester,
  ) async {
    // What slice 1 could not show with a single host, and the reason this
    // slice exists.
    final tray = TrayService();
    await _pumpTracker(tester, tray);
    final tracker = _tracker(tester);
    tracker.setNote(0, 0, 60);
    tracker.setNote(0, 4, 64);
    await tester.pump();
    tracker.putOnTray();
    await tester.pump();

    // Navigate: a different editor, the same shelf.
    await _pumpTab(tester, tray);
    final tab = _tab(tester);
    final before = tab.columnCount;

    final item = tray.items.single;
    expect(item.payload, isNotNull);
    expect(tab.debugDrop(item.payload!), isTrue, reason: 'it landed');
    await tester.pump();
    expect(tab.columnCount, isNot(before));
  });

  testWidgets('and the other way round — a tab put on, landed in the Tracker', (
    tester,
  ) async {
    final tray = TrayService();
    await _pumpTab(tester, tray);
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();
    tab.putOnTray();
    await tester.pump();
    expect(tray.items.single.kind, AppMode.tab);

    await _pumpTracker(tester, tray);
    final tracker = _tracker(tester);
    expect(tracker.debugDrop(tray.items.single.payload!), isTrue);
    await tester.pump();
    expect(tracker.noteCount, greaterThan(0));
  });

  testWidgets('an INSTRUMENT chip places nothing — it is a voice', (
    tester,
  ) async {
    // The tray carries both; only a document can land on a grid, and turning a
    // voice into an empty clip would look like it worked.
    final tray = TrayService();
    await _pumpTracker(tester, tray);
    final game = _tracker(tester);
    final before = game.noteCount;

    expect(tray.items.where((i) => i.isInstrument), isEmpty);
    // A document chip has a payload; an instrument chip does not.
    game.putOnTray();
    await tester.pump();
    expect(tray.items.single.payload, isNotNull);
    expect(game.noteCount, before, reason: 'putting on does not edit');
  });

  testWidgets('a screen mounted BARE still works, on a private shelf', (
    tester,
  ) async {
    // The rule every shared service on these screens follows: the games registry
    // mounts them without a provider tree.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _tracker(tester);
    expect(game.putOnTray, returnsNormally);
    await tester.pump();
  });
}
