// lib/core/interop/app_mode.dart
//
// The five top-level authoring modes, on their own.
//
// This enum used to live in `project_bridge.dart`, which is where it is still
// imported from — that file `export`s this one, so every existing call site is
// unchanged. It was moved because of a dependency, not a tidiness urge:
// `project_bridge.dart` imports `package:crisp_notation/…`, which depends on
// Flutter, so anything naming a mode inherited Flutter with it. `Project`
// (WS-W1) is specified as pure Dart and has to name modes, so the name had to
// be reachable without the rest.
//
// Pure Dart, no Flutter, no imports at all — keep it that way. The moment this
// file needs an import is the moment something that is not a mode has been put
// in it.

/// The five top-level authoring modes (see PLAN.md, "Five-mode product
/// architecture").
///
/// The `name` of each value is an ON-DISK string (project files, clip source
/// tags): add values, never rename them.
enum AppMode {
  /// Pattern matrix, channels, effect commands. Document: `TrackerSong`.
  tracker,

  /// Loops of symbolic events. Document: `List<PatternCell>` (one track).
  loop,

  /// Conventional notation. Document: `MultiPartScore`.
  score,

  /// Strings, frets, fingering. Document: `TabDocument`.
  tab,

  /// The DAW. Reached by BOUNCING — see `ProjectBridge.canConvert`.
  audio,
}

/// A short user-facing name for a mode.
///
/// Deliberately NOT localized: these are the product's own mode names, the same
/// in every language, and the same strings the docs use.
String appModeLabel(AppMode mode) => switch (mode) {
      AppMode.tracker => 'Tracker',
      AppMode.loop => 'Loop Studio',
      AppMode.score => 'Score',
      AppMode.tab => 'Tab',
      AppMode.audio => 'Audio',
    };

/// The mode whose [AppMode.name] is [name], or null for anything else.
///
/// Null rather than a throw or a default: a stored mode name that this build
/// does not know is a file from a newer version, and the caller's job is to
/// preserve it, not to guess which mode was meant.
AppMode? appModeByName(String? name) {
  for (final mode in AppMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}
