// Shared harness for game-screen widget tests.
//
// Staff-based game screens stack one or more engraved staves in a Column. On
// CI's small default test surface (800×600, Linux glyph metrics) those staves
// can overflow and render off-screen, so `tap`/`drag`/`ensureVisible` throw
// `getElementPoint` — even though the same test passes locally (macOS, larger
// effective metrics). This got worse as crisp_notation-public's rendering evolved
// under mus CI, which tracks `crisp_notation@main`.
//
// Use [useGameSurface] (or [pumpGame], which calls it) in every staff-based
// game test so the whole screen is laid out with room to spare and its targets
// stay tappable on any platform. See docs/PLAN.md board note.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Generous surface for game-screen tests: tall enough for several stacked
/// staves plus answer controls, wide enough for horizontal card layouts.
const Size kGameTestSurface = Size(1400, 2400);

/// Enlarge the test surface for a game screen and restore it after the test.
/// Call this first in any staff-based game test.
Future<void> useGameSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kGameTestSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Pump [home] on a generous surface, wrapped in the standard game providers
/// and EN/DE localizations. Pass [sri] to observe recorded responses; otherwise
/// a fresh service is created. Add [extraProviders] for screens that need more.
Future<void> pumpGame(
  WidgetTester tester,
  Widget home, {
  SriService? sri,
  List<SingleChildWidget> extraProviders = const [],
}) async {
  await useGameSurface(tester);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        if (sri != null)
          ChangeNotifierProvider<SriService>.value(value: sri)
        else
          ChangeNotifierProvider(
            create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
          ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ...extraProviders,
      ],
      child: MaterialApp(
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
