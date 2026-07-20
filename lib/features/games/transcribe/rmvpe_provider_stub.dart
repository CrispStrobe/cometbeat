// Web / no-dart:io fallback: no RMVPE. Signature must match the IO impl.

import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

Future<F0Estimator?> loadRmvpeF0Estimator({bool download = false}) async =>
    null;

bool rmvpeModelPresent() => false;
