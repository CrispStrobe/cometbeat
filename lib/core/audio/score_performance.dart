// lib/core/audio/score_performance.dart
//
// WHAT A NOTATED NOTE ACTUALLY SOUNDS LIKE (SE-C5).
//
// The renderer plays one attack per notehead. But several things on a page mean
// "this notehead is not one attack":
//
//   • a TREMOLO beam means repeat the pitch at that rhythmic value for the
//     written length — three beams over a half note is sixteen thirty-seconds,
//     not one long note;
//   • an ORNAMENT is an abbreviation for a small figure the player writes out in
//     their head — a trill is an alternation, a mordent is a flick, a turn is
//     four notes;
//   • a TIE means the opposite: two noteheads, ONE attack.
//
// Until now the preview played all of these as a single plain note, so the page
// and the sound disagreed — and a preview that disagrees with the page is worse
// than no preview, because it teaches the wrong thing.
//
// This file answers only "which attacks, when, at what pitch"; gain, instrument
// and mixing stay in the renderer. That makes the interesting part testable
// without rendering any audio.
//
// ⚠ SLUR LEGATO IS NOT MODELLED, and cannot be honestly faked here. A slur means
// the following notes are not re-articulated — on a real instrument the bow or
// breath simply continues. Our renderer plays a one-shot sample per note, so
// there is no attack to suppress; overlapping the samples would produce a
// chorus, not a legato. That needs an instrument with a separate attack and
// sustain, not a change to this function.
//
// ⚠ Ornament SPEED is a performance choice, not a rule, and this picks one
// plainly rather than pretending otherwise: ornament notes run at thirty-second
// speed for the current tempo. Real players vary it with tempo, style and
// affect. The point is to make the ornament audible as an ornament, not to
// impersonate a performer.
//
// Pure Dart (crisp_notation_core only), so it is testable headlessly.

import 'package:crisp_notation_core/crisp_notation_core.dart';

/// One thing the instrument is actually asked to play.
typedef Attack = ({int atMs, int midi, int lengthMs});

/// The major-scale degrees, in semitones from the tonic.
const List<int> _majorScale = [0, 2, 4, 5, 7, 9, 11];

/// The pitch classes of the key with [fifths] sharps (negative = flats).
///
/// Major and its relative minor share a signature and therefore a pitch-class
/// set, so this needs no mode — which is fortunate, because a [KeySignature]
/// does not always carry one.
Set<int> keyPitchClasses(int fifths) {
  final tonic = ((fifths * 7) % 12 + 12) % 12;
  return {for (final d in _majorScale) (tonic + d) % 12};
}

/// Semitones above C for each letter name.
const Map<Step, int> _stepSemitones = {
  Step.c: 0,
  Step.d: 2,
  Step.e: 4,
  Step.f: 5,
  Step.g: 7,
  Step.a: 9,
  Step.b: 11,
};

/// The upper auxiliary for a trill written with an explicit accidental.
///
/// ⚠ These variants (`trillSharp`/`trillFlat`/`trillNatural`) are a baroque
/// notation saying what the auxiliary IS, overriding the key — so it must be
/// derived from the LETTER above, not from the key's own neighbour. In G major
/// the note above E is F♯; a `trillNatural` there means F♮, and taking the
/// diatonic neighbour would play the sharp the composer explicitly cancelled.
/// The alter comes from the enum's own [Ornament.trillAccidentalAlter], so this
/// is not inventing a meaning for the symbol.
int alteredUpperAuxiliary(Pitch pitch, int alter) {
  const order = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a, Step.b];
  final i = order.indexOf(pitch.step);
  final next = order[(i + 1) % order.length];
  final octave = next == Step.c ? pitch.octave + 1 : pitch.octave;
  return (octave + 1) * 12 + _stepSemitones[next]! + alter;
}

/// The next note of the key above (or below) [midi].
///
/// ⚠ Diatonic, not chromatic. A trill on A in C major alternates with B — a
/// whole step — while a trill on B alternates with C, a half step. Using a
/// fixed interval would be wrong roughly half the time, and wrong in a way that
/// sounds like a mistake rather than an approximation.
///
/// Falls back to a semitone if the key somehow contains no neighbour within an
/// octave, so this can never loop or return the note itself.
int diatonicNeighbour(int midi, {required int fifths, required bool up}) {
  final scale = keyPitchClasses(fifths);
  for (var step = 1; step <= 12; step++) {
    final candidate = up ? midi + step : midi - step;
    if (scale.contains(((candidate % 12) + 12) % 12)) return candidate;
  }
  return up ? midi + 1 : midi - 1;
}

