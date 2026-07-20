// Native RMVPE provider: load the ONNX + mel bundle (download-on-demand) and
// wrap rmvpeF0 as an F0Estimator. dart:io only — reached solely through
// rmvpe_provider.dart's conditional import.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/rmvpe.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

/// An RMVPE-backed [F0Estimator], or null. With [download] false, returns
/// non-null only if the (~300 MB) bundle is already cached; true fetches it.
/// Null on any failure so the caller falls back to CREPE/pYIN.
Future<F0Estimator?> loadRmvpeF0Estimator({bool download = false}) async {
  try {
    final store = RmvpeModelStore();
    if (!download && !store.isPresent()) return null;
    final bundle = await store.load();
    return (Float64List mono, int sampleRate) => rmvpeF0(
          mono,
          model: bundle.model,
          mel: bundle.mel,
          sampleRate: sampleRate,
        );
  } on Object {
    return null;
  }
}

bool rmvpeModelPresent() => RmvpeModelStore().isPresent();
