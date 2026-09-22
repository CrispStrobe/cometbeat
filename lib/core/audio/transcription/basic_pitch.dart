// lib/core/audio/transcription/basic_pitch.dart
//
// Worker 3 — the POLYPHONIC transcriber: Spotify Basic Pitch (ICASSP 2022) run
// on `onnx_runtime_dart` (pure Dart, no FFI). Reads real multi-instrument audio
// a monophonic tracker can't, emitting `NoteEvent`s interchangeable with the
// pYIN chain at S5 (see contracts.dart).
//
// Basic Pitch — spotify/basic-pitch — is Apache-2.0 for BOTH code and weights,
// so this file is a faithful PORT of the Python (constants.py / inference.py /
// note_creation.py), not a clean-room reimplementation. Attribution + the
// Apache-2.0 NOTICE ship next to the downloaded model (see the native
// basic_pitch_model_store.dart).
//
// The shipped ONNX model takes RAW AUDIO windows `[1, 43844, 1]` — the CQT /
// harmonic-stacking front-end lives inside the graph (as convolutions), so
// there is no DSP front-end to port. Verified: nmp.onnx runs on our runtime at
// cosine 1.0 vs onnxruntime on all three output heads.
// WEB-SAFE by design: this transcriber imports only the web-safe
// `onnx_runtime_dart` core (pure Dart, no `dart:io`) and takes a preloaded
// [OnnxModel]. Model download/caching (which needs `dart:io`) lives in the
// separate native `basic_pitch_model_store.dart`, so the transcription logic
// itself compiles for web/WASM too.
library;

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

// ── Constants (basic_pitch/constants.py — verified against the model) ────────
const int _fftHop = 256;
const int _sampleRate = 22050;
const int _midiOffset = 21; // ANNOTATIONS_BASE_FREQUENCY 27.5 Hz = A0 = MIDI 21
const int _maxFreqIdx = 87;
const int _audioNSamples = 43844; // AUDIO_SAMPLE_RATE*2 - FFT_HOP
const int _annotFrames = 172; // ANNOT_N_FRAMES = (22050//256)*2
const int _overlapFrames = 30; // N_OVERLAPPING_FRAMES
const int _energyTol = 11;

// tf2onnx renamed the SavedModel heads; matched by output order + shape:
// contour(264 bins)=:0, note(88)=:1, onset(88)=:2. (Confirmed by the triad
// test: the onset head peaks at note starts.)
const String _inputName = 'serving_default_input_2:0';
const String _noteOut = 'StatefulPartitionedCall:1'; // Yn (frame activations)
const String _onsetOut = 'StatefulPartitionedCall:2'; // Yo (onset activations)

/// Milliseconds of one model frame (`FFT_HOP / SR`), ≈ 11.61 ms.
double _frameToMs(num frame) => frame * _fftHop / _sampleRate * 1000.0;

/// Default minimum note length in *frames* (~127.7 ms, the package default).
const int _defaultMinNoteLen = 11;

/// A raw note event in model-frame units, as basic_pitch emits pre-timing.
typedef _FrameNote = ({int startFrame, int endFrame, int midi, double amp});

/// Transcribe polyphonic [mono] audio to notes with Basic Pitch. Resamples to
/// 22050 Hz, windows into overlapping 43844-sample frames, runs the ONNX
/// [model], stitches the frame/onset posteriorgrams, and decodes notes.
/// Returns notes in onset order. The caller supplies a loaded [model] — obtain
/// it natively via `BasicPitchModelStore` (`basic_pitch_model_store.dart`) or,
/// on web, from bytes you fetched yourself + `OnnxModel.fromBytes`. Pure /
/// synchronous / web-safe.
List<NoteEvent> basicPitchTranscribe(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  double onsetThreshold = 0.5,
  double frameThreshold = 0.3,
  int minNoteLenFrames = _defaultMinNoteLen,
  bool inferOnsets = true,
  bool melodiaTrick = false, // named after (not the patented) Melodia; off.
}) =>
    basicPitchTranscribeWithRunner(
      mono,
      sampleRate: sampleRate,
      onsetThreshold: onsetThreshold,
      frameThreshold: frameThreshold,
      minNoteLenFrames: minNoteLenFrames,
      inferOnsets: inferOnsets,
      melodiaTrick: melodiaTrick,
      run: (window) {
        final out = model.run(
          {
            _inputName: Tensor.float(window, [1, _audioNSamples, 1]),
          },
          const [_noteOut, _onsetOut],
        );
        return (
          notes: out[_noteOut]!.f ?? out[_noteOut]!.asFloatList(),
          onsets: out[_onsetOut]!.f ?? out[_onsetOut]!.asFloatList(),
        );
      },
    );

