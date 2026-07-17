import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/interval_ear_screen.dart';
import 'package:comet_beat/features/games/chords/triad_builder_screen.dart';
import 'package:comet_beat/features/games/note_values/rhythm_tap_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
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
    sri = SriService(getNow: () => DateTime(2026, 7, 10));
  });

  testWidgets('interval detective offers four intervals and records',
      (tester) async {
    await tester.pumpWidget(_wrap(const IntervalEarScreen(), sri));
    await tester.pump();

    for (final label in ['Second', 'Third', 'Fifth', 'Octave']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Fifth'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['chords']!.keys, ['interval']);
    await tester.pumpAndSettle();
  });

  testWidgets('triad builder renders the root on an interactive staff',
      (tester) async {
    await tester.pumpWidget(_wrap(const TriadBuilderScreen(), sri));
    await tester.pump();

    expect(find.byType(InteractiveStaff), findsOneWidget);
    expect(find.textContaining('major triad'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('rhythm echo shows notation, tap dots, and evaluates',
      (tester) async {
    await tester.pumpWidget(_wrap(const RhythmTapScreen(), sri));
    await tester.pump();

    expect(find.text('Tap the rhythm — hold the long notes!'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.text('Tap here!'), findsOneWidget);

    // Press the pad once per pattern note (a tap = a zero-length press, so any
    // long note fails the hold check). The round evaluates as wrong but must
    // record exactly one SRI response.
    final dots = find.byIcon(Icons.circle_outlined).evaluate().length;
    for (var i = 0; i < dots; i++) {
      await tester.tap(find.text('Tap here!'));
      await tester.pump();
    }
    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['rhythm']);
    // Flush the 900 ms retry-reset timer of the wrong-answer path.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
  });
}
