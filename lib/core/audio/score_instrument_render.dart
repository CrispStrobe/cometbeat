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

import 'package:comet_beat/core/audio/score_performance.dart';
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
/// A generic amplitude-envelope release, in ms — the note sustains for its
/// notated length then fades over this tail instead of stopping hard (the true
/// per-instrument SF2 release is the event-accurate synth's job). ~140 ms reads
/// as a natural instrument release without smearing fast passages.
const double _releaseMs = 140;

/// Render a single held note (a rest is caller-handled): the note on step 0,
/// sustained across enough empty rows to cover [durMs], then a [releaseMs] fade
/// so the note-off is a natural decay rather than a hard stop. [gain] scales the
/// whole note (velocity/dynamics), applied here so it rides the envelope.
Float64List _renderNote(
  TrackerInstrument inst,
  int midi,
  int durMs, {
  double gain = 1.0,
  double releaseMs = _releaseMs,
}) {
  final rows = ((durMs + releaseMs) / _stepMs).round().clamp(1, 100000);
  final cells = <TrackerCell>[
    TrackerCell(midi: midi),
    for (var i = 1; i < rows; i++) TrackerCell.empty,
  ];
  // TrackerTiming defaults are 120 BPM / 4 steps-per-beat (= our 125 ms/step).
  final pcm = inst.renderChannel(cells, TrackerTiming(rows: rows));

  // Full [gain] through the sustain, then a quadratic fade over the last
  // releaseMs samples (a gentle, click-free decay).
  final relSamples = (releaseMs * kSampleRate / 1000).round();
  final sustainEnd = pcm.length - relSamples;
  for (var i = 0; i < pcm.length; i++) {
    var env = gain;
    if (relSamples > 0 && i >= sustainEnd) {
      final t = (i - sustainEnd) / relSamples; // 0..1
      final k = 1 - t;
      env *= k * k;
    }
    pcm[i] *= env;
  }
  return pcm;
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
  int fifths = 0,
}) {
  var cursorMs = 0;
  var currentVel = 80; // mf until a dynamic says otherwise
  // SE-C5: a tie means two noteheads and ONE attack, so a tied-from note is
  // skipped as a sounding event and its length is added to the note that
  // started the chain. Without this the preview re-articulated every tie —
  // audibly wrong, and wrong in the one place a beginner is listening hardest.
  var carriedMs = 0; // length lent forward by ties
  int? carriedStart; // where the tied chain BEGAN, in samples
  for (final e in elements) {
    if (e is NoteElement) {
      final ownMs = _durMs(e.duration, quarterMs);
      final durMs = ownMs + carriedMs;
      // ⚠ A tied chain sounds from where it BEGAN, not from the last notehead
      // of the chain. Attaching the sound to the final note put it a whole
      // note-length late and left silence in its place.
      final startSample =
          carriedStart ?? (cursorMs * sampleRate / 1000).round();

      // A per-note gain (and staccato shortening) from the note's loudness:
      // an explicit performed velocity (a MIDI import) wins; else notated
      // dynamics. Left null — and the render byte-identical — when the note has
      // neither, so a plain score is unchanged.
      var gain = 1.0;
      var playMs = durMs;
      int? vel = e.velocity;
      if (vel == null && expressive) {
        vel = currentVel;
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
      }
      if (vel != null) {
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

      // Look ahead: if THIS note ties into the next, it does not sound yet —
      // it lends its length forward. (Chords tie as a unit here; a partial
      // chord tie is not modelled and would need per-pitch tie data.)
      if (e.tieToNext) {
        carriedStart ??= startSample;
        carriedMs = durMs; // accumulates across a chain of three or more
        cursorMs += ownMs;
        continue;
      }

      {
        // SE-C5: one notehead is not always one attack. Tremolo repeats it,
        // an ornament expands it into a figure; a plain note yields exactly
        // one attack of the full length, so ordinary scores are unchanged.
        final attacks =
            attacksFor(e, playMs, quarterMs: quarterMs, fifths: fifths);
        final transpose = e.pitches.first.midiNumber;
        for (final p in e.pitches) {
          // Chord notes follow the same figure, moved to their own pitch: an
          // ornament on a chord decorates every voice of it.
          final offset = p.midiNumber - transpose;
          for (final a in attacks) {
            final at = startSample + (a.atMs * sampleRate / 1000).round();
            final pcm =
                _renderNote(inst, a.midi + offset, a.lengthMs, gain: gain);
            out.add((at, pcm));
            grow(at + pcm.length);
          }
        }
      }
      carriedMs = 0;
      carriedStart = null;
      // ⚠ The cursor advances by this notehead's OWN written length. Advancing
      // by the accumulated length would count a tied note twice and drag
      // everything after it out of time.
      cursorMs += ownMs;
    } else if (e is RestElement) {
      carriedMs = 0;
      carriedStart = null;
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
        // The key decides an ornament's diatonic neighbours; without it a
        // trill in G major would alternate with F natural.
        fifths: score.keySignature.fifths,
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
