// Web / no-dart:io fallback: no CrispASR FFI. Matches the IO signatures.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/beat_grid.dart';

export 'package:comet_beat/core/audio/transcription/beat_grid.dart';

Future<bool> crispasrBeatsAvailable({bool download = false}) async => false;

Future<BeatGrid?> crispasrBeatGrid(
  Float64List mono,
  int sampleRate, {
  bool download = false,
}) async =>
    null;