/// Runs one `[1, 43844, 1]` audio window through Basic Pitch and returns its two
/// flat `[1, 172, 88]` posteriorgrams (frame activations Yn, onset activations
/// Yo). The ONLY model-runtime coupling in the polyphonic chain — supply a
/// runner backed by `onnx_runtime_dart` (the default via [basicPitchTranscribe])
/// OR native ORT (the `onnxFfi` backend); the identical windowing/stitching/
/// decoding runs either way.
typedef BasicPitchWindowRunner = ({Float32List notes, Float32List onsets})
    Function(Float32List window);

/// [basicPitchTranscribe] with the model runtime abstracted behind [run] — same
/// resample/window/overlap-stitch/decode, only the per-window inference differs.
List<NoteEvent> basicPitchTranscribeWithRunner(
  Float64List mono, {
  required BasicPitchWindowRunner run,
  int sampleRate = 44100,
  double onsetThreshold = 0.5,
  double frameThreshold = 0.3,
  int minNoteLenFrames = _defaultMinNoteLen,
  bool inferOnsets = true,
  bool melodiaTrick = false,
}) {
  // 1 · Resample to 22050 Hz mono (ratio = inRate/outRate; 44100 → 2.0).
  final audio = sampleRate == _sampleRate
      ? mono
      : resampleLinear(mono, sampleRate / _sampleRate);

  // 2 · Pad the start by overlap/2 and window at `hopSize`, tail-padded.
  const overlapLen = _overlapFrames * _fftHop; // 7680
  const hopSize = _audioNSamples - overlapLen; // 36164
  const startPad = overlapLen ~/ 2; // 3840
  final padded = Float64List(startPad + audio.length)
    ..setRange(startPad, startPad + audio.length, audio);

  // 3 · Run each window; trim the overlap and stitch full posteriorgrams.
  const nOlap = _overlapFrames ~/ 2; // 15 frames trimmed each side
  final notesGrid = <Float64List>[]; // Yn rows (n_frames × 88)
  final onsetGrid = <Float64List>[];
  final window = Float32List(_audioNSamples);
  for (var i = 0; i < padded.length; i += hopSize) {
    for (var j = 0; j < _audioNSamples; j++) {
      final k = i + j;
      window[j] = k < padded.length ? padded[k].toDouble() : 0.0;
    }
    final out = run(Float32List.fromList(window));
    _appendTrimmed(notesGrid, out.notes, nOlap);
    _appendTrimmed(onsetGrid, out.onsets, nOlap);
  }

  // Trim trailing padded frames: keep n_expected_windows · frames_per_window.
  const framesPerWindow = _annotFrames - _overlapFrames; // 142
  final nKeep = ((audio.length / hopSize) * framesPerWindow).floor();
  final keep = nKeep < notesGrid.length ? nKeep : notesGrid.length;

  // 4 · Decode notes (shared with the deterministic-test entry point).
  return notesFromPosteriorgrams(
    notesGrid.sublist(0, keep),
    onsetGrid.sublist(0, keep),
    onsetThreshold: onsetThreshold,
    frameThreshold: frameThreshold,
    minNoteLenFrames: minNoteLenFrames,
    inferOnsets: inferOnsets,
    melodiaTrick: melodiaTrick,
  );
}

