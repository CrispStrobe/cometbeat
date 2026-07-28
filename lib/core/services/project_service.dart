// lib/core/services/project_service.dart
//
// WS-W1b — the thing that owns the app's one [Project].
//
// WHY THIS EXISTS. `WS-W1` built an excellent container and nothing ever made
// one: a grep for `Project(` outside `lib/core/project/` returns only the Audio
// Editor's unrelated `.cbdaw` save/load, and `registerTabProjectCodec()` — whose
// own comment says "call once at start-up" — was never called, so even a working
// codec was dead. The container was inert in exactly the way the shared
// count-in turned out to be. `WS-X1` (live links), `WS-W5` (the mixer console)
// and `WS-W6` (the browser) all assume a Project instance exists, so none of
// them could start.
//
// WHAT IT DELIBERATELY IS NOT. Not a document model — `Project` is that, and it
// stays pure Dart. Not a second place to keep a mode's state: a track holds the
// mode's OWN document type, unchanged, exactly as W1 designed. This is
// ownership, notification and the small set of mutations a UI needs, and
// nothing else.
//
// EVERY MUTATION REPLACES THE PROJECT. `Project` is immutable and its
// `withTrack` / `withTrackReplaced` / `withoutTrack` return copies, so this
// holds a reference and swaps it. That is what makes an undo entry (WS-W4) a
// one-liner: capture the old project, restore it.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:flutter/foundation.dart';

class ProjectService extends ChangeNotifier {
  ProjectService({Project? project})
      : _project = project ?? Project(name: 'Untitled');

  Project _project;
  Project get project => _project;

  /// Replaces the whole project — opening a file, or an undo restoring one.
  set project(Project value) {
    if (identical(_project, value)) return;
    _project = value;
    notifyListeners();
  }

  String get name => _project.name;
  List<ProjectTrack> get tracks => _project.tracks;
  ProjectTrack? track(String id) => _project.track(id);
  List<ProjectTrack> tracksOf(AppMode kind) => _project.tracksOf(kind);

  /// Whether any track could not be read back — a newer file opened by an older
  /// build. Worth asking BEFORE saving, which is why W1 exposes it.
  bool get hasUnreadableTracks => _project.hasUnreadableTracks;

  void rename(String value) {
    if (value == _project.name) return;
    project = _project.copyWith(name: value);
  }

  /// Adds a track holding [document] — the mode's own type, unchanged.
  ///
  /// Returns the id it was given, because the caller almost always needs it
  /// immediately (to select the track, or to record an undo against it) and
  /// re-deriving it from the list is a race with anything else adding one.
  String addTrack({
    required AppMode kind,
    required Object? document,
    String? name,
    String? id,
  }) {
    final trackId = id ?? _project.freeTrackId(kind);
    project = _project.withTrack(
      ProjectTrack(
        id: trackId,
        kind: kind,
        name: name ?? trackId,
        document: document,
      ),
    );
    return trackId;
  }

  /// Swaps a track's document in place, keeping its id, name and mix.
  ///
  /// This is the seam `WS-X1` (live links) needs: "open in Tracker, edit, come
  /// back" is exactly this call, and it is why the mix lives on the track
  /// rather than inside the document — a returning edit must not silently reset
  /// the level and pan.
  bool updateDocument(String id, Object? document) {
    final existing = _project.track(id);
    if (existing == null) return false;
    // Built directly rather than through `copyWith`, which resolves its
    // document as `document ?? this.document` and therefore cannot CLEAR one —
    // `updateDocument(id, null)` would silently keep the old document, which is
    // the sort of no-op that gets debugged twice.
    project = _project.withTrackReplaced(
      id,
      ProjectTrack(
        id: existing.id,
        kind: existing.kind,
        name: existing.name,
        document: document,
        mix: existing.mix,
        unknownKind: existing.unknownKind,
        unreadable: existing.unreadable,
      ),
    );
    return true;
  }

  bool updateTrack(String id, ProjectTrack replacement) {
    if (_project.track(id) == null) return false;
    project = _project.withTrackReplaced(id, replacement);
    return true;
  }

  bool removeTrack(String id) {
    if (_project.track(id) == null) return false;
    project = _project.withoutTrack(id);
    return true;
  }

  /// Starts a new, empty project.
  void reset({String name = 'Untitled'}) => project = Project(name: name);

  // ------------------------------------------------------------ persistence

  String toJsonString() => projectToJsonString(_project);

  /// Loads [source], returning whether it parsed.
  ///
  /// A false return leaves the current project untouched rather than clearing
  /// it — losing the open project to a bad file would be the worst possible
  /// response to one.
  bool loadJsonString(String source) {
    final loaded = projectFromJsonString(source);
    if (loaded == null) return false;
    project = loaded;
    return true;
  }
}
