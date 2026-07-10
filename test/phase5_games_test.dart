import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/measures/meter_detective_screen.dart';
import 'package:klang_universum/features/games/note_reading/melody_echo_screen.dart';
import 'package:klang_universum/features/games/note_values/beat_count_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show StaffView;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return MultiProvider(
    providers: [
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

  testWidgets('beat count renders notation (possibly tied) and records',
      (tester) async {
    await tester.pumpWidget(_wrap(const BeatCountScreen(), sri));
    await tester.pump();

    expect(find.textContaining('How many beats'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4)); // 1..4

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['beats']);
    await tester.pumpAndSettle();
  });

  testWidgets('meter detective offers 2/4, 3/4, 4/4 and records',
      (tester) async {
    await tester.pumpWidget(_wrap(const MeterDetectiveScreen(), sri));
    await tester.pump();

    for (final label in ['2/4', '3/4', '4/4']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('3/4'));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['measures']!.keys, ['meter']);
    await tester.pumpAndSettle();
  });

  testWidgets('melody echo shows three distinct melody cards',
      (tester) async {
    await tester.pumpWidget(_wrap(const MelodyEchoScreen(), sri));
    await tester.pump();

    expect(find.textContaining('Which melody'), findsOneWidget);
    expect(find.byType(StaffView), findsNWidgets(3));

    await tester.tap(find.byType(StaffView).first);
    await tester.pump();
    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['melody']);
    await tester.pumpAndSettle();
  });
}
