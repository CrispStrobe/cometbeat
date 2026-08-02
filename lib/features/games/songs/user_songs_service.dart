// lib/features/games/songs/user_songs_service.dart
//
// Imported content, persisted in SharedPreferences: notation songs (stored
// as MusicXML — the interchange format survives app updates) and ChordPro
// chord sheets (stored as source text).

import 'dart:async';
import 'dart:convert';

import 'package:comet_beat/features/games/songs/import/omr_source_store.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, Score, multiPartScoreFromMusicXml, scoreFromMusicXml;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImportedSong {
  final String id;
  final String title;
  final String musicXml;

  /// Provenance/credit line for a work imported from an external open-music
  /// library (null for songs the user typed/imported themselves). Shown on the
  /// "Sources & credits" screen so attribution travels with the song.
  final String? attribution;

  /// Canonical URL of the source work, or null.
  final String? sourceUrl;

  /// Composer/arranger credit, or null when the source did not name one.
  ///
  /// These three fields are DERIVED from [musicXml] (see [withDerivedMetadata])
  /// and stored alongside it rather than re-parsed. A songbook list needs them
  /// for every row, and parsing a full MusicXML document per row to draw one
  /// subtitle is the sort of thing that makes a twenty-song book feel broken.
  /// They are a cache, so [musicXml] stays the source of truth.
  final String? composer;

  /// Circle-of-fifths position of the key signature (−7…+7), or null.
  ///
  /// The signature, NOT a tonality: two sharps means D major or B minor and the
  /// file does not say which. `shared/key_signature_label.dart` renders the pair.
  final int? keyFifths;

  /// Initial metronome mark in quarter-notes per minute, or null.
  final double? tempoBpm;

  /// True when the sheet-music photo this song was recognised from is retained
  /// in the OMR source store (see `import/omr_source_store.dart`), so the
  /// recognition can be re-run on a bad scan. Only OMR imports set it.
  final bool hasSourceImage;

  const ImportedSong({
    required this.id,
    required this.title,
    required this.musicXml,
    this.attribution,
    this.sourceUrl,
    this.composer,
    this.keyFifths,
    this.tempoBpm,
    this.hasSourceImage = false,
  });

  /// This song with [composer]/[keyFifths]/[tempoBpm] read out of [musicXml].
  ///
  /// Returns the song unchanged if they are already set, so it is cheap to call
  /// on load, and unchanged if the XML will not parse — a song that cannot be
  /// read is still a song you can see in your book and delete.
  ImportedSong withDerivedMetadata() {
    if (composer != null && keyFifths != null && tempoBpm != null) return this;
    try {
      final s = score;
      return ImportedSong(
        id: id,
        title: title,
        musicXml: musicXml,
        attribution: attribution,
        sourceUrl: sourceUrl,
        composer: composer ?? _blankToNull(s.metadata.composer),
        keyFifths: keyFifths ?? s.keySignature.fifths,
        tempoBpm: tempoBpm ?? s.tempo?.quarterBpm,
        hasSourceImage: hasSourceImage,
      );
    } catch (_) {
      return this;
    }
  }

  static String? _blankToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  /// The first part as a single [Score] (karaoke/play-along/analysis use this).
  Score get score => scoreFromMusicXml(musicXml);

  /// Whether this song looks like it carries chord symbols, and so is worth
  /// offering a backing band for (BB-U5).
  ///
  /// ⚠️ Deliberately a CHEAP marker check on the raw XML, not a parse. [score]
  /// re-parses on every call, so asking it once per row would reparse every
  /// song in a book on every rebuild. `<harmony` is MusicXML's own element for
  /// a chord symbol, so this is structural evidence rather than a guess — but
  /// it is only a gate: a file can carry `<harmony>` elements that yield no
  /// usable chords, so the caller must still handle an empty derivation rather
  /// than assume this promised one.
  bool get mayHaveChords => musicXml.contains('<harmony');

  /// EVERY part (all instruments/staves) — a transcription or ensemble keeps its
  /// voices here. Single-part songs parse to a one-part [MultiPartScore].
  MultiPartScore get multiPart => multiPartScoreFromMusicXml(musicXml);

  /// True when the song has more than one part (so it should be shown on the
  /// stacked multi-staff view, not flattened to part 1). Safe on bad XML.
  bool get isMultiPart {
    try {
      return multiPart.parts.length > 1;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'xml': musicXml,
        if (attribution != null) 'attribution': attribution,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        // Written only when known, so a song saved before these existed and a
        // song whose source names no composer look the same on disk.
        if (composer != null) 'composer': composer,
        if (keyFifths != null) 'keyFifths': keyFifths,
        if (tempoBpm != null) 'tempoBpm': tempoBpm,
        if (hasSourceImage) 'hasSourceImage': true,
      };

  factory ImportedSong.fromJson(Map<String, dynamic> json) => ImportedSong(
        id: json['id'] as String,
        title: json['title'] as String,
        musicXml: json['xml'] as String,
        attribution: json['attribution'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        composer: json['composer'] as String?,
        keyFifths: (json['keyFifths'] as num?)?.toInt(),
        tempoBpm: (json['tempoBpm'] as num?)?.toDouble(),
        hasSourceImage: json['hasSourceImage'] as bool? ?? false,
      );
}

class ImportedChordSheet {
  final String id;
  final String title;
  final String source;

  const ImportedChordSheet({
    required this.id,
    required this.title,
    required this.source,
  });

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'source': source};

  factory ImportedChordSheet.fromJson(Map<String, dynamic> json) =>
      ImportedChordSheet(
        id: json['id'] as String,
        title: json['title'] as String,
        source: json['source'] as String,
      );
}

