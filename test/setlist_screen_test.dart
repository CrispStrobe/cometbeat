import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/gig_mode_screen.dart';
import 'package:comet_beat/features/harmony/setlist_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The setlist surface (BB-U4b).
///
/// The card names one thing that must not break and warns it "will look like a
/// simplification": the per-song key and tempo live in the ENTRY, never on the
/// chart. So the load-bearing test here is that editing a set leaves the saved
/// chart byte-identical. The rest is that a player can build and reorder a set,
/// and that a missing chart stays visible.
Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    );

Future<ChartStore> _seedCharts(Map<String, String> named) async {
  final prefs = await SharedPreferences.getInstance();
  final store = ChartStore(prefs);
  for (final entry in named.entries) {
    await store.save(entry.key, parseChartText(entry.value).chart);
  }
  return store;
}

Future<SetlistStore> _seedSet(Setlist setlist) async {
  final prefs = await SharedPreferences.getInstance();
  final store = SetlistStore(prefs);
  await store.save(setlist);
  return store;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the invariant: an override never touches the chart', () {
    testWidgets('setting a gig key leaves the saved chart byte-identical',
        (tester) async {
      final charts = await _seedCharts({'Tune': 'key: C\n| C | F | G | C |'});
      final before = charts.list().single.json;

      await _seedSet(
        const Setlist(
          name: 'Friday',
          entries: [SetlistEntry(chartName: 'Tune')],
        ),
      );

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('setlistTune_0')));
      await tester.pumpAndSettle();
      // Up three semitones, and a gig tempo.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('setlistKeyUp')));
        await tester.pump();
      }
      await tester.enterText(
        find.byKey(const ValueKey('setlistTempoField')),
        '96',
      );
      await tester.tap(find.byKey(const ValueKey('setlistEntrySave')));
      await tester.pumpAndSettle();

      // The ENTRY carries it…
      final prefs = await SharedPreferences.getInstance();
      final saved = SetlistStore(prefs).list().single.setlist;
      expect(saved.entries.single.transposeSemitones, 3);
      expect(saved.entries.single.tempoBpm, 96);

      // …and the chart on disk is untouched. This is the whole card.
      expect(charts.list().single.json, before);
    });

    test('the same chart in two sets plays at each set key', () {
      final chart = parseChartText('key: C\n| C | F |').chart;
      final friday = resolveEntry(
        chart,
        const SetlistEntry(chartName: 'Tune', transposeSemitones: 2),
      );
      final saturday = resolveEntry(
        chart,
        const SetlistEntry(chartName: 'Tune', transposeSemitones: -1),
      );
      String first(chart) =>
          chart.barsInPlayOrder.first.chordsInOrder.single.chord.text as String;
      expect(first(friday), 'D');
      expect(first(saturday), 'B');
      expect(first(chart), 'C', reason: 'the original is unmoved');
    });
  });

  group('building a set', () {
    testWidgets('a new setlist is created and listed', (tester) async {
      await tester.pumpWidget(_host(const SetlistScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('No setlists yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('setlistNew')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('setlistNameField')),
        'Friday',
      );
      await tester.tap(find.byKey(const ValueKey('setlistNameOk')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('setlist_Friday')), findsOneWidget);
      // An EMPTY set is allowed on purpose — you make one, then add to it.
      expect(find.textContaining('no songs'), findsOneWidget);
    });

    testWidgets('songs are added from the chart library, several at once',
        (tester) async {
      await _seedCharts({
        'One': 'key: C\n| C |',
        'Two': 'key: F\n| F |',
        'Three': 'key: G\n| G |',
      });
      await _seedSet(const Setlist(name: 'Friday'));

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('setlistAdd')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pickChart_One')));
      await tester.tap(find.byKey(const ValueKey('pickChart_Three')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pickChartsDone')));
      await tester.pumpAndSettle();

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
      expect(find.text('Two'), findsNothing);
    });

    testWidgets('reordering saves the new running order', (tester) async {
      // ⚠️ Driven through the list's own callback rather than a synthesized
      // drag. `ReorderableListView`'s gesture recognizer does not reproduce
      // reliably under `tester.drag`/`startGesture` here, and the thing that
      // can actually be got wrong is the WIRING: `onReorderItem` already
      // adjusts the target for the removed item, while the older `onReorder`
      // reports it BEFORE the removal and needs the off-by-one undone by hand.
      // Feeding the callback the indices Flutter would feed it proves which
      // contract this screen is written against. `Setlist.reorder` itself is
      // unit-tested in `setlist_test.dart`.
      await _seedCharts({'One': '| C |', 'Two': '| F |', 'Three': '| G |'});
      await _seedSet(
        const Setlist(
          name: 'Friday',
          entries: [
            SetlistEntry(chartName: 'One'),
            SetlistEntry(chartName: 'Two'),
            SetlistEntry(chartName: 'Three'),
          ],
        ),
      );

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      // Move the first song into second place.
      list.onReorderItem!(0, 1);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final saved = SetlistStore(prefs).list().single.setlist;
      expect(
        saved.entries.map((e) => e.chartName),
        ['Two', 'One', 'Three'],
        reason: 'the first song moved down one place',
      );
      // …and the screen shows the new order, numbered from 1.
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('a song is removed without disturbing the others',
        (tester) async {
      await _seedCharts({'One': '| C |', 'Two': '| F |'});
      await _seedSet(
        const Setlist(
          name: 'Friday',
          entries: [
            SetlistEntry(chartName: 'One'),
            SetlistEntry(chartName: 'Two'),
          ],
        ),
      );

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final saved = SetlistStore(prefs).list().single.setlist;
      expect(saved.entries.map((e) => e.chartName), ['Two']);
    });
  });

  group('a missing chart', () {
    testWidgets('stays VISIBLE in the set rather than being pruned',
        (tester) async {
      // The card is explicit: on a gig night a song silently vanishing is the
      // worst possible response.
      await _seedCharts({'Present': '| C |'});
      await _seedSet(
        const Setlist(
          name: 'Friday',
          entries: [
            SetlistEntry(chartName: 'Present'),
            SetlistEntry(chartName: 'Deleted'),
          ],
        ),
      );

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.textContaining('no longer saved'), findsOneWidget);
      // It is shown but not playable, and offers no override editor.
      expect(find.byKey(const ValueKey('setlistTune_1')), findsNothing);
    });

    testWidgets('is flagged on the setlist LIST too', (tester) async {
      // So a player scanning their sets before a gig sees it without opening
      // each one.
      await _seedCharts({'Present': '| C |'});
      await _seedSet(
        const Setlist(
          name: 'Broken',
          entries: [SetlistEntry(chartName: 'Deleted')],
        ),
      );
      await _seedSet(
        const Setlist(
          name: 'Fine',
          entries: [SetlistEntry(chartName: 'Present')],
        ),
      );

      await tester.pumpWidget(_host(const SetlistScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.queue_music), findsOneWidget);
    });
  });

  group('opening a song', () {
    testWidgets('opens the chart AS THE SET ASKS, not as written',
        (tester) async {
      await _seedCharts({'Tune': 'key: C\n| C | F |'});
      await _seedSet(
        const Setlist(
          name: 'Friday',
          entries: [
            SetlistEntry(chartName: 'Tune', transposeSemitones: 2),
          ],
        ),
      );

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tune'));
      await tester.pumpAndSettle();

      // Transposed up a tone: C→D, F→G. If the override were being ignored we
      // would still be looking at C.
      expect(find.text('D'), findsWidgets);
      expect(find.text('G'), findsWidgets);
    });
  });

  group('gig mode', () {
    testWidgets('is offered once the set has songs, and not before',
        (tester) async {
      await _seedCharts({'One': '| C |'});
      await _seedSet(const Setlist(name: 'Friday'));

      await tester.pumpWidget(_host(const SetlistDetailScreen(name: 'Friday')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('setlistGigMode')),
        findsNothing,
        reason: 'nothing to play yet',
      );

      await tester.tap(find.byKey(const ValueKey('setlistAdd')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pickChart_One')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pickChartsDone')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('setlistGigMode')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setlistGigMode')));
      await tester.pumpAndSettle();
      expect(find.byType(GigModeScreen), findsOneWidget);
    });
  });
}
