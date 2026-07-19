// lib/core/audio/transcription/separate.dart
//
// W-SEP (adapter shell) — source separation via a Demucs / HTDemucs ONNX, the
// biggest "transcribe a whole song" lever. Splits a mix into stems that the
// stem-assembly glue (stems.dart) then routes per-engine into a multi-part
// score. onnx_runtime_dart 0.10.x fast-pathed HTDemucs (ConvTranspose + GLU), so
// this runs the same ONNX path as basic_pitch/crepe.
//
// STATUS: everything here — mono→stereo, per-segment normalisation, the
// overlap-add reconstruction, and the stem-order mapping — is implemented and
// unit-tested WITHOUT the model. A model worker only publishes the HTDemucs ONNX
// and confirms the two tensor names + the segment length below (see
// separate_model_store.dart). Backend is free (ORT / FFI / ggml — CrispASR's
// --separate is the ggml route); anything producing [1, 4, 2, N] stems fits.
//
// Web-safe: takes a preloaded [OnnxModel]; the dart:io download lives in
// separate_model_store.dart. The app injects it as the stems.dart `Separator`
// via `demucsSeparator(model)`.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int _demucsRate = 44100;
const int _sources = 4; // HTDemucs order: drums, bass, other, vocals
const int _channels = 2; // stereo in/out

// TODO(model worker): confirm against the published HTDemucs ONNX export.
const String _inputName = 'mix';
const String _outputName = 'stems';
// Samples per inference segment (HTDemucs default ≈ 7.8 s). Match the export.
const int _segment = 343980; // 7.8 * 44100

/// Split [mono] into stems with a Demucs/HTDemucs [model]. Processes overlapping
/// [segment]-sample windows and overlap-adds the result, so there are no segment
/// seams. [overlap] is the fraction shared between windows.
Future<Stems> demucsSeparate(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  int segment = _segment,
  double overlap = 0.25,
}) async {
  final audio = sampleRate == _demucsRate
      ? mono
      : resampleLinear(mono, sampleRate / _demucsRate);
  final n = audio.length;
  if (n == 0) {
    return (vocals: null, bass: null, drums: null, other: null);
  }

  final hop = math.max(1, (segment * (1 - overlap)).round());
  final starts = <int>[];
  final segs = [for (var s = 0; s < _sources; s++) <Float64List>[]];

  for (var start = 0; start < n; start += hop) {
    final len = math.min(segment, n - start);
    final norm = normalizeSegment(audio, start, len);
    // Stereo input [1, 2, len] with the mono source duplicated to both channels.
    final input = Float32List(_channels * len);
    for (var i = 0; i < len; i++) {
      input[i] = norm.data[i]; // left
      input[len + i] = norm.data[i]; // right
    }
    final tensor = Tensor.float(input, [1, _channels, len]);
    final out = model.run({_inputName: tensor}, const [_outputName]);
    final t = out[_outputName]!;
    final f = t.f ?? t.asFloatList();
    // out [1, sources, channels, len]: downmix stereo→mono + denormalise.
    starts.add(start);
    for (var s = 0; s < _sources; s++) {
      final base0 = (s * _channels) * len;
      final base1 = (s * _channels + 1) * len;
      final seg = Float64List(len);
      for (var i = 0; i < len; i++) {
        seg[i] = 0.5 * (f[base0 + i] + f[base1 + i]) * norm.std + norm.mean;
      }
      segs[s].add(seg);
    }
    if (start + len >= n) break;
  }

  return (
    drums: overlapAdd(segs[0], starts, n),
    bass: overlapAdd(segs[1], starts, n),
    other: overlapAdd(segs[2], starts, n),
    vocals: overlapAdd(segs[3], starts, n),
  );
}

/// Wrap a loaded [model] as the stems.dart [Separator] the pipeline injects.
Separator demucsSeparator(OnnxModel model) => (mono, sampleRate) =>
    demucsSeparate(mono, model: model, sampleRate: sampleRate);

/// Overlap-add [segments] (each beginning at the matching [starts] index) into a
/// [total]-sample buffer, triangular-weighted and normalised by the weight sum —
/// the seamless-join reconstruction, one call per stem. Identity segments
/// reconstruct the original signal exactly.
Float64List overlapAdd(
  List<Float64List> segments,
  List<int> starts,
  int total,
) {
  final acc = Float64List(total);
  final wsum = Float64List(total);
  for (var k = 0; k < segments.length; k++) {
    final seg = segments[k];
    final start = starts[k];
    final w = _triangular(seg.length);
    for (var i = 0; i < seg.length; i++) {
      acc[start + i] += seg[i] * w[i];
      wsum[start + i] += w[i];
    }
  }
  for (var i = 0; i < total; i++) {
    if (wsum[i] > 0) acc[i] /= wsum[i];
  }
  return acc;
}

/// Mean/std normalisation of [audio][start..start+len) — HTDemucs expects a
/// zero-mean, unit-std mix; the returned [mean]/[std] re-apply to the output.
({Float64List data, double mean, double std}) normalizeSegment(
  Float64List audio,
  int start,
  int len,
) {
  var mean = 0.0;
  for (var i = 0; i < len; i++) {
    mean += audio[start + i];
  }
  mean /= len;
  var varSum = 0.0;
  for (var i = 0; i < len; i++) {
    final d = audio[start + i] - mean;
    varSum += d * d;
  }
  final std = math.sqrt(varSum / len);
  final inv = std > 1e-8 ? 1.0 / std : 0.0;
  final data = Float64List(len);
  for (var i = 0; i < len; i++) {
    data[i] = (audio[start + i] - mean) * inv;
  }
  return (data: data, mean: mean, std: std > 1e-8 ? std : 1.0);
}

/// Triangular (Bartlett) window — the overlap-add weights that cross-fade
/// adjacent segments. Ends kept just above zero so the weight sum never hits 0.
Float64List _triangular(int len) {
  final w = Float64List(len);
  final half = (len - 1) / 2;
  for (var i = 0; i < len; i++) {
    w[i] = half <= 0 ? 1.0 : 1 - (i - half).abs() / half;
    if (w[i] < 1e-3) w[i] = 1e-3;
  }
  return w;
}
