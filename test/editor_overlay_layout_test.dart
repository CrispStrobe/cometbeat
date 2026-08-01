// Layout audit for the surfaces the editor-UX arc added.
//
// `layout_audit_test.dart` walks `kGamesByModule`, and none of these are games:
// the pattern editor is a route pushed from Loop Studio, and the mixer is a
// sheet. So the arc shipped three new surfaces that no overflow sweep touched.
//
// German is not decoration here. It is the locale that overflows — "Trommel
// hinzufügen", "Zur Timeline hinzufügen" and "Diese Stimme folgt den Akkorden…"
// are all materially longer than their English counterparts, and the pattern
// editor puts a SegmentedButton with two labels in an AppBar that already has a
// title. 375×667 is the narrowest supported phone, so it is the binding case.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/project_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/composition/loop_pattern_editor.dart';
import 'package:comet_beat/features/games/composition/mixer_console_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sizes = <String, Size>{
  'SE 375x667': Size(375, 667),
  'Flagship 440x956': Size(440, 956),
};

Widget _wrap(Widget child, Locale locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 8, 2)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => ProjectService()),
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
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child,
        ),
      ),
    );

/// A groove in the state the editor is hardest to lay out in: a progression
/// running (so pitched parts seed from a resolved four-bar shape), and a drum
/// pattern using extended kit voices (so the grid draws more than three lanes).
LoopEngine _busyEngine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass', 'melody', 'chords', 'sparkle']);
  e.progression = kProgressions.first;
  e.setTrackDrums(
    'drums',
    DrumRowsPattern({
      Drum.kick: List<bool>.filled(kPatternSteps, false)..[0] = true,
      Drum.snare: List<bool>.filled(kPatternSteps, false)..[4] = true,
      Drum.hat: List<bool>.filled(kPatternSteps, true),
      Drum.clap: List<bool>.filled(kPatternSteps, false)..[12] = true,
      Drum.ride: List<bool>.filled(kPatternSteps, false)..[2] = true,
      Drum.crash: List<bool>.filled(kPatternSteps, false)..[0] = true,
    }),
  );
  return e;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the pattern editor lays out on a phone, EN + DE, both lenses',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final overflows = <String>[];

    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final size in _sizes.entries) {
        await tester.binding.setSurfaceSize(size.value);
        // Both a pitched target and a percussive one: they build completely
        // different grids (fitted pitch rows vs a lane per kit voice).
        for (final target in ['melody', 'bass', 'drums']) {
          await tester.pumpWidget(
            _wrap(
              LoopPatternEditorScreen(
                engine: _busyEngine(),
                initialTrackId: target,
                labelOf: (id) => id,
                onChanged: () {},
              ),
              locale,
            ),
          );
          for (var frame = 0; frame < 2; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final ex = tester.takeException();
            if (ex != null &&
                ex.toString().toLowerCase().contains('overflow')) {
              overflows.add(
                'editor/$target @ ${size.key} [${locale.languageCode}]: '
                '${ex.toString().split('\n').first}',
              );
            }
          }

          // Precise widens the grid to every semitone and adds a label gutter
          // plus a readout bar — strictly more to fit than Simple, so it is the
          // case that overflows if either does.
          final preciseFinder = find.byType(SegmentedButton<bool>);
          if (preciseFinder.evaluate().isNotEmpty) {
            await tester.tap(
              find.descendant(
                of: preciseFinder,
                matching: find.byIcon(Icons.straighten),
              ),
              warnIfMissed: false,
            );
            for (var frame = 0; frame < 2; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              final ex = tester.takeException();
              if (ex != null &&
                  ex.toString().toLowerCase().contains('overflow')) {
                overflows.add(
                  'editor/$target precise @ ${size.key} '
                  '[${locale.languageCode}]: '
                  '${ex.toString().split('\n').first}',
                );
              }
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        }
      }
    }

    expect(
      overflows,
      isEmpty,
      reason: 'RenderFlex overflows:\n${overflows.join('\n')}',
    );
  });

  testWidgets('the mixer sheet lays out on a phone, EN + DE', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final overflows = <String>[];

    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final size in _sizes.entries) {
        await tester.binding.setSurfaceSize(size.value);
        // The sheet form specifically — the screen form is already covered by
        // mixer_console_test, and it is the sheet that is new.
        await tester.pumpWidget(
          _wrap(
            const Scaffold(body: MixerConsoleScreen(asSheet: true)),
            locale,
          ),
        );
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final ex = tester.takeException();
          if (ex != null && ex.toString().toLowerCase().contains('overflow')) {
            overflows.add(
              'mixer-sheet @ ${size.key} [${locale.languageCode}]: '
              '${ex.toString().split('\n').first}',
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    }

    expect(
      overflows,
      isEmpty,
      reason: 'RenderFlex overflows:\n${overflows.join('\n')}',
    );
  });
}
