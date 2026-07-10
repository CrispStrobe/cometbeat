import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/progress/screens/progress_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SettingsService persists the locale override', () async {
    final settings = SettingsService();
    await settings.load();
    expect(settings.locale, isNull);

    await settings.setLocale(const Locale('de'));

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.locale, const Locale('de'));

    await reloaded.setLocale(null);
    final again = SettingsService();
    await again.load();
    expect(again.locale, isNull);
  });

  testWidgets('progress screen shows boxes and module mastery',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 10));
    // Two tracked items: one brand-new failure (box 1), one in progress.
    sri.recordResponse('note_values.symbol.whole_note', false);
    sri.recordResponse('note_values.symbol.half_note', true);

    await tester.pumpWidget(
      ChangeNotifierProvider<SriService>.value(
        value: sri,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: ProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flashcard boxes'), findsOneWidget);
    // note_values counts its 2 tracked items; other visible modules show 0
    // (the lazy ListView may not mount all six cards in the test viewport).
    expect(find.text('0 of 2 mastered'), findsOneWidget);
    expect(find.text('0 of 0 mastered'), findsWidgets);
  });
}
