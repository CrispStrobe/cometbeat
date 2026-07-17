import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/keyboard/grand_staff_read_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'grand staff reading offers four notes and records under '
      'keyboard.grand', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));

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
          home: GrandStaffReadScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GrandStaffView), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['keyboard']!.keys, ['grand']);
    await tester.pumpAndSettle();
  });
}
