// Cross-cutting consistency checks: the registry, module list, star
// brackets and localizations must stay in sync as games are added.

import 'package:comet_beat/core/models/learning_module.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module ids are unique and every game module exists', () {
    final moduleIds = kLearningModules.map((m) => m.id).toList();
    expect(
      moduleIds.toSet().length,
      moduleIds.length,
      reason: 'duplicate module id',
    );

    for (final key in kGamesByModule.keys) {
      expect(
        moduleIds,
        contains(key),
        reason: 'games registered for unknown module "$key"',
      );
    }
  });

  test('every module has at least one game', () {
    for (final module in kLearningModules) {
      expect(
        kGamesByModule[module.id],
        isNotNull,
        reason: 'module "${module.id}" has no games',
      );
      expect(
        kGamesByModule[module.id],
        isNotEmpty,
        reason: 'module "${module.id}" has an empty game list',
      );
    }
  });

  test('game ids are globally unique', () {
    final ids = kGamesByModule.values
        .expand((games) => games.map((g) => g.id))
        .toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate game id');
  });

  test('star brackets are strictly ascending positive triples', () {
    kStarThresholds.forEach((game, bracket) {
      expect(bracket.length, 3, reason: '$game bracket length');
      expect(bracket[0], greaterThan(0), reason: '$game 1-star');
      expect(bracket[1], greaterThan(bracket[0]), reason: '$game 2-star');
      expect(bracket[2], greaterThan(bracket[1]), reason: '$game 3-star');
    });
  });

  test('titles and subtitles resolve in both locales for all content',
      () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final module in kLearningModules) {
        expect(module.title(l10n), isNotEmpty);
        expect(module.subtitle(l10n), isNotEmpty);
      }
      for (final games in kGamesByModule.values) {
        for (final game in games) {
          expect(
            game.title(l10n),
            isNotEmpty,
            reason: '${game.id} title (${locale.languageCode})',
          );
          expect(
            game.subtitle(l10n),
            isNotEmpty,
            reason: '${game.id} subtitle (${locale.languageCode})',
          );
        }
      }
    }
  });

  test('German note naming: B is H', () {
    final de = lookupAppLocalizations(const Locale('de'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(de.noteNameB, 'H');
    expect(en.noteNameB, 'B');
    expect(de.noteNameC, 'C');
  });
}
