// The "Good to know" explanation card can be switched off in Settings.
//
// With it on (the default) a solved round shows the card and holds for
// kExplanationHold (~2.8 s) so it can be read. With it off the card, its demo
// sound and the extra hold all go: the round advances at the ordinary
// kRoundAdvanceDelay, like a game without explanations.

import 'package:comet_beat/core/services/debug_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/settings/screens/settings_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/music_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

QuizRoundMixin _quiz(WidgetTester tester) =>
    tester.state(find.byType(DynamicsDuelScreen)) as QuizRoundMixin;

/// Taps the louder of the two dynamic cards (a right answer).
Future<void> _tapLouder(WidgetTester tester) async {
  final glyphs = find.descendant(
    of: find.byType(InkWell),
    matching: find.byType(MusicGlyph),
  );
  final shown = [
    for (final g in tester.widgetList<MusicGlyph>(glyphs))
      for (final m in kDynamicMarks)
        if (m.code == g.glyph.runes.first) m,
  ];
  final louder = shown.reduce((a, b) => a.rank >= b.rank ? a : b);
  await tester.tap(
    find.descendant(
      of: find.byType(InkWell),
      matching: find.byWidgetPredicate(
        (w) => w is MusicGlyph && w.glyph.runes.first == louder.code,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('on (default): the card shows and the round holds for it',
      (tester) async {
    await pumpGame(tester, const DynamicsDuelScreen());
    await _tapLouder(tester);

    expect(find.byKey(AnswerExplanation.panelKey), findsOneWidget);
    await tester.pump(kRoundAdvanceDelay + const Duration(milliseconds: 100));
    expect(_quiz(tester).round, 0, reason: 'still holding for the card');
    await tester.pump(kExplanationHold);
    expect(_quiz(tester).round, 1);
  });

  testWidgets('off: no card, and the round moves on at the ordinary pace',
      (tester) async {
    await pumpGame(tester, const DynamicsDuelScreen());
    final settings = Provider.of<SettingsService>(
      tester.element(find.byType(DynamicsDuelScreen)),
      listen: false,
    );
    await settings.setAnswerExplanations(false);
    await tester.pump();

    await _tapLouder(tester);
    expect(find.byKey(AnswerExplanation.panelKey), findsNothing);
    await tester.pump(kRoundAdvanceDelay + const Duration(milliseconds: 100));
    expect(_quiz(tester).round, 1, reason: 'no 2.8 s hold without the card');
    expect(find.byKey(AnswerExplanation.panelKey), findsNothing);
  });

  test('the setting persists and defaults to on', () async {
    final fresh = SettingsService();
    await fresh.load();
    expect(fresh.answerExplanations, isTrue);

    await fresh.setAnswerExplanations(false);
    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.answerExplanations, isFalse);
  });

  testWidgets('Settings has the toggle, in English and German', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in const [Locale('en'), Locale('de')]) {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider(
              create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
            ),
            ChangeNotifierProvider(create: (_) => DebugService()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('de')],
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)),
      )!;
      final toggle = find.byKey(const ValueKey('settings_answer_explanations'));
      await tester.scrollUntilVisible(toggle, 200);
      expect(find.text(l10n.answerExplanationsLabel), findsOneWidget);
      expect(settings.answerExplanations, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(settings.answerExplanations, isFalse);
    }
  });
}
