// kokoro_synth.dart — pure-Dart Kokoro-82M TTS runner.
//
// Turns Kokoro phoneme token ids (from `../g2p/g2p_phonemizer.dart`
// `kokoroTokens(...)`) into 24 kHz PCM audio by running the Kokoro-82M ONNX
// graph on `onnx_runtime_dart` — a pure-Dart ONNX interpreter, so this path
// runs on web/WASM with NO dart:ffi and NO native onnxruntime. The whole
// text→phonemes→audio chain is now pure Dart.
//
// CLEAN-ROOM / LICENSE:
//   - Kokoro-82M weights + architecture: Apache-2.0 (`hexgrad/Kokoro-82M`,
//     ONNX export `onnx-community/Kokoro-82M-v1.0-ONNX`).
//   - onnx_runtime_dart: our own package (Apache-2.0 protobuf bindings).
//   - g2p tokens: our own code (see the g2p module headers).
// This runner takes a PRELOADED [OnnxModel] + voice bytes injected by the
// caller (mirroring `basic_pitch.dart`); model download/caching lives in the
// native `kokoro_model_store.dart` (dart:io), kept out of this web-safe file.
//
// I/O contract — verified by loading `onnx-community/Kokoro-82M-v1.0-ONNX` and
// inspecting the graph (NOT guessed):
//   input  `input_ids` : int64  [1, N]   — pad-wrapped token ids [0, …, 0]
//   input  `style`     : float32[1, 256] — the voice reference vector ref_s
//   input  `speed`     : float32[1]      — speaking rate (1.0 = normal)
//   output `waveform`  : float32[T]      — mono PCM @ 24 kHz
//
// Style (ref_s) indexing — matches the canonical onnx-community usage
// (`ref_s = voices[len(tokens)]`, computed on the UNPADDED token list, THEN
// padded with 0 at both ends). Our [kokoroTokens] returns the already-padded
// sequence, so the unpadded length is `tokenIds.length - 2`, and:
//     ref_s = voicePack[ clamp(unpaddedLen, 0, rows-1) ]   (256 floats)
// (The CrispASR ggml port uses len-1; the onnx-community reference graph — the
// one we run here — uses len, so we follow len to match this graph.)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Runs the Kokoro-82M ONNX graph (via [OnnxModel]) to synthesize speech.
class KokoroSynth {
  /// [model] is a preloaded Kokoro ONNX graph (see `kokoro_model_store.dart`
  /// on native, or fetch the bytes yourself on web and use
  /// `OnnxModel.fromBytes`). Tensor names default to the verified graph names
  /// but are overridable for future exports.
  KokoroSynth(
    this.model, {
    this.sampleRate = 24000,
    this.styleDim = 256,
    this.inputIdsName = 'input_ids',
    this.styleName = 'style',
    this.speedName = 'speed',
    this.outputName = 'waveform',
  });

  final OnnxModel model;
  final int sampleRate;
  final int styleDim;
  final String inputIdsName;
  final String styleName;
  final String speedName;
  final String outputName;

  /// Number of style rows available in a [voice] pack of `voice.length` floats.
  int voiceRows(Float32List voice) => voice.length ~/ styleDim;

  /// Select the reference style vector ref_s (256 floats) for a pad-wrapped
  /// [tokenIds] sequence from a [voice] pack (`rows × styleDim` float32).
  ///
  /// Index = unpadded token count (`tokenIds.length - 2`), clamped to the pack.
  Float32List selectRefS(List<int> tokenIds, Float32List voice) {
    final rows = voiceRows(voice);
    if (rows <= 0) {
      throw ArgumentError('voice pack has no rows (length ${voice.length} is '
          'not a multiple of styleDim $styleDim)');
    }
    // Pad-wrap adds one pad id at each end; the reference indexes by the
    // unpadded phoneme count. Guard sequences shorter than the wrap.
    final unpadded =
        tokenIds.length >= 2 ? tokenIds.length - 2 : tokenIds.length;
    final idx = unpadded.clamp(0, rows - 1);
    return Float32List.fromList(
      voice.sublist(idx * styleDim, idx * styleDim + styleDim),
    );
  }

  /// Synthesize mono PCM (float32 @ [sampleRate]) for the pad-wrapped
  /// [tokenIds] (from `kokoroTokens(...)`) using the reference [voice] pack.
  ///
  /// [speed] scales the predicted durations (1.0 = normal; >1 faster).
  /// Throws [ArgumentError] on empty tokens / malformed voice, [StateError] if
  /// the graph yields no `waveform`.
  Float32List synthesize(
    List<int> tokenIds, {
    required Float32List voice,
    double speed = 1.0,
  }) {
    if (tokenIds.isEmpty) {
      throw ArgumentError('tokenIds is empty');
    }
    final refS = selectRefS(tokenIds, voice);
    final ids = Int64List.fromList(tokenIds);

    final out = model.run(
      {
        inputIdsName: Tensor.int64(ids, [1, tokenIds.length]),
        styleName: Tensor.float(refS, [1, styleDim]),
        speedName: Tensor.float(Float32List.fromList([speed]), [1]),
      },
      [outputName],
    );
    final wave = out[outputName];
    if (wave == null) {
      throw StateError('Kokoro graph produced no "$outputName" output');
    }
    // asFloatList upcasts fp16 outputs and flattens any [1, T] wrapper.
    return wave.asFloatList();
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

  /// Reinterpret raw little-endian float32 voice-pack bytes (e.g. an
  /// `af_heart.bin` of `rows × 256 × 4` bytes) as a [Float32List]. Copies so the
  /// result is independent of the source [bytes]' backing store/alignment.
  static Float32List voiceFromBytes(Uint8List bytes) {
    final n = bytes.lengthInBytes ~/ 4;
    final out = Float32List(n);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}
