// piper_synth.dart — pure-Dart Piper VITS TTS runner.
//
// Turns Piper phoneme ids (see `piper_phonemes.dart`) into PCM audio by running
// a Piper VITS ONNX graph on `onnx_runtime_dart` — a pure-Dart ONNX interpreter,
// so this runs on web/WASM with NO dart:ffi and NO native onnxruntime.
//
// WHY PIPER (vs Kokoro): Piper is a single end-to-end VITS graph (no separate
// LSTM/iSTFT vocoder stage), which measured ~4–15× faster than Kokoro on our
// pure-Dart runtime. It is still not real-time-interactive on the web, so the
// intended use is PRE-RENDERED narration (render fixed text once, cache the PCM).
//
// CLEAN-ROOM / LICENSE:
//   - Piper (rhasspy/piper): MIT — code + the VITS architecture.
//   - Voices: pick CC0/PD packs (see `piper_voice_store.dart`).
//   - onnx_runtime_dart: our own package (Apache-2.0 protobuf bindings).
// This runner takes a PRELOADED [OnnxModel]; model/voice download+caching lives
// in the native `piper_voice_store.dart` (dart:io), kept out of this web-safe
// file (mirrors `basic_pitch.dart` / `KokoroSynth`).
//
// I/O contract — verified by loading a Piper voice graph and inspecting it:
//   input  `input`         : int64  [1, N] — phoneme ids (BOS/pad/EOS-wrapped)
//   input  `input_lengths` : int64  [1]    — N
//   input  `scales`        : float32[3]    — [noiseScale, lengthScale, noiseW]
//   output `output`        : float32[1,1,T]— mono PCM at the voice's sample_rate
//                                            (per-voice, e.g. 16000 or 22050 Hz)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Runs a Piper VITS ONNX graph (via [OnnxModel]) to synthesize speech.
class PiperSynth {
  /// [model] is a preloaded Piper voice graph. [sampleRate] is the voice's
  /// output rate from its `.onnx.json` (`audio.sample_rate`) — it varies per
  /// voice, so pass the right value (default 22050). Tensor names default to
  /// the verified graph names but are overridable.
  PiperSynth(
    this.model, {
    this.sampleRate = 22050,
    this.inputName = 'input',
    this.inputLengthsName = 'input_lengths',
    this.scalesName = 'scales',
    this.outputName = 'output',
  });

  final OnnxModel model;

  /// Output sample rate (Hz) of this voice; also the rate of [synthesize]'s PCM.
  final int sampleRate;
  final String inputName;
  final String inputLengthsName;
  final String scalesName;
  final String outputName;

  /// Synthesize mono PCM (float32 @ [sampleRate]) for [phonemeIds] (from
  /// `piperPhonemeIds(...)`, already BOS/pad/EOS-wrapped).
  ///
  /// [noiseScale]/[lengthScale]/[noiseW] are Piper's VITS inference scales
  /// (defaults are the standard Piper values; larger [lengthScale] = slower
  /// speech). Throws [ArgumentError] on empty input, [StateError] if the graph
  /// yields no output.
  Float32List synthesize(
    List<int> phonemeIds, {
    double noiseScale = 0.667,
    double lengthScale = 1.0,
    double noiseW = 0.8,
  }) {
    if (phonemeIds.isEmpty) {
      throw ArgumentError('phonemeIds is empty');
    }
    final n = phonemeIds.length;
    final out = model.run(
      {
        inputName: Tensor.int64(Int64List.fromList(phonemeIds), [1, n]),
        inputLengthsName: Tensor.int64(Int64List.fromList([n]), [1]),
        scalesName: Tensor.float(
          Float32List.fromList([noiseScale, lengthScale, noiseW]),
          [3],
        ),
      },
      [outputName],
    );
    final wave = out[outputName];
    if (wave == null) {
      throw StateError('Piper graph produced no "$outputName" output');
    }
    // asFloatList flattens the [1, 1, T] output to T samples.
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
}