/// A named, ordered grouping of imported songs — a "songbook". Holds only song
/// *ids* (not copies) so a song lives in one place and can sit in many books;
/// missing ids are skipped when resolving, so a deleted song just drops out.
class SongCollection {
  final String id;
  final String title;
  final List<String> songIds;

  const SongCollection({
    required this.id,
    required this.title,
    this.songIds = const [],
  });

  SongCollection copyWith({String? title, List<String>? songIds}) =>
      SongCollection(
        id: id,
        title: title ?? this.title,
        songIds: songIds ?? this.songIds,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'songIds': songIds};

  factory SongCollection.fromJson(Map<String, dynamic> json) => SongCollection(
        id: json['id'] as String,
        title: json['title'] as String,
        songIds: [
          for (final s in (json['songIds'] as List? ?? [])) s as String,
        ],
      );
}

class UserSongsService with ChangeNotifier {
  static const _storageKey = 'user_songs';

  List<ImportedSong> _songs = [];
  List<ImportedChordSheet> _sheets = [];
  List<SongCollection> _collections = [];

  List<ImportedSong> get songs => List.unmodifiable(_songs);
  List<ImportedChordSheet> get sheets => List.unmodifiable(_sheets);
  List<SongCollection> get collections => List.unmodifiable(_collections);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final map = json.decode(jsonString) as Map<String, dynamic>;
        _songs = [
          // withDerivedMetadata(): songs saved before composer/key/tempo existed
          // have none on disk, and showing a book of blanks would look like the
          // feature is broken rather than like the data predates it. Deriving on
          // load fills them in from the MusicXML that was always there; the next
          // _save() persists the result, so this cost is paid once.
          for (final s in (map['songs'] as List? ?? []))
            ImportedSong.fromJson(s as Map<String, dynamic>)
                .withDerivedMetadata(),
        ];
        _sheets = [
          for (final s in (map['sheets'] as List? ?? []))
            ImportedChordSheet.fromJson(s as Map<String, dynamic>),
        ];
        _collections = [
          for (final c in (map['collections'] as List? ?? []))
            SongCollection.fromJson(c as Map<String, dynamic>),
        ];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[USER_SONGS] load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        json.encode({
          'songs': [for (final s in _songs) s.toJson()],
          'sheets': [for (final s in _sheets) s.toJson()],
          'collections': [for (final c in _collections) c.toJson()],
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[USER_SONGS] save failed: $e');
    }
  }

  void addSong(ImportedSong song) {
    // Derive here too, so a freshly imported song shows its composer/key/tempo
    // immediately instead of only after the next app start. Callers do not have
    // to know the fields exist.
    _songs = [..._songs, song.withDerivedMetadata()];
    notifyListeners();
    _save();
  }

