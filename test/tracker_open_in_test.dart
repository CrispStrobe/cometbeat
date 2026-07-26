// test/tracker_open_in_test.dart
//
// E4 (Tracker half) — the shared "Open in…" action in the Advanced Tracker.
//
// These assert the WIRING structurally rather than by tapping. The Advanced
// Tracker mounts an overlay that absorbs pointer events (the existing tests in
// advanced_tracker_screen_test.dart drive it through its tester seam for the
// same reason), so a tap on a toolbar action never lands. The menu's INTERACTION
// — the loss dialog, cancel, lossless pass-through — is covered end-to-end in
// open_in_menu_test.dart and tab_rig_open_in_test.dart; what is left to prove
// here is that this screen mounts it, from the right mode, restricted to the
// destinations it can actually push.

import 'package:comet_beat/core/interop/project_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart' show kSongs;
import 'package:comet_beat/shared/widgets/open_in_menu.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiPartScore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Future<OpenInMenu> _menu(WidgetTester tester) async {
  await pumpGame(tester, const AdvancedTrackerScreen());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  return tester.widget<OpenInMenu>(find.byType(OpenInMenu));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the action is mounted, from the Tracker mode', (t) async {
    final menu = await _menu(t);
    expect(menu.from, AppMode.tracker);
  });

  testWidgets('it is restricted to the modes this screen can push', (t) async {
    // The bridge can also reach Loop and Audio from Tracker, but this screen
    // has no route to push either — offering one would convert the user's song
    // and then drop it.
    final menu = await _menu(t);
    expect(menu.targets, isNotNull);
    expect(menu.targets, containsAll([AppMode.tab, AppMode.score]));
    expect(menu.targets, isNot(contains(AppMode.loop)));
    expect(menu.targets, isNot(contains(AppMode.audio)));
  });

  testWidgets('every offered target is one the bridge can actually reach',
      (t) async {
    final menu = await _menu(t);
    for (final target in menu.targets!) {
      expect(
        ProjectBridge.canConvert(AppMode.tracker, target),
        isTrue,
        reason: '$target is offered but unreachable',
      );
    }
  });

  testWidgets('the builder hands over the live song', (t) async {
    // The builder is only called once a target is chosen, so it must read the
    // song as it stands then — not a snapshot taken when the menu was built.
    final menu = await _menu(t);
    final tester = t.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

    tester.debugImportMusic(MultiPartScore([kSongs.first.score]));
    await t.pump();

    final result = ProjectBridge.convert(
      from: AppMode.tracker,
      to: AppMode.score,
      document: menu.documentBuilder(),
    );
    expect(result.isUnsupported, isFalse);
    expect(result.document, isA<MultiPartScore>());
  });

  testWidgets('an EMPTY song degrades gracefully instead of crashing',
      (t) async {
    // A fresh tracker has no notes, and a score needs at least one part — so
    // this edge legitimately has nothing to convert. It must say so rather than
    // throw, which is exactly what the bridge's never-throws contract buys.
    final menu = await _menu(t);
    final result = ProjectBridge.convert(
      from: AppMode.tracker,
      to: AppMode.score,
      document: menu.documentBuilder(),
    );
    expect(result.isUnsupported, isTrue);
    expect(result.unsupportedReason, isNotEmpty);
  });
}
