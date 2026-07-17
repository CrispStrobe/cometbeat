// Unit tests for UserSongsService — the persistence layer behind imported
// songs and chord sheets. Pure logic (add/remove/load/save + JSON), so it is
// tested directly rather than through a widget.

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _xml = '''
<score-partwise version="4.0"><part-list><score-part id="P1">
<part-name>M</part-name></score-part></part-list><part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

ImportedSong _song(String id) =>
    ImportedSong(id: id, title: 'Song $id', musicXml: _xml);

ImportedChordSheet _sheet(String id) =>
    ImportedChordSheet(id: id, title: 'Sheet $id', source: '{title: x}\n[C]la');

/// Let the fire-and-forget `_save()` flush to the mock store.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh service is empty', () async {
    final svc = UserSongsService();
    await svc.load();
    expect(svc.songs, isEmpty);
    expect(svc.sheets, isEmpty);
  });

  test('addSong / addSheet append and notify listeners', () async {
    final svc = UserSongsService();
    var notifications = 0;
    svc.addListener(() => notifications++);

    svc.addSong(_song('a'));
    svc.addSheet(_sheet('b'));

    expect(svc.songs.map((s) => s.id), ['a']);
    expect(svc.sheets.map((s) => s.id), ['b']);
    expect(notifications, 2);
  });

  test('removeSong / removeSheet drop by id and leave others', () async {
    final svc = UserSongsService()
      ..addSong(_song('a'))
      ..addSong(_song('b'))
      ..addSheet(_sheet('c'));

    svc.removeSong('a');
    svc.removeSheet('missing'); // no-op

    expect(svc.songs.map((s) => s.id), ['b']);
    expect(svc.sheets.map((s) => s.id), ['c']);
  });

  test('the exposed lists are unmodifiable', () async {
    final svc = UserSongsService()..addSong(_song('a'));
    expect(() => svc.songs.add(_song('x')), throwsUnsupportedError);
    expect(() => svc.sheets.add(_sheet('y')), throwsUnsupportedError);
  });

  test('added content persists across service instances', () async {
    UserSongsService()
      ..addSong(_song('a'))
      ..addSheet(_sheet('b'));
    await _settle();

    final second = UserSongsService();
    await second.load();

    expect(second.songs.single.id, 'a');
    expect(second.songs.single.title, 'Song a');
    expect(second.songs.single.musicXml, _xml);
    expect(second.sheets.single.id, 'b');
    expect(second.sheets.single.source, contains('[C]la'));
  });

  test('a removal persists too', () async {
    final first = UserSongsService()
      ..addSong(_song('a'))
      ..addSong(_song('b'));
    await _settle();
    first.removeSong('a');
    await _settle();

    final second = UserSongsService();
    await second.load();
    expect(second.songs.map((s) => s.id), ['b']);
  });

  test('load tolerates corrupt storage without throwing', () async {
    SharedPreferences.setMockInitialValues({'user_songs': 'not json {{{'});
    final svc = UserSongsService();
    await svc.load(); // must not throw
    expect(svc.songs, isEmpty);
    expect(svc.sheets, isEmpty);
  });

  test('ImportedSong JSON round-trips', () {
    final song = _song('a');
    final back = ImportedSong.fromJson(song.toJson());
    expect(back.id, song.id);
    expect(back.title, song.title);
    expect(back.musicXml, song.musicXml);
  });

  test('ImportedChordSheet JSON round-trips', () {
    final sheet = _sheet('b');
    final back = ImportedChordSheet.fromJson(sheet.toJson());
    expect(back.id, sheet.id);
    expect(back.title, sheet.title);
    expect(back.source, sheet.source);
  });

  // --- Songbook collections ------------------------------------------------

  test('createCollection makes an empty, named book', () {
    final svc = UserSongsService();
    final book = svc.createCollection('Favourites', id: 'fav');
    expect(book.id, 'fav');
    expect(book.title, 'Favourites');
    expect(svc.collections.single.id, 'fav');
    expect(svc.collections.single.songIds, isEmpty);
  });

  test('adding a song to a book is ordered and deduped', () {
    final svc = UserSongsService()
      ..addSong(_song('a'))
      ..addSong(_song('b'));
    svc.createCollection('Set', id: 's');

    svc
      ..addSongToCollection('s', 'b')
      ..addSongToCollection('s', 'a')
      ..addSongToCollection('s', 'b'); // duplicate ignored

    expect(svc.collections.single.songIds, ['b', 'a']);
    expect(svc.songsInCollection('s').map((s) => s.id), ['b', 'a']);
  });

  test('songsInCollection skips ids that no longer resolve', () {
    final svc = UserSongsService()..addSong(_song('a'));
    svc.createCollection('Set', id: 's');
    svc
      ..addSongToCollection('s', 'a')
      ..addSongToCollection('s', 'ghost');
    expect(svc.songsInCollection('s').map((s) => s.id), ['a']);
  });

  test('removing a song prunes it from every book', () {
    final svc = UserSongsService()
      ..addSong(_song('a'))
      ..addSong(_song('b'));
    svc.createCollection('One', id: 'one');
    svc.createCollection('Two', id: 'two');
    svc
      ..addSongToCollection('one', 'a')
      ..addSongToCollection('one', 'b')
      ..addSongToCollection('two', 'a');

    svc.removeSong('a');

    expect(svc.collections.firstWhere((c) => c.id == 'one').songIds, ['b']);
    expect(svc.collections.firstWhere((c) => c.id == 'two').songIds, isEmpty);
  });

  test(
      'reorderCollection moves an item (onReorderItem insert-index convention)',
      () {
    final svc = UserSongsService()
      ..addSong(_song('a'))
      ..addSong(_song('b'))
      ..addSong(_song('c'));
    svc.createCollection('Set', id: 's');
    for (final id in ['a', 'b', 'c']) {
      svc.addSongToCollection('s', id);
    }

    // Move 'a' (index 0) to the end: after removal it inserts at index 2.
    svc.reorderCollection('s', 0, 2);
    expect(svc.songsInCollection('s').map((s) => s.id), ['b', 'c', 'a']);

    // Move it back to the front.
    svc.reorderCollection('s', 2, 0);
    expect(svc.songsInCollection('s').map((s) => s.id), ['a', 'b', 'c']);
  });

  test('rename and remove a book', () {
    final svc = UserSongsService()..createCollection('Old', id: 'x');
    svc.renameCollection('x', 'New');
    expect(svc.collections.single.title, 'New');
    svc.removeCollection('x');
    expect(svc.collections, isEmpty);
  });

  test('collections persist across instances', () async {
    final first = UserSongsService()..addSong(_song('a'));
    first.createCollection('Set', id: 's');
    first.addSongToCollection('s', 'a');
    await _settle();

    final second = UserSongsService();
    await second.load();
    expect(second.collections.single.id, 's');
    expect(second.collections.single.songIds, ['a']);
    expect(second.songsInCollection('s').map((s) => s.id), ['a']);
  });

  test('SongCollection JSON round-trips', () {
    const book = SongCollection(id: 'x', title: 'B', songIds: ['a', 'b']);
    final back = SongCollection.fromJson(book.toJson());
    expect(back.id, 'x');
    expect(back.title, 'B');
    expect(back.songIds, ['a', 'b']);
  });
}