  void addSheet(ImportedChordSheet sheet) {
    _sheets = [..._sheets, sheet];
    notifyListeners();
    _save();
  }

  /// Replaces a song's notation with freshly recognised [musicXml] (the re-run
  /// OMR flow), re-deriving its metadata. Keeps id/title/attribution and the
  /// retained-image flag. No-op if [id] is unknown.
  void updateSongXml(String id, String musicXml) {
    var changed = false;
    _songs = [
      for (final s in _songs)
        if (s.id == id)
          () {
            changed = true;
            return ImportedSong(
              id: s.id,
              title: s.title,
              musicXml: musicXml,
              attribution: s.attribution,
              sourceUrl: s.sourceUrl,
              hasSourceImage: s.hasSourceImage,
              // composer/key/tempo left null so withDerivedMetadata re-reads
              // them from the new XML rather than keeping the old scan's cache.
            ).withDerivedMetadata();
          }()
        else
          s,
    ];
    if (!changed) return;
    notifyListeners();
    _save();
  }

  void removeSong(String id) {
    _songs = _songs.where((s) => s.id != id).toList();
    // Drop it from any songbook it was in so no book points at a ghost.
    _collections = [
      for (final c in _collections)
        c.songIds.contains(id)
            ? c.copyWith(songIds: c.songIds.where((s) => s != id).toList())
            : c,
    ];
    // A removed song leaves no retained scan behind.
    unawaited(deleteOmrSource(id));
    notifyListeners();
    _save();
  }

  void removeSheet(String id) {
    _sheets = _sheets.where((s) => s.id != id).toList();
    notifyListeners();
    _save();
  }

  // --- Songbook collections -------------------------------------------------

  /// Create an empty songbook and return it. [id] is provided by callers that
  /// need determinism (tests); otherwise one is derived from the title.
  SongCollection createCollection(String title, {String? id}) {
    final book = SongCollection(
      id: id ?? 'book-${_collections.length}-${title.hashCode}',
      title: title,
    );
    _collections = [..._collections, book];
    notifyListeners();
    _save();
    return book;
  }

  void renameCollection(String id, String title) =>
      _updateCollection(id, (c) => c.copyWith(title: title));

  void removeCollection(String id) {
    _collections = _collections.where((c) => c.id != id).toList();
    notifyListeners();
    _save();
  }

  /// Add a song to a book (no-op if already present, so it can't appear twice).
  void addSongToCollection(String collectionId, String songId) =>
      _updateCollection(
        collectionId,
        (c) => c.songIds.contains(songId)
            ? c
            : c.copyWith(songIds: [...c.songIds, songId]),
      );

  void removeSongFromCollection(String collectionId, String songId) =>
      _updateCollection(
        collectionId,
        (c) => c.copyWith(
          songIds: c.songIds.where((s) => s != songId).toList(),
        ),
      );

  /// Move a song within a book. [newIndex] is the insertion index *after* the
  /// item is removed — the convention of `ReorderableListView.onReorderItem`.
  void reorderCollection(String collectionId, int oldIndex, int newIndex) =>
      _updateCollection(collectionId, (c) {
        final ids = [...c.songIds];
        if (oldIndex < 0 || oldIndex >= ids.length) return c;
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex.clamp(0, ids.length), moved);
        return c.copyWith(songIds: ids);
      });

  /// The songs in a book, in order, skipping any whose id no longer resolves.
  List<ImportedSong> songsInCollection(String collectionId) {
    final matches = _collections.where((c) => c.id == collectionId);
    if (matches.isEmpty) return const [];
    final book = matches.first;
    final byId = {for (final s in _songs) s.id: s};
    return [
      for (final id in book.songIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  void _updateCollection(String id, SongCollection Function(SongCollection) f) {
    var changed = false;
    final next = <SongCollection>[];
    for (final c in _collections) {
      if (c.id == id) {
        changed = true;
        next.add(f(c));
      } else {
        next.add(c);
      }
    }
    if (!changed) return;
    _collections = next;
    notifyListeners();
    _save();
  }
}
