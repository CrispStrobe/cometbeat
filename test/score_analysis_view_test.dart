// The computed AnaVis: ScoreAnalysisView runs the crisp_notation analysis
// engine on a real Score and shows key + roman numerals + function colours +
// cadences, at an adaptive depth (kids / learner / expert).
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/score_analysis_view.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show analyze;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget home) => MultiProvider(
      providers: [Provider<AudioService>(create: (_) => AudioService())],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    );

void main() {
  final iToneIV = blockChordScore([
    [60, 64, 67], // C  = I
    [65, 69, 72], // F  = IV
    [67, 71, 74], // G  = V
    [60, 64, 67], // C  = I
  ]);

  testWidgets('computes key, roman numerals and a cadence from the notes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(ScoreAnalysisView(score: iToneIV)));
    await tester.pumpAndSettle();

    // Detected key (C major) in the chip.
    expect(find.text('C Major'), findsOneWidget);
    // Roman numerals on the function blocks (learner depth is the default).
    expect(find.text('IV'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(find.text('I'), findsNWidgets(2));
    // The V→I close is a perfect (authentic) cadence.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.cadenceAuthentic), findsOneWidget);
  });

  testWidgets(
      'the depth dial hides labels for kids and adds chord symbols '
      'for experts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(_app(ScoreAnalysisView(score: iToneIV)));
    await tester.pumpAndSettle();

    // Kids: colours only — the roman numerals disappear.
    await tester.tap(find.text(l10n.analysisDepthKids));
    await tester.pumpAndSettle();
    expect(find.text('IV'), findsNothing);

    // Expert: chord symbols appear (IV is the F chord → "F").
    await tester.tap(find.text(l10n.analysisDepthExpert));
    await tester.pumpAndSettle();
    expect(find.text('IV'), findsOneWidget); // roman back
    expect(find.text('F'), findsWidgets); // chord symbol
  });

  testWidgets('playing a chord and the whole progression does not throw',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(_app(ScoreAnalysisView(score: iToneIV)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('V')); // a function block
    await tester.pump();
    await tester.tap(find.text(l10n.formAnalysisPlayWhole));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('the built-in examples all analyse to at least one chord', () {
    for (final (_, score) in kAnalysisExamples) {
      final a = analyze(score);
      expect(a.segments.where((s) => s.hasChord), isNotEmpty);
    }
  });
}
