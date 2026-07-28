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
// ⚠ Deliberately NOT modelled: barre chords (one finger stopping several strings),
// thumb-over-the-neck bass notes, and finger substitution on a held note. Each is
// real technique that the digits alone cannot express, and guessing at them would
// produce confident nonsense. Where a chord shape needs a barre, the digits here
// will name four separate fingers — correct as far as it goes, and honest about
// what it does not know. See PLAN.md if that becomes worth doing properly.
//
// Pure Dart, Flutter-free (crisp_notation_core only), so it runs headless.

import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// How many frets the hand covers without moving. Four is the usual teaching
/// span (one finger per fret); a stretchy player or a wide chord exceeds it, and
/// then the hand simply re-anchors.
const int kGuitarHandSpan = 4;

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

  final out = <String, List<int>>{};
  int? position; // lowest fret currently under the index finger

  for (var i = 0; i < notes.length && i < frettings.length; i++) {
    final id = notes[i].id;
    final shape = frettings[i];
    if (shape.isEmpty) continue;

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

    if (id == null) continue;
    // Fingers follow the PITCH order the note stores (low → high), not the
    // string order, so digit i belongs to pitch i.
    final byString = shape.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // string 0 = highest
    final fingers = <int>[];
    for (final e in byString) {
      final fret = e.value;
      if (fret == 0) {
        fingers.add(0);
        continue;
      }
      final f = fret - (position ?? fret) + 1;
      fingers.add(f.clamp(1, handSpan));
    }
    if (fingers.isNotEmpty) out[id] = fingers;
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
