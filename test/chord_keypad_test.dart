import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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
Widget host() => const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ChordKeypad()),
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
}
