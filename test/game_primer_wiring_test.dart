// The six recently-added games (connect degrees/time/keysig/roadmap, and the
// dynamics/tempo ordering games) should each carry their OWN concept primer,
// not just fall back to the generic module intro. Locks that wiring + checks
// the newly-authored roadmap primer resolves in both locales.

import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final byId = {
    for (final g in kGamesByModule.values.expand((x) => x)) g.id: g,
  };

  test('each recently-added / corrected game carries its own primer', () {
    for (final id in const [
      // My six new games.
      'connect_degrees',
      'connect_time',
      'connect_keysig',
      'connect_roadmap',
      'dynamics_order',
      'tempo_order',
      // Corrected: were falling back to a general/mismatched module primer.
      'meter_detective', // march/waltz → strong-beat pattern
      'place_note_bass', // bass reading (not the treble fallback)
      'key_name', // key-signature naming (not the module general)
      // The aural-expression trio — dedicated primers that demonstrate the
      // gradual change / articulation, not the generic expression fallback.
      'crescendo_ear',
      'tempo_change_ear',
      'articulation_ear',
    ]) {
      expect(byId[id], isNotNull, reason: '$id is registered');
      expect(
        byId[id]!.tutorial,
        isNotNull,
        reason: '$id should have its own concept primer, not the fallback',
      );
    }
  });

  test('roadmapPrimer resolves with non-empty steps in en and de', () {
    for (final locale in const [Locale('en'), Locale('de')]) {
      final tutorial = roadmapPrimer(lookupAppLocalizations(locale));
      expect(tutorial.title, isNotEmpty, reason: locale.languageCode);
      expect(tutorial.steps, isNotEmpty, reason: locale.languageCode);
      for (final step in tutorial.steps) {
        expect(step.text, isNotEmpty, reason: '${locale.languageCode} step');
      }
    }
  });

  test('the aural-expression primers resolve (title, text, try-it) in en/de',
      () {
    final primers = [
      crescendoEarPrimer,
      tempoChangeEarPrimer,
      articulationEarPrimer,
    ];
    for (final locale in const [Locale('en'), Locale('de')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final primer in primers) {
        final tutorial = primer(l10n);
        expect(tutorial.title, isNotEmpty, reason: locale.languageCode);
        expect(tutorial.steps, isNotEmpty, reason: locale.languageCode);
        for (final step in tutorial.steps) {
          expect(step.text, isNotEmpty, reason: '${locale.languageCode} step');
        }
        // Each ends with a "try it" step (audio + two labelled choices).
        final tryIt = tutorial.steps.last;
        expect(
          tryIt.hasChoices,
          isTrue,
          reason: '${locale.languageCode} tryit',
        );
        expect(tryIt.hasAudio, isTrue, reason: '${locale.languageCode} audio');
        expect(tryIt.choices!.where((c) => c.correct), hasLength(1));
      }
    }
  });

  test('the Loop Studio carries a Kiffness first-run flow (resolves en/de)',
      () {
    final loop = byId['loop_mixer'];
    expect(loop, isNotNull, reason: 'loop_mixer is registered');
    // Wired so the TutorialGate auto-shows it once on the first visit.
    expect(
      loop!.tutorial,
      isNotNull,
      reason: 'Loop Studio should auto-show a first-run flow',
    );
    for (final locale in const [Locale('en'), Locale('de')]) {
      final t = loopStudioFirstRun(lookupAppLocalizations(locale));
      expect(t.title, isNotEmpty, reason: locale.languageCode);
      // start → layer → record → edit → more.
      expect(t.steps, hasLength(5), reason: locale.languageCode);
      for (final step in t.steps) {
        expect(step.text, isNotEmpty, reason: '${locale.languageCode} step');
      }
    }
  });
}
