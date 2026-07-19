// Native provider: load the HTDemucs ONNX (download-on-demand) and wrap it as a
// stems.dart Separator. dart:io only — reached solely through
// separator_provider.dart's conditional import, so web never compiles it.

import 'package:comet_beat/core/audio/transcription/separate.dart';
import 'package:comet_beat/core/audio/transcription/separate_model_store.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;

/// A HTDemucs-backed [Separator], or null.
///
/// With [download] false, returns non-null only if the model is already cached
/// (no network). With [download] true, fetches it first. Null on any failure so
/// the caller falls back to a single-part transcription.
Future<Separator?> loadSeparator({bool download = false}) async {
  try {
    final store = DemucsModelStore();
    if (!download && !store.isPresent()) return null;
    final model =
        await store.load(); // downloads if missing (throws if it can't)
    return demucsSeparator(model);
  } on Object {
    return null;
  }
}

/// Whether the separation model is already on disk, without touching the network.
bool separatorModelPresent() => DemucsModelStore().isPresent();
