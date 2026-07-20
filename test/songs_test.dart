import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/chord_sheet_screen.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import_screen.dart';
import 'package:comet_beat/features/games/songs/multi_part_song_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/tune_quiz_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiSystemView, multiPartToMusicXml;
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns a fixed file (or null) from the picker so the import file-pick
/// paths can be driven without a real dialog.
class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this._file);
  final XFile? _file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      _file;
}

/// Home screen with a button that pushes [screen], so a screen that pops
/// itself on success has a route to return to.
Widget _launcher(Widget screen) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => screen),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

/// A minimal valid single-track SMF: C4, D4, E4 quarters.
Uint8List _buildMidi() {
  final track = <int>[
    0x00,
    0x90,
    60,
    100,
    0x83,
    0x60,
    0x80,
    60,
    0,
    0x00,
    0x90,
    62,
    100,
    0x83,
    0x60,
    0x80,
    62,
    0,
    0x00,
    0x90,
    64,
    100,
    0x87,
    0x40,
    0x80,
    64,
    0,
    0x00,
    0xff,
    0x2f,
    0x00,
  ];
  return Uint8List.fromList([
    ...'MThd'.codeUnits,
    0,
    0,
    0,
    6,
    0,
    0,
    0,
    1,
    0x01,
    0xe0,
    ...'MTrk'.codeUnits,
    (track.length >> 24) & 0xff,
    (track.length >> 16) & 0xff,
    (track.length >> 8) & 0xff,
    track.length & 0xff,
    ...track,
  ]);
}

