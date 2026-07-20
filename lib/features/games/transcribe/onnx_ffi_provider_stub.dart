// Web / no-dart:io fallback: no native ORT ⇒ every onnxFfi loader is null.
// Signatures mirror onnx_ffi_provider_io.dart.

import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;

Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) async => null;
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) async =>
    null;
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) async =>
    null;
