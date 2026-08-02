import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/setlist.dart';
import 'package:comet_beat/core/services/chart_store.dart';
import 'package:comet_beat/features/harmony/chart_grid_view.dart';
import 'package:comet_beat/features/harmony/gig_mode_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gig mode (BB-U4b).
///
/// A READING surface. The things that matter on a stand are that the chart is
/// the one the SET asks for, that you can move through the set without
/// looking, and that you cannot change anything by brushing the screen.

/// Records what gig mode asked of the platform, so the wake-lock seam can be
/// proven without a plugin.
class _RecordingKeepAwake extends KeepAwake {
  final calls = <String>[];
  @override
  Future<void> enable() async => calls.add('enable');
  @override
  Future<void> disable() async => calls.add('disable');
}

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

Future<ChartStore> _seed(Map<String, String> named) async {
  final prefs = await SharedPreferences.getInstance();
  final store = ChartStore(prefs);
  for (final e in named.entries) {
    await store.save(e.key, parseChartText(e.value).chart);
  }
  return store;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the chart shown is the one the SET asks for', () {
    testWidgets('a re-keyed song reads in its gig key', (tester) async {
      final charts = await _seed({'Tune': 'key: C\n| C | F | G | C |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [
                SetlistEntry(chartName: 'Tune', transposeSemitones: 2),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // C F G C up a tone is D G A D. Seeing C would mean the override was
      // dropped somewhere between the set and the stand.
      expect(find.text('D'), findsWidgets);
      expect(find.text('G'), findsWidgets);
      expect(find.text('A'), findsWidgets);
      expect(find.text('C'), findsNothing);
    });

    testWidgets('a missing chart says so instead of showing an empty page',
        (tester) async {
      final charts = await _seed({'Present': '| C |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Deleted')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gigMissing')), findsOneWidget);
    });
  });

  group('moving through the set', () {
    Future<void> pumpThree(WidgetTester tester) async {
      final charts = await _seed({
        'One': '| C |',
        'Two': '| F |',
        'Three': '| G |',
      });
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [
                SetlistEntry(chartName: 'One'),
                SetlistEntry(chartName: 'Two'),
                SetlistEntry(chartName: 'Three'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('next and previous walk the set, and say where you are',
        (tester) async {
      await pumpThree(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gigNext')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gigPrev')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('the ends of the set are dead ends, not wraps', (tester) async {
      // Wrapping round to the first tune after the last one is the wrong
      // behaviour on a stand: the set ENDED.
      await pumpThree(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('gigPrev')))
            .onPressed,
        isNull,
        reason: 'no previous song at the start',
      );

      await tester.tap(find.byKey(const ValueKey('gigNext')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gigNext')));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('gigNext')))
            .onPressed,
        isNull,
        reason: 'no next song at the end',
      );
      expect(find.textContaining('End of the set'), findsOneWidget);
    });
  });

  group('editing is off', () {
    testWidgets('the grid is given no tap handler at all', (tester) async {
      // Asserted on the WIDGET rather than by trying to tap: "edits are off"
      // must be structural. A missing callback cannot be forgotten the way a
      // `readOnly: true` flag can.
      final charts = await _seed({'Tune': '| C | F |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Tune')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.widget<ChartGridView>(find.byType(ChartGridView));
      expect(grid.onTapBar, isNull);
      expect(grid.selected, isNull);
    });
  });

  group('the cue', () {
    testWidgets("the player's own note is the first thing on the page",
        (tester) async {
      // "capo 3" is no use after the count-in.
      final charts = await _seed({'Tune': '| C |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Tune', note: 'capo 3')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gigCue')), findsOneWidget);
      expect(find.text('capo 3'), findsOneWidget);
    });

    testWidgets('no cue means no empty banner', (tester) async {
      final charts = await _seed({'Tune': '| C |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Tune')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gigCue')), findsNothing);
    });
  });

  group('the wake-lock seam', () {
    testWidgets('is asked to hold on entry and RELEASE on the way out',
        (tester) async {
      // The release is the half that matters: a phone that never sleeps again
      // after one gig is a bug the user blames on the app, correctly.
      final charts = await _seed({'Tune': '| C |'});
      final awake = _RecordingKeepAwake();

      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            keepAwake: awake,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Tune')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(awake.calls, ['enable']);

      // Leave the screen.
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpAndSettle();
      expect(awake.calls, ['enable', 'disable']);
    });
  });

  group('degenerate input', () {
    testWidgets('an empty set does not crash', (tester) async {
      final charts = await _seed({});
      await tester.pumpWidget(
        _host(
          GigModeScreen(charts: charts, setlist: const Setlist(name: 'Empty')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No songs yet'), findsOneWidget);
    });

    testWidgets('a start index past the end is clamped, not thrown',
        (tester) async {
      final charts = await _seed({'Tune': '| C |'});
      await tester.pumpWidget(
        _host(
          GigModeScreen(
            charts: charts,
            startIndex: 99,
            setlist: const Setlist(
              name: 'Friday',
              entries: [SetlistEntry(chartName: 'Tune')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 1'), findsOneWidget);
    });
  });
}
