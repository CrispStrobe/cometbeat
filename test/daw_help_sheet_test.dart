// The Audio Editor guide (help overlay) + the editor-linked clip badge. Verifies
// the guide opens, shows every section, and does not overflow at phone AND
// desktop widths in EN and DE, and that the "linked to editor" affordance appears
// only on editor-linked (score) clips — not on plain audio/beat clips.

import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_help_sheet.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

const _phone = Size(360, 640);
const _desktop = Size(1400, 900);

Future<AppLocalizations> _l10n(Locale locale) =>
    AppLocalizations.delegate.load(locale);

Future<void> _pumpGuide(
  WidgetTester tester, {
  required Locale locale,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDawHelpSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final locale in const [Locale('en'), Locale('de')]) {
    for (final entry in const {'phone': _phone, 'desktop': _desktop}.entries) {
      testWidgets(
        'guide shows every section without overflow — ${locale.languageCode} '
        '${entry.key}',
        (tester) async {
          final l = await _l10n(locale);
          await _pumpGuide(tester, locale: locale, size: entry.value);

          // Title + every section heading is present and reachable.
          expect(find.text(l.dawHelpTitle), findsOneWidget);
          for (final title in [
            l.dawHelpToolbarTitle,
            l.dawHelpBuildTitle,
            l.dawHelpClipsTitle,
            l.dawHelpFxTitle,
            l.dawHelpRoundTripTitle,
          ]) {
            // Long content scrolls; scroll it into view before asserting.
            await tester.scrollUntilVisible(
              find.text(title),
              120,
              scrollable: find.byType(Scrollable).last,
            );
            expect(find.text(title), findsOneWidget);
          }

          // No RenderFlex overflow at this size/locale.
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('linked badge + hint appear only on editor-linked score clips',
      (tester) async {
    final l = await _l10n(const Locale('en'));
    await pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );
    final daw = _daw(tester);

    // A plain beat clip is NOT editor-linked → no link badge, no hint.
    daw.addDemoBeat();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link), findsNothing);

    // A tune clip IS a ScoreSource → the timeline shows the link badge.
    daw.addDemoTune();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link), findsWidgets);

    // Opening its inspector explains the round-trip in words.
    await tester.tap(find.text('🎼')); // the score clip's kind label
    await tester.pumpAndSettle();
    expect(find.text(l.dawClipLinked), findsOneWidget);
    expect(find.text(l.dawClipLinkedHint), findsOneWidget);
  });
}
