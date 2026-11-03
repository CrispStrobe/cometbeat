// Web / no-dart:io: no CrispASR, so nothing can be separated. Matches the IO
// signature.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';

export 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';

Future<PracticeSongSplit> splitSongForPractice(
  String path,
  Uint8List bytes, {
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
  bool download = false,
  bool inMemory = false,
  void Function(PracticeSplitPhase phase, double? seconds)? onPhase,
}) =>
    Future.error(StateError('separation'));
