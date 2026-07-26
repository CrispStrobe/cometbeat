// Responsive layout audit: pump EVERY registered game on real phone and tablet
// surfaces, in EN and DE, and assert nothing overflows (no yellow/black
// RenderFlex stripe). Game widget tests use a generous 1400×2400 surface that
// never overflows; this catches breakage at the sizes real devices use —
// especially German, which runs longer and is where overflows hide.
//
// It does NOT tap anything (so it's immune to the getElementPoint issue on a
// small surface) — it only builds, lays out and paints each screen, then drains
// the frame's exception with takeException() and flags the overflows.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The narrowest common phone — where content overflows if it's going to. Wider
// phones/tablets have strictly more room, so this is the binding case for an
// overflow audit; the option-centering on wide screens is handled structurally
// by AnswerRow, not something an overflow check would catch anyway. One size ×
// two locales keeps the audit fast enough to live in the default suite.
const _sizes = <String, Size>{
  'SE 375x667': Size(375, 667),
};

Widget _wrap(Widget child, Locale locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 18)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        // Reduced motion so animated games settle to a static first frame.
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child,
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every game renders without overflow (phone + tablet × EN/DE)',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final overflows = <String>[];
    // (The standalone Beginner-Tracker tile was retired 2026-07-26 — folded into
    // the Loop Studio editors — so its old audit skip is gone with it.)
    final games = kGamesByModule.values.expand((g) => g).toList();

    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final size in _sizes.entries) {
        await tester.binding.setSurfaceSize(size.value);
        for (final g in games) {
          await tester.pumpWidget(_wrap(Builder(builder: g.builder), locale));
          // Two frames: the first lays out, the second catches any overflow a
          // game only reveals after its post-frame rebuild (auto-play, etc.).
          for (var frame = 0; frame < 2; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final ex = tester.takeException();
            if (ex != null &&
                ex.toString().toLowerCase().contains('overflow')) {
              overflows.add(
                '${g.id} @ ${size.key} [${locale.languageCode}]: '
                '${ex.toString().split('\n').first}',
              );
            }
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink()); // dispose all game state

    expect(
      overflows,
      isEmpty,
      reason: 'RenderFlex overflows:\n${overflows.join('\n')}',
    );
  });
}
