// Web / no-dart:io fallback: no neural chord model. Signature must match the IO.

import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;

Future<ChordEstimator?> loadHarmonyEstimator({bool download = false}) async =>
    null;

bool harmonyModelPresent() => false;
