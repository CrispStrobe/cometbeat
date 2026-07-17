import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/guitar_string_quiz_screen.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab_read_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget home, SriService sri) => MultiProvider(
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
        home: home,
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('guitar tab data', () {
    test('every note sits at its lowest-fret position for standard tuning', () {
      for (final note in kGuitarFirstPosition) {
        final assigned = kGuitarTuning.fretFor(note.pitch);
        expect(
          assigned,
          (note.stringIndex, note.fret),
          reason: 'pitch ${note.pitch} should render at '
              'string ${note.stringIndex} fret ${note.fret}',
        );
      }
    });

    test('the six open strings spell E A D G B E, string 1 first', () {
      expect(
        kGuitarOpenStrings.map((s) => s.pitch.step.name).toList(),
        ['e', 'b', 'g', 'd', 'a', 'e'],
      );
      expect(
        kGuitarOpenStrings.map((s) => s.stringNumber).toList(),
        [1, 2, 3, 4, 5, 6],
      );
    });

    test('fretted material excludes open strings', () {
      expect(kGuitarFrettedNotes, isNotEmpty);
      expect(kGuitarFrettedNotes.every((n) => n.fret > 0), isTrue);
    });
  });

  testWidgets('open-strings game records under guitar.string', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const GuitarStringQuizScreen(), sri));
    await tester.pump();

    // Five distinct open-string letters offered.
    expect(find.byType(FilledButton), findsNWidgets(5));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['guitar']!.keys, ['string']);
    await tester.pumpAndSettle();
  });

  testWidgets('read-the-tab game records under guitar.fret', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const GuitarTabReadScreen(), sri));
    await tester.pump();

    expect(find.byType(FilledButton), findsNWidgets(4));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['guitar']!.keys, ['fret']);
    await tester.pumpAndSettle();
  });
}
