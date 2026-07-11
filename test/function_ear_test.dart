import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/harmony/function_ear_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
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

  testWidgets('offers T/S/D, records first answer under harmony.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(_wrap(const FunctionEarScreen(), sri));
    await tester.pump();

    expect(find.text('Tonic'), findsOneWidget);
    expect(find.text('Subdominant'), findsOneWidget);
    expect(find.text('Dominant'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.text('Tonic'));
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['harmony']!.keys, ['hear']);
    await tester.pumpAndSettle();
  });

  testWidgets('review mode runs exactly the supplied items', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(
      _wrap(
        const FunctionEarScreen(
          reviewItemIds: ['harmony.hear.c_dominant'],
        ),
        sri,
      ),
    );
    await tester.pump();

    // Single-round review: answering correctly finishes the session.
    expect(find.textContaining('1'), findsWidgets); // round 1 of 1
    await tester.tap(find.text('Dominant'));
    await tester.pumpAndSettle();

    expect(sri.totalTrackedItems, 1);
    // Review sessions don't offer a replay button on the result screen.
    expect(find.byIcon(Icons.replay), findsNothing);
  });
}
