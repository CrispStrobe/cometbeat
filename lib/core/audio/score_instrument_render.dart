// Render an engraved [Score] / [MultiPartScore] with an arbitrary
// [TrackerInstrument] voice, instead of the default synth timbre
// ([renderScore] in daw_sources.dart). This is the bridge that lets a saved
// "My Instruments" voice play a piece: every note is rendered through the
// instrument (held for its notated duration) and placed at its time offset, so
// Score/TAB/Workshop content can sound with any voice the tracker can make.
//
// Pure Dart — no Flutter — so it is unit-testable and web-safe.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
// The Flutter-free notation core (a dependency_override, re-exported via
// crisp_notation) — import it directly so this stays usable under plain
// `dart run` (the CLI bin/rendersong.dart), matching bin/notaconv.dart.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

// A note is rendered on a fixed 120 BPM / 4-steps-per-beat grid (125 ms/step);
// the row count is chosen so the note sustains for its notated length.
const int _tempoBpm = 120;
const int _stepsPerBeat = 4;
const double _stepMs = 60000 / (_tempoBpm * _stepsPerBeat); // 125 ms

int _durMs(NoteDuration d, int quarterMs) {
  final (num, den) = d.fraction; // fraction of a whole note
  return (4 * quarterMs * num / den).round();
}

/// Render a single held note (a rest is caller-handled): the note on step 0,
/// sustained across enough empty rows to cover [durMs].
Float64List _renderNote(TrackerInstrument inst, int midi, int durMs) {
  final rows = (durMs / _stepMs).round().clamp(1, 100000);
  final cells = <TrackerCell>[
    TrackerCell(midi: midi),
    for (var i = 1; i < rows; i++) TrackerCell.empty,
  ];
  // TrackerTiming defaults are 120 BPM / 4 steps-per-beat (= our 125 ms/step).
  return inst.renderChannel(cells, TrackerTiming(rows: rows));
}

void _placeVoice(
  List<MusicElement> elements,
  TrackerInstrument inst,
  int quarterMs,
  int sampleRate,
  List<(int, Float64List)> out,
  void Function(int end) grow,
) {
  var cursorMs = 0;
  for (final e in elements) {
    if (e is NoteElement) {
      final durMs = _durMs(e.duration, quarterMs);
      final startSample = (cursorMs * sampleRate / 1000).round();
      for (final p in e.pitches) {
        final pcm = _renderNote(inst, p.midiNumber, durMs);
        out.add((startSample, pcm));
        grow(startSample + pcm.length);
      }
      cursorMs += durMs;
    } else if (e is RestElement) {
      cursorMs += _durMs(e.duration, quarterMs);
    }
  }
}

/// Render [score] (all voices 1–4) through [inst] to mono PCM.
Float64List renderScoreWithInstrument(
  Score score,
  TrackerInstrument inst, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) {
  final placements = <(int, Float64List)>[];
  var maxLen = 0;
  void grow(int end) => maxLen = end > maxLen ? end : maxLen;

  final voices = <List<MusicElement>>[[], [], [], []];
  for (final m in score.measures) {
    voices[0].addAll(m.elements);
    voices[1].addAll(m.voice2);
    voices[2].addAll(m.voice3);
    voices[3].addAll(m.voice4);
  }
  for (final v in voices) {
    if (v.isNotEmpty) {
      _placeVoice(v, inst, quarterMs, sampleRate, placements, grow);
    }
  }

  final mix = Float64List(maxLen);
  for (final (start, pcm) in placements) {
    for (var i = 0; i < pcm.length; i++) {
      mix[start + i] += pcm[i];
    }
  }
  return mix;
}

/// Render each `(score, voice)` pair through its OWN instrument and sum them —
/// the per-part voicing a General-MIDI song needs (piano on one part, bass on
/// another, a drum kit on a third). [quarterMs] sets the shared tempo.
Float64List renderPartsWithVoices(
  List<(Score, TrackerInstrument)> parts, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) {
  final rendered = [
    for (final (score, voice) in parts)
      renderScoreWithInstrument(
        score,
        voice,
        quarterMs: quarterMs,
        sampleRate: sampleRate,
      ),
  ];
  var len = 0;
  for (final p in rendered) {
    if (p.length > len) len = p.length;
  }
  final out = Float64List(len);
  for (final p in rendered) {
    for (var i = 0; i < p.length; i++) {
      out[i] += p[i];
    }
  }
  return out;
}

/// Render every part of [mp] through [inst] and sum.
Float64List renderMultiPartWithInstrument(
  MultiPartScore mp,
  TrackerInstrument inst, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) {
  final parts = [
    for (final part in mp.parts)
      renderScoreWithInstrument(
        part,
        inst,
        quarterMs: quarterMs,
        sampleRate: sampleRate,
      ),
  ];
  var len = 0;
  for (final p in parts) {
    if (p.length > len) len = p.length;
  }
  final out = Float64List(len);
  for (final p in parts) {
    for (var i = 0; i < p.length; i++) {
      out[i] += p[i];
    }
  }
  return out;
}
