// GENERATOR (not a real test): rebuilds tool/narration_strings.json from the
// app's tutorials, so the pre-baked narration set stays in sync with the actual
// read-aloud text (tutorial_sheet._readAloud speaks TutorialStep.text). Run:
//   flutter test test/gen_narration_strings.dart
// then bake: dart run tool/bake_narration.dart tool/narration_strings.json
//
// It needs Flutter l10n (AppLocalizations), so it lives as a test rather than a
// plain `dart run` tool. It only READS the registry + WRITES the JSON.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/tutorial.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('regenerate tool/narration_strings.json from the app tutorials', () {
    final byLang = <String, AppLocalizations>{
      'en': lookupAppLocalizations(const Locale('en')),
      'de': lookupAppLocalizations(const Locale('de')),
    };

    // Every game's help tutorial (its own, or the module fallback) — dedup the
    // shared primer functions by identity so we build each primer once.
    final primers = <Tutorial Function(AppLocalizations)>{};
    for (final games in kGamesByModule.values) {
      for (final g in games) {
        final t = helpPrimerFor(g);
        if (t != null) primers.add(t);
      }
    }

    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final builder in primers) {
      for (final entry in byLang.entries) {
        final tut = builder(entry.value);
        for (final step in tut.steps) {
          final text = step.text.trim();
          if (text.isEmpty) continue;
          if (seen.add('${entry.key}|$text')) {
            out.add({'lang': entry.key, 'text': text});
          }
        }
      }
    }
    String sortKey(Map<String, String> m) => '${m['lang']}${m['text']}';
    out.sort((a, b) => sortKey(a).compareTo(sortKey(b)));

    File('tool/narration_strings.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(out)}\n',
    );
    // ignore: avoid_print
    print('wrote ${out.length} narration strings from ${primers.length} '
        'unique primers → tool/narration_strings.json');
    expect(out, isNotEmpty);
  });
}
