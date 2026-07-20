// lib/core/audio/transcription/crepe.dart
//
// W-CREPE — neural monophonic F0 (CREPE, Kim et al. 2018, MIT) behind the
// `PitchTrack` contract. A timbre-robust alternative to pYIN that fixes the
// sung-voice octave-doubling / drift the pure-Dart chain shows on real singing.
// Runs the CREPE model on `onnx_runtime_dart` (pure Dart, no FFI).
//
// A faithful port of the torchcrepe pipeline: 16 kHz mono, 1024-sample frames
// at a 10 ms hop, each frame mean/std-normalised; the model emits a 360-bin
// pitch activation (20-cent resolution); F0 is the weighted average of bin
// centres around the argmax (torchcrepe `weighted_argmax`), voicing = the peak
// activation. Verified: the exported crepe-tiny ONNX runs on our runtime at
// cosine 1.0 vs onnxruntime; end-to-end F0 matches torchcrepe.
//
// WEB-SAFE: imports only the `onnx_runtime_dart` core and takes a preloaded
// [OnnxModel]. Model download/caching (dart:io) lives in the native
// `crepe_model_store.dart`, so this transcription logic compiles for web too.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

// ── CREPE constants (torchcrepe) ─────────────────────────────────────────────
const int _sr = 16000;
const int _window = 1024;
const int _pitchBins = 360;
const double _centsPerBin = 20;
const double _centsBase = 1997.3794084376191; // cents of bin 0
const String _inName = 'frames';
const String _outName = 'activation';

/// Neural monophonic F0 with CREPE. Resamples [mono] to 16 kHz, frames it
/// (1024 samples, [hopMs] ms hop), runs the [model], and decodes each frame to
/// an F0 + voicing → a [PitchTrack]. Only bins in `[fmin, fmax]` Hz are
/// considered (CREPE defaults 50–2006 Hz). Pure / synchronous / web-safe; the
/// caller supplies a loaded [model] (see `crepe_model_store.dart`).
///
/// This is the single-threaded path. For the isolate-pool path (`runAsync`), see
/// [crepeF0Async] — same math, same output, selected by env in the native
/// `crepe_model_store.dart`.
PitchTrack crepeF0(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  double hopMs = 10,
  double fmin = 50,
  double fmax = 2006,
  int batchFrames = 512,
}) =>
    crepeF0WithRunner(
      mono,
      run: (frames, nf) {
        final act = model.run(
          {
            _inName: Tensor.float(frames, [nf, _window]),
          },
          const [_outName],
        )[_outName]!;
        return act.f ?? act.asFloatList();
      },
      sampleRate: sampleRate,
      hopMs: hopMs,
      fmin: fmin,
      fmax: fmax,
      batchFrames: batchFrames,
    );

/// Runs one batch of `[nFrames, 1024]` normalised frames and returns the flat
/// `[nFrames·360]` activation. This is the ONLY model-runtime coupling in the
/// CREPE chain — supply a runner backed by `onnx_runtime_dart` (pure Dart, the
/// default via [crepeF0]) OR the native ONNX Runtime (the `onnxFfi` backend),
/// and the identical framing/normalisation/decoding runs either way.
typedef CrepeActivationRunner = Float32List Function(
  Float32List frames,
  int nFrames,
);

/// [crepeF0] with the model runtime abstracted behind [run]. Same 16 kHz
/// framing, per-frame normalisation, and `weighted_argmax` decoding as [crepeF0]
/// — only the inference call differs, so the pure-Dart and native-ORT paths
/// stay bit-for-bit identical apart from the backend. [run] receives a freshly
/// copied `[nFrames·1024]` Float32List and must return `[nFrames·360]`.
PitchTrack crepeF0WithRunner(
  Float64List mono, {
  required CrepeActivationRunner run,
  int sampleRate = 44100,
  double hopMs = 10,
  double fmin = 50,
  double fmax = 2006,
  int batchFrames = 512,
}) {
  final p = _prepare(mono, sampleRate, hopMs, fmin, fmax);
  final track = <PitchFrame>[];
  final frameBuf = Float32List(batchFrames * _window);
  for (var f0i = 0; f0i < p.totalFrames; f0i += batchFrames) {
    final nf = math.min(batchFrames, p.totalFrames - f0i);
    final input = _fillBatch(p.padded, p.hop, f0i, nf, frameBuf, batchFrames);
    final af = run(Float32List.fromList(input), nf);
    _decodeBatch(af, nf, f0i, p, track);
  }
  return track;
}

