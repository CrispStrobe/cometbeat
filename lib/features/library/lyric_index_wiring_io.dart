// Native wiring: try FTS5, fall back to the linear scan.
import 'dart:async';

import 'package:comet_beat/features/library/lyric_index.dart';
import 'package:comet_beat/features/library/lyric_index_fts.dart';

FutureOr<LyricIndex> buildLyricIndex(
  Map<String, String> texts, {
  required String version,
  String? directory,
}) async =>
    await Fts5LyricIndex.open(texts, version: version, directory: directory) ??
    LinearLyricIndex(texts);
