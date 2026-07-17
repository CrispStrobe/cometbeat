import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/melody_dictation_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
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

  testWidgets('renders an interactive staff, prompt, dots and undo',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));
    await tester.pumpWidget(_wrap(const MelodyDictationScreen(), sri));
    await tester.pump();

    expect(find.byType(InteractiveStaff), findsOneWidget);
    expect(find.textContaining('add the ones you hear'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    // The first note is given (one filled dot); the rest are empty.
    expect(
      find.byIcon(Icons.circle_outlined),
      findsNWidgets(MelodyDictationScreen.melodyLength - 1),
    );
  });

  testWidgets('placing the full melody records under note_reading.dictation',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));
    await tester.pumpWidget(_wrap(const MelodyDictationScreen(), sri));
    await tester.pump();

    // The first note is given, so place the remaining ones; the final tap
    // triggers the note-for-note check that records the round's SRI response.
    for (var i = 0; i < MelodyDictationScreen.melodyLength - 1; i++) {
      await tester.tap(find.byType(InteractiveStaff));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['dictation']);

    // Let any retry timer fire so the test tears down cleanly.
    await tester.pump(const Duration(milliseconds: 1200));
  });
}