const _xml = '''
<score-partwise version="4.0"><part-list><score-part id="P1">
<part-name>M</part-name></score-part></part-list><part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

Widget _wrap(
  Widget child,
  SriService sri, {
  UserSongsService? songs,
  DawService? daw,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsService()),
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider(create: (_) => ProgressService()),
      ChangeNotifierProvider<UserSongsService>.value(
        value: songs ?? UserSongsService(),
      ),
      ChangeNotifierProvider<DawService>.value(value: daw ?? DawService()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('every song parses: lyrics align with notes, playback is sane', () {
    for (final song in kSongs) {
      // Building the score throws if lyric tokens do not match the notes.
      final score = song.score;
      expect(score.lyrics, isNotEmpty, reason: song.id);
      expect(
        score.lyrics.length,
        song.playback.length,
        reason: '${song.id}: one syllable per note in these songs',
      );

      final playback = song.playback;
      expect(playback.length, greaterThan(10 - 1), reason: song.id);
      for (final (id, midi, ms) in playback) {
        expect(id, isNotEmpty);
        expect(midi, inInclusiveRange(48, 84), reason: song.id);
        expect(ms, greaterThan(0));
      }
    }
  });

  test('ensemble songs parse to 2–5 aligned voices with rest-aware playback',
      () {
    expect(kEnsembleSongs, isNotEmpty);
    for (final song in kEnsembleSongs) {
      final parts = song.score.parts;
      expect(parts.length, song.voices.length, reason: song.id);
      expect(parts.length, inInclusiveRange(2, 5), reason: song.id);

      // Every voice plays (rest-aware), and all voices span the same total time
      // — a canon's staggered entries and a part-song's bars must line up.
      final totals = <int>[];
      for (final v in song.voices) {
        final pb = ensembleVoicePlayback(v.score);
        expect(pb, isNotEmpty, reason: '${song.id}/${v.name}');
        for (final (midis, ms) in pb) {
          expect(ms, greaterThan(0));
          for (final midi in midis) {
            expect(midi, inInclusiveRange(40, 84), reason: song.id);
          }
        }
        totals.add(pb.fold<int>(0, (a, e) => a + e.$2));
      }
      expect(
        totals.toSet(),
        hasLength(1),
        reason: '${song.id}: voices must be equal length',
      );
    }
  });

  testWidgets('song book lists all songs; song screen renders systems',
      (tester) async {
    // A tall window so the whole (now longer) song list renders — the ListView
    // is lazy, so off-screen titles wouldn't otherwise be built.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const SongListScreen(), sri));
    await tester.pump();

    for (final song in kSongs) {
      expect(find.text(song.title), findsOneWidget);
    }
    // The multi-voice ensemble samples are listed in their own section.
    for (final song in kEnsembleSongs) {
      expect(find.text(song.title), findsOneWidget);
    }

    await tester.tap(find.text('Alle meine Entchen'));
    await tester.pumpAndSettle();

    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('an imported multi-part song exposes ALL its parts (not flattened)', () {
    // A 4-voice canon written to multi-part MusicXML must read back as 4 parts —
    // this is exactly what a saved whole-song transcription stores.
    final canon = kEnsembleSongs.firstWhere((s) => s.voices.length == 4);
    final xml = multiPartToMusicXml(canon.score, partNames: canon.partNames);
    final song = ImportedSong(id: 'x', title: 'Canon', musicXml: xml);

    expect(song.isMultiPart, isTrue);
    expect(song.multiPart.parts, hasLength(4));
    // The single-part getter still yields just the first part (karaoke path).
    expect(song.score.measures, isNotEmpty);
  });

  testWidgets('ensemble screen stacks a staff per voice and plays',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final song = kEnsembleSongs.firstWhere((s) => s.voices.length == 4);
    await tester.pumpWidget(
      _wrap(
        MultiPartSongScreen(
          title: song.title,
          score: song.score,
          partNames: song.partNames,
        ),
        sri,
      ),
    );
    await tester.pumpAndSettle();

    // One staff (system view) per voice.
    expect(find.byType(MultiSystemView), findsNWidgets(song.voices.length));
    // Play mixes all voices without throwing.
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tune quiz offers all song titles and records', (tester) async {
    // Tall window so every option renders (see the song-book test above).
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const TuneQuizScreen(), sri));
    await tester.pump();

    expect(find.textContaining('Which song'), findsOneWidget);
    for (final song in kSongs) {
      expect(find.text(song.title), findsOneWidget);
    }

    await tester.tap(find.text(kSongs.first.title));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['songs']!.keys, ['tune']);
    await tester.pumpAndSettle();
  });

  testWidgets('song screen: Play walks the cursor and finishes on its own',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    // A tiny two-note song keeps the fake-clock walk short.
    const song =
        Song(id: 't', title: 'Test', dsl: 'c4:q d4:q', lyrics: 'la la');
    await tester.pumpWidget(_wrap(SongScreen(song: song), sri));
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget); // now playing

    // Walk both quarter notes (500 ms each) to completion.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Play'), findsOneWidget); // finished, reset to Play
  });

  testWidgets('song screen: To Multitrack sends the song as a DAW clip',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final daw = DawService();
    const song =
        Song(id: 't', title: 'Test', dsl: 'c4:q d4:q', lyrics: 'la la');
    await tester.pumpWidget(_wrap(SongScreen(song: song), sri, daw: daw));
    await tester.pump();

    expect(daw.clipCount, 0);
    await tester.tap(find.byIcon(Icons.library_add));
    await tester.pump();

    expect(daw.clipCount, 1);
    expect(daw.bake(), isNotEmpty); // the song renders to real audio as a clip
  });

  testWidgets('song screen: Analyse opens the computed harmony view',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    // A C-major arpeggio bar → the engine reads an implied I chord.
    const song =
        Song(id: 't', title: 'Arp', dsl: 'c4:q e4:q g4:q c5:q', lyrics: '');
    await tester.pumpWidget(_wrap(SongScreen(song: song), sri));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byIcon(Icons.insights));
    await tester.pumpAndSettle();
    // The analysis screen, with the tonic chord read from the notes.
    expect(find.text(l10n.analysisHarmonyHeading), findsOneWidget);
    expect(find.text('I'), findsWidgets);
  });

  testWidgets('song screen: Stop halts playback', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    const song =
        Song(id: 't', title: 'Test', dsl: 'c4:q d4:q', lyrics: 'la la');
    await tester.pumpWidget(_wrap(SongScreen(song: song), sri));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);

    // Flush the pending cursor delay so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('song screen: a Sing-along button sits beside Play',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    const song =
        Song(id: 't', title: 'Test', dsl: 'c4:q d4:q', lyrics: 'la la');
    await tester.pumpWidget(_wrap(SongScreen(song: song), sri));
    await tester.pump();

    // Present and enabled — the song has a singable melody (non-null onPressed).
    final singBtn = find.widgetWithText(OutlinedButton, 'Sing along');
    expect(singBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(singBtn).onPressed, isNotNull);

    // Its instrument twin sits alongside it.
    final playBtn = find.widgetWithText(OutlinedButton, 'Play along');
    expect(playBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(playBtn).onPressed, isNotNull);
  });

  testWidgets(
      'song book lists imported songs + sheets, and delete removes them',
      (tester) async {
    // Tall surface so the lazy ListView builds the whole list.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService()
      ..addSong(
        const ImportedSong(id: 's1', title: 'Imported One', musicXml: _xml),
      )
      ..addSheet(
        const ImportedChordSheet(
          id: 'sh1',
          title: 'Sheet One',
          source: '{title: x}\n[C]la',
        ),
      );

    await tester.pumpWidget(_wrap(const SongListScreen(), sri, songs: songs));
    await tester.pump();

    expect(find.text('My imported songs'), findsOneWidget);
    expect(find.text('Imported One'), findsOneWidget);
    expect(find.text('Chord sheets'), findsOneWidget);
    expect(find.text('Sheet One'), findsOneWidget);

    // Delete the imported song via its trailing button.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Card, 'Imported One'),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pump();
    expect(find.text('Imported One'), findsNothing);
    expect(find.text('Sheet One'), findsOneWidget); // sheet untouched
  });

  testWidgets('chord sheet screen renders the chord row and lyrics',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final sheet = parseChordPro('{title: Test}\n[C]Twin- kle [G]twin- kle');
    await tester.pumpWidget(
      _wrap(ChordSheetScreen(title: 'Test', sheet: sheet), sri),
    );
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Test'), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets); // the strum row
    expect(find.text('C'), findsWidgets);
    expect(find.textContaining('Twin'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import screen: pasted MusicXML lands in the Song Book',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImportScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        sri,
        songs: songs,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The paste + the universal file-import affordances are present.
    expect(find.text('Import as MusicXML'), findsOneWidget);
    expect(
      find.text('Import a file (MusicXML/MXL/ABC/MEI/kern/MIDI)…'),
      findsOneWidget,
    );

    // Paste valid MusicXML and import it.
    await tester.enterText(find.byType(TextField).last, _xml);
    await tester.tap(find.text('Import as MusicXML'));
    await tester.pumpAndSettle();

    expect(songs.songs, hasLength(1));
    expect(find.text('open'), findsOneWidget); // popped back
  });

  testWidgets('import screen: picking a MusicXML file adds a song',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(
        Uint8List.fromList(utf8.encode(_xml)),
        path: 'my_tune.musicxml',
      ),
    );

    await tester
        .pumpWidget(_wrap(_launcher(const ImportScreen()), sri, songs: songs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Import a file (MusicXML/MXL/ABC/MEI/kern/MIDI)…'));
    await tester.pumpAndSettle();

    expect(songs.songs, hasLength(1));
    // No title typed -> filename is the fallback.
    expect(songs.songs.single.title, 'my_tune');
  });

  testWidgets('import screen: picking a MIDI file adds a song', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(_buildMidi(), path: 'ditty.mid'),
    );

    await tester
        .pumpWidget(_wrap(_launcher(const ImportScreen()), sri, songs: songs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Import a file (MusicXML/MXL/ABC/MEI/kern/MIDI)…'));
    await tester.pumpAndSettle();

    // Parsed + persisted as MusicXML under the filename.
    expect(songs.songs, hasLength(1));
    expect(songs.songs.single.title, 'ditty');
  });

  testWidgets('import screen: picking a JAMS file adds a chord sheet',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    const jams = '{"file_metadata":{"title":"Blues"},"annotations":['
        '{"namespace":"chord","data":['
        '{"time":0.0,"duration":2.0,"value":"C:maj"},'
        '{"time":2.0,"duration":2.0,"value":"F:maj"},'
        '{"time":4.0,"duration":2.0,"value":"G:7"},'
        '{"time":6.0,"duration":2.0,"value":"A:min7"}]}]}';
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(Uint8List.fromList(utf8.encode(jams)), path: 'blues.jams'),
    );

    await tester
        .pumpWidget(_wrap(_launcher(const ImportScreen()), sri, songs: songs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import a JAMS file (chords or melody)…'));
    await tester.pumpAndSettle();

    // Imported as a chord sheet (not a song), titled from file_metadata.
    expect(songs.songs, isEmpty);
    expect(songs.sheets, hasLength(1));
    expect(songs.sheets.single.title, 'Blues');
    // The Harte labels became the app's plain chord chips.
    expect(parseChordPro(songs.sheets.single.source).chords, [
      'C',
      'F',
      'G',
      'Am',
    ]);
  });

  testWidgets('import screen: picking a JAMS melody adds a song (key in title)',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    const jams = '{"file_metadata":{"title":"Scale"},"annotations":['
        '{"namespace":"note_midi","data":['
        '{"time":0.0,"duration":0.5,"value":60},'
        '{"time":0.5,"duration":0.5,"value":62},'
        '{"time":1.0,"duration":0.5,"value":64}]},'
        '{"namespace":"tempo","data":[{"time":0.0,"duration":0.0,"value":120}]},'
        '{"namespace":"key_mode","data":['
        '{"time":0.0,"duration":0.0,"value":"C:major"}]}]}';
    FileSelectorPlatform.instance = _FakeFileSelector(
      XFile.fromData(Uint8List.fromList(utf8.encode(jams)), path: 'scale.jams'),
    );

    await tester
        .pumpWidget(_wrap(_launcher(const ImportScreen()), sri, songs: songs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import a JAMS file (chords or melody)…'));
    await tester.pumpAndSettle();

    // A note_midi melody imports as a song (not a chord sheet); key_mode is
    // surfaced in the title.
    expect(songs.sheets, isEmpty);
    expect(songs.songs, hasLength(1));
    expect(songs.songs.single.title, 'Scale — C major');
  });
}
