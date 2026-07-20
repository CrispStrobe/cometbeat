// Native BTC chord provider: load the ONNX + CQT bundle (download-on-demand) and
// wrap estimateChords as a ChordEstimator. dart:io only — reached solely through
// harmony_provider.dart's conditional import.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';

/// A BTC-backed [ChordEstimator], or null. With [download] false, returns
/// non-null only if the model+CQT are already cached; true fetches them. Null on
/// any failure so the caller carries no chords.
Future<ChordEstimator?> loadHarmonyEstimator({bool download = false}) async {
  try {
    final store = HarmonyModelStore();
    if (!download && !store.isPresent()) return null;
    final bundle = await store.load();
    return (Float64List mono, int sampleRate) async => estimateChords(
          mono,
          model: bundle.model,
          cqt: bundle.cqt,
          sampleRate: sampleRate,
        );
  } on Object {
    return null;
  }
}

bool harmonyModelPresent() => HarmonyModelStore().isPresent();
