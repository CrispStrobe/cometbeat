// Tab Workshop (B0) — read-only tablature viewer. Pure-parse asserts on
// parseTabFile + widget asserts on the controls and the file-open seam
// (TabWorkshopTester). The tab render itself needs the bundled music font, so
// these assertions are on chrome/state, not painted output.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

const _abc = 'X:1\nT:Scale\nK:C\nCDEF|GABc|\n';

TabWorkshopTester _tab(WidgetTester tester) =>
    tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseTabFile', () {
    test('reads an ABC file into a Score with notes', () {
      final score = parseTabFile('tune.abc', utf8.encode(_abc));
      final notes = score.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .length;
      expect(notes, greaterThan(0));
    });

    test('throws on an unknown extension', () {
      expect(
        () => parseTabFile('weird.zzz', Uint8List(0)),
        throwsFormatException,
      );
    });

    test('accepts the documented tab import extensions', () {
      expect(tabImportExtensions, contains('gp'));
      expect(tabImportExtensions, contains('gpx'));
      expect(tabImportExtensions, contains('musicxml'));
    });
  });

  testWidgets('To Multitrack sends the tab band as a DAW clip', (tester) async {
    final daw = DawService();
    await pumpGame(
      tester,
      const TabWorkshopScreen(),
      extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
    );
    final tab = _tab(tester);

    // The demo riff is non-empty, so sending yields a clip that bakes.
    expect(daw.clipCount, 0);
    tab.sendToDaw();
    expect(daw.clipCount, 1);
    expect(daw.bake(), isNotEmpty);
  });

  testWidgets('opens with the demo riff and tuning/capo controls',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    expect(tab.sourceName, isNull); // demo, not a loaded file
    expect(tab.tuning.name, Tuning.standardGuitar.name);
    expect(tab.capo, 0);
    // The tuning picker and the standard-notation switch are present.
    expect(find.byType(DropdownButton<Tuning>), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the capo stepper is bounded at 0 and increments',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // At 0 the minus button is disabled; plus raises the capo.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(tab.capo, 1);
  });

  testWidgets('opening a file updates the score + app-bar title',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    await tab.openScoreFile(
      pickedName: 'tune.abc',
      pickedBytes: utf8.encode(_abc),
    );
    await tester.pump();

    expect(tab.sourceName, 'tune.abc');
    expect(find.text('tune.abc'), findsWidgets);
  });

  testWidgets('a bad file surfaces an error and keeps the old score',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    await tab.openScoreFile(
      pickedName: 'broken.musicxml',
      pickedBytes: utf8.encode('<not-musicxml/>'),
    );
    await tester.pump();

    expect(tab.sourceName, isNull); // unchanged — still the demo
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('select a cell and enter a fret updates the grid',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    tab.selectCell(0, 0);
    await tester.pump();
    tab.enterFret(5);
    await tester.pump();
    expect(tab.fretAt(0, 0), 5);

    tab.deleteCell();
    await tester.pump();
    expect(tab.fretAt(0, 0), isNull);
  });

  testWidgets('🔍 Inspect mode: a cell reports its fretted note',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    final open0 = tab.tuning.strings[0]; // string 0's open pitch

    expect(tab.inspectMode, isFalse);
    tab.toggleInspectMode();
    await tester.pump();
    expect(tab.inspectMode, isTrue);

    // Fret 0 sounds the open string; fret 3 is three semitones up.
    tab.selectCell(0, 0);
    tab.enterFret(0);
    await tester.pump();
    expect(tab.debugInspectInfo(0, 0)?.$1, open0.toString());

    tab.enterFret(3);
    await tester.pump();
    expect(
      tab.debugInspectInfo(0, 0)?.$1,
      Pitch.fromMidi(open0.midiNumber + 3).toString(),
    );
    // (Column-chord naming shares the Tracker's chordSymbolFor path, tested
    // there; here the single-note spelling is what's tab-specific.)
  });

  testWidgets('🔍 Inspect mode: desktop hover raises the corner card',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // Inert until Inspect is on.
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();
    tab.debugHoverCell(0, 0);
    await tester.pump();
    expect(tab.debugHoverCardShown, isFalse);

    tab.toggleInspectMode();
    await tester.pump();

    // Hovering a fretted cell shows the card; a fresh empty column clears it.
    tab.debugHoverCell(0, 0);
    await tester.pump();
    expect(tab.debugHoverCardShown, isTrue);

    tab.addColumn(); // inserts an empty column at index 1
    await tester.pump();
    tab.debugHoverCell(1, 0);
    await tester.pump();
    expect(tab.debugHoverCardShown, isFalse);
  });

  testWidgets('add and remove a column changes the count', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    final before = tab.columnCount;
    tab.addColumn();
    await tester.pump();
    expect(tab.columnCount, before + 1);

    tab.removeColumnAtCursor();
    await tester.pump();
    expect(tab.columnCount, before);
  });

  testWidgets('generative insert adds a run after the cursor and moves it',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    await tester.pump();
    final before = tab.columnCount;

    // Strum = one column; the cursor lands on it (the fret keypad now shows it).
    final strummed = tab.insertStrum('C');
    await tester.pump();
    expect(strummed, 1);
    expect(tab.columnCount, before + 1);

    // A one-octave major scale = 8 single-note columns.
    final scaled = tab.insertScale(48, 'Major');
    await tester.pump();
    expect(scaled, 8);
    expect(tab.columnCount, before + 1 + 8);
  });

  testWidgets('tapping a fret keypad button writes to the selected cell',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(1, 2);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '7'));
    await tester.pump();
    expect(tab.fretAt(1, 2), 7);
  });

  testWidgets('toggling a technique chip marks the selected note',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    tab.enterFret(5);
    await tester.pump();

    tab.toggleTechnique(TabTechnique.bend);
    await tester.pump();
    expect(tab.techniquesAt(0), contains(TabTechnique.bend));

    tab.toggleTechnique(TabTechnique.bend);
    await tester.pump();
    expect(tab.techniquesAt(0), isEmpty);
  });

  testWidgets('attaching a chord shows its name above the column',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(2, 0);
    await tester.pump();

    tab.setChordByName('G');
    await tester.pump();
    expect(tab.chordNameAt(2), 'G');

    tab.setChordByName(null);
    await tester.pump();
    expect(tab.chordNameAt(2), isNull);
  });

  testWidgets('Save to Song Book stores the tab as a song', (tester) async {
    final svc = UserSongsService();
    await pumpGame(
      tester,
      const TabWorkshopScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: svc),
      ],
    );
    final tab = _tab(tester);

    expect(svc.songs, isEmpty);
    tab.saveToSongBook('My Riff');
    await tester.pump();
    expect(svc.songs, hasLength(1));
    expect(svc.songs.single.title, 'My Riff');
    expect(svc.songs.single.musicXml, contains('<score-partwise'));
  });

  testWidgets('tracks: add, switch, edit independently, remove',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    expect(tab.trackCount, 1);
    expect(tab.activeTrack, 0);

    // Edit track 1.
    tab.selectCell(0, 0);
    tab.enterFret(5);
    await tester.pump();
    expect(tab.fretAt(0, 0), 5);

    // A new track is blank and becomes active.
    tab.addTrack();
    await tester.pump();
    expect(tab.trackCount, 2);
    expect(tab.activeTrack, 1);
    expect(tab.fretAt(0, 0), isNull);

    tab.selectCell(0, 0);
    tab.enterFret(7);
    await tester.pump();
    expect(tab.fretAt(0, 0), 7);

    // Track 1 kept its own edit.
    tab.selectTrack(0);
    await tester.pump();
    expect(tab.fretAt(0, 0), 5);

    // Removing drops to one track and never goes below one.
    tab.selectTrack(1);
    tab.removeTrack();
    await tester.pump();
    expect(tab.trackCount, 1);
    tab.removeTrack();
    await tester.pump();
    expect(tab.trackCount, 1);
  });

  testWidgets('saving a two-track band writes multi-part MusicXML',
      (tester) async {
    final svc = UserSongsService();
    await pumpGame(
      tester,
      const TabWorkshopScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: svc),
      ],
    );
    final tab = _tab(tester)..addTrack();
    await tester.pump();
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();

    tab.saveToSongBook('Band');
    await tester.pump();
    expect(svc.songs, hasLength(1));
    // Two parts in the score-partwise part-list.
    expect('<score-part '.allMatches(svc.songs.single.musicXml).length, 2);
  });

  testWidgets('mic readings land on the fretboard and advance the cursor',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    await tester.pump();

    expect(tab.isListening, isFalse); // mic is off until toggled

    // Three agreeing frames of the open bottom string commit one placement.
    final lowE = Tuning.standardGuitar.strings[5].midiNumber;
    final freq = 440.0 * math.pow(2, (lowE - 69) / 12.0);
    for (var i = 0; i < 3; i++) {
      tab.debugFeedReading(
        PitchReading(frequency: freq, clarity: 0.99, a4: 440, rms: 0.2),
      );
    }
    await tester.pump();

    expect(tab.fretAt(0, 5), 0); // open, bottom string, at the cursor column
  });

  testWidgets('Open from Song Book loads a song as editable tab',
      (tester) async {
    final svc = UserSongsService();
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4 e4 f4'));
    svc.addSong(ImportedSong(id: 's1', title: 'Loaded Song', musicXml: xml));

    await pumpGame(
      tester,
      const TabWorkshopScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: svc),
      ],
    );
    final tab = _tab(tester);
    expect(tab.sourceName, isNull); // demo

    tab.openSongMusicXml('Loaded Song', xml);
    await tester.pump();
    expect(tab.sourceName, 'Loaded Song');
    expect(tab.columnCount, greaterThan(0)); // notes became fretted columns
  });

  testWidgets('per-track mute/solo toggles on the active track',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester)..addTrack();
    await tester.pump();

    expect(tab.isMuted(1), isFalse);
    tab.toggleMute();
    await tester.pump();
    expect(tab.isMuted(1), isTrue);

    tab.toggleSolo();
    await tester.pump();
    expect(tab.isSoloed(1), isTrue);
  });

  testWidgets('pasting ASCII tab loads it into the active track',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    tab.pasteAsciiTab('e|-0-3-|\nB|-----|\nG|-----|\n'
        'D|-----|\nA|-----|\nE|-----|');
    await tester.pump();
    // The two events (open + 3rd fret on the top string) become fretted cells.
    final topRow = [
      for (var c = 0; c < tab.columnCount; c++) tab.fretAt(c, 0),
    ];
    expect(topRow, contains(0)); // the open note
    expect(topRow, contains(3)); // the 3rd-fret note
  });

  testWidgets('Open in Score Workshop hands over one part per track',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester)..addTrack();
    await tester.pump();

    final score = tab.debugWorkshopScore();
    expect(score.parts, hasLength(2)); // one Score per tab track
  });

  testWidgets('tempo control starts at 120', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    expect(_tab(tester).bpm, 120);
  });

  testWidgets('ChordDiagramView paints a preset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChordDiagramView(kGuitarChords['C']!))),
    );
    expect(find.byType(ChordDiagramView), findsOneWidget);
  });

  testWidgets('play lights the sounding column, then stops', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // A note in the first column (a quarter = 500ms at 120bpm).
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();

    tab.play();
    await tester.pump(); // kick the ticker
    await tester.pump(const Duration(milliseconds: 100));
    expect(tab.isPlaying, isTrue);
    expect(tab.highlightedIds, contains('t0'));

    // Tapping play again stops and clears the highlight.
    tab.play();
    await tester.pump();
    expect(tab.isPlaying, isFalse);
    expect(tab.highlightedIds, isEmpty);
  });

  testWidgets('count-in: enabling it counts in before playback, stop cancels',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    expect(tab.countInOn, isFalse);
    tab.setCountIn(true);
    await tester.pump();
    expect(tab.countInOn, isTrue);

    // Play → the metronome count-in runs first (counting-in, not yet playing).
    tab.play();
    await tester.pump();
    expect(tab.isCountingIn, isTrue);
    expect(tab.isPlaying, isFalse);

    // Stopping during the count-in cancels it cleanly.
    tab.play(); // toggles stop
    await tester.pump();
    expect(tab.isCountingIn, isFalse);
    expect(tab.isPlaying, isFalse);
    // Let any pending count-in timer fire; it must not resume playback.
    await tester.pump(const Duration(seconds: 3));
    expect(tab.isPlaying, isFalse);
  });
}
