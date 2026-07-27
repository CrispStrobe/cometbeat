// onnx_ort_tts.dart — Piper VITS TTS runner over NATIVE ONNX Runtime (the
// `onnxruntime` FFI plugin, GPU-capable), the runtime twin of `piper_synth.dart`.
//
// Same I/O contract, g2p, vocab and phoneme-id sequence as the pure-Dart
// `PiperSynth` (see `piper/piper_synth.dart`) — the ONLY difference is the
// runtime: this feeds the graph through [OrtFfiSession.runMulti] instead of the
// pure-Dart `onnx_runtime_dart` interpreter. That makes it native-only and fast
// (hardware execution providers), so it's the `onnxFfi` TtsEngine's synth.
//
// This file stays pure of Flutter and of dart:io/ffi: it speaks only to the
// [OrtFfiSession] facade (`transcription/onnx_ort_session.dart`), which is itself
// conditional-imported — web/`dart run` get the null stub (whose `runMulti`
// returns nothing), native gets the real ORT wrapper. Model bytes are loaded by
// the backend (see `onnx_ort_tts_backend.dart`), which is where dart:io lives.
//
// I/O contract (identical to PiperSynth, verified against Piper voice graphs):
//   input  `input`         : int64  [1, N] — phoneme ids (BOS/pad/EOS-wrapped)
//   input  `input_lengths` : int64  [1]    — N
//   input  `scales`        : float32[3]    — [noiseScale, lengthScale, noiseW]
//   output `output`        : float32[1,1,T]— mono PCM at the voice's sample_rate
//
// CLEAN-ROOM / LICENSE: onnxruntime plugin MIT; Piper (code + VITS arch) MIT;
// CC0 voices (see `piper/piper_voice_store.dart`); g2p/id-shaping ours.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/onnx_ort_session.dart';

/// Runs a Piper VITS ONNX graph through the native ORT [OrtFfiSession] to
/// synthesize speech. Mirrors `PiperSynth`'s surface; only the runtime differs.
class OnnxOrtTtsSynth {
  /// [session] is a preloaded Piper voice graph (via [OrtFfiSession.fromBytes]).
  /// [sampleRate] is the voice's output rate from its `.onnx.json`
  /// (`audio.sample_rate`) — it varies per voice, so pass the right value.
  /// Tensor names default to the verified graph names but are overridable.
  OnnxOrtTtsSynth(
    this.session, {
    this.sampleRate = 22050,
    this.inputName = 'input',
    this.inputLengthsName = 'input_lengths',
    this.scalesName = 'scales',
    this.outputName = 'output',
  });

  final OrtFfiSession session;

  /// Output sample rate (Hz) of this voice; also the rate of [synthesize]'s PCM.
  final int sampleRate;
  final String inputName;
  final String inputLengthsName;
  final String scalesName;
  final String outputName;

  /// Build the mixed-type input map for [phonemeIds] + VITS scales, shaped
  /// exactly as the Piper graph expects. Pure + static (no ORT session needed) —
  /// the unit-testable core of [synthesize]: `input`/`input_lengths` are int64,
  /// `scales` is float32. Tensor names default to the verified graph names.
  static Map<String, ({List<num> data, List<int> shape, bool int64})>
      buildInputs(
    List<int> phonemeIds, {
    String inputName = 'input',
    String inputLengthsName = 'input_lengths',
    String scalesName = 'scales',
    double noiseScale = 0.667,
    double lengthScale = 1.0,
    double noiseW = 0.8,
  }) {
    final n = phonemeIds.length;
    return {
      inputName: (data: phonemeIds, shape: [1, n], int64: true),
      inputLengthsName: (data: [n], shape: [1], int64: true),
      scalesName: (
        data: [noiseScale, lengthScale, noiseW],
        shape: [3],
        int64: false,
      ),
    };
  }

  /// Synthesize mono PCM (float32 @ [sampleRate]) for [phonemeIds] (from
  /// `piperPhonemeIds(...)`, already BOS/pad/EOS-wrapped).
  ///
  /// Throws [ArgumentError] on empty input, [StateError] if the graph yields no
  /// output (e.g. the native ORT stub, or a bad model).
  Float32List synthesize(
    List<int> phonemeIds, {
    double noiseScale = 0.667,
    double lengthScale = 1.0,
    double noiseW = 0.8,
  }) {
    if (phonemeIds.isEmpty) {
      throw ArgumentError('phonemeIds is empty');
    }
    final out = session.runMulti(
      buildInputs(
        phonemeIds,
        inputName: inputName,
        inputLengthsName: inputLengthsName,
        scalesName: scalesName,
        noiseScale: noiseScale,
        lengthScale: lengthScale,
        noiseW: noiseW,
      ),
      [outputName],
    );
    final wave = out[outputName];
    if (wave == null || wave.isEmpty) {
      throw StateError('ORT Piper graph produced no "$outputName" output');
    }
    // runMulti already flattens the [1, 1, T] output to T samples.
    return wave;
  }

  /// Root-mean-square level of a PCM buffer — a cheap non-silence check.
  static double rms(Float32List pcm) {
    if (pcm.isEmpty) return 0;
    var sum = 0.0;
    for (final s in pcm) {
      sum += s * s;
    }
    return math.sqrt(sum / pcm.length);
  }
}
