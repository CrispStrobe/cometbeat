// The post-answer explanation card must fit on a small phone in the longer
// (German) UI: answer one item in each wired game on a 375×667 surface and
// assert nothing overflows. The answers are given by invoking the buttons'
// callbacks (no hit-testing), like the layout audit, so off-screen geometry
// cannot make the test flaky.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/explain/answer_explanation.dart';
import 'package:comet_beat/features/games/expression/articulation_ear_screen.dart';
import 'package:comet_beat/features/games/expression/charades_screen.dart';
import 'package:comet_beat/features/games/expression/crescendo_ear_screen.dart';
import 'package:comet_beat/features/games/expression/crescendo_read_screen.dart';
import 'package:comet_beat/features/games/expression/tempo_change_ear_screen.dart';
import 'package:comet_beat/features/games/note_reading/articulation_read_screen.dart';
import 'package:comet_beat/features/games/note_values/dynamics_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/dynamics_order_screen.dart';
import 'package:comet_beat/features/games/note_values/tempo_duel_screen.dart';
import 'package:comet_beat/features/games/note_values/tempo_order_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(375, 667));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 18)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
      ),
    ),
  );
  await tester.pump();
}

/// Presses the first answer control of the given type by its callback.
void _pressFirst(WidgetTester tester) {
  final buttons = find.byWidgetPredicate(
    (w) => w is FilledButton && w.onPressed != null,
  );
  if (buttons.evaluate().isNotEmpty) {
    tester.widget<FilledButton>(buttons.first).onPressed!();
  } else {
    // The duels: the answer cards are InkWells inside Cards.
    final inkWells = find.descendant(
      of: find.byType(Card),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(inkWells.first).onTap!();
  }
}

Future<void> _expectFits(WidgetTester tester, String what) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    find.byKey(AnswerExplanation.panelKey),
    findsOneWidget,
    reason: '$what: card shown',
  );
  final errors = <Object>[];
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    errors.add(e);
  }
  expect(errors, isEmpty, reason: '$what: $errors');
  // Let the hold run out so no timer is left pending.
  await tester.pump(kExplanationHold * 2);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final games = <String, Widget>{
    'dynamics duel': const DynamicsDuelScreen(),
    'tempo duel': const TempoDuelScreen(),
    'charades': const CharadesScreen(),
    'crescendo ear': const CrescendoEarScreen(),
    'crescendo read': const CrescendoReadScreen(),
    'tempo change ear': const TempoChangeEarScreen(),
    'articulation ear': const ArticulationEarScreen(),
    'articulation read': const ArticulationReadScreen(),
  };
  for (final MapEntry(key: name, value: screen) in games.entries) {
    testWidgets('$name: the explanation fits a small phone (de)',
        (tester) async {
      await _pump(tester, screen);
      _pressFirst(tester);
      await _expectFits(tester, name);
    });
  }

  testWidgets('dynamics order: the four-mark explanation fits (de)',
      (tester) async {
    await _pump(tester, const DynamicsOrderScreen());
    final game = tester.state<State<DynamicsOrderScreen>>(
      find.byType(DynamicsOrderScreen),
    ) as DynamicsOrderTester;
    for (final i in game.tapOrder) {
      final ink = find.descendant(
        of: find.byKey(ValueKey('dynamic_card_$i')),
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(ink.first).onTap!();
      await tester.pump();
    }
    await _expectFits(tester, 'dynamics order');
  });

  testWidgets('tempo order: the four-word explanation fits (de)',
      (tester) async {
    await _pump(tester, const TempoOrderScreen());
    final game = tester.state<State<TempoOrderScreen>>(
      find.byType(TempoOrderScreen),
    ) as TempoOrderTester;
    for (final i in game.tapOrder) {
      final ink = find.descendant(
        of: find.byKey(ValueKey('tempo_card_$i')),
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(ink.first).onTap!();
      await tester.pump();
    }
    await _expectFits(tester, 'tempo order');
  });
}
