// lib/core/audio/transcription/harmony.dart
//
// W-HARMONY — neural chord recognition (BTC, Park ISMIR 2019, MIT) behind an
// additive `ChordEvent` seam. Upgrades the app's classical key/engraving with
// actual audio→chord-label estimation. Runs the BTC transformer on
// `onnx_runtime_dart` (pure Dart, no FFI).
//
// Pipeline: resample→22.05 kHz → CQT feature (see `harmony_cqt.dart`, validated
// against librosa.cqt) → 108-frame segments → BTC → per-frame chord logits →
// argmax → merge runs into timed [ChordEvent]s.
//
// WEB-SAFE: takes a preloaded [OnnxModel] + [CqtFilterBank] bytes; model/asset
// download (dart:io) lives in the native `harmony_model_store.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A recognised chord over a time span. Additive to the frozen `contracts.dart`.
/// [label] is BTC's symbol (`'C'`, `'C:min'`, `'N'` for no-chord); [rootPc] is
/// the pitch class 0–11 (C=0), or -1 for `'N'`; [quality] is `'maj'`/`'min'`/`'N'`.
typedef ChordEvent = ({
  String label,
  int rootPc,
  String quality,
  double onMs,
  double offMs,
});

/// A chord recogniser over mono audio — the injectable seam for the neural
/// (BTC) chord backend, mirroring F0Estimator / NeuralTranscriber.
typedef ChordEstimator = Future<List<ChordEvent>> Function(
  Float64List mono,
  int sampleRate,
);

/// BTC's 25-class maj/min vocabulary (index → symbol).
const List<String> btcChordLabels = [
  'C', 'C:min', 'C#', 'C#:min', 'D', 'D:min', 'D#', 'D#:min', 'E', 'E:min', //
  'F', 'F:min', 'F#', 'F#:min', 'G', 'G:min', 'G#', 'G#:min', 'A', 'A:min', //
  'A#', 'A#:min', 'B', 'B:min', 'N',
];

const int _timestep = 108;
const int _sr = 22050;
const String _inName = 'cqt';
const String _outName = 'chord';

/// Estimate chords over [mono] with BTC. [cqt] is the parsed filterbank asset,
/// [model] the preloaded BTC ONNX. Returns timed [ChordEvent]s (runs of equal
/// frames merged); includes `'N'` spans. Pure / synchronous / web-safe.
List<ChordEvent> estimateChords(
  Float64List mono, {
  required OnnxModel model,
  required CqtFilterBank cqt,
  int sampleRate = 44100,
  bool keepNoChord = false,
}) {
  final audio =
      sampleRate == _sr ? mono : resampleLinear(mono, sampleRate / _sr);
  final (feat, nFrames) = btcCqtFeature(cqt, audio);
  if (nFrames == 0) return const [];
  final nBins = cqt.nBins;

  // Pad to a whole number of 108-frame segments (zeros = silence).
  final nSeg = (nFrames + _timestep - 1) ~/ _timestep;
  final padded = Float32List(nSeg * _timestep * nBins)
    ..setRange(0, nFrames * nBins, feat);

  final labels = decodeChordLogits(_runSegments(model, padded, nSeg, nBins));
  return _mergeRuns(labels, nFrames, _sr / cqt.hop, keepNoChord: keepNoChord);
}

/// Run each 108-frame segment through BTC; concatenate `[nSeg·108 × 25]` logits.
Float32List _runSegments(
  OnnxModel model,
  Float32List padded,
  int nSeg,
  int nBins,
) {
  const nClass = 25;
  final out = Float32List(nSeg * _timestep * nClass);
  for (var s = 0; s < nSeg; s++) {
    final seg = Float32List.sublistView(
      padded,
      s * _timestep * nBins,
      (s + 1) * _timestep * nBins,
    );
    final r = model.run(
      {
        _inName: Tensor.float(Float32List.fromList(seg), [1, _timestep, nBins]),
      },
      const [_outName],
    )[_outName]!;
    final lg = r.f ?? r.asFloatList();
    out.setRange(s * _timestep * nClass, (s + 1) * _timestep * nClass, lg);
  }
  return out;
}

/// Per-frame argmax over the 25 chord classes → chord indices.
List<int> decodeChordLogits(Float32List logits) {
  const nClass = 25;
  final n = logits.length ~/ nClass;
  final out = List<int>.filled(n, 0);
  for (var t = 0; t < n; t++) {
    var best = 0;
    var bv = logits[t * nClass];
    for (var c = 1; c < nClass; c++) {
      final v = logits[t * nClass + c];
      if (v > bv) {
        bv = v;
        best = c;
      }
    }
    out[t] = best;
  }
  return out;
}

/// Merge consecutive equal-label frames (first [nFrames] only) into timed
/// events. [framesPerSec] = sr/hop.
List<ChordEvent> _mergeRuns(
  List<int> labels,
  int nFrames,
  double framesPerSec, {
  required bool keepNoChord,
}) {
  final events = <ChordEvent>[];
  var runStart = 0;
  for (var t = 1; t <= nFrames; t++) {
    if (t == nFrames || labels[t] != labels[runStart]) {
      final idx = labels[runStart];
      if (keepNoChord || idx != 24) {
        events.add(
          chordFromIndex(
            idx,
            runStart / framesPerSec * 1000.0,
            t / framesPerSec * 1000.0,
          ),
        );
      }
      runStart = t;
    }
  }
  return events;
}

/// Build a [ChordEvent] from a BTC class [idx] (0–24) and a time span.
ChordEvent chordFromIndex(int idx, double onMs, double offMs) {
  final label = btcChordLabels[idx];
  if (idx == 24) {
    return (label: 'N', rootPc: -1, quality: 'N', onMs: onMs, offMs: offMs);
  }
  return (
    label: label,
    rootPc: idx ~/ 2, // 0=C,1=C#,… interleaved maj/min
    quality: idx.isEven ? 'maj' : 'min',
    onMs: onMs,
    offMs: offMs,
  );
}

/// Frequency (Hz) of a chord root pitch class in octave 4 — small helper for
/// callers that want to sonify/anchor a detected chord.
double chordRootHz(int rootPc) => 440.0 * math.pow(2, (rootPc - 9) / 12.0);
