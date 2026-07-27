// test/tab_rig_open_in_test.dart
//
// E2 (the Tab guitar rig) + E4 (the shared "Open in…" action in the Tab
// toolbar).
//
// E2 matters because Tab was the ONE mode with no effects at all — the mode
// whose entire subject is guitar was the only one that could not sound like
// one. The rig is per TRACK, so the tests check that a chip lands on the active
// track and leaves the others dry.
//
// E4's restriction is the interesting part: the menu is limited to the modes
// this screen can actually PUSH. Offering a destination it cannot open would
// convert the user's work and then quietly drop it.

import 'package:comet_beat/core/audio/fx/fx_presets.dart';
import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:comet_beat/shared/widgets/fx_rack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Future<TabWorkshopTester> _open(WidgetTester tester) async {
  await pumpGame(tester, const TabWorkshopScreen());
  await tester.pumpAndSettle();
  return tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
      as TabWorkshopTester;
}

Future<void> _openRigSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  // The overflow menu is long enough to scroll, so the entry has to be brought
  // into view before it can be tapped.
  final entry = find.text('Guitar rig');
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('E2 — the guitar rig', () {
    testWidgets('a tab starts dry, so nothing about its sound changes',
        (t) async {
      await _open(t);
      expect(find.byType(FxRack), findsNothing);
    });

    testWidgets('the rig sheet offers every preset and the rack', (t) async {
      await _open(t);
      await _openRigSheet(t);

      for (final preset in GuitarFxPreset.values) {
        expect(
          find.byKey(ValueKey('tab-rig-${preset.name}')),
          findsOneWidget,
          reason: '$preset is not offered',
        );
      }
      expect(find.byType(FxRack), findsOneWidget);
    });

    testWidgets('picking a preset gives the active track a chain', (t) async {
      await _open(t);
      await _openRigSheet(t);

      await t.tap(find.byKey(const ValueKey('tab-rig-overdrive')));
      await t.pumpAndSettle();

      // The rack now shows the preset's effects.
      expect(find.byType(FxRack), findsOneWidget);
      expect(find.textContaining('No effects'), findsNothing);
    });

    testWidgets('Clean puts the track back to no effects', (t) async {
      await _open(t);
      await _openRigSheet(t);

      await t.tap(find.byKey(const ValueKey('tab-rig-fuzz')));
      await t.pumpAndSettle();
      expect(find.textContaining('No effects'), findsNothing);

      await t.tap(find.byKey(const ValueKey('tab-rig-clean')));
      await t.pumpAndSettle();
      expect(find.textContaining('No effects'), findsOneWidget);
    });
  });

  group('E4 — Open in…', () {
    testWidgets('the action is in the toolbar', (t) async {
      await _open(t);
      expect(find.byKey(const ValueKey('open-in')), findsOneWidget);
    });

    testWidgets('it offers only the modes this screen can actually push',
        (t) async {
      // The bridge can also reach Loop and Audio from Tab, but this screen has
      // no route to push either — offering them would convert and then drop.
      await _open(t);
      await t.tap(find.byKey(const ValueKey('open-in')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('open-in-tracker')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-score')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-loop')), findsNothing);
      expect(find.byKey(const ValueKey('open-in-audio')), findsNothing);
    });

    testWidgets('Tab -> Score is lossless now, so it opens straight away',
        (t) async {
      // The fingering used to be reported dropped on this edge. It is not:
      // TabDocument.toScore records each string/fret in Score.tabVoicings (C4),
      // so the score carries the exact fretting and the edge is lossless — it
      // must open the Score editor directly, with no loss dialog.
      await _open(t);
      await t.tap(find.byKey(const ValueKey('open-in')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-in-score')));
      // Bounded pumps, not pumpAndSettle: this pushes the Composition Workshop,
      // which animates — the timeout would be the route WORKING, not failing.
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsNothing);
      expect(
        find.byType(TabWorkshopScreen),
        findsNothing,
        reason: 'the Score editor was never pushed',
      );
    });

    testWidgets('Tab -> Tracker is lossless, so it opens straight away',
        (t) async {
      // One channel per string, so nothing to warn about — and a dialog that
      // always appears is a dialog nobody reads.
      await _open(t);
      await t.tap(find.byKey(const ValueKey('open-in')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-in-tracker')));
      // Bounded pumps, not pumpAndSettle: this actually pushes the Advanced
      // Tracker, which animates continuously — the timeout would be the route
      // WORKING, not failing.
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const ValueKey('open-in-loss-dialog')), findsNothing);
      expect(
        find.byType(TabWorkshopScreen),
        findsNothing,
        reason: 'the Tracker was never pushed',
      );
    });

    testWidgets('the menu describes each edge before it is chosen', (t) async {
      await _open(t);
      await t.tap(find.byKey(const ValueKey('open-in')));
      await t.pumpAndSettle();
      expect(
        find.text(ProjectBridge.describeEdge(AppMode.tab, AppMode.tracker)),
        findsOneWidget,
      );
    });
  });
}
