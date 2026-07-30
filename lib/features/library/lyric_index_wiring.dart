// Picks the lyric-index implementation at compile time. Import THIS, never the
// _io / _web halves — importing those directly drags `dart:io` (or excludes the
// native path) onto the wrong platform and breaks the build.
//
// Native: SQLite FTS5, persisted per catalog version.
// Web:    SQLite FTS5 via WebAssembly, in memory.
// Either: falls back to a linear scan when SQLite will not load, so the feature
//         degrades in speed and never in availability.
import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:comet_beat/features/library/lyric_index_wiring_web.dart'
    if (dart.library.io) 'package:comet_beat/features/library/lyric_index_wiring_io.dart';

export 'package:comet_beat/features/library/lyric_index.dart';

/// Installs the platform implementation as the default. Idempotent; call it
/// before the first lyric search (the catalog source does).
void installLyricIndexBackend() {
  defaultLyricIndexBuilder = buildLyricIndex;
}
