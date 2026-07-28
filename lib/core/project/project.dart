// lib/core/project/project.dart
//
// WS-W1 — one document, many track kinds.
//
// The app has five editors and five documents, and nothing that can hold more
// than one of them at a time. "The tracker pattern in bar 9" and "the clip on
// the timeline" are the same musical object to a person and two unrelated
// values to the code, which is the first of the three structural gaps in
// docs/WORKSTATION_PARITY.md. This is the container that lets them be one
// thing.
//
// THE RULE THIS FILE EXISTS TO KEEP: a Project WRAPS the mode documents, it
// never absorbs or replaces them. `ProjectTrack.document` holds each mode's
// EXISTING type, untouched — a `TrackerSong` is still a `TrackerSong`, and a
// mode opened without a project behaves exactly as it does today. Every
// alternative (a universal note model, a lowest-common-denominator document)
// loses something from some mode, and the mode that loses is always the one
// whose editor is deepest.
//
// WHY `Object?` AND NOT A SEALED TYPE. A sealed union of the five document
// types would be checked by the compiler, and would drag all five — including
// the two that depend on Flutter — into this file. Then nothing could hold a
// project without Flutter, and a sixth mode could not be added without editing
// the container. The type is recovered at the edges instead: the codec knows
// which decoder owns each kind, and a caller that asked for a tracker track
// casts what it gets. See `project_codec.dart` for how an unknown kind survives.
//
// MIX STATE LIVES HERE, NOT IN THE DOCUMENTS. Level, pan, mute and solo belong
// to a track's place in a project, not to the music on it — the same tracker
// song used twice at different levels is one document and two tracks. Putting
// them in the documents would also mean WS-W5's mixer console has to unpick
// them from four places that each spell them differently.
//
// Pure Dart, no Flutter — deliberately, so a CLI or a headless test can hold a
// project. `AppMode` was moved to its own file to make that possible.

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/interop/app_mode.dart';

/// Where a track sits in the mix: everything that is about the track rather
/// than about the music on it.
///
/// Immutable with value equality, so a project can be compared and a change can
/// be detected without walking documents.
class ProjectTrackMix {
  const ProjectTrackMix({
    this.level = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
  });

  /// 0 = silent … 1 = unity. Not decibels: every mixer in the app is already
  /// linear here, and a project that disagreed would be converting on the way
  /// in and out of five screens.
  final double level;

  /// −1 = hard left … 0 = centre … +1 = hard right.
  final double pan;

  final bool muted;

  /// Solo is stored, not derived. Whether a soloed track silences the others is
  /// a decision for whatever is PLAYING the project — the Loop Studio and the
  /// DAW already answer it differently — so the project records the intent and
  /// leaves the arithmetic to the transport.
  final bool soloed;

  /// True when this is exactly a default mix — the common case, and the one the
  /// codec omits so an untouched project stays small.
  bool get isDefault => level == 1.0 && pan == 0.0 && !muted && !soloed;

  ProjectTrackMix copyWith({
    double? level,
    double? pan,
    bool? muted,
    bool? soloed,
  }) =>
      ProjectTrackMix(
        level: level ?? this.level,
        pan: pan ?? this.pan,
        muted: muted ?? this.muted,
        soloed: soloed ?? this.soloed,
      );

  @override
  bool operator ==(Object other) =>
      other is ProjectTrackMix &&
      other.level == level &&
      other.pan == pan &&
      other.muted == muted &&
      other.soloed == soloed;

  @override
  int get hashCode => Object.hash(level, pan, muted, soloed);

  @override
  String toString() =>
      'ProjectTrackMix(level: $level, pan: $pan, muted: $muted, '
      'soloed: $soloed)';
}

/// One track: a mode's document, plus where it sits in the project.
class ProjectTrack {
  ProjectTrack({
    required this.id,
    required this.kind,
    this.name = '',
    this.document,
    this.mix = const ProjectTrackMix(),
    this.unreadable,
    this.unknownKind,
  });

  /// Stable within a project — referenced by the transport, the mixer and any
  /// future link between tracks. Not a display name: renaming must not break a
  /// reference.
  final String id;

  /// Which editor owns this track's [document].
  final AppMode kind;

  /// What the player calls it. Empty = fall back to the mode's own label, which
  /// is a decision for the UI, not for this file.
  final String name;

