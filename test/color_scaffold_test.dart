import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/note_colors.dart';
import 'package:comet_beat/features/settings/screens/settings_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('pitch-class colours', () {
    test('every step has a distinct colour', () {
      final colours = Step.values.map(pitchClassColor).toList();
      expect(colours.length, 7);
      expect(colours.toSet().length, 7); // all distinct
    });
  });

  group('colorScaffold setting', () {
    test('defaults off and persists across loads', () async {
      final a = SettingsService();
      await a.load();
      expect(a.colorScaffold, isFalse);

      await a.setColorScaffold(true);
      final b = SettingsService();
      await b.load();
      expect(b.colorScaffold, isTrue);
    });
  });

  testWidgets('settings toggle turns on the scaffold and shows the legend',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PackageInfo.setMockInitialValues(
      appName: 'CometBeat',
      packageName: 'com.crispstrobe.cometBeat',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<SriService>.value(
            value: SriService(getNow: () => DateTime(2026, 7, 11)),
          ),
          ChangeNotifierProvider(create: (_) => DebugService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Colour helper for beginners'), findsOneWidget);
    await tester.tap(find.text('Colour helper for beginners'));
    await tester.pumpAndSettle();

    expect(settings.colorScaffold, isTrue);
    // The 7-colour legend now shows one labelled swatch per letter.
    expect(find.text('C'), findsWidgets);
    expect(find.text('G'), findsWidgets);
  });
}
