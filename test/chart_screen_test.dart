import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/features/harmony/chart_library_sheet.dart';
import 'package:comet_beat/features/harmony/chart_screen.dart';
import 'package:comet_beat/features/harmony/chord_keypad.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('library', _libraryTests);

  group('screen', _screenTests);

  group('autoscroll', _autoScrollTests);

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

/// The library sheet, driven through its real entry point.
///
/// `showChartLibrary` resolves SharedPreferences itself, so the only honest way
/// to exercise it is to open it from a real widget the way the screen does.
void _libraryTests() {
  testWidgets('saving puts the chart in the list, and opening returns it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final chart = parseChartText('| Dm7 | G7 | Cmaj7 |').chart;
    ChartLibraryResult? result;

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showChartLibrary(context, current: chart);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nothing saved yet.
    expect(find.byKey(const Key('chartRow_Tune')), findsNothing);

    await tester.enterText(find.byKey(const Key('chartSaveName')), 'Tune');
    await tester.tap(find.byKey(const Key('chartSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chartRow_Tune')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chartRow_Tune')));
    await tester.pumpAndSettle();

    expect(result, isA<ChartOpened>());
    final opened = result! as ChartOpened;
    expect(opened.name, 'Tune');
    expect(opened.chart.totalBars, 3);
  });

  testWidgets('an empty chart cannot be saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showChartLibrary(context, current: const Chart()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('chartSaveButton')),
    );
    expect(button.onPressed, isNull, reason: 'saving a blank grid is refused');
  });
}

/// The screen itself, which needs an AudioService from a provider.
void _screenTests() {
  Widget screen() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<AudioService>(
          create: (_) => AudioService(),
          child: const ChartScreen(),
        ),
      );

  testWidgets('opens on the starter chart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('C7'), findsWidgets);
    expect(find.byKey(const Key('chartPlayButton')), findsOneWidget);
  });

  testWidgets('restores the working chart from a previous visit',
      (tester) async {
    // What makes leaving the screen non-destructive.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await ChartStore(prefs).saveWorking(parseChartText('| Ebmaj7 |').chart);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Ebmaj7'), findsOneWidget);
  });

  testWidgets('an explicit initialChart wins over the working slot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await ChartStore(prefs).saveWorking(parseChartText('| Ebmaj7 |').chart);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Provider<AudioService>(
          create: (_) => AudioService(),
          child: ChartScreen(initialChart: parseChartText('| Abm7 |').chart),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abm7'), findsOneWidget);
    expect(find.text('Ebmaj7'), findsNothing);
  });
}

/// Autoscroll: the playing bar stays on screen.
void _autoScrollTests() {
  /// A chart long enough that later bars start off screen.
  Chart longChart() => parseChartText(
        '[A]\n${List.filled(8, '| C | Am | F | G |').join('\n')}',
      ).chart;

  Widget scrollHost(Chart chart, ChartBarRef? playing) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChartGridView(chart: chart, playingBar: playing),
          ),
        ),
      );

  testWidgets('a bar below the fold is scrolled into view', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chart = longChart();
    await tester.pumpWidget(scrollHost(chart, null));
    await tester.pumpAndSettle();

    final scroll = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scroll.controller?.offset ?? 0, 0, reason: 'starts at the top');

    // Jump the playhead to a late bar.
    await tester.pumpWidget(scrollHost(chart, const ChartBarRef(0, 30)));
    await tester.pumpAndSettle();

    final after = tester
        .widget<Scrollable>(find.byType(Scrollable).first)
        .controller
        ?.offset;
    expect(after, isNotNull);
    expect(after, greaterThan(0), reason: 'the view followed the playhead');
  });

  testWidgets('autoScroll:false leaves the view alone', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chart = longChart();
    Widget host(ChartBarRef? playing) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartGridView(
                chart: chart,
                playingBar: playing,
                autoScroll: false,
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(null));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const ChartBarRef(0, 30)));
    await tester.pumpAndSettle();

    final offset = tester
        .widget<Scrollable>(find.byType(Scrollable).first)
        .controller
        ?.offset;
    expect(offset ?? 0, 0);
  });

  testWidgets('no enclosing scrollable is not a crash', (tester) async {
    // The grid is also used inside fixed-height hosts and in tests.
    await tester.pumpWidget(
      host(
        ChartGridView(
          chart: parseChartText('| C | G |').chart,
          playingBar: const ChartBarRef(0, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
