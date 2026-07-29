// test/note_highway_screen_test.dart
//
// The screen and the painter, end to end: every instrument, every skin and
// both projections must build, run a few frames and take a tap without
// throwing — the painter does a lot of geometry, and a divide-by-zero in one
// skin/instrument combination would only ever show up here.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_instrument.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/highway/highway_strip.dart';
import 'package:comet_beat/features/games/highway/highway_theme.dart';
import 'package:comet_beat/features/games/highway/highway_view.dart';
import 'package:comet_beat/features/games/highway/note_highway_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chart = HighwayChart(
  name: 'test',
  bpm: 100,
  events: [
    HighwayEvent(startBeat: 0, beats: 1, midi: 60),
    HighwayEvent(startBeat: 0, beats: 1, midi: 64, voice: 1),
    HighwayEvent(startBeat: 1, beats: 0.5, midi: 61), // a black key
    HighwayEvent(startBeat: 2, beats: 2, midi: 67),
  ],
);

Widget _app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
      ),
    );

/// The setup list is long and lazily built, so the Start button has to be
/// scrolled into existence before it can be tapped.
Future<void> _tapStart(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Start'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the setup screen offers every instrument and starts a run',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const NoteHighwayScreen(
          gameId: 'note_highway_piano',
          title: 'Note Highway',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Piano'), findsOneWidget);
    expect(find.text('Guitar'), findsOneWidget);
    expect(find.text('Cello'), findsOneWidget);

    await _tapStart(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HighwayView), findsOneWidget);
    expect(find.byType(HighwayReadingStrip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching instrument swaps in that instrument’s pieces',
      (tester) async {
    await tester.pumpWidget(
      _app(const NoteHighwayScreen(gameId: 'note_highway_piano')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Two hands: C major'), findsOneWidget);

    await tester.tap(find.text('Guitar'));
    await tester.pumpAndSettle();
    expect(find.text('Two hands: C major'), findsNothing);
    expect(find.text('Four chords: Em G D C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a run survives frames and a tap on the rail', (tester) async {
    await tester.pumpWidget(
      _app(const NoteHighwayScreen(gameId: 'note_highway_piano')),
    );
    await tester.pumpAndSettle();
    await _tapStart(tester);
    await tester.pump();

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    // Tap the middle of the highway — whatever lane that is, it must not throw.
    await tester.tap(find.byType(HighwayView));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a looped section repeats instead of finishing, and is not scored',
      (tester) async {
    // Eight bars so the section picker appears, with the run set to bars 1–2.
    final piece = HighwayChart(
      name: 'eight bars',
      bpm: 240, // fast, so a pass is short in wall-clock terms
      events: [
        for (var b = 0; b < 8; b++)
          HighwayEvent(startBeat: b * 4.0, beats: 1, midi: 60 + b),
      ],
    );
    final progress = ProgressService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()),
          Provider<AudioService>(create: (_) => AudioService()),
          ChangeNotifierProvider<ProgressService>.value(value: progress),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: NoteHighwayScreen(gameId: 'note_highway_piano', chart: piece),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag the range slider's right thumb down to make a short section.
    // The setup list is lazy, so the control has to be scrolled into existence
    // before it can be found at all — adding one more instrument chip was
    // enough to push it out of the built window.
    await tester.scrollUntilVisible(
      find.byType(RangeSlider),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Practise a section'), findsOneWidget);
    final slider = tester.getRect(find.byType(RangeSlider));
    await tester.dragFrom(
      Offset(slider.right - 8, slider.center.dy),
      Offset(-slider.width * 0.7, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Bars 1'), findsOneWidget);

    await _tapStart(tester);
    await tester.pump();
    // Run well past the end of a two-bar section: it must still be playing.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(HighwayView),
      findsOneWidget,
      reason: 'a loop comes round again; it never reaches the result screen',
    );
    // …and drilling is practice, so nothing is recorded.
    expect(progress.starsFor('note_highway_piano'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drum highway opens on its own grooves and pads',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const NoteHighwayScreen(
          instrument: HighwayInstrument.drums,
          gameId: 'beat_highway',
          title: 'Beat Highway',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The kit's own starter grooves, not a piano piece.
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Ode to Joy'), findsNothing);

    await _tapStart(tester);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final view = tester.widget<HighwayView>(find.byType(HighwayView));
    expect(view.laneMap, isA<PadLaneMap>());
    expect(view.laneMap.laneCount, kHighwayDrumLanes.length);
    // Every block is a lane, not a pitch.
    expect(
      view.chart.events.every((e) => e.midi == null && e.lane != null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every instrument × skin × projection paints', (tester) async {
    for (final instrument in HighwayInstrument.values) {
      final profile = HighwayInstrumentProfile.of(instrument);
      final prepared = profile.prepare(_chart);
      final laneMap = profile.laneMapFor(prepared);
      final rules = HighwayRules.of(HighwayDifficulty.easy);
      final grader = HighwayGrader(
        chart: prepared,
        rules: rules,
        laneMap: laneMap,
      );
      for (final skin in HighwaySkin.values) {
        for (final projection in HighwayProjection.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: HighwayView(
                  chart: prepared,
                  laneMap: laneMap,
                  notes: grader.notes,
                  beat: 0.7,
                  rules: rules,
                  palette: HighwayPalette.of(skin),
                  projection: projection,
                  litMidi: const {60},
                  litLanes: const {0},
                  noteNameOf: (m) => 'C',
                  flashes: const [
                    HighwayFlash(unitX: 0.5, beat: 0.5, perfect: true),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '$instrument / $skin / $projection',
          );
        }
      }
    }
  });

  testWidgets('an empty chart draws nothing rather than dividing by zero',
      (tester) async {
    const empty = HighwayChart(name: 'empty', bpm: 100, events: []);
    final laneMap = KeyboardLaneMap.forRange(60, 72);
    final rules = HighwayRules.of(HighwayDifficulty.medium);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighwayView(
            chart: empty,
            laneMap: laneMap,
            notes: const [],
            beat: 0,
            rules: rules,
            palette: HighwayPalette.of(HighwaySkin.midnight),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reading strip renders both of its modes', (tester) async {
    final profile = HighwayInstrumentProfile.of(HighwayInstrument.guitar);
    final prepared = profile.prepare(_chart);
    for (final mode in HighwayStripMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HighwayReadingStrip(
              chart: prepared,
              laneMap: profile.laneMapFor(prepared),
              beat: 1.2,
              palette: HighwayPalette.of(HighwaySkin.ink),
              mode: mode,
              noteNameOf: (m) => 'C',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$mode');
    }
  });
}
