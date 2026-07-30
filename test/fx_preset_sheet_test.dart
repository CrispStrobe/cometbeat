// WS-W6 — the saved-chain sheet, as a widget.
//
// The store has its own suite; what is left is the join, and one thing that is
// specifically a WIDGET risk. Slice 1 of this card was bitten by a
// `TextEditingController` created per dialog and disposed when it returned: the
// dialog is still animating out when the await resumes, and that exit frame
// rebuilds the `TextField` against a disposed controller. It throws on exactly
// one frame, which is why the pattern survives casual use — so the save flow is
// pumped all the way through its exit animation here, deliberately.

import 'dart:async';
import 'dart:io';

import 'package:comet_beat/core/audio/fx/fx_chain_codec.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/fx_preset_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mounts a host and hands back a function that opens the sheet from it.
Future<Future<List<FxSpec>?> Function()> _host(
  WidgetTester tester, {
  List<FxSpec> current = const [],
}) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      // ⚠️ Pinned: without it the sheet came up in GERMAN here, and every
      // text-based finder failed for a reason that had nothing to do with the
      // widget under test.
      locale: const Locale('en'),
      home: Builder(
        builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );
  return () => showFxPresetSheet(hostContext, current: current);
}

List<FxSpec> _chain(String source) => parseFxChain(source).chain;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an empty store says so, and offers nothing to apply', (
    tester,
  ) async {
    final open = await _host(tester);
    final result = open();
    await tester.pumpAndSettle();

    // Text via the delegate, not a literal: the copy is localised and a test
    // that hard-codes English breaks the day someone edits the ARB.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.fxPresetsEmpty), findsOneWidget);
    // No chain in hand, so no save control: offering to save nothing is worse
    // than not offering.
    expect(find.byKey(const ValueKey('fx-preset-save')), findsNothing);

    // Dismiss: nothing was applied.
    Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('saving a chain keeps it, THROUGH the dialog exit frame', (
    tester,
  ) async {
    // The controller-lifetime trap: this passes only if the controller outlives
    // the dialog.
    final open = await _host(tester, current: _chain('lowpass freq=400'));
    unawaited(open());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fx-preset-save')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Warm');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.fxPresetSave));
    // Pump generously: the throw happens on the dialog's exit frame.
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fx-preset-Warm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a preset returns its chain to the host', (tester) async {
    SharedPreferences.setMockInitialValues({
      'fx_presets_v1':
          '[{"name":"Warm","chain":"lowpass freq=400","savedAtMs":1}]',
    });
    final open = await _host(tester);
    final result = open();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('fx-preset-Warm')));
    await tester.pumpAndSettle();

    final picked = await result;
    expect(picked, isNotNull);
    expect(picked!.single.type, FxType.lowpass);
  });

  testWidgets('⚠️ an automated chain warns that automation will not travel', (
    tester,
  ) async {
    final open = await _host(
      tester,
      current: [
        const FxSpec(
          type: FxType.gain,
          params: {'gainDb': -6},
          automation: {
            'gainDb': [FxAutomationPoint(ms: 0, value: -12)],
          },
        ),
      ],
    );
    unawaited(open());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fx-preset-lossy')), findsOneWidget);
  });

  testWidgets('a plain chain does NOT warn', (tester) async {
    // A warning on every save is a warning nobody reads.
    final open = await _host(tester, current: _chain('lowpass freq=400'));
    unawaited(open());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fx-preset-lossy')), findsNothing);
  });

  group('every host that claims the sheet actually reaches it', () {
    // ⚠️ This ladder keeps finding shipped-but-never-called code — a field that
    // exists, a widget with no host, an output nothing renders. A shared sheet
    // is the easiest possible instance of that shape: it is "hosted" by whoever
    // remembers to add a button, and nothing fails when they do not. So the
    // hosts are asserted by their KEYS, in the same file as the sheet.
    //
    // Widget keys rather than pumping four screens: three of them run continuous
    // tickers, which makes them slow and awkward to pump, and what is being
    // checked here is that the wiring exists at all.
    const hosts = {
      'lib/features/workshop/screens/composition_workshop_screen.dart':
          'workshop-fx-presets',
      'lib/features/games/composition/tab_workshop_screen.dart':
          'tab-fx-presets',
      'lib/features/games/composition/tracker_screen.dart':
          'tracker-fx-presets',
      'lib/features/games/composition/daw_screen.dart': 'daw-fx-presets',
    };

    for (final entry in hosts.entries) {
      test(entry.key.split('/').last, () {
        final source = File(entry.key).readAsStringSync();
        expect(
          source,
          contains('showFxPresetSheet'),
          reason:
              'this host is claimed on the card but does not open the sheet',
        );
        expect(source, contains(entry.value), reason: 'and it is keyed');
      });
    }

    test('Loop Studio is deliberately NOT a host yet', () {
      // Its file belongs to another lane and was not mine to edit. Recorded as a
      // test so the omission is a decision rather than something forgotten.
      final source = File(
        'lib/features/games/composition/loop_mixer_screen.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('showFxPresetSheet')));
    });
  });
}
