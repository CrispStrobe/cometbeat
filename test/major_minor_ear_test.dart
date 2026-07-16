import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/scales/major_minor_ear_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ear game plays, offers Major/Minor, records under scales.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider<SriService>.value(value: sri),
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => ProgressService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: MajorMinorEarScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Major'), findsOneWidget);
    expect(find.text('Minor'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.text('Major'));
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['scales']!.keys, ['hear']);
    await tester.pumpAndSettle();
  });

  testWidgets('at 2 stars it widens to Diminished + Augmented', (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('major_minor_ear', score: 700, stars: 2);

    await pumpGame(
      tester,
      const MajorMinorEarScreen(),
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    expect(find.text('Major'), findsOneWidget);
    expect(find.text('Minor'), findsOneWidget);
    expect(find.text('Diminished'), findsOneWidget);
    expect(find.text('Augmented'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('below 2 stars it stays Major / Minor', (tester) async {
    await pumpGame(tester, const MajorMinorEarScreen());
    expect(find.text('Diminished'), findsNothing);
    await tester.pumpAndSettle();
  });
}
