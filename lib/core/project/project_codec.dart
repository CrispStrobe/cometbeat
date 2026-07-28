// lib/core/project/project_codec.dart
//
// WS-W1 — a [Project] to JSON and back.
//
// A REGISTRY, NOT A SWITCH. The obvious shape is one `switch (kind)` naming all
// five document types. That shape fails twice. It would drag every mode's
// types into this file — two of them Flutter-bound, so nothing could read a
// project headlessly. And it would make the set of modes closed: a sixth kind,
// or a kind whose codec is not written yet, would mean editing the container's
// codec. So each mode REGISTERS how its document is encoded, and this file
// knows only that a registration exists.
//
// That choice pays for itself immediately, because two kinds have no codec to
// register today:
//
//   * `tab` — `TabDocument` has NO serialization at all. Tab's only persistence
//     is `saveToSongBook`, which goes through MusicXML and drops the tuning,
//     the strings, the frets and every technique, i.e. everything that makes a
//     tab a tab. A lossless codec is its own task (WS-L11).
//   * `audio` — a `DawTimeline` is saveable (`daw_project.dart`) but only with
//     a PCM render callback, which a pure container has no business holding.
//     Its adapter registers from the DAW side, where that callback lives.
//
// UNKNOWN AND UNREGISTERED ARE THE SAME CASE. A kind this build does not know
// and a kind whose codec is not registered both mean "I cannot read this
// document" — and the answer to both is to carry it through VERBATIM rather
// than drop it. That is what makes an older build safe to open a newer file
// with: the track it cannot read is written back exactly as it arrived. Dropping
// would be silent data loss on the second save, which is the worst kind,
// because the file looked fine after the first.
//
// Pure Dart, no Flutter.

import 'dart:convert';

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/audio/tracker_song_codec.dart'
    show trackerSongFromJson, trackerSongToJson;
import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
// The PURE core, not the Flutter `crisp_notation` barrel: MusicXML lives in
// `crisp_notation_core`, so the score kind costs this file nothing in
// dependencies.
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, multiPartScoreFromMusicXml, multiPartToMusicXml;

/// The version WRITTEN.
const int kProjectFormatVersion = 1;

/// Versions that can be READ.
const Set<int> kReadableProjectFormatVersions = {1};

/// How one mode's document becomes JSON and comes back.
///
/// [encode] returns null when this particular document cannot be encoded, which
/// is not an error — the track is then carried as unreadable rather than lost.
/// [decode] returns null on anything it does not recognise, for the same
/// reason: a codec that has moved on should cost editability, never the file.
class ProjectDocumentCodec {
  const ProjectDocumentCodec({
    required this.kind,
    required this.encode,
    required this.decode,
  });

  final AppMode kind;
  final Map<String, dynamic>? Function(Object document) encode;
  final Object? Function(Map<String, dynamic> json) decode;
}

final Map<AppMode, ProjectDocumentCodec> _codecs = {};

/// Registers [codec] for its kind, replacing any previous one.
///
/// Modes whose document types depend on Flutter (or on a render callback)
/// register from their own side — that is the whole point of the registry, and
/// it is why this file names only the three kinds that are pure.
void registerProjectDocumentCodec(ProjectDocumentCodec codec) {
  _codecs[codec.kind] = codec;
}

/// The codec for [kind], or null when nothing has registered one.
ProjectDocumentCodec? projectDocumentCodecFor(AppMode kind) => _codecs[kind];

/// Drops every registration. For tests that need a known starting state — the
/// registry is global, so a test that registers a fake must be able to undo it.
void resetProjectDocumentCodecs() {
  _codecs
    ..clear()
    ..addAll(_builtIn);
}

/// The three kinds whose documents already have a pure-Dart codec.
///
/// Each REUSES the encoder that mode already depends on rather than inventing a
/// second one — the tracker's song JSON, the Loop Studio's `GrooveSpec` (whose
/// JSON is literally its share token), and MusicXML for engraved music. This is
/// the same principle `daw_clip_source_codec.dart` follows: nothing here knows
/// how to encode music, only which encoder owns each kind.
final Map<AppMode, ProjectDocumentCodec> _builtIn = {
  AppMode.tracker: ProjectDocumentCodec(
    kind: AppMode.tracker,
    encode: (doc) =>
        doc is TrackerSong ? {'song': trackerSongToJson(doc)} : null,
    decode: (json) {
      final song = json['song'];
      if (song is! Map) return null;
      return trackerSongFromJson(Map<String, dynamic>.from(song));
    },
  ),
  AppMode.loop: ProjectDocumentCodec(
    kind: AppMode.loop,
    encode: (doc) => doc is GrooveSpec ? {'groove': doc.toJson()} : null,
    decode: (json) {
      final groove = json['groove'];
      if (groove is! Map) return null;
      return GrooveSpec.fromJson(Map<String, dynamic>.from(groove));
    },
  ),
  AppMode.score: ProjectDocumentCodec(
    kind: AppMode.score,
    // MusicXML rather than a private encoding, so a project's music stays
    // openable by every route that accepts a score — including outside the app.
    encode: (doc) =>
        doc is MultiPartScore ? {'musicxml': multiPartToMusicXml(doc)} : null,
    decode: (json) {
      final xml = json['musicxml'];
      if (xml is! String) return null;
      return multiPartScoreFromMusicXml(xml);
    },
  ),
};

bool _seeded = false;

void _ensureSeeded() {
  if (_seeded) return;
  _seeded = true;
  _codecs.addAll(_builtIn);
}

// --- Project → JSON ---------------------------------------------------------

