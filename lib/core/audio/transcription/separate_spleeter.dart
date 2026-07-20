// lib/core/audio/transcription/separate_spleeter.dart
//
// W-SEP (full 4-stem) — Deezer **Spleeter** source separation (MIT), the
// spectrogram-domain multi-stem separator that completes Tier-2 #4. Where
// `separate_umx.dart` (Open-Unmix) isolates ONLY vocals, Spleeter splits the
// whole mix into vocals / drums / bass / other (4stems) — or vocals /
// accompaniment (2stems) — so `transcribeStems` (stems.dart) can route each stem
// to the right engine and assemble a full multi-part score. Runs on
// `onnx_runtime_dart`.
//
// Model: Deezer's TF Spleeter exported to ONNX (one all-conv U-Net per stem —
// 7 Conv + 6 ConvTranspose + BatchNorm + LeakyRelu + a Sigmoid mask; NO RNN, so
// every op is already supported). Same export used by sherpa-onnx; this port
// reproduces sherpa's pipeline exactly (verified to the knf reference).
//
// Pipeline (per channel; the app's Separator seam is mono → duplicated to the
// model's 2 channels):
//   resample→44.1 kHz → STFT (n_fft 4096, hop 1024, Hann, **center=false**,
//   stft.dart) → magnitude of the first 1024 freq bins, padded to a multiple of
//   512 frames, packed [2, num_splits, 512, 1024] → each stem model → estimated
//   magnitude → **power-ratio (Wiener) soft mask** normalised across the stems
//   → apply to the mix's complex STFT (bins ≥1024 masked to zero) → iSTFT.
//
// PERF: ~2.3× realtime PER STEM (all-conv; the isolate pool gives no benefit at
// these conv shapes) — ~1.7× RT for all four. Heavy, opt-in, native-only.
//
// WEB-SAFE: takes preloaded [OnnxModel]s; the model downloads (dart:io) live in
// `separate_spleeter_model_store.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:comet_beat/core/audio/transcription/stft.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int spleeterSampleRate = 44100;
const int _nFft = 4096;
const int _hop = 1024;
const int _bins = 1024; // the network sees only the first 1024 freq bins
const int _chunk = 512; // frames per patch (the model's fixed time dim)
const String _inName = 'x';
const String _outName = 'y';

/// Power-ratio (Wiener) soft masks: `mask_i = (spec_i² + eps/N) / (Σ spec_j² +
/// eps)`, matching Spleeter/sherpa. [specs] are the per-stem estimated
/// magnitudes (identical length/layout); returns masks in the same layout. The
/// pure, testable core of the separation.
List<Float64List> spleeterMasks(List<Float32List> specs, {double eps = 1e-10}) {
  final n = specs.length;
  assert(n > 0);
  final len = specs.first.length;
  final sum = Float64List(len);
  for (final s in specs) {
    for (var i = 0; i < len; i++) {
      final v = s[i].toDouble();
      sum[i] += v * v;
    }
  }
  final epsN = eps / n;
  return [
    for (final s in specs)
      () {
        final m = Float64List(len);
        for (var i = 0; i < len; i++) {
          final v = s[i].toDouble();
          m[i] = (v * v + epsN) / (sum[i] + eps);
        }
        return m;
      }(),
  ];
}

/// The model-ready input + the STFT context needed to reconstruct — the output
/// of [spleeterPrepare], consumed by [spleeterAssemble]. Splitting prepare from
/// the model runs lets a native caller run the (independent) stem models
/// CONCURRENTLY across isolates between the two (see the model store).
typedef SpleeterInput = ({
  Float32List input, // packed [2, splits, 512, 1024]
  List<int> shape,
  Float64List re, // mix STFT (real), [nFrames × nFreq]
  Float64List im,
  int nFrames,
  int nFreq,
  int audioLen,
});

const String spleeterInputName = _inName;
const String spleeterOutputName = _outName;

/// STFT + magnitude-pack the mix [mono] into the model input. Web-safe/pure.
/// Returns null-ish (empty input, nFrames 0) for silence too short to frame.
SpleeterInput spleeterPrepare(
  Float64List mono, {
  int sampleRate = spleeterSampleRate,
}) {
  final audio = sampleRate == spleeterSampleRate
      ? mono
      : resampleLinear(mono, sampleRate / spleeterSampleRate);
  final st = Stft(_nFft, _hop, center: false);
  final (re, im, nFrames) = st.forward(audio);
  final nFreq = st.nFreq; // 2049
  if (nFrames == 0) {
    return (
      input: Float32List(0),
      shape: const [2, 0, _chunk, _bins],
      re: re,
      im: im,
      nFrames: 0,
      nFreq: nFreq,
      audioLen: audio.length,
    );
  }

  // Magnitude of the first 1024 bins, padded to a multiple of 512 frames, packed
  // [2, splits, 512, 1024] with the mono signal duplicated to both channels.
  final pad = (_chunk - nFrames % _chunk) % _chunk;
  final framesP = nFrames + pad;
  final splits = framesP ~/ _chunk;
  final chBlock = framesP * _bins;
  final input = Float32List(2 * chBlock);
  for (var t = 0; t < nFrames; t++) {
    final src = t * nFreq;
    final dst = t * _bins;
    for (var b = 0; b < _bins; b++) {
      final r = re[src + b], i2 = im[src + b];
      final mag = math.sqrt(r * r + i2 * i2);
      input[dst + b] = mag; // channel 0
      input[chBlock + dst + b] = mag; // channel 1 (== ch0, mono)
    }
  }
  return (
    input: input,
    shape: [2, splits, _chunk, _bins],
    re: re,
    im: im,
    nFrames: nFrames,
    nFreq: nFreq,
    audioLen: audio.length,
  );
}

