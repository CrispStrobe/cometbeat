// Native-ONNX-Runtime ("onnxFfi") providers. Loads the same .onnx models the
// pure-Dart path caches, but runs inference on native ORT (onnxruntime plugin)
// via the OrtFfiSession wrapper, reusing the identical Dart framing/decoding
// (crepeF0WithRunner / rmvpeF0WithRunner). Returns null when the model isn't
// cached OR the native ORT runtime can't load here (headless test / `dart run`)
// — so it's a no-op fallback everywhere except a real app build. dart:io only.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/basic_pitch.dart'
    show basicPitchTranscribeWithRunner;
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/crepe.dart'
    show crepeF0WithRunner;
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator, estimateChordsWithRunner;
import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/transcription/onnx_ort_session.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe.dart'
    show rmvpeF0WithRunner;
import 'package:comet_beat/core/audio/transcription/rmvpe_mel.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;

// Model IO tensor names (mirror the engines' private consts).
const String _crepeIn = 'frames';
const String _crepeOut = 'activation';
const int _crepeWindow = 1024;
const String _rmvpeIn = 'input';
const String _rmvpeOut = 'output';
const String _bpIn = 'serving_default_input_2:0';
const String _bpNoteOut = 'StatefulPartitionedCall:1';
const String _bpOnsetOut = 'StatefulPartitionedCall:2';
const int _bpSamples = 43844;
const String _btcIn = 'cqt';
const String _btcOut = 'chord';
const int _btcTimestep = 108;

/// Native-ORT monophonic F0: RMVPE if its bundle is cached (preferred, matching
/// the pure-Dart onnx path), else CREPE. [download] pulls the model if missing
/// (an explicit backend choice); otherwise used only if already cached. Null ⇒
/// no model or no native ORT here → the resolver falls to the pure-Dart onnx
/// path.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) async =>
    await _rmvpeFfiF0(download: download) ??
    await _crepeFfiF0(download: download);

/// Native-ORT polyphony (Basic Pitch): the same nmp.onnx on native ORT via the
/// basicPitchTranscribeWithRunner seam. Null ⇒ no model / no native ORT here →
/// resolver falls to the pure-Dart onnx Basic Pitch.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) async {
  final bytes = await _basicPitchBytes(download: download);
  if (bytes == null) return null;
  final session = OrtFfiSession.fromBytes(bytes);
  if (session == null) return null; // native ORT not loadable here
  ({Float32List notes, Float32List onsets}) runWindow(Float32List window) {
    final out = session.run(
      _bpIn,
      window,
      [1, _bpSamples, 1],
      const [_bpNoteOut, _bpOnsetOut],
    );
    return (notes: out[_bpNoteOut]!, onsets: out[_bpOnsetOut]!);
  }

  return (Float64List mono, int sampleRate) async =>
      basicPitchTranscribeWithRunner(
        mono,
        sampleRate: sampleRate,
        run: runWindow,
      );
}

/// Native-ORT chords (BTC): the same btc-chord.onnx + CQT on native ORT via the
/// estimateChordsWithRunner seam. Null ⇒ no model / no native ORT → resolver
/// falls to the pure-Dart onnx BTC.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) async {
  final store = HarmonyModelStore();
  if (!download && !store.isPresent()) return null;
  if (download) {
    // ensureFiles() throws if the BTC licence (CC-BY-NC-SA, non-commercial)
    // isn't accepted. This is a best-effort resolver probe, so it must degrade
    // to null (the resolver then falls back / leaves chords off), NOT abort the
    // whole resolve — consent is enforced on the explicit download/UI path.
    try {
      if (!await store.ensureFiles()) return null;
    } catch (_) {
      return null;
    }
  }
  if (!store.isPresent()) return null;
  final Uint8List modelBytes;
  final CqtFilterBank cqt;
  try {
    modelBytes = await store.modelFile().readAsBytes();
    cqt = CqtFilterBank.fromBytes(await store.cqtFile().readAsBytes());
  } catch (_) {
    return null;
  }
  final session = OrtFfiSession.fromBytes(modelBytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runSegment(Float32List segment, int nBins) {
    final out =
        session.run(_btcIn, segment, [1, _btcTimestep, nBins], const [_btcOut]);
    return out[_btcOut]!;
  }

  return (Float64List mono, int sampleRate) async => estimateChordsWithRunner(
        mono,
        cqt: cqt,
        sampleRate: sampleRate,
        run: runSegment,
      );
}

// ── model bytes ──────────────────────────────────────────────────────────────

/// The cached Basic Pitch nmp.onnx bytes (downloading first if [download]), or
/// null.
Future<Uint8List?> _basicPitchBytes({required bool download}) async {
  final store = BasicPitchModelStore();
  final File? file;
  if (download) {
    file = await store.ensureFile();
  } else {
    final cached = store.modelFile();
    file = cached.existsSync() ? cached : null;
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

// ── F0 backends ──────────────────────────────────────────────────────────────

Future<F0Estimator?> _rmvpeFfiF0({required bool download}) async {
  final store = RmvpeModelStore();
  if (!download && !store.isPresent()) return null;
  if (download && !await store.ensureFiles()) return null;
  if (!store.isPresent()) return null;
  final Uint8List modelBytes;
  final RmvpeMel mel;
  try {
    modelBytes = await store.modelFile().readAsBytes();
    mel = RmvpeMel.fromBytes(await store.melFile().readAsBytes());
  } catch (_) {
    return null;
  }
  final session = OrtFfiSession.fromBytes(modelBytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runRmvpe(Float32List input, int nMels, int pf) {
    final out = session.run(_rmvpeIn, input, [1, nMels, pf], const [_rmvpeOut]);
    return out[_rmvpeOut]!;
  }

  return (Float64List mono, int sampleRate) async =>
      rmvpeF0WithRunner(mono, mel: mel, sampleRate: sampleRate, run: runRmvpe);
}

Future<F0Estimator?> _crepeFfiF0({required bool download}) async {
  final bytes = await _crepeBytes(download: download);
  if (bytes == null) return null;
  final session = OrtFfiSession.fromBytes(bytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runCrepe(Float32List frames, int nf) {
    final out =
        session.run(_crepeIn, frames, [nf, _crepeWindow], const [_crepeOut]);
    return out[_crepeOut]!;
  }

  return (Float64List mono, int sampleRate) async =>
      crepeF0WithRunner(mono, sampleRate: sampleRate, run: runCrepe);
}

/// The cached CREPE .onnx bytes (downloading first if [download]), or null.
Future<Uint8List?> _crepeBytes({required bool download}) async {
  final store = CrepeModelStore();
  final File? file;
  if (download) {
    file = await store.ensureFile();
  } else {
    final cached = store.modelFile();
    file = cached.existsSync() ? cached : null;
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
