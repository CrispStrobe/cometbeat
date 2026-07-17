// App Store screenshot capture. Runs the real app, navigates to a handful of
// representative screens and takes a screenshot at each. Driven via
// `flutter drive --driver=test_driver/integration_test.dart
//   --target=integration_test/screenshots_test.dart -d <sim>`
// on a macOS CI runner (see .github/workflows/screenshots.yml). `flutter drive`
// is used (not `flutter test`) so custom fonts — incl. the Bravura music font —
// render, and so takeScreenshot() bytes reach the driver's onScreenshot sink.
//
// SHOT_PREFIX (a --dart-define) tags the files per device, e.g. iphone_01_home.
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const prefix = String.fromEnvironment('SHOT_PREFIX', defaultValue: 'shot');
  // Force the app language so we can capture an EN and a DE set from one test
  // (the store needs screenshots per localization). Empty = follow the device.
  const shotLocale = String.fromEnvironment('SHOT_LOCALE');

  // Never pumpAndSettle — a looping animation (mascot, animated background)
  // never settles and would hang the run. Hold a screen by pumping fixed steps.
  Future<void> hold(WidgetTester tester, {int ms = 2200}) async {
    for (var t = 0; t < ms; t += 150) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await hold(tester);
    await binding.takeScreenshot('${prefix}_$name');
  }

  // Best-effort navigation: a missing finder skips that one shot, never aborts
  // the rest (so we always keep whatever we did capture).
  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      debugPrint('SHOT_STEP_SKIPPED $name: $e');
    }
  }

  Future<void> back(WidgetTester tester) async {
    try {
      await tester.pageBack();
    } catch (_) {}
    await hold(tester);
  }

  testWidgets('capture store screenshots', (tester) async {
    await app.main();
    autoShowTutorials = false; // don't let a first-run tutorial cover a screen
    await hold(tester, ms: 1500); // let the first frame render

    if (shotLocale.isNotEmpty) {
      // MultiProvider sits above MaterialApp in main.dart, so MaterialApp's
      // context can read SettingsService and force this capture's language.
      final ctx = tester.element(find.byType(MaterialApp));
      await Provider.of<SettingsService>(ctx, listen: false)
          .setLocale(Locale(shotLocale));
      await hold(tester, ms: 900);
    }

    await binding
        .convertFlutterSurfaceToImage(); // required on iOS before shots
    await hold(tester, ms: 600);

    // 1) Home — the learning-module grid
    await shot(tester, '01_home');

    // 2) A real game (first module -> first game): shows live notation
    await step('game', () async {
      await tester.tap(find.byType(Card).first);
      await hold(tester);
      await tester.tap(find.byType(Card).first);
      await shot(tester, '02_game');
      await back(tester);
      await back(tester);
    });

    // 3) Composition workshop (score editor)
    await step('workshop', () async {
      await tester.tap(find.byIcon(Icons.piano));
      await shot(tester, '03_workshop');
      await back(tester);
    });

    // 4) Curriculum
    await step('curriculum', () async {
      await tester.tap(find.byIcon(Icons.school));
      await shot(tester, '04_curriculum');
      await back(tester);
    });

    // 5) Progress
    await step('progress', () async {
      await tester.tap(find.byIcon(Icons.bar_chart));
      await shot(tester, '05_progress');
      await back(tester);
    });
  });
}
