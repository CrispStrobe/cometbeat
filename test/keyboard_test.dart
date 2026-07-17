import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/keyboard/key_chord_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_ear_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_find_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_melody_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_name_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsService()),
      ChangeNotifierProvider<SriService>.value(value: sri),
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
      home: child,
    ),
  );
}

void main() {
  late SriService sri;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sri = SriService(getNow: () => DateTime(2026, 7, 11));
  });

  test('keyboard maps white keys and black-key gaps correctly', () {
    const keyboard = PianoKeyboard();
    // C4 D4 E4 F4 G4 A4 B4 C5 D5 E5 F5 G5
    expect(keyboard.whiteMidi(0), 60);
    expect(keyboard.whiteMidi(2), 64); // E4
    expect(keyboard.whiteMidi(6), 71); // B4
    expect(keyboard.whiteMidi(7), 72); // C5
    expect(keyboard.whiteMidi(11), 79); // G5
    // No black key between E-F (i=2) and B-C (i=6).
    expect(keyboard.hasBlackAfter(2), isFalse);
    expect(keyboard.hasBlackAfter(6), isFalse);
    expect(keyboard.hasBlackAfter(0), isTrue); // C#
    expect(keyboard.hasBlackAfter(3), isTrue); // F#
  });

  testWidgets('find-the-key: tapping a key records under keyboard.find',
      (tester) async {
    await tester.pumpWidget(_wrap(const KeyFindScreen(), sri));
    await tester.pump();

    expect(find.text('Tap the key for this note!'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);

    // Tap the leftmost white key (C4) — records either way.
    final keyboardBox = tester.getRect(find.byType(PianoKeyboard));
    await tester.tapAt(Offset(keyboardBox.left + 10, keyboardBox.bottom - 10));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['find']);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });

  testWidgets('key quiz highlights a key and offers four names',
      (tester) async {
    await tester.pumpWidget(_wrap(const KeyNameScreen(), sri));
    await tester.pump();

    expect(find.text('What is the marked key called?'), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['name']);
    await tester.pumpAndSettle();
  });

  testWidgets('echo keys plays an anchor and accepts key taps', (tester) async {
    await tester.pumpWidget(_wrap(const KeyEarScreen(), sri));
    await tester.pump();

    expect(
      find.textContaining('mystery note'),
      findsOneWidget,
    );
    expect(find.byType(PianoKeyboard), findsOneWidget);

    final keyboardBox = tester.getRect(find.byType(PianoKeyboard));
    await tester.tapAt(Offset(keyboardBox.left + 10, keyboardBox.bottom - 10));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['ear']);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });

  testWidgets('play-the-melody shows staff + labeled keys and records',
      (tester) async {
    await tester.pumpWidget(_wrap(const KeyMelodyScreen(), sri));
    await tester.pump();

    expect(find.text('Play these notes in order!'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);

    final keyboardBox = tester.getRect(find.byType(PianoKeyboard));
    await tester.tapAt(Offset(keyboardBox.left + 10, keyboardBox.bottom - 10));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['melody']);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  });

  testWidgets('chord grip asks for a triad and records on key taps',
      (tester) async {
    await tester.pumpWidget(_wrap(const KeyChordScreen(), sri));
    await tester.pump();

    expect(find.textContaining('major chord'), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);

    // Tap the top-left corner of the keyboard: that's a black key (C#4),
    // never part of the C/F/G base triads — records a wrong answer.
    final keyboardBox = tester.getRect(find.byType(PianoKeyboard));
    await tester.tapAt(
      Offset(
        keyboardBox.left + keyboardBox.width / 12 * 0.9,
        keyboardBox.top + 10,
      ),
    );
    await tester.pump();
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['chord']);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  });
}
