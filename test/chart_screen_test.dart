import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

/// The chart surface.
///
/// These drive the widgets directly rather than the whole screen, because the
/// screen needs an `AudioService` from a provider and the parts worth asserting
/// — what is drawn, what a tap reports, what the keypad returns — do not.
Widget host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('grid', () {
    testWidgets('every bar of the chart is drawn', (tester) async {
      final chart = parseChartText('| C | Am | F | G7 |').chart;
      await tester.pumpWidget(host(ChartGridView(chart: chart)));

      for (final symbol in ['C', 'Am', 'F', 'G7']) {
        expect(find.text(symbol), findsOneWidget, reason: 'missing $symbol');
      }
    });

    testWidgets('a held bar shows the repeat sign, not an empty box',
        (tester) async {
      final chart = parseChartText('| C | % |').chart;
      await tester.pumpWidget(host(ChartGridView(chart: chart)));
      expect(find.text('%'), findsOneWidget);
    });

    testWidgets('a split bar shows both chords', (tester) async {
      final chart = parseChartText('| Dm7 G7 |').chart;
      await tester.pumpWidget(host(ChartGridView(chart: chart)));
      expect(find.text('Dm7'), findsOneWidget);
      expect(find.text('G7'), findsOneWidget);
    });

    testWidgets('section labels and repeat counts are shown', (tester) async {
      final chart = parseChartText('[A] x2\n| C |\n[B]\n| G |').chart;
      await tester.pumpWidget(host(ChartGridView(chart: chart)));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
    });

    testWidgets('a tap reports the DOCUMENT bar, not a play-order index',
        (tester) async {
      // With a repeat, play order and document order diverge; an edit must
      // land on the bar the user actually pointed at.
      final chart = parseChartText('[A] x2\n| C | G |').chart;
      ChartBarRef? tapped;
      await tester.pumpWidget(
        host(ChartGridView(chart: chart, onTapBar: (ref) => tapped = ref)),
      );

      await tester.tap(find.text('G'));
      await tester.pump();
      expect(tapped, const ChartBarRef(0, 1));
    });

    testWidgets('an empty chart draws nothing rather than throwing',
        (tester) async {
      await tester.pumpWidget(host(const ChartGridView(chart: Chart())));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a narrow viewport keeps chord type readable by using fewer '
        'bars per row', (tester) async {
      final chart = parseChartText('| C | Am | F | G |').chart;

      // Phone portrait. With a 132px floor, 360px admits two bars, not four.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(ChartGridView(chart: chart)));
      await tester.pumpAndSettle();

      // All four still drawn — the row count changed, nothing was dropped.
      for (final symbol in ['C', 'Am', 'F', 'G']) {
        expect(find.text(symbol), findsOneWidget);
      }
      // Two bars share a row, so C and Am sit at the same height while F is
      // below them.
      final c = tester.getTopLeft(find.text('C'));
      final am = tester.getTopLeft(find.text('Am'));
      final f = tester.getTopLeft(find.text('F'));
      expect(am.dy, c.dy);
      expect(f.dy, greaterThan(c.dy));
    });

    testWidgets('no horizontal overflow at phone, landscape or tablet',
        (tester) async {
      final chart = parseChartText(
        '[A]\n| Cmaj9#11 | F#m7b5 | Bb13sus4 | Ebmaj7/G |',
      ).chart;

      for (final size in const [
        Size(360, 800), // phone portrait
        Size(800, 360), // phone landscape
        Size(1024, 768), // tablet
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(host(ChartGridView(chart: chart)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflow at $size');
      }
      addTearDown(tester.view.reset);
    });
  });

  group('keypad', () {
    testWidgets('opens on the chord it was given', (tester) async {
      await tester.pumpWidget(
        host(
          const ChordKeypad(
            initial: ChordSpec(
              root: Pitch(Step.d),
              triad: ChordTriad.minor,
              seventh: ChordSeventh.minor,
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'Dm7',
      );
    });

    testWidgets('root then quality is two taps', (tester) async {
      await tester.pumpWidget(host(const ChordKeypad()));

      await tester.tap(find.widgetWithText(InkWell, 'G'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '7'));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'G7',
      );
    });

    testWidgets('a root alone is a major chord — the one-tap common case',
        (tester) async {
      await tester.pumpWidget(host(const ChordKeypad()));
      await tester.tap(find.widgetWithText(InkWell, 'F'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'F',
      );
    });

    testWidgets('an accidental sticks to the root', (tester) async {
      await tester.pumpWidget(host(const ChordKeypad()));
      await tester.tap(find.widgetWithText(InkWell, 'B'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '♭'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '7'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'Bb7',
      );
    });

    testWidgets('changing to a quality with no seventh drops the extension',
        (tester) async {
      // Otherwise a 9 quietly survives onto a plain triad and prints a chord
      // the user did not build.
      await tester.pumpWidget(
        host(
          const ChordKeypad(
            initial: ChordSpec(
              root: Pitch(Step.c),
              seventh: ChordSeventh.minor,
              extension: 9,
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'C9',
      );

      await tester.tap(find.widgetWithText(InkWell, 'm'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chordKeypadPreview'))).data,
        'Cm',
      );
    });
  });

  group('bar editing', () {
    test('replacing a chord keeps the rest of the bar', () {
      // A bar is more than its chords; rebuilding it on every edit would drop
      // the barline and the ending number.
      const bar = ChartBar(
        barline: ChartBarline.repeatEnd,
        endingNumber: 2,
      );
      final edited = barWithChord(
        bar,
        const ChordSpec(root: Pitch(Step.a), triad: ChordTriad.minor),
      );
      expect(edited.chordsInOrder.single.chord.text, 'Am');
      expect(edited.barline, ChartBarline.repeatEnd);
      expect(edited.endingNumber, 2);
    });

    test('clearing a bar empties it, which means HOLD not silence', () {
      const bar = ChartBar();
      expect(barWithChord(bar, null).chords, isEmpty);
    });
  });
}