/// The attacks [note] produces over [durMs], relative to its own start.
///
/// [quarterMs] sets the ornament and tremolo rate; [fifths] is the key
/// signature, used for the diatonic neighbours. A plain note yields exactly one
/// attack of the full length, so an unornamented score renders as before.
List<Attack> attacksFor(
  NoteElement note,
  int durMs, {
  required int quarterMs,
  int fifths = 0,
}) {
  if (note.pitches.isEmpty || durMs <= 0) return const [];
  final midi = note.pitches.first.midiNumber;

  // Tremolo first: it is a property of the WRITTEN note (how to sustain it),
  // whereas an ornament decorates the start. A note marked both is vanishingly
  // rare, and repeating the pitch is the more audible instruction.
  final beams = note.tremolo;
  if (beams != null && beams > 0) {
    // 1 beam = eighths, 2 = sixteenths, 3 = thirty-seconds …
    //
    // ⚠ Count the repeats from the exact ratio and then PARTITION the duration,
    // rather than stepping by a rounded sub-length. Stepping loses a repeat
    // whenever the sub-length rounds up — a 32nd tremolo on a quarter at 120bpm
    // is 62.5 ms, which rounds to 63, and seven of those fit where eight
    // belong. Partitioning also guarantees the repeats fill the note exactly
    // instead of leaving a silent tail that drifts with the tempo.
    final count = (durMs * (1 << beams) / quarterMs).round();
    if (count >= 2) {
      int edge(int i) => (i * durMs / count).round();
      return [
        for (var i = 0; i < count; i++)
          (atMs: edge(i), midi: midi, lengthMs: edge(i + 1) - edge(i)),
      ];
    }
    return [(atMs: 0, midi: midi, lengthMs: durMs)];
  }

  final ornament = note.ornament;
  if (ornament == null) {
    return [(atMs: 0, midi: midi, lengthMs: durMs)];
  }

  // A trill-with-accidental names its own auxiliary; everything else takes the
  // note of the key.
  final alter = ornament.trillAccidentalAlter;
  final upper = alter == null
      ? diatonicNeighbour(midi, fifths: fifths, up: true)
      : alteredUpperAuxiliary(note.pitches.first, alter);
  final lower = diatonicNeighbour(midi, fifths: fifths, up: false);
  // Thirty-second speed, but never so fine that a short note becomes a blur:
  // an ornament must fit inside its own note.
  final unit = (quarterMs / 8).round().clamp(1, durMs);

  List<int> figure;
  switch (ornament) {
    case Ornament.trill:
    case Ornament.trillSharp:
    case Ornament.trillFlat:
    case Ornament.trillNatural:
      // A modern trill starts on the written note and alternates for its
      // length. (Baroque practice often starts above — a style question we do
      // not pretend to settle.)
      final count = (durMs / unit).floor().clamp(2, 64);
      figure = [for (var i = 0; i < count; i++) i.isEven ? midi : upper];
    case Ornament.shortTrill:
      figure = [midi, upper, midi];
    case Ornament.mordent:
      figure = [midi, lower, midi];
    case Ornament.turn:
      figure = [upper, midi, lower, midi];
    case Ornament.invertedTurn:
      figure = [lower, midi, upper, midi];
  }

  final out = <Attack>[];
  var t = 0;
  for (var i = 0; i < figure.length; i++) {
    final last = i == figure.length - 1;
    // The final note of the figure holds whatever is left of the written
    // duration — that is what makes an ornament decorate a note rather than
    // replace it. A trill, which fills its note, leaves nothing over.
    final length = last ? (durMs - t).clamp(1, durMs) : unit;
    if (t >= durMs) break;
    out.add((atMs: t, midi: figure[i], lengthMs: length));
    t += unit;
  }
  return out.isEmpty ? [(atMs: 0, midi: midi, lengthMs: durMs)] : out;
}
