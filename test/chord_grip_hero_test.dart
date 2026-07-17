// Chord Grip Hero — Falling Keys for chords. Verifies: pressing all the chord's
// keys catches it (score + SRI), letting one land ungripped costs a life, and
// clearing the run finishes with a result screen.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/keyboard/chord_grip_hero_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 11)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: ChordGripHeroScreen(),
      ),
    );

ChordGripHeroTester _game(WidgetTester tester) =>
    tester.state<State<ChordGripHeroScreen>>(find.byType(ChordGripHeroScreen))
        as ChordGripHeroTester;

// Tap every white key whose MIDI is in [midis].
Future<void> _pressChord(WidgetTester tester, List<int> midis) async {
  const kb = PianoKeyboard();
  final box = tester.getRect(find.byType(PianoKeyboard));
  final keyW = box.width / kb.whiteKeyCount;
  for (final midi in midis) {
    for (var i = 0; i < kb.whiteKeyCount; i++) {
      if (kb.whiteMidi(i) == midi) {
        await tester.tapAt(Offset(box.left + (i + 0.5) * keyW, box.bottom - 8));
        await tester.pump();
        break;
      }
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('gripping all chord keys catches it and scores', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    final sri =
        tester.element(find.byType(ChordGripHeroScreen)).read<SriService>();
    await _pressChord(tester, List.of(_game(tester).requiredMidis));

    expect(_game(tester).score, 1);
    expect(_game(tester).lives, ChordGripHeroScreen.maxLives);
    expect(sri.getDetailedBreakdown()['keyboard'], isNotNull);
  });

  testWidgets('a chord that lands ungripped costs a life', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(_game(tester).lives, ChordGripHeroScreen.maxLives);

    // Level-1 fall time is 6s; pump past it without pressing anything.
    await tester.pump(const Duration(milliseconds: 6200));
    expect(_game(tester).lives, lessThan(ChordGripHeroScreen.maxLives));
    expect(_game(tester).score, 0);
  });

  testWidgets('gripping every chord finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0;
        i < ChordGripHeroScreen.totalChords && !_game(tester).finished;
        i++) {
      await _pressChord(tester, List.of(_game(tester).requiredMidis));
    }

    expect(_game(tester).finished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