/// Decode `(frames, onsets)` posteriorgrams directly into [NoteEvent]s — the
/// model-independent half of [basicPitchTranscribe], exposed so the note
/// decoder can be tested deterministically on a hand-built posteriorgram (no
/// ONNX model). [frames]/[onsets] are `n_frames` rows of 88 activations
/// (`0..1`); frame indices map to ms via `FFT_HOP / 22050`.
List<NoteEvent> notesFromPosteriorgrams(
  List<Float64List> frames,
  List<Float64List> onsets, {
  double onsetThreshold = 0.5,
  double frameThreshold = 0.3,
  int minNoteLenFrames = _defaultMinNoteLen,
  bool inferOnsets = true,
  bool melodiaTrick = false,
}) {
  final raw = _outputToNotes(
    frames,
    onsets,
    onsetThresh: onsetThreshold,
    frameThresh: frameThreshold,
    minNoteLen: minNoteLenFrames,
    inferOnsets: inferOnsets,
    melodiaTrick: melodiaTrick,
  );
  return [
    for (final n in raw)
      (
        midi: n.midi,
        onMs: _frameToMs(n.startFrame),
        offMs: _frameToMs(n.endFrame),
        confidence: n.amp.clamp(0.0, 1.0),
        // Basic Pitch is instrument-agnostic by design — one pitch grid, no
        // timbre head. gmProgramUnknown, never 0.
        program: gmProgramUnknown,
      ),
  ]..sort((a, b) => a.onMs.compareTo(b.onMs));
}

/// Append a flat model output `[1, 172, 88]` to [grid], trimming [nOlap] frames
/// from each end (basic_pitch `unwrap_output`). The window output shape is fixed
/// (`_annotFrames` × `_nBins`), so it's inferred from the flat length.
void _appendTrimmed(List<Float64List> grid, Float32List f, int nOlap) {
  const nFrames = _annotFrames; // fixed window output height (172)
  final nFreq = f.length ~/ nFrames; // 88 (piano range)
  for (var t = nOlap; t < nFrames - nOlap; t++) {
    final row = Float64List(nFreq);
    final base = t * nFreq;
    for (var b = 0; b < nFreq; b++) {
      row[b] = f[base + b];
    }
    grid.add(row);
  }
}

/// Decode `(frames, onsets)` posteriorgrams into note events (frame units) —
/// a port of basic_pitch `output_to_notes_polyphonic`. Exposed for
/// deterministic testing on a hand-built posteriorgram (no model needed).
/// [frames]/[onsets] are `n_frames` rows of [_nBins] activations.
List<_FrameNote> _outputToNotes(
  List<Float64List> frames,
  List<Float64List> onsets, {
  required double onsetThresh,
  required double frameThresh,
  required int minNoteLen,
  required bool inferOnsets,
  required bool melodiaTrick,
}) {
  final nFrames = frames.length;
  if (nFrames < 2) return const [];
  final nFreq = frames[0].length;

  final onsetsUsed =
      inferOnsets ? _getInferredOnsets(onsets, frames, nFreq) : onsets;

  // Onset peaks (scipy argrelmax over time, order 1) above threshold; walked
  // backwards in time as basic_pitch does (deterministic ordering).
  final peaks = <(int, int)>[]; // (frame, freq)
  for (var t = 1; t < nFrames - 1; t++) {
    final cur = onsetsUsed[t],
        prev = onsetsUsed[t - 1],
        next = onsetsUsed[t + 1];
    for (var b = 0; b < nFreq; b++) {
      final v = cur[b];
      if (v > prev[b] && v > next[b] && v >= onsetThresh) peaks.add((t, b));
    }
  }
  peaks.sort((a, b) {
    final c = b.$1.compareTo(a.$1); // time descending
    return c != 0 ? c : b.$2.compareTo(a.$2);
  });

  // Remaining-energy copy of the frame matrix, consumed as notes are formed.
  final energy = [for (final r in frames) Float64List.fromList(r)];
  final events = <_FrameNote>[];

  for (final (noteStart, freqIdx) in peaks) {
    if (noteStart >= nFrames - 1) continue;
    var i = noteStart + 1;
    var k = 0;
    while (i < nFrames - 1 && k < _energyTol) {
      k = energy[i][freqIdx] < frameThresh ? k + 1 : 0;
      i++;
    }
    i -= k; // back to the last frame above threshold
    if (i - noteStart <= minNoteLen) continue;
    _zeroBand(energy, noteStart, i, freqIdx, nFreq);
    events.add(
      (
        startFrame: noteStart,
        endFrame: i,
        midi: freqIdx + _midiOffset,
        amp: _meanColumn(frames, noteStart, i, freqIdx),
      ),
    );
  }

  if (melodiaTrick) {
    _melodiaTrick(
      frames,
      energy,
      events,
      nFrames,
      nFreq,
      frameThresh,
      minNoteLen,
    );
  }
  return events;
}

