// lib/core/audio/transcription/piano.dart
//
// Piano-specialist transcription — ByteDance/Kong's high-resolution
// onset/offset REGRESSION model (MIT, `piano_transcription_inference`), Tier-3
// #7. Near-SOTA solo-piano note transcription: a CNN + biGRU that regresses
// onset/offset/frame/velocity heads on a log-mel spectrogram, then Kong's
// onset-regression post-processing turns the heads into precise note events with
// SUB-FRAME onset/offset timing + velocity. Runs on `onnx_runtime_dart`.
//
// The log-mel front-end (torchlibrosa, as conv layers) is INSIDE the exported
// ONNX, so the model takes raw 16 kHz audio → four [1, frames, 88] heads. This
// file only enframes/deframes (10 s segments, 5 s hop) and ports Kong's
// RegressionPostProcessor exactly (verified vs the Python reference).
//
// Fits the frozen `NeuralTranscriber` seam (route.dart) → the router selects it
// for piano. WEB-SAFE: takes a preloaded [OnnxModel]; the ~99 MB download
// (dart:io) lives in `piano_model_store.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int pianoSampleRate = 16000;
const int _classes = 88; // piano notes, from A0
const int _beginNote = 21; // MIDI of A0
const int _framesPerSecond = 100;
const int _velocityScale = 128;
const int _segSamples = pianoSampleRate * 10; // 160000 (10 s segments)
const String _inName = 'waveform';
const List<String> _outNames = ['reg_onset', 'reg_offset', 'frame', 'velocity'];

// Kong's inference thresholds.
const double _onsetThreshold = 0.3;
const double _offsetThreshold = 0.3;
const double _frameThreshold = 0.1;

/// The four decoded heads for one whole recording, each row-major `[frames×88]`.
typedef PianoHeads = ({
  Float64List onset,
  Float64List offset,
  Float64List frame,
  Float64List velocity,
  int frames,
});

/// Transcribe a solo-piano [mono] recording into [NoteEvent]s with Kong's model.
/// Pure/async; feed a preloaded [model]. Web-safe.
Future<List<NoteEvent>> pianoTranscribe(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = pianoSampleRate,
}) async {
  final audio = sampleRate == pianoSampleRate
      ? mono
      : resampleLinear(mono, sampleRate / pianoSampleRate);
  if (audio.isEmpty) return const [];

  final segs = pianoEnframe(audio);
  final perSeg = [for (final seg in segs) pianoRunSegment(model, seg)];
  return decodePianoHeads(pianoDeframeSegments(perSeg));
}

/// Wrap a loaded [model] as the route.dart [NeuralTranscriber] the pipeline
/// injects.
NeuralTranscriber pianoTranscriber(OnnxModel model) => (mono, sampleRate) =>
    pianoTranscribe(mono, model: model, sampleRate: sampleRate);

/// Enframe [audio] (already 16 kHz) into overlapping 10 s segments (5 s hop),
/// padded to a whole number of segments. Each segment is a model input.
List<Float32List> pianoEnframe(Float64List audio) {
  final nSeg = (audio.length / _segSamples).ceil();
  final padded = Float32List(nSeg * _segSamples);
  for (var i = 0; i < audio.length; i++) {
    padded[i] = audio[i];
  }
  const hop = _segSamples ~/ 2;
  final segs = <Float32List>[];
  for (var p = 0; p + _segSamples <= padded.length; p += hop) {
    final seg = Float32List(_segSamples);
    seg.setRange(0, _segSamples, padded, p);
    segs.add(seg);
  }
  if (segs.isEmpty) {
    segs.add(Float32List(_segSamples)..setRange(0, _segSamples, padded, 0));
  }
  return segs;
}

/// Run ONE 10 s [seg] through [model] → the four head rows
/// `[reg_onset, reg_offset, frame, velocity]`, each row-major `[segFrames×88]`.
List<Float32List> pianoRunSegment(OnnxModel model, Float32List seg) {
  final out = model.run(
    {_inName: Tensor.float(seg, [1, _segSamples])},
    _outNames,
  );
  return [
    for (final n in _outNames)
      () {
        final t = out[n]!;
        return Float32List.fromList(t.f ?? t.asFloatList());
      }(),
  ];
}

/// Deframe per-segment head rows (from [pianoRunSegment]) back to whole-
/// recording [PianoHeads].
PianoHeads pianoDeframeSegments(List<List<Float32List>> perSeg) {
  List<Float32List> col(int i) => [for (final s in perSeg) s[i]];
  final segFrames = perSeg.first.first.length ~/ _classes;
  final onset = _deframe(col(0), segFrames);
  return (
    onset: onset,
    offset: _deframe(col(1), segFrames),
    frame: _deframe(col(2), segFrames),
    velocity: _deframe(col(3), segFrames),
    frames: onset.length ~/ _classes,
  );
}

/// Stitch per-segment heads (each row-major `[segFrames×88]`) back to the full
/// sequence — Kong's `deframe`: one segment passes through; otherwise drop each
/// segment's extra final frame and keep the middle 50 % of interior segments.
Float64List _deframe(List<Float32List> segs, int segFrames) {
  if (segs.length == 1) {
    return Float64List.fromList(segs.first);
  }
  final s = segFrames - 1; // drop the extra frame (spectrogram center=True)
  final lo = (s * 0.25).toInt();
  final hi = (s * 0.75).toInt();
  final out = <double>[];
  void add(Float32List seg, int f0, int f1) {
    for (var f = f0; f < f1; f++) {
      final base = f * _classes;
      for (var k = 0; k < _classes; k++) {
        out.add(seg[base + k]);
      }
    }
  }

  add(segs.first, 0, hi);
  for (var i = 1; i < segs.length - 1; i++) {
    add(segs[i], lo, hi);
  }
  add(segs.last, lo, s);
  return Float64List.fromList(out);
}