/// [project] as a JSON map.
Map<String, dynamic> projectToJson(Project project) {
  _ensureSeeded();
  return {
    'v': kProjectFormatVersion,
    if (project.name.isNotEmpty) 'name': project.name,
    // Omitted while the tempo never changes AND is the default, so an untouched
    // project stays small and two projects that differ only in tempo still
    // differ in their JSON.
    if (!project.tempo.isConstant || project.tempo.changes.first.bpm != 120)
      'tempo': project.tempo.toJson(),
    'tracks': [for (final track in project.tracks) _trackToJson(track)],
  };
}

Map<String, dynamic> _trackToJson(ProjectTrack track) {
  final out = <String, dynamic>{
    'id': track.id,
    // The STORED name, not the enum's: a kind this build does not know is
    // written back as itself, which is what lets an older build open a newer
    // file, save it, and hand it back intact.
    'kind': track.storedKindName,
    if (track.name.isNotEmpty) 'name': track.name,
    if (!track.mix.isDefault) 'mix': _mixToJson(track.mix),
  };
  // A track this build could not read is written back EXACTLY as it arrived.
  // Re-encoding it from a document we never decoded is not possible, and
  // dropping it would make opening a newer file in an older build a silent
  // delete on the next save.
  if (track.unreadable case final stored?) {
    out['doc'] = stored;
    return out;
  }
  if (track.unknownKind != null) return out;
  final document = track.document;
  if (document == null) return out;
  final codec = _codecs[track.kind];
  final encoded = codec?.encode(document);
  // No codec, or a codec that declined this document: no entry. The track
  // survives with its name, kind and mix — everything except the music, which
  // nothing here can write. `Project.hasUnreadableTracks` is how a caller warns
  // about that BEFORE the save rather than after it.
  if (encoded != null) out['doc'] = encoded;
  return out;
}

Map<String, dynamic> _mixToJson(ProjectTrackMix mix) => {
      if (mix.level != 1.0) 'level': _round(mix.level),
      if (mix.pan != 0.0) 'pan': _round(mix.pan),
      if (mix.muted) 'muted': true,
      if (mix.soloed) 'soloed': true,
    };

double _round(double v) => double.parse(v.toStringAsFixed(3));

/// [project] as a JSON string.
String projectToJsonString(Project project) =>
    jsonEncode(projectToJson(project));

// --- JSON → Project ---------------------------------------------------------

/// Rebuilds a [Project] from [raw], or null when it is not a project at all.
///
/// Null is reserved for "this is not a project file" — a wrong shape or a
/// version this build cannot read. Everything else degrades: a malformed track
/// is skipped, an unknown kind is carried verbatim, an undecodable document is
/// carried verbatim. A project should open.
Project? projectFromJson(Object? raw) {
  _ensureSeeded();
  if (raw is! Map) return null;
  final version = raw['v'];
  if (version is! num ||
      !kReadableProjectFormatVersions.contains(version.toInt())) {
    return null;
  }
  final name = raw['name'];
  final tempo = raw['tempo'];
  final tracksRaw = raw['tracks'];
  return Project(
    name: name is String ? name : '',
    tempo: tempo is List ? TempoMap.fromJson(tempo) : TempoMap.constant(120),
    tracks: [
      if (tracksRaw is List)
        for (final entry in tracksRaw)
          if (_trackFromJson(entry) case final track?) track,
    ],
  );
}

/// The inverse of [projectToJsonString]; null on anything unparseable.
Project? projectFromJsonString(String source) {
  try {
    return projectFromJson(jsonDecode(source));
  } catch (_) {
    return null;
  }
}

ProjectTrack? _trackFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final kindName = raw['kind'];
  if (id is! String || id.isEmpty || kindName is! String) return null;
  final name = raw['name'];
  final mix = _mixFromJson(raw['mix']);
  final storedDoc = raw['doc'];
  final stored = storedDoc is Map ? Map<String, dynamic>.from(storedDoc) : null;
  final kind = appModeByName(kindName);

  // A kind this build does not know. The document is kept verbatim and the
  // stored kind name alongside it, so writing the track back reproduces the
  // file exactly. `kind` is parked on a real value only because it cannot be
  // null; `unknownKind` is what identifies the track and what gets written.
  if (kind == null) {
    return ProjectTrack(
      id: id,
      kind: AppMode.loop,
      name: name is String ? name : '',
      mix: mix,
      unreadable: stored,
      unknownKind: kindName,
    );
  }

  if (stored == null) {
    return ProjectTrack(
      id: id,
      kind: kind,
      name: name is String ? name : '',
      mix: mix,
    );
  }

  Object? document;
  try {
    document = _codecs[kind]?.decode(stored);
  } catch (_) {
    // A codec that rejects its own older output, a truncated entry, a format
    // that moved on — all mean "carry it unread", not "lose the project".
    document = null;
  }
  return ProjectTrack(
    id: id,
    kind: kind,
    name: name is String ? name : '',
    mix: mix,
    document: document,
    unreadable: document == null ? stored : null,
  );
}

ProjectTrackMix _mixFromJson(Object? raw) {
  if (raw is! Map) return const ProjectTrackMix();
  final level = raw['level'];
  final pan = raw['pan'];
  return ProjectTrackMix(
    level: level is num ? level.toDouble().clamp(0.0, 1.0) : 1.0,
    pan: pan is num ? pan.toDouble().clamp(-1.0, 1.0) : 0.0,
    muted: raw['muted'] == true,
    soloed: raw['soloed'] == true,
  );
}
