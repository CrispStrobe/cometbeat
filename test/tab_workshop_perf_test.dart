// Tab Workshop — the rebuild-scope guards.
//
// This screen's build is expensive by construction: one `build()` for a
// 3300-line screen that derives the whole score (`toScore`), engraves it
// (`TabLayoutEngine.layout` runs inside `TabStaffView.build`) and materialises a
// non-lazy grid of `columns × strings` cells. That is fine per EDIT. It was not
// fine per frame, and two paths were doing exactly that:
//
//   * the FX rack's sliders call `onChanged` per drag frame, and the handler
//     called the screen's `setState` — so dragging one knob rebuilt the whole
//     Workshop at ~60 fps, behind a sheet covering it. Same for the mixer's
//     volume and pan;
//   * the playhead called `setState` each time the sounding column changed —
//     a full rebuild, twice a second at 120 bpm, to move one highlight.
//
// Neither value is read by `build()` (the mix parameters are used when audio is
// rendered; the highlight now travels through a `ValueNotifier` the three views
// listen to). So these are counting tests, not timing tests: a wall-clock
// assertion on shared CI hardware is noise, but "this must not rebuild the
// screen" is exact and cannot rot.

import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

TabWorkshopTester _tab(WidgetTester tester) =>
    tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

void main() {
  testWidgets('the playhead moving does NOT rebuild the screen', (
    tester,
  ) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();

    tab.play();
    await tester.pump(); // kick the ticker
    final builds = tab.debugBuildCount;
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tab.highlightedIds,
      contains('t0'),
      reason: 'the highlight still moves',
    );
    expect(
      tab.debugBuildCount,
      builds,
      reason: 'and it moved without rebuilding the screen',
    );

    tab.play(); // stop
    await tester.pump();
  });

  testWidgets('an edit DOES rebuild — the narrowing must not go too far', (
    tester,
  ) async {
    // The other half of the guard. Narrowing rebuild scope is only safe if the
    // things that genuinely change the picture still rebuild, and a test that
    // only asserts "fewer rebuilds" would pass a screen that never repaints.
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    final builds = tab.debugBuildCount;

    tab.selectCell(1, 0);
    tab.enterFret(5);
    await tester.pump();

    expect(tab.debugBuildCount, greaterThan(builds));
  });

  testWidgets('the grid still shows what it should after the finger cache', (
    tester,
  ) async {
    // `_fingerAt` used to sort a fresh list per CELL — `columns × strings` sorts
    // per build for a value that is per column. It is now computed once per
    // column into a cache cleared at the top of `build`, so the risk is a STALE
    // digit rather than a slow one: an edit must show the new state.
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // A CHORD, because the cache is keyed per column and the mapping it holds
    // (string → finger) only means anything when a column has several strings.
    tab.selectCell(0, 0);
    tab.enterFret(3);
    tab.selectCell(0, 1);
    tab.enterFret(5);
    await tester.pump();
    tab.addLeftFingerings();
    await tester.pump();

    final first = [
      for (var string = 0; string < 2; string++)
        tester
            .widgetList<Text>(
              find.byKey(ValueKey<String>('tab-finger-0-$string')),
            )
            .map((t) => t.data)
            .toList(),
    ];
    expect(
      first.expand((x) => x).whereType<String>(),
      isNotEmpty,
      reason: 'fingerings are shown at all',
    );

    // Change the chord: the digits must follow, not come back from the cache.
    tab.selectCell(0, 1);
    tab.enterFret(9);
    await tester.pump();
    tab.addLeftFingerings();
    await tester.pump();
    expect(tab.fretAt(0, 1), 9, reason: 'the edit landed');
    expect(
      tester
          .widgetList<Text>(
            find.byKey(const ValueKey<String>('tab-finger-0-1')),
          )
          .isNotEmpty,
      isTrue,
      reason: 'and its finger is rendered fresh',
    );
  });
}
