// Loop Studio's save/export entry points must be REACHABLE.
//
// Two ways they were not:
// * Simple view (the default) had no overflow menu, so no route to any save or
//   export at all.
// * The share sheet holds ~20 rows in a plain Column. A modal sheet without
//   scroll control is capped at 9/16 of the window, so on a laptop-sized
//   window everything below the cap — "Save as audio" included — overflowed
//   off the bottom, untappable.

import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Simple view has a share & export button', (tester) async {
    await pumpGame(tester, const LoopMixerScreen(simpleLayout: true));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LoopMixerScreen)),
    )!;
    final button = find.byKey(const ValueKey('loop-share-export'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.loopMixerSaveAudio), findsOneWidget);
  });

  testWidgets('every share-sheet row is reachable on a laptop-sized window',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen(simpleLayout: true));
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LoopMixerScreen)),
    )!;
    final loop = tester.state<State<LoopMixerScreen>>(
      find.byType(LoopMixerScreen),
    ) as LoopMixerTester;
    loop.toggleTrack('drums');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('loop-share-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');

    // The last row of the sheet, and the audio save in the lower half.
    for (final label in [l10n.loopMixerSaveAudio, l10n.tuneLoadShared]) {
      final row = find.text(label);
      await tester.ensureVisible(row);
      await tester.pump();
      final centre = tester.getCenter(row);
      expect(
        centre.dy,
        lessThan(720),
        reason: '"$label" must be on screen',
      );
      final hit = tester.hitTestOnBinding(centre);
      expect(
        hit.path.any(
          (e) => e.target == tester.renderObject(row),
        ),
        isTrue,
        reason: '"$label" must receive the tap',
      );
    }
  });
}
