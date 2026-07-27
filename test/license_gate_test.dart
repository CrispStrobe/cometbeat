// confirmLicenseObligations — the shared export-time licence gate (dialog).
// The pure decision logic lives in license_obligations.dart (tested
// separately); this covers the three UI branches the gate turns those
// obligations into:
//   * nothing owed  → returns true with NO dialog (the common case stays
//     click-free);
//   * blocking      → shows the reason, offers only "Close", returns false
//     (there is deliberately no "export anyway");
//   * share-alike   → offers "Agree and export" / "Cancel" and returns the
//     user's choice.
import 'package:comet_beat/core/licensing/license_obligations.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/license_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pumps a button that runs the gate for [works] and records the result.
  Future<void> pumpGate(
    WidgetTester tester,
    List<LicensedWork> works,
    List<bool?> sink,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('trigger'),
              onPressed: () async {
                sink.add(
                  await confirmLicenseObligations(
                    context,
                    obligationsFor(works),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('clear obligations return true with no dialog', (tester) async {
    final results = <bool?>[];
    await pumpGate(
      tester,
      const [LicensedWork(title: 'Freebie', license: 'CC0-1.0')],
      results,
    );
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(results, [true]);
  });

  testWidgets('blocking material shows a reason and only Close → false',
      (tester) async {
    final results = <bool?>[];
    await pumpGate(
      tester,
      const [LicensedWork(title: 'NC track', license: 'CC BY-NC 4.0')],
      results,
    );
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Cannot export'), findsOneWidget);
    // No "export anyway": the agree button must be absent when blocked.
    expect(find.text('Agree and export'), findsNothing);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('share-alike: Agree returns true', (tester) async {
    final results = <bool?>[];
    await pumpGate(
      tester,
      const [LicensedWork(title: 'SA loop', license: 'CC BY-SA 4.0')],
      results,
    );
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Licence terms'), findsOneWidget);
    expect(find.text('Agree and export'), findsOneWidget);

    await tester.tap(find.text('Agree and export'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('share-alike: Cancel returns false', (tester) async {
    final results = <bool?>[];
    await pumpGate(
      tester,
      const [LicensedWork(title: 'SA loop', license: 'CC BY-SA 4.0')],
      results,
    );
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });
}
