// App Store screenshot capture. Runs the real app, navigates to a handful of
// representative screens and takes a screenshot at each. Driven via
// `flutter drive --driver=test_driver/integration_test.dart
//   --target=integration_test/screenshots_test.dart -d <sim>`
// on a macOS CI runner (see .github/workflows/screenshots.yml). `flutter drive`
// is used (not `flutter test`) so custom fonts — incl. the Bravura music font —
// render, and so takeScreenshot() bytes reach the driver's onScreenshot sink.
//
// SHOT_PREFIX (a --dart-define) tags the files per device, e.g. iphone_01_home.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  // SHOT_DIR: write PNGs straight from the render tree instead of going through
  // the driver's screenshot sink.
  //
  // WHY. On macOS `flutter drive` runs the test fine but the driver's
  // onScreenshot channel does not attach — the run warns "not capturing test
  // results properly" and `binding.takeScreenshot` yields no files, silently.
  // And the host-side fallbacks are closed too: there is no macOS simulator
  // framebuffer to read (`simctl io screenshot` is iOS-only) and `screencapture`
  // needs a Screen Recording grant.
  //
  // The render tree needs none of that. `RenderView.debugLayer` is an
  // OffsetLayer, which can rasterise itself — so the test writes the bytes
  // itself, with an exact pixelRatio, and the driver is not involved at all.
  const shotDir = String.fromEnvironment('SHOT_DIR');
  const shotRatio = int.fromEnvironment('SHOT_RATIO', defaultValue: 2);

  Future<void> writeLayerPng(WidgetTester tester, String file) async {
    // `renderView` is deprecated in favour of renderViews (multi-view); take
    // the single view this app actually has.
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      view.paintBounds,
      pixelRatio: shotRatio.toDouble(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    // ⚠️ The macOS app runs SANDBOXED (app-sandbox is in the entitlements and is
    // mandatory for the Mac App Store), so it cannot write to an arbitrary path:
    // '/tmp/...' fails with "Operation not permitted". Directory.systemTemp
    // resolves INSIDE the container and is writable, so fall back to it and
    // print where the bytes actually landed.
    Directory dir;
    try {
      dir = Directory(shotDir)..createSync(recursive: true);
    } on FileSystemException {
      dir = Directory('${Directory.systemTemp.path}/cometbeat-shots')
        ..createSync(recursive: true);
    }
    final f = File('${dir.path}/$file.png');
    await f.writeAsBytes(data.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT ${f.path} ${image.width}x${image.height}');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await hold(tester);
    if (shotDir.isNotEmpty) {
      await writeLayerPng(tester, '${prefix}_$name');
    } else {
      await binding.takeScreenshot('${prefix}_$name');
    }
  }

  // Best-effort navigation: a missing finder skips that one shot, never aborts
  // the rest (so we always keep whatever we did capture). Each step is also
  // hard-bounded in wall-clock: a screen whose init blocks (e.g. a plugin/mic/
  // audio channel that never returns) would otherwise silently eat the whole
  // 60-min CI budget with NO clue which screen. On timeout we log the name and
  // move on — the job finishes, the capture degrades gracefully, and the log
  // names the culprit for a targeted follow-up. Runs on the Dart isolate, so a
  // deadlocked *platform* thread still lets this timer fire.
  Future<void> step(
    String name,
    Future<void> Function() body, {
    int seconds = 120,
  }) async {
    try {
      await body().timeout(Duration(seconds: seconds));
    } on TimeoutException {
      debugPrint('SHOT_STEP_TIMEOUT $name: exceeded ${seconds}s — skipping');
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
    // Bound startup too: if app.main() (or an eager service init) ever blocks,
    // fail fast with a clear message instead of a mute 60-min timeout.
    await app.main().timeout(const Duration(seconds: 120));
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
    await step('home', () => shot(tester, '01_home'));

    // 2) A real game (first module -> first game): shows live notation
    await step('game', () async {
      await tester.tap(find.byType(Card).first);
      await hold(tester);
      await tester.tap(find.byType(Card).first);
      await shot(tester, '02_game');
      await back(tester);
      await back(tester);
    });

    // 3) Composition workshop (score editor). Scope the tap to the AppBar: the
    // module grid also renders Icons.piano on game cards, so a bare byIcon is
    // ambiguous on the wider iPad layout (2 matches → tap throws → iPad missed
    // this shot). The AppBar has exactly one piano (the Workshop menu button).
    await step('workshop', () async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.piano),
        ),
      );
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
