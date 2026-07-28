// lib/core/services/project_store.dart
//
// WS-W6 slice 1 — where a [Project] lives when the app is not running.
//
// WHY THIS EXISTS. `ProjectService` (WS-W1b) owns the app's one project and can
// turn it into a string and back — and nothing ever called either method, so
// closing the app lost the project. That is the same inert-container pattern
// W1b itself described one level down ("W1 built an excellent container and
// nothing ever made one"), repeated at the next level: W1b made one, and
// nothing kept it. Every remaining shell item assumes projects that survive a
// restart.
//
// The shape follows `GrooveSlotsService`, which has done exactly this job for
// groove tokens since the Loop Mixer shipped: SharedPreferences, a named list,
// newest first. Same idea, one level up — a project rather than one groove.
//
// TWO THINGS THIS DELIBERATELY DOES NOT DO:
//
//   * It does not hold the live project. `ProjectService` does, and a store
//     that also held one would be a second source of truth for the question
//     "what am I editing".
//   * It does not merge. Saving under an existing name REPLACES that entry,
//     because a project is one document and "merge two versions of it" is a
//     question no part of this app can answer.

import 'dart:convert';

import 'package:comet_beat/core/project/project.dart';
import 'package:comet_beat/core/project/project_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved project: a name, when it was last written, and its JSON.
///
/// The JSON is kept as a STRING rather than a decoded `Project` so that listing
/// is cheap and a single unreadable entry cannot break the list. Decoding
/// happens only when one is actually opened.
class SavedProject {
  const SavedProject({
    required this.name,
    required this.savedAtMs,
    required this.json,
  });

  final String name;

  /// Milliseconds since the epoch, so the list can be newest-first without
  /// storing an order that a second device would disagree with.
  final int savedAtMs;

  final String json;

  Map<String, dynamic> toJson() => {
        'name': name,
        'at': savedAtMs,
        'p': json,
      };

  /// Null for anything that is not an entry — a hand-edited preference, or one
  /// written by a newer build. Skipped rather than throwing: one bad row must
  /// not cost the whole list.
  static SavedProject? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final json = raw['p'];
    if (name is! String || name.isEmpty || json is! String) return null;
    final at = raw['at'];
    return SavedProject(
      name: name,
      savedAtMs: at is num ? at.toInt() : 0,
      json: json,
    );
  }
}

/// Saved projects, newest first.
class ProjectStore {
  ProjectStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'projects_v1';

  /// How many are kept. A cap rather than unbounded growth because these live
  /// in SharedPreferences, which is not a database — and because a list nobody
  /// can scroll is not a browser. The OLDEST is dropped, never the newest.
  static const maxProjects = 30;

  /// Every saved project, newest first. Never throws: a corrupt store reads as
  /// empty, which is recoverable, where a throw at start-up is not.
  List<SavedProject> list() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SavedProject>[
        for (final entry in decoded)
          if (SavedProject.fromJson(entry) case final saved?) saved,
      ];
      out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// The entry called [name], or null.
  SavedProject? find(String name) {
    for (final saved in list()) {
      if (saved.name == name) return saved;
    }
    return null;
  }

  /// Writes [project] under [name], replacing any entry with that name.
  ///
  /// [nowMs] is injected rather than read from the clock so a test can assert
  /// ordering without sleeping.
  Future<List<SavedProject>> save(
    String name,
    Project project, {
    int? nowMs,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return list();
    final entry = SavedProject(
      name: trimmed,
      savedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      json: projectToJsonString(project),
    );
    final kept = [
      entry,
      for (final saved in list())
        if (saved.name != trimmed) saved,
    ]..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    return _write(
      kept.length > maxProjects ? kept.sublist(0, maxProjects) : kept,
    );
  }

  /// Removes [name] if it is there.
  Future<List<SavedProject>> delete(String name) => _write([
        for (final saved in list())
          if (saved.name != name) saved,
      ]);

  /// Renames [from] to [to], keeping its saved-at time.
  ///
  /// Refused when [to] is blank or already taken: silently overwriting somebody
  /// else's save because two names collided is the kind of data loss that is
  /// only noticed much later.
  Future<bool> rename(String from, String to) async {
    final target = to.trim();
    if (target.isEmpty || target == from) return false;
    final entries = list();
    if (!entries.any((s) => s.name == from)) return false;
    if (entries.any((s) => s.name == target)) return false;
    await _write([
      for (final saved in entries)
        if (saved.name == from)
          SavedProject(
            name: target,
            savedAtMs: saved.savedAtMs,
            json: saved.json,
          )
        else
          saved,
    ]);
    return true;
  }

  /// The project stored under [name], decoded, or null when there is none or it
  /// cannot be read by this build.
  Project? open(String name) {
    final saved = find(name);
    if (saved == null) return null;
    return projectFromJsonString(saved.json);
  }

  Future<List<SavedProject>> _write(List<SavedProject> entries) async {
    await _prefs.setString(
      _key,
      jsonEncode([for (final saved in entries) saved.toJson()]),
    );
    return entries;
  }
}
