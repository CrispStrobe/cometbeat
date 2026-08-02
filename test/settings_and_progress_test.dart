import 'package:comet_beat/core/harmony/chart_level.dart';
import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:comet_beat/features/progress/screens/progress_screen.dart';
import 'package:comet_beat/features/settings/screens/settings_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  test('SettingsService persists the note-naming convention', () async {
    final settings = SettingsService();
    await settings.load();
    expect(settings.noteNaming, NoteNaming.auto); // default

    await settings.setNoteNaming(NoteNaming.solfege);

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.noteNaming, NoteNaming.solfege);
  });

  testWidgets('progress screen shows boxes and module mastery', (tester) async {
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

  testWidgets('settings screen: language options + stats, switch to German',
      (tester) async {
    // Tall surface so the whole settings ListView builds (stats near bottom).
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
    final sri = SriService(getNow: () => DateTime(2026, 7, 11))
      ..recordResponse('note_values.symbol.whole_note', true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<SriService>.value(value: sri),
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

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);

    // Language tiles sit at the top; tap while they're on screen.
    await tester.tap(find.text('Deutsch'));
    await tester.pump();
    expect(settings.locale, const Locale('de'));

    // Stats live at the bottom of the (lazy) ListView — scroll them in first.
    final ones = find.text('1');
    for (var i = 0; i < 12 && ones.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
    }
    expect(ones, findsWidgets); // tracked/learning stats
  });

  testWidgets(
      'Advanced transcription pickers expose the distinct neural '
      'backends (no longer collapsed to "Neural")', (tester) async {
    // Tall surface so the whole ListView builds and the expander is tappable.
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = SettingsService();
    await settings.load();
    final cfg = TranscriptionConfigService();
    await cfg.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<SriService>.value(value: SriService()),
          ChangeNotifierProvider(create: (_) => DebugService()),
          ChangeNotifierProvider<TranscriptionConfigService>.value(value: cfg),
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

    // Open the Advanced expander that holds the per-step backend pickers.
    await tester.ensureVisible(find.byType(ExpansionTile).first);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    // Each neural runtime now has its own chip label; previously all three
    // (onnx/onnxFfi/crispasr) rendered as a single "Neural".
    expect(find.text('GGUF (native)'), findsWidgets);
    expect(find.text('ONNX (native)'), findsWidgets);
  });

  testWidgets('the chart-detail dial is on screen and changes the setting',
      (tester) async {
    // BB-U6. The dial only earns its keep if a player can reach it.
    PackageInfo.setMockInitialValues(
      appName: 'CometBeat',
      packageName: 'com.crispstrobe.cometBeat',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider(create: (_) => SriService()),
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

    final dial = find.byKey(const ValueKey('chartLevelSelector'));
    await tester.scrollUntilVisible(dial, 300);
    await tester.pumpAndSettle();

    expect(settings.chartLevel, ChartLevel.learner, reason: 'the default');
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();
    expect(settings.chartLevel, ChartLevel.beginner);

    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    expect(settings.chartLevel, ChartLevel.expert);
  });
}