/// Isolate-pool variant of [crepeF0]: identical framing / normalisation /
/// decoding, but inference goes through [OnnxModel.runAsync] so a model that was
/// [OnnxModel.parallelize]d executes its Conv/MatMul on the worker pool. With no
/// prior `parallelize` this behaves exactly like [crepeF0] (just async). The
/// native `crepe_model_store.dart` sets up the pool and picks this path from env
/// (`COMET_CREPE_WORKERS`); results stay bitwise identical to the sync path.
Future<PitchTrack> crepeF0Async(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  double hopMs = 10,
  double fmin = 50,
  double fmax = 2006,
  int batchFrames = 512,
}) async {
  final p = _prepare(mono, sampleRate, hopMs, fmin, fmax);
  final track = <PitchFrame>[];
  final frameBuf = Float32List(batchFrames * _window);
  for (var f0i = 0; f0i < p.totalFrames; f0i += batchFrames) {
    final nf = math.min(batchFrames, p.totalFrames - f0i);
    final input = _fillBatch(p.padded, p.hop, f0i, nf, frameBuf, batchFrames);
    final out = await model.runAsync(
      {
        _inName: Tensor.float(Float32List.fromList(input), [nf, _window]),
      },
      const [_outName],
    );
    final af = out[_outName]!.f ?? out[_outName]!.asFloatList();
    _decodeBatch(af, nf, f0i, p, track);
  }
  return track;
}

/// Shared prep: resample→16 kHz, 512-pad each side, frame count, and the
/// fmin/fmax bin gate. `totalFrames == 0` when the audio is empty (→ empty
/// track).
({Float64List padded, int hop, int totalFrames, int minBin, int maxBin})
    _prepare(
  Float64List mono,
  int sampleRate,
  double hopMs,
  double fmin,
  double fmax,
) {
  final audio =
      sampleRate == _sr ? mono : resampleLinear(mono, sampleRate / _sr);
  final hop = (_sr * hopMs / 1000).round();
  const halfWin = _window ~/ 2;
  final totalFrames = (audio.isEmpty || hop <= 0) ? 0 : 1 + audio.length ~/ hop;
  final padded = Float64List(audio.length + _window)
    ..setRange(halfWin, halfWin + audio.length, audio);
  final (minBin, maxBin) = _binRange(fmin, fmax);
  return (
    padded: padded,
    hop: hop,
    totalFrames: totalFrames,
    minBin: minBin,
    maxBin: maxBin,
  );
}

/// Normalise [nf] frames starting at global frame [start] into [frameBuf];
/// return the `[nf, 1024]` input view (the whole buffer when full).
Float32List _fillBatch(
  Float64List padded,
  int hop,
  int start,
  int nf,
  Float32List frameBuf,
  int batchFrames,
) {
  for (var b = 0; b < nf; b++) {
    _fillNormalizedFrame(padded, (start + b) * hop, frameBuf, b * _window);
  }
  return nf == batchFrames
      ? frameBuf
      : Float32List.sublistView(frameBuf, 0, nf * _window);
}

/// Decode [nf] activation rows and append their PitchFrames (timed from global
/// frame [start]).
void _decodeBatch(
  Float32List af,
  int nf,
  int start,
  ({Float64List padded, int hop, int totalFrames, int minBin, int maxBin}) p,
  List<PitchFrame> track,
) {
  for (var b = 0; b < nf; b++) {
    final (hz, voiced) = _decodeFrame(af, b * _pitchBins, p.minBin, p.maxBin);
    track.add(
      (
        timeMs: (start + b) * p.hop / _sr * 1000.0,
        f0Hz: hz,
        voicedProb: voiced,
      ),
    );
  }
}