/// basic_pitch `get_infered_onsets`: boost onset activations where the frame
/// activations rise sharply, rescaled to the onset range, taken elementwise-max
/// with the predicted onsets.
List<Float64List> _getInferredOnsets(
  List<Float64List> onsets,
  List<Float64List> frames,
  int nFreq, {
  int nDiff = 2,
}) {
  final nFrames = frames.length;
  // frame_diff[t] = min over n in 1..nDiff of (frames[t] - frames[t-n]); the
  // first nDiff rows are zeroed; negatives clipped to 0.
  final diff = [for (var t = 0; t < nFrames; t++) Float64List(nFreq)];
  for (var t = nDiff; t < nFrames; t++) {
    for (var b = 0; b < nFreq; b++) {
      var mn = double.infinity;
      for (var n = 1; n <= nDiff; n++) {
        final d = frames[t][b] - frames[t - n][b];
        if (d < mn) mn = d;
      }
      diff[t][b] = mn < 0 ? 0 : mn;
    }
  }
  var maxOnset = 0.0, maxDiff = 0.0;
  for (var t = 0; t < nFrames; t++) {
    for (var b = 0; b < nFreq; b++) {
      if (onsets[t][b] > maxOnset) maxOnset = onsets[t][b];
      if (diff[t][b] > maxDiff) maxDiff = diff[t][b];
    }
  }
  final scale = maxDiff > 0 ? maxOnset / maxDiff : 0.0;
  return [
    for (var t = 0; t < nFrames; t++)
      Float64List.fromList([
        for (var b = 0; b < nFreq; b++)
          onsets[t][b] > diff[t][b] * scale ? onsets[t][b] : diff[t][b] * scale,
      ]),
  ];
}

void _zeroBand(List<Float64List> e, int start, int end, int freq, int nFreq) {
  for (var t = start; t < end; t++) {
    e[t][freq] = 0;
    if (freq < _maxFreqIdx) e[t][freq + 1] = 0;
    if (freq > 0) e[t][freq - 1] = 0;
  }
}

double _meanColumn(List<Float64List> m, int start, int end, int freq) {
  var s = 0.0;
  for (var t = start; t < end; t++) {
    s += m[t][freq];
  }
  return end > start ? s / (end - start) : 0;
}

/// basic_pitch `melodia_trick` gap-fill (NOT the patented Melodia salience
/// method — a heuristic merely named after it). Off by default.
void _melodiaTrick(
  List<Float64List> frames,
  List<Float64List> energy,
  List<_FrameNote> events,
  int nFrames,
  int nFreq,
  double frameThresh,
  int minNoteLen,
) {
  while (true) {
    var maxV = 0.0, mi = -1, mf = -1;
    for (var t = 0; t < nFrames; t++) {
      for (var b = 0; b < nFreq; b++) {
        if (energy[t][b] > maxV) {
          maxV = energy[t][b];
          mi = t;
          mf = b;
        }
      }
    }
    if (maxV <= frameThresh || mi < 0) break;
    energy[mi][mf] = 0;
    var i = mi + 1, k = 0;
    while (i < nFrames - 1 && k < _energyTol) {
      k = energy[i][mf] < frameThresh ? k + 1 : 0;
      energy[i][mf] = 0;
      if (mf < _maxFreqIdx) energy[i][mf + 1] = 0;
      if (mf > 0) energy[i][mf - 1] = 0;
      i++;
    }
    final iEnd = i - 1 - k;
    i = mi - 1;
    k = 0;
    while (i > 0 && k < _energyTol) {
      k = energy[i][mf] < frameThresh ? k + 1 : 0;
      energy[i][mf] = 0;
      if (mf < _maxFreqIdx) energy[i][mf + 1] = 0;
      if (mf > 0) energy[i][mf - 1] = 0;
      i--;
    }
    final iStart = i + 1 + k;
    if (iEnd - iStart <= minNoteLen) continue;
    events.add(
      (
        startFrame: iStart,
        endFrame: iEnd,
        midi: mf + _midiOffset,
        amp: _meanColumn(frames, iStart, iEnd, mf),
      ),
    );
  }
}
