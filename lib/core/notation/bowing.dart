// lib/core/notation/bowing.dart
//
// Which way the bow goes. The left-hand arranger says where to put the fingers;
// this says whether each note is pulled (down-bow, ⊓) or pushed (up-bow, ∨) —
// the other half of what an edited string part tells a player.
//
// Pure rules, no search: unlike fingering, bowing has no large space of plausible
// answers to optimise over. A teacher's markings follow a short list of
// conventions, and the conventions are the algorithm:
//
//  1. **Alternate.** The default is down, up, down, up — the bow has two
//     directions and you use them in turn.
//  2. **A slur is one stroke.** Every note under a slur is taken in the same bow,
//     so a slurred group counts once for the alternation.
//  3. **A rest restarts.** After a break the bow is reset to the frog, so the next
//     note is a down-bow.
//  4. **The rule of the down-bow.** The bar's first note wants a down-bow, because
//     the strong beat wants the stronger stroke. When plain alternation would put
//     an up-bow there, the player RETAKES — lifts and starts down again, printed
//     as two down-bows in a row. That retake is the one thing here that a naive
//     alternator gets wrong, and it is what makes printed bowings look the way
//     they do.
//
// Deliberately NOT modelled: hooked bowings (two notes in one stroke to fix the
// parity without a retake), the whole-bow/half-bow economy that decides retakes in
// fast music, and style (a Baroque player and a Romantic one bow the same bar
// differently). Those are choices, not rules, and a wrong guess would be worse
// than no mark.

import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Articulation, NoteElement, RestElement, Score;

/// A bow direction per note-element id: [Articulation.downBow] (pulled) or
/// [Articulation.upBow] (pushed).
///
/// Only voice 1 is bowed — a second voice on the same staff is another player's
/// line, and its bowing is their business.
Map<String, Articulation> bowingFor(Score score) {
  // Notes under a slur share one stroke, so map every slurred note to the id of
  // the note that STARTS its stroke.
  final index = <String, (int measure, int position)>{};
  var measureIndex = 0;
  for (final measure in score.measures) {
    var position = 0;
    for (final element in measure.elements) {
      if (element is NoteElement && element.id != null) {
        index[element.id!] = (measureIndex, position);
      }
      position++;
    }
    measureIndex++;
  }
  final strokeOwner = <String, String>{};
  for (final slur in score.slurs) {
    final from = index[slur.startId];
    final to = index[slur.endId];
    if (from == null || to == null) continue;
    var m = 0;
    for (final measure in score.measures) {
      var p = 0;
      for (final element in measure.elements) {
        if (element is NoteElement && element.id != null) {
          final at = (m, p);
          final afterStart =
              at.$1 > from.$1 || (at.$1 == from.$1 && at.$2 >= from.$2);
          final beforeEnd = at.$1 < to.$1 || (at.$1 == to.$1 && at.$2 <= to.$2);
          if (afterStart && beforeEnd) strokeOwner[element.id!] = slur.startId;
        }
        p++;
      }
      m++;
    }
  }

  final out = <String, Articulation>{};
  // The direction the NEXT new stroke takes. A piece starts down-bow.
  var next = Articulation.downBow;
  var firstInBar = true;
  for (final measure in score.measures) {
    firstInBar = true;
    for (final element in measure.elements) {
      if (element is RestElement) {
        // Rule 3: the bow resets over a break.
        next = Articulation.downBow;
        continue;
      }
      if (element is! NoteElement || element.id == null) continue;
      final owner = strokeOwner[element.id!];
      if (owner != null && owner != element.id) {
        // Rule 2: mid-slur — same stroke as the note that began it, and no mark
        // of its own (the slur already says "keep going").
        firstInBar = false;
        continue;
      }
      var direction = next;
      if (firstInBar && direction == Articulation.upBow) {
        // Rule 4: the retake. Start the bar down instead, and pay for it by
        // taking two down-bows in a row.
        direction = Articulation.downBow;
      }
      out[element.id!] = direction;
      next = direction == Articulation.downBow
          ? Articulation.upBow
          : Articulation.downBow;
      firstInBar = false;
    }
  }
  return out;
}
