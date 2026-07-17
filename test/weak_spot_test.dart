// The weak-spot engine: SriService.weakestItems ranks the learner's most-missed
// items, describeSriItem labels them readably, and the Progress screen surfaces
// them as "your tricky notes".

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/progress/screens/progress_screen.dart';
import 'package:comet_beat/features/progress/sri_item_label.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('weakestItems ranks by misses, excludes never-missed items', () {
    final sri = SriService(getNow: () => DateTime(2026, 1, 10));
    // g4: missed twice; a_major: missed once; e4: always correct.
    sri.recordResponse('note_reading.treble.g4', false);
    sri.recordResponse('note_reading.treble.g4', false);
    sri.recordResponse('chords.triad.a_major', false);
    sri.recordResponse('note_reading.treble.e4', true);

    final weak = sri.weakestItems();
    expect(weak.map((d) => d.itemId), [
      'note_reading.treble.g4', // most misses first
      'chords.triad.a_major',
    ]);
  });

  test('describeSriItem produces readable labels', () {
    final en = AppLocalizationsEn();
    expect(describeSriItem(en, 'note_reading.treble.g4'), 'G4 · Treble');
    expect(describeSriItem(en, 'chords.triad.a_major'), 'A major');
    expect(describeSriItem(en, 'note_values.symbol.half_rest'), isNotEmpty);
    // Non-note skills read as skills, not bare pitches.
    expect(describeSriItem(en, 'note_values.rhythm.p2'), 'Rhythm Echo');
    expect(describeSriItem(en, 'key_sig.g'), 'G major');
    expect(
      describeSriItem(en, 'note_reading.ledger.treble.below2'),
      'Ledger Leap',
    );
  });

  testWidgets('progress screen surfaces the tricky-notes card', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 1, 10))
      ..recordResponse('note_reading.treble.g4', false);

    await tester.pumpWidget(
      ChangeNotifierProvider<SriService>.value(
        value: sri,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('de')],
          home: ProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your tricky spots'), findsOneWidget);
    expect(find.text('G4 · Treble'), findsOneWidget);
    expect(find.text('missed 1×'), findsOneWidget);
  });
}
