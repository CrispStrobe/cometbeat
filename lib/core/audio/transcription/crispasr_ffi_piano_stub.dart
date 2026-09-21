// Web / no-dart:io fallback: no CrispASR FFI. Matches the IO signature,
// [CrispasrNoteModel] included — the choice of model is meaningless without the
// native runtime, but the parameter has to exist for the two to be drop-in.

import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show CrispasrNoteModel;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;

Future<NeuralTranscriber?> loadCrispasrPianoFfi({
  bool download = false,
  CrispasrNoteModel model = CrispasrNoteModel.auto,
}) async {
  return null;
}