  /// The mode's EXISTING document type, unchanged — a `TrackerSong`, a
  /// `GrooveSpec`, a `MultiPartScore`, a `TabDocument`. Null when the track
  /// came from a file this build could not decode; see [unreadable].
  final Object? document;

  final ProjectTrackMix mix;

  /// The `kind` string exactly as it was stored, when it is not an [AppMode]
  /// this build knows.
  ///
  /// Without this the track could not be written back as itself: [kind] has to
  /// hold SOMETHING, so an unknown one is parked on a real value, and only this
  /// remembers what the file actually said. Null for every track whose kind was
  /// understood.
  final String? unknownKind;

  /// The document exactly as it was stored, kept when this build could not
  /// decode it.
  ///
  /// This is what stops a newer project losing data in an older build: the
  /// track is carried through unread and written back out byte-identical
  /// instead of being dropped. A track with an [unreadable] document must be
  /// treated as read-only — editing what you cannot see is how the SECOND save
  /// loses what the first one saved.
  final Map<String, dynamic>? unreadable;

  /// Whether this track's document survived the trip into this build.
  bool get isReadable => unreadable == null && unknownKind == null;

  /// The kind as it will be WRITTEN — the stored string when this build did not
  /// recognise it, so a file round-trips through a build that predates a mode.
  String get storedKindName => unknownKind ?? kind.name;

  ProjectTrack copyWith({
    String? id,
    AppMode? kind,
    String? name,
    Object? document,
    ProjectTrackMix? mix,
  }) =>
      ProjectTrack(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        document: document ?? this.document,
        mix: mix ?? this.mix,
        // Deliberately not carried: a track whose document has been replaced by
        // a live one is no longer the thing that could not be read.
        unreadable: document == null ? unreadable : null,
        unknownKind: document == null ? unknownKind : null,
      );

  @override
  String toString() =>
      'ProjectTrack($id, ${kind.name}${name.isEmpty ? '' : ', "$name"'})';
}

/// One project: the tracks, the tempo, and a name.
///
/// Deliberately thin. It owns no playback, no undo and no rendering — those are
/// WS-W2 and WS-W4, and a container that grew them would be the fourth clock
/// rather than the one clock.
class Project {
  Project({
    this.name = '',
    List<ProjectTrack>? tracks,
    TempoMap? tempo,
  })  : tracks = List<ProjectTrack>.unmodifiable(tracks ?? const []),
        tempo = tempo ?? TempoMap.constant(120);

  final String name;

  /// In display order. Unmodifiable — a project is replaced, not mutated, so a
  /// listener can compare the old and new value.
  final List<ProjectTrack> tracks;

  /// The project's tempo, shared by every surface. A one-entry map is the
  /// ordinary case and means "this tempo throughout".
  final TempoMap tempo;

  /// The track with [id], or null.
  ProjectTrack? track(String id) {
    for (final t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Every track of [kind], in order.
  List<ProjectTrack> tracksOf(AppMode kind) => [
        for (final t in tracks)
          if (t.kind == kind) t,
      ];

  /// True when any track arrived from a file this build could not read — the
  /// signal a caller needs before offering "save", since saving is what would
  /// otherwise be the moment the data is lost.
  bool get hasUnreadableTracks => tracks.any((t) => !t.isReadable);

  /// An id nothing in this project is using, based on [kind].
  String freeTrackId(AppMode kind) {
    final taken = {for (final t in tracks) t.id};
    for (var n = 1;; n++) {
      final id = '${kind.name}-$n';
      if (!taken.contains(id)) return id;
    }
  }

  Project copyWith({
    String? name,
    List<ProjectTrack>? tracks,
    TempoMap? tempo,
  }) =>
      Project(
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
        tempo: tempo ?? this.tempo,
      );

  /// This project with [track] appended.
  Project withTrack(ProjectTrack track) => copyWith(tracks: [...tracks, track]);

  /// This project with the track at [id] replaced by [replacement], or
  /// unchanged when there is no such track.
  Project withTrackReplaced(String id, ProjectTrack replacement) => copyWith(
        tracks: [
          for (final t in tracks)
            if (t.id == id) replacement else t,
        ],
      );

  /// This project without the track at [id].
  Project withoutTrack(String id) => copyWith(
        tracks: [
          for (final t in tracks)
            if (t.id != id) t,
        ],
      );

  @override
  String toString() => 'Project("$name", ${tracks.length} tracks)';
}
