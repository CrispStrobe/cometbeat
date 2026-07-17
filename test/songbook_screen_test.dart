// Widget coverage for the songbook browse/reorder UI on top of the
// SongCollection model. The list screen shows books and creates them; the book
// screen adds songs from the picker and removes them.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/songs/songbook_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
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

  testWidgets('add-songs picker toggles membership; remove drops from book',
      (tester) async {
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

    // Open the picker and tick both songs.
    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(1));
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
}