/// Decode whole-recording [heads] into [NoteEvent]s — Kong's
/// RegressionPostProcessor + per-note onset/offset state machine.
List<NoteEvent> decodePianoHeads(PianoHeads heads) {
  final f = heads.frames;
  final (onsetBin, onsetShift) = _binarize(heads.onset, f, _onsetThreshold, 2);
  final (offsetBin, offsetShift) =
      _binarize(heads.offset, f, _offsetThreshold, 4);

  final events = <NoteEvent>[];
  for (var k = 0; k < _classes; k++) {
    _detectNotes(
      k,
      f,
      frame: heads.frame,
      onsetBin: onsetBin,
      onsetShift: onsetShift,
      offsetBin: offsetBin,
      offsetShift: offsetShift,
      velocity: heads.velocity,
      out: events,
    );
  }
  // Kong emits in pitch order (the note loop); within a note, onset order. Keep
  // that order so decoded events match the reference exactly.
  return events;
}

/// Binarize a regression head (`reg` row-major `[frames×88]`): a frame is an
/// onset/offset iff it exceeds [threshold] and is a local max with monotonic
/// [neighbour] sides; the sub-frame [shift] is Kong's parabolic interpolation.
(Float64List, Float64List) _binarize(
  Float64List reg,
  int frames,
  double threshold,
  int neighbour,
) {
  final binary = Float64List(frames * _classes);
  final shift = Float64List(frames * _classes);
  for (var k = 0; k < _classes; k++) {
    double x(int n) => reg[n * _classes + k];
    for (var n = neighbour; n < frames - neighbour; n++) {
      final xn = x(n);
      if (xn <= threshold) continue;
      var monotonic = true;
      for (var i = 0; i < neighbour; i++) {
        if (x(n - i) < x(n - i - 1)) monotonic = false;
        if (x(n + i) < x(n + i + 1)) monotonic = false;
      }
      if (!monotonic) continue;
      binary[n * _classes + k] = 1;
      final xm1 = x(n - 1), xp1 = x(n + 1);
      shift[n * _classes + k] = (xm1 > xp1)
          ? (xp1 - xm1) / (xn - xp1) / 2
          : (xp1 - xm1) / (xn - xm1) / 2;
    }
  }
  return (binary, shift);
}

/// Per-note onset/offset state machine (Kong's
/// `note_detection_with_onset_offset_regress`) → appends [NoteEvent]s for note
/// [k] to [out].
void _detectNotes(
  int k,
  int frames, {
  required Float64List frame,
  required Float64List onsetBin,
  required Float64List onsetShift,
  required Float64List offsetBin,
  required Float64List offsetShift,
  required Float64List velocity,
  required List<NoteEvent> out,
}) {
  double col(Float64List a, int n) => a[n * _classes + k];

  void emit(int bgn, int fin) {
    final onMs = (bgn + col(onsetShift, bgn)) / _framesPerSecond * 1000.0;
    final offMs = (fin + col(offsetShift, fin)) / _framesPerSecond * 1000.0;
    final vel = col(velocity, bgn);
    out.add((midi: k + _beginNote, onMs: onMs, offMs: offMs, confidence: vel));
  }

  int? bgn;
  int? frameDisappear;
  int? offsetOccur;
  for (var i = 0; i < frames; i++) {
    if (col(onsetBin, i) == 1) {
      if (bgn != null) {
        // Consecutive onsets — close the previous note at i-1.
        emit(bgn, math.max(i - 1, 0));
        frameDisappear = null;
        offsetOccur = null;
      }
      bgn = i;
    }

    if (bgn != null && i > bgn) {
      if (col(frame, i) <= _frameThreshold && frameDisappear == null) {
        frameDisappear = i;
      }
      if (col(offsetBin, i) == 1 && offsetOccur == null) {
        offsetOccur = i;
      }
      if (frameDisappear != null) {
        final int fin;
        if (offsetOccur != null &&
            offsetOccur - bgn > frameDisappear - offsetOccur) {
          fin = offsetOccur;
        } else {
          fin = frameDisappear;
        }
        emit(bgn, fin);
        bgn = null;
        frameDisappear = null;
        offsetOccur = null;
      }
      if (bgn != null && (i - bgn >= 600 || i == frames - 1)) {
        emit(bgn, i);
        bgn = null;
        frameDisappear = null;
        offsetOccur = null;
      }
    }
  }
}

/// The velocity (0..127) a caller would write to MIDI for [n] — Kong scales the
/// normalized velocity ([NoteEvent.confidence]) by 128.
int pianoMidiVelocity(NoteEvent n) =>
    (n.confidence * _velocityScale).toInt().clamp(0, 127);

/// Run ONLY the first 10 s segment and return each head's first 100 frames
/// (row-major `[100×88]`) — the runtime-parity probe used by tests.
Map<String, Float32List> pianoHeadsForTest(Float64List audio, OnnxModel model) {
  final seg = Float32List(_segSamples);
  for (var i = 0; i < audio.length && i < _segSamples; i++) {
    seg[i] = audio[i];
  }
  final out = model.run(
    {
      _inName: Tensor.float(seg, [1, _segSamples]),
    },
    _outNames,
  );
  const crop = 100 * _classes;
  Float32List head(String name) {
    final t = out[name]!;
    final f = t.f ?? t.asFloatList();
    return Float32List.sublistView(Float32List.fromList(f), 0, crop);
  }

  return {for (final n in _outNames) n: head(n)};
}
