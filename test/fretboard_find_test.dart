// Find the Note (fretboard_find) — tap where a note lives on the fretboard.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/fretboard_find_screen.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget home, SriService sri) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
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
    );

/// Flat index of the first fret cell (row-major over strings × frets 0..4) that
/// spells [target] — mirrors the screen's own placement so the test is robust
/// to tuning order.
int _firstCellFor(Step target) {
  final strings = kGuitarTuning.strings;
  for (var s = 0; s < strings.length; s++) {
    for (var f = 0; f <= 4; f++) {
      final p = Pitch.fromMidi(strings[s].midiNumber + f);
      if (p.alter == 0 && p.step == target) return s * 5 + f;
    }
  }
  throw StateError('no $target in the 0..4 window');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the full 6×5 fret grid', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FretboardFindScreen(),
        SriService(getNow: () => DateTime(2026, 7, 19)),
      ),
    );
    await tester.pump();
    // 6 strings × frets 0..4 = 30 tappable cells.
    expect(find.byType(OutlinedButton), findsNWidgets(30));
  });

  testWidgets('tapping a correct fret records under guitar.fret and advances',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 19));
    await tester.pumpWidget(_wrap(const FretboardFindScreen(), sri));
    await tester.pump();

    // Round 0's target is the first natural (C); tap a fret that plays a C.
    await tester.tap(find.byType(OutlinedButton).at(_firstCellFor(Step.c)));
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['guitar']!.keys, contains('fret'));
    await tester.pumpAndSettle();
  });
}
