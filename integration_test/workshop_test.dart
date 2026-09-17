// On-device / live integration test for the Composition Workshop. Boots the
// REAL app (real fonts, real SMuFL metadata via Bravura.load(), real audio and
// layout), opens the Workshop, composes on the on-screen piano, exercises the
// range clipboard, and switches to the grand staff — asserting no crash and the
// expected document state throughout.
//
// Run on a device with a real, foregroundable display:
//   flutter test integration_test/workshop_test.dart -d macos
//   flutter test integration_test/workshop_test.dart -d chrome   # needs chromedriver
// A macOS runner may report "Failed to foreground app; open returned 1" even
// when this test succeeds. Judge the run by its assertions and exit status.
// Scroll controls into view and use the actions sheet on narrow windows.
// This native run requires working audio: errors fail, and playback position
// must advance. It does not measure physical speaker output.
// The same editing flows are covered by test/composition_workshop_test.dart.

import 'package:audioplayers/audioplayers.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/services/audio_cache_directory.dart';
import 'package:comet_beat/features/home/screens/home_screen.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show InteractiveGrandStaffView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompositionWorkshopTester _editor(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native byte-source playback advances its position',
      (tester) async {
    final player = AudioPlayer();
    addTearDown(player.dispose);
    await prepareAudioCacheDirectory();
    await player.play(
      BytesSource(
        renderWav([
          (freqs: [440.0], ms: 3000),
        ]),
        mimeType: 'audio/wav',
      ),
    );
    expect(player.state, PlayerState.playing);
    final initial = await player.getCurrentPosition() ?? Duration.zero;
    await tester.pump(const Duration(milliseconds: 400));
    final advanced = await player.getCurrentPosition();
    expect(advanced, isNotNull);
    expect(advanced! > initial, isTrue);
    await player.stop();
  });

  testWidgets('compose on the piano, copy/paste, and switch to grand staff',
      (tester) async {
    final audioErrors = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('[AUDIO] playback unavailable')) {
        audioErrors.add(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
    addTearDown(() => debugPrint = originalDebugPrint);
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The home authoring button opens a mode menu, not the editor directly.
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    await tester.tap(find.byTooltip(l10n.workshopTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workshopModeScore));
    await tester.pumpAndSettle();
    expect(find.byType(CompositionWorkshopScreen), findsOneWidget);

    // Compose three notes on the on-screen piano.
    final editor = _editor(tester);
    for (var i = 0; i < 3; i++) {
      final key = find
          .descendant(
            of: find.byType(PianoKeyboard),
            matching: find.byType(GestureDetector),
          )
          .at(16 + i);
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(editor.noteCount, 3);
    expect(editor.hasSelection, isTrue);

    // Copy the selected note and paste it (scroll the strip buttons into view
    // — at 578×545 they sit beyond the right edge of the scrollable input bar).
    final copy = find.byIcon(Icons.copy);
    final paste = find.byIcon(Icons.content_paste);
    final undo = find.byIcon(Icons.undo);
    await tester.ensureVisible(copy);
    await tester.pump();
    await tester.tap(copy);
    await tester.pump();
    await tester.ensureVisible(paste);
    await tester.pump();
    await tester.tap(paste);
    await tester.pump();
    expect(editor.noteCount, 4);

    // Narrow windows put transport/history actions in the actions sheet.
    if (undo.evaluate().isEmpty) {
      await tester.tap(find.byTooltip(l10n.workshopMoreActions));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(undo);
    await tester.pump();
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(editor.noteCount, 3);

    // Switch to the grand staff (both clefs).
    await tester.tap(find.text('𝄞').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('𝄞𝄢').last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveGrandStaffView), findsOneWidget);
    expect(
      audioErrors,
      isEmpty,
      reason: 'Native note playback must prepare successfully',
    );
  });
}
