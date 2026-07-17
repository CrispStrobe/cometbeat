import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/songs/chord_sheet_screen.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import_screen.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/tune_quiz_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiSystemView;
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

Widget _wrap(Widget child, SriService sri, {UserSongsService? songs}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsService()),
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider(create: (_) => ProgressService()),
      ChangeNotifierProvider<UserSongsService>.value(
        value: songs ?? UserSongsService(),
      ),
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

  testWidgets('song book lists all songs; song screen renders systems',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const SongListScreen(), sri));
    await tester.pump();

    for (final song in kSongs) {
      expect(find.text(song.title), findsOneWidget);
    }

    await tester.tap(find.text('Alle meine Entchen'));
    await tester.pumpAndSettle();

    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tune quiz offers all song titles and records', (tester) async {
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

    // All four import affordances are present.
    expect(find.text('Import as MusicXML'), findsOneWidget);
    expect(find.text('Pick a MusicXML file…'), findsOneWidget);
    expect(find.text('Pick a MIDI file…'), findsOneWidget);

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
    await tester.tap(find.text('Pick a MusicXML file…'));
    await tester.pumpAndSettle();

    expect(songs.songs, hasLength(1));
    // No title typed and no work-title in the XML -> filename is the fallback.
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
    await tester.tap(find.text('Pick a MIDI file…'));
    await tester.pumpAndSettle();

    // Parsed + quantized + persisted as MusicXML under the filename.
    expect(songs.songs, hasLength(1));
    expect(songs.songs.single.title, 'ditty');
  });
}
