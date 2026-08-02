// Widget coverage for the songbook browse/reorder UI on top of the
// SongCollection model. The list screen shows books and creates them; the book
// screen adds songs from the picker and removes them.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart'
    show SongListScreen;
import 'package:comet_beat/features/games/songs/songbook_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/harmony/chart_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _xml = '''
<score-partwise version="4.0"><part-list><score-part id="P1">
<part-name>M</part-name></score-part></part-list><part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

/// The same song WITH a chord symbol, so the band affordance has something to
/// derive from. `<harmony>` is MusicXML's own element for a chord.
const _xmlWithChords = '''
<score-partwise version="4.0"><part-list><score-part id="P1">
<part-name>M</part-name></score-part></part-list><part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

Widget _host(UserSongsService songs, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: songs),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        Provider<AudioService>(create: (_) => AudioService()),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'the Song Book lists the built-in children songs when the library is empty',
      (tester) async {
    final songs = UserSongsService();
    await songs.load(); // fresh: no collections, no imported songs
    await tester.pumpWidget(_host(songs, const SongListScreen()));
    await tester.pumpAndSettle();

    // The public-domain children's songs are always shown on the main Song Book
    // list — an empty user library never makes the Song Book itself empty.
    // (The "empty" message only appears inside an empty *collection*.)
    expect(find.text('Alle meine Entchen'), findsOneWidget);
    expect(find.text('Twinkle, Twinkle, Little Star'), findsOneWidget);
    expect(find.text('Old MacDonald Had a Farm'), findsOneWidget);
    expect(find.text('No songs yet — tap Add songs.'), findsNothing);
  });

  testWidgets('add-songs picker toggles membership; remove drops from book',
      (tester) async {
    // Tall window: the picker now also lists the built-in songs, so the user's
    // own songs sit lower down — make everything render.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final songs = UserSongsService()
      ..addSong(
        const ImportedSong(id: 'a', title: 'Song A', musicXml: _xml),
      )
      ..addSong(
        const ImportedSong(id: 'b', title: 'Song B', musicXml: _xml),
      );
    songs.createCollection('My Book', id: 'book');

    await tester.pumpWidget(
      _host(songs, const SongbookScreen(collectionId: 'book')),
    );
    await tester.pumpAndSettle();

    // Empty book → the empty hint, no song tiles.
    expect(find.text('No songs yet — tap Add songs.'), findsOneWidget);

    // Open the picker and tick both of the user's own songs (by title, since
    // the built-in children's songs are listed above them now).
    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song A'));
    await tester.tap(find.text('Song B'));
    await tester.pumpAndSettle();
    expect(songs.songsInCollection('book').map((s) => s.id), ['a', 'b']);

    // Close the sheet; both songs now render in the book.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Song B'), findsOneWidget);

    // Remove the first one; it leaves the book but stays in the library.
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    expect(songs.songsInCollection('book').map((s) => s.id), ['b']);
    expect(songs.songs.map((s) => s.id), ['a', 'b']);
  });

  testWidgets('a built-in song can be added to a book (materialised)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final songs = UserSongsService();
    await songs.load(); // fresh: no imported songs at all
    songs.createCollection('My Book', id: 'book');

    await tester.pumpWidget(
      _host(songs, const SongbookScreen(collectionId: 'book')),
    );
    await tester.pumpAndSettle();

    // The picker opens even with an empty library (built-in songs are always
    // offered) — the old "import something first" dead end is gone.
    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Twinkle, Twinkle, Little Star'));
    await tester.pumpAndSettle();

    // Ticking it materialises the built-in into the library (as builtin_<id>)
    // and adds it to the book.
    expect(
      songs.songsInCollection('book').map((s) => s.id),
      ['builtin_twinkle'],
    );
    expect(songs.songs.single.title, 'Twinkle, Twinkle, Little Star');
    expect(songs.songs.single.musicXml, contains('score-partwise'));
  });

  testWidgets('deleting the book pops the screen', (tester) async {
    final songs = UserSongsService()..createCollection('Gone', id: 'g');
    await tester.pumpWidget(
      _host(
        songs,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SongbookScreen(collectionId: 'g'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Gone'), findsOneWidget);

    // Delete via the overflow menu → back on the launcher.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete songbook'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(songs.collections, isEmpty);
  });

  testWidgets('a song with chords offers a band; one without does NOT',
      (tester) async {
    // BB-U5's acceptance, verbatim: a library item with no derived chart shows
    // no dead "play with band" affordance. Both songs are in the same book, so
    // the difference can only be the chords.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final songs = UserSongsService()
      ..addSong(const ImportedSong(id: 'plain', title: 'Plain', musicXml: _xml))
      ..addSong(
        const ImportedSong(
          id: 'chords',
          title: 'Chords',
          musicXml: _xmlWithChords,
        ),
      );
    songs.createCollection('My Book', id: 'book');
    songs.addSongToCollection('book', 'plain');
    songs.addSongToCollection('book', 'chords');

    await tester.pumpWidget(
      _host(songs, const SongbookScreen(collectionId: 'book')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plain'), findsOneWidget);
    expect(find.text('Chords'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('playWithBand_chords')),
      findsOneWidget,
      reason: 'a song WITH chords should offer the band',
    );
    expect(
      find.byKey(const ValueKey('playWithBand_plain')),
      findsNothing,
      reason: 'a song with no chords must not show a dead affordance',
    );
  });

  test('the chord gate reads the XML rather than parsing it', () {
    // It is a cheap marker check by design — `score` re-parses on every call,
    // so asking it once per row would reparse a whole book on every rebuild.
    expect(
      const ImportedSong(id: 'a', title: 'A', musicXml: _xmlWithChords)
          .mayHaveChords,
      isTrue,
    );
    expect(
      const ImportedSong(id: 'b', title: 'B', musicXml: _xml).mayHaveChords,
      isFalse,
    );
  });

  testWidgets('tapping the band button opens the chart with the song chords',
      (tester) async {
    // The affordance has to LAND somewhere: on the full chart surface, with
    // the chords derived from the song rather than a blank starter chart.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    final songs = UserSongsService()
      ..addSong(
        const ImportedSong(
          id: 'chords',
          title: 'Chords',
          musicXml: _xmlWithChords,
        ),
      );
    songs.createCollection('My Book', id: 'book');
    songs.addSongToCollection('book', 'chords');

    await tester.pumpWidget(
      _host(songs, const SongbookScreen(collectionId: 'book')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playWithBand_chords')));
    await tester.pumpAndSettle();

    expect(find.byType(ChartScreen), findsOneWidget);
    // The C major from the song's <harmony>, not the starter chart.
    expect(find.text('C'), findsWidgets);
  });
}
