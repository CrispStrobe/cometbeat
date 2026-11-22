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

import 'dart:io';
import 'dart:math' as math;

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show InteractiveGrandStaffView, MultiSystemView, NoteElement;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompositionWorkshopTester _editor(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compose on the piano, copy/paste, and switch to grand staff',
      (tester) async {
    // The authoring menu is opt-in on a fresh install (Settings ▸ Studio tools).
    SharedPreferences.setMockInitialValues({'studio_mode': true});
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

  testWidgets('typing cdefgabcdefgabc stays in one octave, never chords',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // The real screen with real fonts, layout and audio on the real device.
    // Pumped directly rather than navigated to, because a headless macOS run
    // cannot foreground the window and pointer taps would be dropped.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => UserSongsService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => DawService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: CompositionWorkshopScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CompositionWorkshopScreen), findsOneWidget);

    // Focus the real entry surface explicitly: the runner's window is not
    // foregrounded, so autofocus alone leaves key events undelivered.
    final editor = tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;
    editor.debugFocusEntry();
    await tester.pump();

    final audio = Provider.of<AudioService>(
      tester.element(find.byType(CompositionWorkshopScreen)),
      listen: false,
    );

    // A headless test runner does not foreground its window, so the key events
    // would be dropped. Bring the app to the front first (macOS only).
    if (Platform.isMacOS) {
      await Process.run(
        'osascript',
        ['-e', 'tell application "CometBeat" to activate'],
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    const seq = [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC,
    ];
    for (final k in seq) {
      await tester.sendKeyEvent(k);
      await tester.pump(const Duration(milliseconds: 40));
    }

    final elements = tester
        .widget<MultiSystemView>(find.byType(MultiSystemView))
        .score
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .toList();
    final midis = [
      for (final e in elements) ...e.pitches.map((p) => p.midiNumber),
    ];

    expect(
      elements,
      hasLength(seq.length),
      reason: 'every typed letter is its own note',
    );
    expect(
      elements.every((e) => e.pitches.length == 1),
      isTrue,
      reason: 'no letter may be stacked into a chord',
    );
    expect(
      midis.reduce(math.max) - midis.reduce(math.min),
      lessThan(12),
      reason: 'all 15 notes stay inside one octave',
    );
    expect(
      midis.sublist(7, 14),
      midis.sublist(0, 7),
      reason: 'the repeated run is identical, not transposed',
    );

    // Shift+E adds E above the selected (last) C: MuseScore/Sibelius style.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 40));

    // Q turns Dorico-style chord mode on; G joins the same chord; Q off.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump(const Duration(milliseconds: 40));

    // Stop the note-preview player before the tree is disposed: audioplayers'
    // position updater schedules frame callbacks that outlive the widget tree.
    audio.dispose();
    await tester.pump();

    final chorded = tester
        .widget<MultiSystemView>(find.byType(MultiSystemView))
        .score
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .toList();
    expect(chorded, hasLength(15), reason: 'chord tones join, not advance');
    expect(
      chorded.last.pitches.length,
      3,
      reason: 'C + Shift+E + chord-mode G stacked on one stem',
    );
  });
}