/// The `[minBin, maxBin)` pitch-bin range for `[fmin, fmax]` Hz — the frequency
/// gate torchcrepe applies before decoding (floor for min, ceil for max).
(int, int) _binRange(double fmin, double fmax) {
  double freqToCents(double f) => 1200 * math.log(f / 10) / math.ln2;
  double centsToBin(double c) => (c - _centsBase) / _centsPerBin;
  final lo = centsToBin(freqToCents(fmin)).floor().clamp(0, _pitchBins);
  final hi = centsToBin(freqToCents(fmax)).ceil().clamp(0, _pitchBins);
  return (lo, hi);
}

/// Copy `padded[start : start+1024]` into [dst] at [off], mean-centred and
/// scaled by its std (clamped, as torchcrepe does — silent frames blow up, but
/// that is what the network expects).
void _fillNormalizedFrame(
  Float64List padded,
  int start,
  Float32List dst,
  int off,
) {
  var mean = 0.0;
  for (var i = 0; i < _window; i++) {
    mean += padded[start + i];
  }
  mean /= _window;
  var variance = 0.0;
  for (var i = 0; i < _window; i++) {
    final d = padded[start + i] - mean;
    variance += d * d;
  }
  final std = math.max(1e-10, math.sqrt(variance / _window));
  final inv = 1.0 / std;
  for (var i = 0; i < _window; i++) {
    dst[off + i] = (padded[start + i] - mean) * inv;
  }
}

/// Decode one 360-bin activation row (at [base]) to (F0 Hz, voicing). F0 is the
/// weighted average of bin-centre cents over `[argmax-4, argmax+5)` (bounded to
/// `[minBin, maxBin)`), weighted by `sigmoid(activation)` — torchcrepe
/// `weighted_argmax`, which sigmoids the already-sigmoid probabilities. Voicing
/// is the peak activation.
///
/// We deliberately omit torchcrepe's per-weight anti-quantization *dither* (a
/// random ±20-cent triangular noise it adds to trade quantization for noise):
/// a deterministic F0 is what the downstream note-HMM wants. Matches torchcrepe
/// to float precision once its dither is disabled.
(double, double) _decodeFrame(
  Float32List act,
  int base,
  int minBin,
  int maxBin,
) {
  var argmax = minBin, peak = -double.infinity;
  for (var b = minBin; b < maxBin; b++) {
    final v = act[base + b];
    if (v > peak) {
      peak = v;
      argmax = b;
    }
  }
  final start = math.max(0, argmax - 4), end = math.min(_pitchBins, argmax + 5);
  var num = 0.0, den = 0.0;
  for (var b = start; b < end; b++) {
    if (b < minBin || b >= maxBin) continue; // masked out
    final p = 1.0 / (1.0 + math.exp(-act[base + b])); // sigmoid(prob)
    num += (_centsPerBin * b + _centsBase) * p;
    den += p;
  }
  final cents = den > 0 ? num / den : 0.0;
  final hz = 10.0 * math.pow(2.0, cents / 1200.0);
  return (hz, peak.isFinite ? peak.clamp(0.0, 1.0).toDouble() : 0.0);
}

/// Decode a full activation matrix `[nFrames, 360]` to `(f0Hz, voicing)` pairs —
/// exposed so the decoder can be tested against a torchcrepe reference without
/// running the model.
List<(double, double)> decodeCrepeActivation(
  Float32List activation,
  int nFrames, {
  double fmin = 50,
  double fmax = 2006,
}) {
  final (minBin, maxBin) = _binRange(fmin, fmax);
  return [
    for (var f = 0; f < nFrames; f++)
      _decodeFrame(activation, f * _pitchBins, minBin, maxBin),
  ];
}
