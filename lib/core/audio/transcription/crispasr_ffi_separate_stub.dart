// Web / no-dart:io fallback: no CrispASR FFI. Matches the IO signatures.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;

export 'package:comet_beat/core/audio/transcription/separated_stem.dart';

Future<bool> crispasrSeparatorAvailable(
  CrispasrSeparatorModel model, {
  bool download = false,
}) async =>
    false;

Future<List<SeparatedStem>?> separateStereoCrispasr(
  Float32List left,
  Float32List right,
  int sampleRate, {
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
  bool download = false,
}) async =>
    null;

Future<Separator?> loadCrispasrFfiSeparator({
  bool download = false,
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
}) async =>
    null;

bool crispasrSeparatorSupported(CrispasrSeparatorModel model) => false;
