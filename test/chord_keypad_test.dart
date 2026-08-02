import 'package:comet_beat/core/harmony/chart_level.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

/// The chord keypad.
///
/// Every quality button is a promise: the label the player taps must be the
/// chord they get. That is not automatic — a chord is a triad AND a seventh
/// AND its alterations, and at least one button needs all three.
///
/// The assertions read the live preview (`chordKeypadPreview`), which is the
/// canonical `format()` of what the keypad currently holds. That is exactly
/// what the player sees, so a test that passes here cannot be lying about the
/// experience.
Widget host({ChartLevel level = ChartLevel.expert}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ChordKeypad(level: level)),
    );

String preview(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data!;

Future<void> tapKey(WidgetTester tester, String label) async {
  final button = find.widgetWithText(InkWell, label);
  expect(button, findsWidgets, reason: 'no key labelled "$label"');
  await tester.tap(button.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every quality button produces the chord it is labelled with',
      (tester) async {
    // ⚠️ The regression this file exists for: `m7b5` was built as a DIMINISHED
    // triad with a minor seventh, which the formatter correctly prints as
    // `Cdim7` — a different chord (B♭♭, not B♭). The label promised one chord
    // and the keypad handed back another.
    //
    // `chord_spec.dart` is explicit that the two are NOT merged, so the model
    // was right and the button table was wrong. The whole table is asserted
    // rather than the one row, because the same slip fits any of them.
    const expected = {
      'maj': 'C',
      'm': 'Cm',
      '7': 'C7',
      'm7': 'Cm7',
      'maj7': 'Cmaj7',
      '6': 'C6',
      'm6': 'Cm6',
      'sus4': 'Csus4',
      'sus2': 'Csus2',
      '7sus4': 'C7sus4',
      'dim': 'Cdim',
      'dim7': 'Cdim7',
      'm7b5': 'Cm7b5',
      'aug': 'Caug',
      '5': 'C5',
    };

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final entry in expected.entries) {
      await tapKey(tester, entry.key);
      expect(
        preview(tester),
        entry.value,
        reason: 'tapping "${entry.key}" should give ${entry.value}',
      );
    }
  });

  testWidgets('switching m7b5 → m7 drops the flat five again', (tester) async {
    // The other half of the fix: an alteration a quality IMPLIES must not
    // outlive it, or every chord chosen afterwards silently carries a ♭5.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tapKey(tester, 'm7b5');
    expect(preview(tester), 'Cm7b5');
    await tapKey(tester, 'm7');
    expect(preview(tester), 'Cm7');
  });

  testWidgets('an alteration the player added SURVIVES a quality change',
      (tester) async {
    // …but only the quality's own implied alteration is cleared. A ♭9 the
    // player asked for is theirs, and wiping it would be a different bug from
    // the one being fixed.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tapKey(tester, '7');
    // The alterations live behind the "more" toggle.
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    await tapKey(tester, '♭9');
    expect(preview(tester), 'C7b9');
    await tapKey(tester, 'm7');
    expect(preview(tester), 'Cm7b9');
  });

  group('the beginner↔expert dial (BB-U6)', () {
    testWidgets('a beginner is offered a short vocabulary', (tester) async {
      await tester.pumpWidget(host(level: ChartLevel.beginner));
      await tester.pumpAndSettle();

      // Present: the chords a first song is made of.
      for (final label in ['maj', 'm', '7', 'm7']) {
        expect(
          find.widgetWithText(InkWell, label),
          findsWidgets,
          reason: 'a beginner should still have "$label"',
        );
      }
      // Absent: the vocabulary that arrives with function labels.
      for (final label in ['m7b5', 'dim7', '7sus4', 'm6']) {
        expect(
          find.widgetWithText(InkWell, label),
          findsNothing,
          reason: '"$label" should not be offered to a beginner',
        );
      }
      // …and there is no route to the extensions/alterations at all. Asserted
      // on the KEYS rather than on "no TextButton" — the Clear/Cancel/OK row
      // is made of TextButtons too, so that check passed for the wrong reason.
      for (final label in ['♭9', '♯11', 'alt', '9', '13']) {
        expect(
          find.widgetWithText(InkWell, label),
          findsNothing,
          reason: '"$label" should be unreachable for a beginner',
        );
      }
    });

    testWidgets('an expert is offered the whole table', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      for (final label in ['maj', 'm7b5', 'dim7', '7sus4', 'aug', '5']) {
        expect(find.widgetWithText(InkWell, label), findsWidgets);
      }
    });

    testWidgets('a beginner KEEPS an alteration they cannot see',
        (tester) async {
      // The card's invariant at the widget level: narrowing the surface must
      // not edit the music. Opening an expert's ♭9 chord on a beginner keypad
      // shows it in the preview and hands it back untouched.
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChordKeypad(
              initial: ChordSpec(
                root: Pitch(Step.c),
                seventh: ChordSeventh.minor,
                alterations: {ChordAlteration.flatNine},
              ),
              level: ChartLevel.beginner,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(preview(tester), 'C7b9', reason: 'the chord must still READ true');
      // Changing quality keeps the alteration the player never saw.
      await tapKey(tester, 'm7');
      expect(preview(tester), 'Cm7b9');
    });
  });

  testWidgets('the keypad opens with NO SettingsService above it',
      (tester) async {
    // ⚠️ Regression, caught by CI and not by me. `showChordKeypad` reads the
    // dial from app settings, and reading the provider unguarded threw
    // `ProviderNotFoundException` for any host that has none — a standalone
    // embed, or `chart_screen_no_storage_test`, which pumps the screen with
    // nothing but itself. The fallback is the full keypad, which is exactly
    // what it did before the dial existed.
    ChordKeypadResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showChordKeypad(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // It opened rather than throwing, and it opened UNNARROWED.
    expect(find.byType(ChordKeypad), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'm7b5'), findsWidgets);
    expect(result, isNull, reason: 'nothing chosen yet');
  });
}
