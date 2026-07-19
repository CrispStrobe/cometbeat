// Render an engraved [Score] / [MultiPartScore] with an arbitrary
// [TrackerInstrument] voice, instead of the default synth timbre
// ([renderScore] in daw_sources.dart). This is the bridge that lets a saved
// "My Instruments" voice play a piece: every note is rendered through the
// instrument (held for its notated duration) and placed at its time offset, so
// Score/TAB/Workshop content can sound with any voice the tracker can make.
//
// Pure Dart — no Flutter — so it is unit-testable and web-safe.

import 'dart:math' as math;
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

// Note-on velocity per dynamic level — mirrors crisp_notation_core's MIDI writer
// so the rendered dynamics match an exported MIDI. Gain is velocity/127, so the
// louder a mark the closer to unity; the caller's normalize restores overall
// level (relative dynamics are what matter). mf (80) → 0.63.
const Map<DynamicLevel, int> _dynamicVelocity = {
  DynamicLevel.pppp: 8,
  DynamicLevel.ppp: 20,
  DynamicLevel.pp: 33,
  DynamicLevel.p: 49,
  DynamicLevel.mp: 64,
  DynamicLevel.mf: 80,
  DynamicLevel.f: 96,
  DynamicLevel.ff: 112,
  DynamicLevel.fff: 122,
  DynamicLevel.ffff: 127,
  DynamicLevel.sf: 112,
  DynamicLevel.sfz: 118,
  DynamicLevel.sffz: 124,
  DynamicLevel.fz: 112,
  DynamicLevel.rf: 100,
  DynamicLevel.fp: 96,
};

/// Levels that accent one note rather than setting a lasting level (they don't
/// carry forward the way p/f/… do).
const Set<DynamicLevel> _momentary = {
  DynamicLevel.sf,
  DynamicLevel.sfz,
  DynamicLevel.sffz,
  DynamicLevel.fz,
  DynamicLevel.rf,
  DynamicLevel.fp,
};

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
  void Function(int end) grow, {
  required Map<String, DynamicLevel> dynByElement,
  required bool expressive,
}) {
  var cursorMs = 0;
  var currentVel = 80; // mf until a dynamic says otherwise
  for (final e in elements) {
    if (e is NoteElement) {
      final durMs = _durMs(e.duration, quarterMs);
      final startSample = (cursorMs * sampleRate / 1000).round();

      // Dynamics + articulations → a per-note gain (and staccato shortening).
      // Only when the score actually carries dynamics, so an unmarked score is
      // byte-identical to the plain render.
      var gain = 1.0;
      var playMs = durMs;
      if (expressive) {
        var vel = currentVel;
        final marked = e.id == null ? null : dynByElement[e.id];
        if (marked != null) {
          final v = _dynamicVelocity[marked] ?? 80;
          if (_momentary.contains(marked)) {
            vel = v; // this note only
          } else {
            currentVel = v; // lasting level
            vel = v;
          }
        }
        if (e.articulations.contains(Articulation.accent)) {
          vel = (vel + 15).clamp(0, 127);
        }
        if (e.articulations.contains(Articulation.marcato)) {
          vel = (vel + 20).clamp(0, 127);
        }
        gain = vel / 127.0;
        if (e.articulations.contains(Articulation.staccato)) {
          playMs = (durMs * 0.55).round(); // clipped, but timing unchanged
        }
      }

      for (final p in e.pitches) {
        final pcm = _renderNote(inst, p.midiNumber, playMs);
        if (gain != 1.0) {
          for (var i = 0; i < pcm.length; i++) {
            pcm[i] *= gain;
          }
        }
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

  final dynByElement = {
    for (final d in score.dynamics) d.elementId: d.level,
  };
  final expressive = dynByElement.isNotEmpty;

  final voices = <List<MusicElement>>[[], [], [], []];
  for (final m in score.measures) {
    voices[0].addAll(m.elements);
    voices[1].addAll(m.voice2);
    voices[2].addAll(m.voice3);
    voices[3].addAll(m.voice4);
  }
  for (final v in voices) {
    if (v.isNotEmpty) {
      _placeVoice(
        v,
        inst,
        quarterMs,
        sampleRate,
        placements,
        grow,
        dynByElement: dynByElement,
        expressive: expressive,
      );
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
  final rendered = renderPartsSeparate(
    parts,
    quarterMs: quarterMs,
    sampleRate: sampleRate,
  );
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

/// Render each `(score, voice)` pair to its OWN mono buffer (not summed) — so a
/// caller can pan the parts across the stereo field ([panPartsToStereo]).
List<Float64List> renderPartsSeparate(
  List<(Score, TrackerInstrument)> parts, {
  int quarterMs = 500,
  int sampleRate = kSampleRate,
}) =>
    [
      for (final (score, voice) in parts)
        renderScoreWithInstrument(
          score,
          voice,
          quarterMs: quarterMs,
          sampleRate: sampleRate,
        ),
    ];

/// Pan [parts] across the stereo field with a constant-power law and sum into
/// (left, right). Parts are spread evenly within ±[spread] (0 = mono-centred,
/// 1 = hard L/R); a single part is centred. Constant-power keeps the summed
/// loudness even as a part moves off-centre.
(Float64List left, Float64List right) panPartsToStereo(
  List<Float64List> parts, {
  double spread = 0.6,
}) {
  var len = 0;
  for (final p in parts) {
    if (p.length > len) len = p.length;
  }
  final left = Float64List(len);
  final right = Float64List(len);
  for (var k = 0; k < parts.length; k++) {
    final pan = parts.length < 2
        ? 0.0
        : (-spread + 2 * spread * k / (parts.length - 1));
    // pan −1..1 → angle 0..π/2; cos/sin give the L/R gains (equal at centre).
    final theta = (pan + 1) * 0.25 * math.pi;
    final lg = math.cos(theta);
    final rg = math.sin(theta);
    final p = parts[k];
    for (var i = 0; i < p.length; i++) {
      left[i] += p[i] * lg;
      right[i] += p[i] * rg;
    }
  }
  return (left, right);
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
