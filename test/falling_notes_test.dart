// Falling Notes — the arcade reading game. Verifies the core loop with the
// ticker driven by tester.pump(): notes spawn, naming the active note catches
// it (score + SRI), letting one cross the hit-line costs a life, and catching
// the whole run finishes with a result screen.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/falling_notes_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({FallingMode mode = FallingMode.name}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: FallingNotesScreen(mode: mode),
      ),
    );

/// The letter shown on the pad for a step (en locale, auto naming = C..B).
String _letter(Step step) => step.name.toUpperCase();

/// Typed handle to the running game (the state class is private).
FallingNotesTester _game(WidgetTester tester) =>
    tester.state<State<FallingNotesScreen>>(find.byType(FallingNotesScreen))
        as FallingNotesTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('naming the active note catches it and scores', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Let the first note spawn and become the active target.
    await tester.pump(const Duration(milliseconds: 800));
    final active = game.activeTargetPitch();
    expect(active, isNotNull, reason: 'a note should be falling by now');

    await tester.tap(find.widgetWithText(FilledButton, _letter(active!.step)));
    await tester.pump();

    expect(game.caughtCount, 1);
    expect(game.score, greaterThan(0));
    expect(game.lives, FallingNotesScreen.maxLives);
  });

  testWidgets('the letter keys catch the active note (keyboard control)',
      (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    await tester.pump(const Duration(milliseconds: 800));
    final active = game.activeTargetPitch();
    expect(active, isNotNull);

    const keys = {
      'c': LogicalKeyboardKey.keyC,
      'd': LogicalKeyboardKey.keyD,
      'e': LogicalKeyboardKey.keyE,
      'f': LogicalKeyboardKey.keyF,
      'g': LogicalKeyboardKey.keyG,
      'a': LogicalKeyboardKey.keyA,
      'b': LogicalKeyboardKey.keyB,
    };
    await tester.sendKeyEvent(keys[active!.step.name]!);
    await tester.pump();

    expect(game.caughtCount, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('letting a note cross the line costs a life', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    await tester.pump(const Duration(milliseconds: 800));
    expect(game.activeTargetPitch(), isNotNull);

    // Do nothing until well past the (level-1) fall time: the note drops
    // uncaught. Level 1 fall is ~9s, so pump comfortably past it.
    await tester.pump(const Duration(milliseconds: 10000));
    expect(game.lives, lessThan(FallingNotesScreen.maxLives));
    expect(game.caughtCount, 0);
  });

  testWidgets('catching the whole run finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Play it: every few frames, name whatever note is active.
    for (var i = 0; i < 300 && !game.finished; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      final active = game.activeTargetPitch();
      if (active != null) {
        await tester.tap(
          find.widgetWithText(FilledButton, _letter(active.step)),
          warnIfMissed: false,
        );
        await tester.pump();
      }
    }

    expect(game.finished, isTrue);
    // The result screen shows the star row (three star icons).
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('play mode: pressing the matching piano key catches the note',
      (tester) async {
    await tester.pumpWidget(_app(mode: FallingMode.play));
    final game = _game(tester);
    expect(find.byType(PianoKeyboard), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    final active = game.activeTargetPitch();
    expect(active, isNotNull);

    // Tap the white key whose MIDI matches the falling note.
    const kb = PianoKeyboard();
    var idx = 0;
    for (var i = 0; i < 12; i++) {
      if (kb.whiteMidi(i) == active!.midiNumber) {
        idx = i;
        break;
      }
    }
    final box = tester.getRect(find.byType(PianoKeyboard));
    final keyW = box.width / 12;
    await tester.tapAt(Offset(box.left + (idx + 0.5) * keyW, box.bottom - 8));
    await tester.pump();

    expect(game.caughtCount, 1);
    expect(game.score, greaterThan(0));
  });
}