/// Given each stem model's estimated-magnitude output [specs] (in [stemNames]
/// order), form the power-ratio masks and reconstruct each stem. Web-safe/pure.
Map<String, Float64List> spleeterAssemble(
  SpleeterInput prep,
  List<Float32List> specs,
  List<String> stemNames,
) {
  if (prep.nFrames == 0) {
    return {for (final name in stemNames) name: Float64List(0)};
  }
  final st = Stft(_nFft, _hop, center: false);
  final masks = spleeterMasks(specs); // full [2*chBlock] each
  final result = <String, Float64List>{};
  for (var k = 0; k < specs.length; k++) {
    final mask = masks[k];
    final vre = Float64List(prep.nFrames * prep.nFreq);
    final vim = Float64List(prep.nFrames * prep.nFreq);
    for (var t = 0; t < prep.nFrames; t++) {
      final mrow = t * _bins; // channel-0 block, frame t
      final srow = t * prep.nFreq;
      for (var b = 0; b < _bins; b++) {
        final m = mask[mrow + b];
        vre[srow + b] = prep.re[srow + b] * m;
        vim[srow + b] = prep.im[srow + b] * m;
      }
      // bins ≥ 1024 stay zero (masked out — the network never modelled them).
    }
    result[stemNames[k]] = st.inverse(vre, vim, prep.nFrames, prep.audioLen);
  }
  return result;
}

/// Run one stem [model] on the prepared [input] → its estimated-magnitude spec
/// (a copy — the runtime may reuse buffers).
Float32List spleeterRunModel(OnnxModel model, SpleeterInput input) {
  final out = model.run(
    {_inName: Tensor.float(input.input, input.shape)},
    const [_outName],
  )[_outName]!;
  return Float32List.fromList(out.f ?? out.asFloatList());
}

/// Separate [mono] into named stems with Spleeter [models] (one ONNX per stem,
/// aligned with [stemNames]). Returns a name→waveform map at 44.1 kHz. Pure /
/// synchronous / web-safe. (The native model store offers a concurrent variant.)
Map<String, Float64List> spleeterSeparateNamed(
  Float64List mono, {
  required List<OnnxModel> models,
  required List<String> stemNames,
  int sampleRate = spleeterSampleRate,
}) {
  assert(models.length == stemNames.length && models.isNotEmpty);
  final prep = spleeterPrepare(mono, sampleRate: sampleRate);
  if (prep.nFrames == 0) {
    return {for (final name in stemNames) name: Float64List(0)};
  }
  final specs = [for (final model in models) spleeterRunModel(model, prep)];
  return spleeterAssemble(prep, specs, stemNames);
}

/// Canonical stem orders for the two published Spleeter configs.
const List<String> spleeter4Stems = ['vocals', 'drums', 'bass', 'other'];
const List<String> spleeter2Stems = ['vocals', 'accompaniment'];

/// Spleeter as a [Stems] record. [models] is keyed by stem name (`vocals`,
/// `drums`, `bass`, `other` for 4stems; `vocals`, `accompaniment` for 2stems).
/// A 2-stem `accompaniment` maps onto the [Stems] `other` slot (→ chords).
Future<Stems> spleeterSeparate(
  Float64List mono, {
  required Map<String, OnnxModel> models,
  int sampleRate = spleeterSampleRate,
}) async {
  final names = models.keys.toList();
  final res = spleeterSeparateNamed(
    mono,
    models: [for (final n in names) models[n]!],
    stemNames: names,
    sampleRate: sampleRate,
  );
  return (
    vocals: res['vocals'],
    drums: res['drums'],
    bass: res['bass'],
    other: res['other'] ?? res['accompaniment'],
  );
}

/// Wrap loaded Spleeter [models] (name→model) as the stems.dart [Separator] the
/// pipeline injects — the full multi-stem separator.
Separator spleeterSeparator(Map<String, OnnxModel> models) =>
    (mono, sampleRate) =>
        spleeterSeparate(mono, models: models, sampleRate: sampleRate);
