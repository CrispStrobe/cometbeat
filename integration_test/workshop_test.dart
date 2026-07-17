// On-device / live integration test for the Composition Workshop. Boots the
// REAL app (real fonts, real SMuFL metadata via Bravura.load(), real audio and
// layout), opens the Workshop, composes on the on-screen piano, exercises the
// range clipboard, and switches to the grand staff — asserting no crash and the
// expected document state throughout.
//
// Run on a device with a real, foregroundable display:
//   flutter test integration_test/workshop_test.dart -d macos
//   flutter test integration_test/workshop_test.dart -d chrome   # needs chromedriver
// NB: a *headless* macOS run cannot foreground the app window ("Failed to
// foreground app; open returned 1"), so pointer taps do not land — run it on a
// real desktop session or a CI runner with a display. The same flows are also
// covered headlessly (and in CI) by test/composition_workshop_test.dart.

import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
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

  testWidgets('compose on the piano, copy/paste, and switch to grand staff',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Open the Workshop from the home app bar.
    await tester.tap(find.byTooltip('Workshop'));
    await tester.pumpAndSettle();
    expect(find.byType(CompositionWorkshopScreen), findsOneWidget);

    // Compose three notes on the on-screen piano.
    final editor = _editor(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(PianoKeyboard));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(editor.noteCount, 3);
    expect(editor.hasSelection, isTrue);

    // Copy the selected note and paste it.
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(editor.noteCount, 4);

    // Undo the paste.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(editor.noteCount, 3);

    // Switch to the grand staff (both clefs).
    await tester.tap(find.text('𝄞').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('𝄞𝄢').last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveGrandStaffView), findsOneWidget);
  });
}
