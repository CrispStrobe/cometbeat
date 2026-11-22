// Documentation screenshots for docs/WORKSHOP_GUIDE.md. Pumps the real Score
// Workshop, types a short line and a chord, and writes two PNGs from the render
// tree. Run on a desktop:
//
//   flutter test integration_test/docs_screenshots_test.dart -d macos
//
// The files land in the system temp dir (the app sandbox cannot write into the
// repo); the printed SHOT paths are copied into docs/screenshots/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer;
    if (layer is! OffsetLayer) {
      // ignore: avoid_print
      print('SHOT_SKIP $name: render layer is not OffsetLayer');
      return;
    }
    final image = await layer.toImage(view.paintBounds, pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/cometbeat-docs')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT ${file.path} ${image.width}x${image.height}');
  }

  testWidgets('docs: workshop note entry and help', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => UserSongsService()),
          ChangeNotifierProvider(create: (_) => SettingsService()),
          ChangeNotifierProvider(create: (_) => DawService()),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: CompositionWorkshopScreen(),
        ),
      ),
    );
    await hold(tester);
    expect(find.byType(CompositionWorkshopScreen), findsOneWidget);

    final editor = tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;
    editor.debugFocusEntry();
    await tester.pump();

    final audio = Provider.of<AudioService>(
      tester.element(find.byType(CompositionWorkshopScreen)),
      listen: false,
    );

    // A short line, then a chord via Q + G, so the score is not empty.
    for (final k in [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC,
    ]) {
      await tester.sendKeyEvent(k);
      await tester.pump(const Duration(milliseconds: 40));
    }
    // Zoom the staff in so the notes read at documentation size.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.zoom_in).first);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await hold(tester);
    await shot(tester, 'workshop-note-entry');

    // The generic help sheet.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.ensureVisible(find.byTooltip(l10n.workshopHelpButton));
    await tester.tap(find.byTooltip(l10n.workshopHelpButton));
    await hold(tester);
    await shot(tester, 'workshop-help');

    audio.dispose();
    await tester.pump();
  });
}
