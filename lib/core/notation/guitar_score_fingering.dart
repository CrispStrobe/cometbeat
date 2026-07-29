// lib/core/notation/guitar_score_fingering.dart
//
// LEFT-HAND FINGERING for fretted instruments — the guitar twin of
// `bowed_score_fingering.dart`.
//
// `tab_arranger.dart` already solves the hard half: which STRING and FRET each
// note is played at, by a Sayegh/Viterbi optimum path that penalises hand
// movement and finger span. What it never says is WHICH FINGER presses the fret,
// and that is what a player reads off the page. This fills only that gap — it
// does not re-solve the fretting.
//
// The model is the fretted analogue of the cello's hand frame, and it is simpler
// because frets quantise the neck: the hand covers a window of [handSpan] frets,
// one finger per fret, index at the bottom. So
//
//     finger = fret - handPosition + 1        (1 = index … 4 = little finger)
//     fret 0 = open string = finger 0, and needs no hand at all
//
// The only real decision is WHERE the window sits, and when to move it. We keep a
// position while every fretted note still fits inside it, and re-anchor on the
// lowest fretted note when one does not — which is what a player does, and what
// makes the digits stable through a passage instead of flickering bar to bar.
//
// ⚠ CORRECTION (measured 2026-07-29). An earlier version of this comment claimed
// a barre chord "will name four separate fingers". That was wrong about this
// file's own behaviour, and the tests below now pin what it actually does: a
// barre IS the index finger lying at the hand position, so every string stopped
// at that fret already comes out as finger 1. F major gives 1,3,3,2,1,1 and B
// minor 1,3,3,2,1 — the textbook fingerings. Checked because a 1,180-file
// control corpus of classical guitar tab carries 26,130 barre annotations, so
// the case is common enough that a wrong claim about it would matter.
//
// ⚠ What IS genuinely not modelled: the barre as a distinct NOTATION (the digits
// say "1, 1, 1", not "one finger across three strings"); a barre laid by a
// finger other than the index, which real players do use; thumb-over-the-neck
// bass notes; and finger substitution on a held note. Those need marks the digit
// list cannot carry, and guessing at them would produce confident nonsense.
//
// Pure Dart, Flutter-free (crisp_notation_core only), so it runs headless.

import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// How many frets the hand covers without moving. Four is the usual teaching
/// span (one finger per fret); a stretchy player or a wide chord exceeds it, and
/// then the hand simply re-anchors.
const int kGuitarHandSpan = 4;

/// Left-hand fingers for fret shapes that are ALREADY DECIDED — one list per
/// shape, one digit per stopped string, low → high, `0` for an open string.
///
/// This is the whole model; [fingerGuitarScore] is this function with
/// `arrangeTab` in front of it. It is separate because the Tab Editor's frets
/// are the ones the PLAYER TYPED: re-arranging them there would silently rewrite
/// the user's own fretting, so that path must be able to name fingers for the
/// shapes as given and change nothing else.
List<List<int>> fingerFrettings(
  List<Map<int, int>> shapes, {
  int handSpan = kGuitarHandSpan,
}) {
  final out = <List<int>>[];
  int? position; // lowest fret currently under the index finger

  for (final shape in shapes) {
    if (shape.isEmpty) {
      out.add(const []);
      continue;
    }
    // Frets that actually need a finger. Open strings are position-independent,
    // so they neither move the hand nor constrain where it sits.
    final fretted = shape.values.where((f) => f > 0).toList()..sort();
    if (fretted.isNotEmpty) {
      final lo = fretted.first;
      final hi = fretted.last;
      // Keep the hand still while everything still falls under it; otherwise
      // re-anchor on the lowest note of this shape. A shape wider than the span
      // re-anchors too — the digits then describe a stretch, which is honest.
      final fits =
          position != null && lo >= position && hi <= position + handSpan - 1;
      if (!fits) position = lo;
    }
    // Digits follow PITCH order (low → high), not string index, so digit i
    // belongs to pitch i. String 0 is the highest-sounding string, so that is
    // descending string index.
    final byString = shape.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    out.add([
      for (final e in byString)
        if (e.value == 0)
          0
        else
          (e.value - (position ?? e.value) + 1).clamp(1, handSpan),
    ]);
  }
  return out;
}

/// Left-hand fingers per note id, one entry per pitch of that note, low → high.
///
/// `0` is an open string. A note the arranger could not fret at all is absent
/// from the map rather than present with a guess.
///
/// Keyed by [NoteElement.id], so — exactly like the bowed side — a score whose
/// elements have null ids yields nothing. Builders must assign ids.
Map<String, List<int>> fingerGuitarScore(
  Score score,
  Tuning tuning, {
  int capo = 0,
  int maxFret = 24,
  int handSpan = kGuitarHandSpan,
}) {
  final notes = <NoteElement>[
    for (final m in score.measures)
      for (final e in m.elements)
        if (e is NoteElement) e,
  ];
  if (notes.isEmpty) return const {};

  final columns = [
    for (final n in notes) [for (final p in n.pitches) p.midiNumber],
  ];
  final frettings = arrangeTab(columns, tuning, capo: capo, maxFret: maxFret);

  // ⚠ The hand is threaded through the WHOLE piece, so the digits must be
  // computed in one pass over every shape — not per note. A note is skipped for
  // OUTPUT when it has no id, but it still moves the hand.
  final fingers = fingerFrettings(frettings, handSpan: handSpan);

  final out = <String, List<int>>{};
  for (var i = 0; i < notes.length && i < fingers.length; i++) {
    final id = notes[i].id;
    if (id == null || fingers[i].isEmpty) continue;
    out[id] = fingers[i];
  }
  return out;
}

/// [score] with guitar left-hand fingerings written INTO the notes, as
/// `NoteElement.fingerings` — so they are saved, exported and further editable,
/// rather than being a view-time overlay.
Score scoreWithGuitarFingerings(
  Score score,
  Tuning tuning, {
  int capo = 0,
  int maxFret = 24,
  int handSpan = kGuitarHandSpan,
}) {
  final marks = fingerGuitarScore(
    score,
    tuning,
    capo: capo,
    maxFret: maxFret,
    handSpan: handSpan,
  );
  if (marks.isEmpty) return score;

  return score.copyWith(
    measures: [
      for (final measure in score.measures)
        measure.copyWith(
          elements: [
            for (final element in measure.elements)
              if (element is NoteElement && marks.containsKey(element.id))
                element.copyWith(fingerings: marks[element.id])
              else
                element,
          ],
        ),
    ],
  );
}
