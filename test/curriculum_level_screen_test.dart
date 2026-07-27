// CurriculumLevelScreen — a data-driven level view (title, practice buttons,
// one tile per topic). No mic/plugins, so it's a clean widget test: it renders
// every real curriculum level without throwing, with the title and topics.
import 'package:comet_beat/core/curriculum/curriculum.dart';
import 'package:comet_beat/features/curriculum/screens/curriculum_level_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders a level with its badge+name title and topics header',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final level = kCurricula.first.levels.first;

    await pumpGame(tester, CurriculumLevelScreen(level: level));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('${level.badge}  ${level.name(l10n)}'), findsOneWidget);
    expect(find.text(l10n.curTopicsHeader), findsOneWidget);
    // One card per topic in the level.
    expect(find.byType(Card), findsNWidgets(level.topics.length));
  });

  testWidgets('every curriculum level renders without throwing',
      (tester) async {
    for (final level in kCurricula.first.levels) {
      await pumpGame(tester, CurriculumLevelScreen(level: level));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'level ${level.badge} threw',
      );
    }
  });
}
