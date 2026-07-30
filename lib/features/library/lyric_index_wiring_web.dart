// Web wiring: FTS5 via the WebAssembly build, falling back to the linear scan.
//
// The WASM is fetched lazily from the same dataset as the catalog (748 KB, only
// when someone actually searches lyrics) rather than bundled, and the index is
// built in memory from the already-cached lyrics shard. Both choices are
// explained in `lyric_index_fts_web.dart`.
//
// `directory` is ignored: there is no filesystem here, and persisting a DERIVED
// index through OPFS/IndexedDB would add real complexity for something that
// rebuilds in a couple of seconds from data the app already has.
import 'dart:async';

import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:comet_beat/features/library/lyric_index_fts_web.dart';

FutureOr<LyricIndex> buildLyricIndex(
  Map<String, String> texts, {
  required String version,
  String? directory,
}) async =>
    await Fts5WebLyricIndex.open(texts) ?? LinearLyricIndex(texts);
