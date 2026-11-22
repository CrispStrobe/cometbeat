// Every per-surface guide must exist and be non-empty in both app languages.
// The guides are the "?" content for the tools that are not minigames; an empty
// string would silently ship a blank help sheet.

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/app_guides.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:comet_beat/shared/tutorial/tutorial_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guides = <String, Tutorial Function(AppLocalizations)>{
    'home': homeGuide,
    'tab': tabWorkshopGuide,
    'transcribe': transcribeGuide,
    'practice': practiceGuide,
    'tracker': trackerGuide,
    'perform': performGuide,
    'chart': chartGuide,
    'soundLab': soundLabGuide,
    'voiceLab': voiceLabGuide,
    'songBook': songBookGuide,
    'library': libraryGuide,
    'mixer': mixerGuide,
    'setlist': setlistGuide,
    'gig': gigGuide,
    'tuner': tunerGuide,
    'sampleExtractor': sampleExtractorGuide,
    'import': importGuide,
  };

  for (final locale in const [Locale('en'), Locale('de')]) {
    test('every app guide is complete (${locale.languageCode})', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final entry in guides.entries) {
        final tutorial = entry.value(l10n);
        expect(tutorial.title.trim(), isNotEmpty, reason: '${entry.key} title');
        expect(tutorial.steps, isNotEmpty, reason: '${entry.key} steps');
        for (final step in tutorial.steps) {
          expect(step.text.trim(), isNotEmpty, reason: '${entry.key} step');
        }
      }
    });
  }

  testWidgets('the help button opens its guide', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: TutorialButton(
              builder: homeGuide,
              tooltip: 'Help',
            ),
          ),
        ),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byType(TutorialButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.helpHomeTitle), findsOneWidget);
    expect(find.text(l10n.helpHomeBody), findsOneWidget);
  });
}
