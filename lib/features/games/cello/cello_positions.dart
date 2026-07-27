// lib/features/games/cello/cello_positions.dart
//
// The notes a cellist can reach in a given neck position, DERIVED from the bowed
// arranger's hand model (`core/notation/bowed_arranger.dart`) instead of typed
// out by hand.
//
// `cello_first_position.dart` holds a hand-typed table read off a method book,
// which is why the Cello Corner's games could only ever ask about first position.
// The frame model already knows every position — fingers a semitone apart,
// anchored a whole step above the open string in first position and one semitone
// higher per position after that — so the pool for any position is a derivation,
// not more typing.
//
// The hand-typed table stays: `celloNotesInPosition(1)` must reproduce it exactly
// (`test/cello_positions_test.dart`). That is the point of keeping it — a book
// wrote it, this file did not, so it is an independent check on the geometry.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// Highest position SLOT these games offer.
///
/// ⚠ This is an internal slot index, NOT the number a cellist would say. The slots
/// step by a semitone (slot `n` anchors at `n + 1` semitones above the open
/// string); real position names step by a LETTER. Slots 1–4 therefore cover what a
/// teacher calls 1st, 2nd, raised-2nd and 3rd position — see [celloPositionName],
/// which is what the UI must display. Raising this to 6 would add raised-3rd and
/// 4th position; that is a content decision, not a naming one, and is not made here.
const int kMaxGamePosition = 4;

/// What a cellist CALLS the hand at game slot [position] — the number plus whether
/// it is the "raised" (Becker: *erhöhte*) variant.
///
/// Cello positions are numbered by LETTER NAME, not by semitone: the number is the
/// scale degree the first finger takes above the open string. On the A string that
/// is B = 1st, C = 2nd, D = 3rd, E = 4th, F = 5th, G = 6th, A = 7th. A chromatic
/// step between two of those is the lower one "raised" — and it only exists where
/// the letters are a whole tone apart. There is no raised 1st (B→C is already a
/// semitone) and no raised 4th (E→F likewise), which is precisely the argument
/// Becker makes in *Fingersatz. Positionen*: he prints `1ste · 2te · 2te erhöhte ·
/// 3te · 3te erhöhte` and never a `1ste erhöhte`.
///
/// Keeping the slots in semitones and naming them only here is deliberate: the
/// arranger's Viterbi reasons in semitone anchors, and nothing about the search
/// should depend on what humans call the result.
({int number, bool raised}) celloPositionName(int position) {
  final anchor = BowedInstrument.cello.anchorOfPosition(position);
  // Semitones above the open string -> (degree, raised). Index = anchor.
  const table = <int, (int, bool)>{
    2: (1, false), // B  — 1st
    3: (2, false), // C  — 2nd
    4: (2, true), //  C♯ — 2nd raised
    5: (3, false), // D  — 3rd
    6: (3, true), //  D♯ — 3rd raised
    7: (4, false), // E  — 4th
    8: (5, false), // F  — 5th
    9: (5, true), //  F♯ — 5th raised
    10: (6, false), // G — 6th
    11: (6, true), //  G♯ — 6th raised
    12: (7, false), // A — 7th
  };
  final e = table[anchor];
  // Below first position is the "half position"; above the 7th the thumb takes
  // over and the neck numbering stops meaning anything. Both fall back to the
  // slot index rather than inventing a name.
  if (e == null) return (number: position, raised: false);
  return (number: e.$1, raised: e.$2);
}

/// The chip/label text for game slot [position]: `1`, `2`, `2♯`, `3`…
///
/// The raised variants get a ♯ suffix because a chip has room for two glyphs and
/// not for a word; screen readers and tooltips should use the spelled-out l10n form
/// (`celloPositionRaised`) instead, since "♯" is not what anyone says out loud.
String celloPositionLabel(int position) {
  final n = celloPositionName(position);
  return n.raised ? '${n.number}♯' : '${n.number}';
}

/// The naturals reachable in neck [position] (1 = first position, the default),
/// low string to high, ascending within each string.
///
/// Naturals only, like the method-book table: a quiz that asks "which finger?"
/// about a G♯ teaches the fingerboard, not the piece. Open strings are included
/// only in first position and below — from third position the hand is not near
/// the nut, and an open string there is a different decision (a colour, or a
/// convenience), not part of the position's shape.
List<CelloNote> celloNotesInPosition(int position) {
  final inst = BowedInstrument.cello;
  final anchor = inst.anchorOfPosition(position);
  final frame = frameOf(inst, BowedHandMode.neck, anchor);
  final fingers = frame.keys.toList()..sort();

  final out = <CelloNote>[];
  // Lowest string first (index 3 = C), to read like the method book.
  for (var s = inst.tuning.strings.length - 1; s >= 0; s--) {
    final open = inst.tuning.strings[s].midiNumber;
    final string = _stringOf(s);
    if (position <= 1) {
      final openPitch = _naturalOf(open);
      if (openPitch != null) out.add(CelloNote(openPitch, string, 0));
    }
    for (final finger in fingers) {
      final pitch = _naturalOf(open + frame[finger]!);
      if (pitch == null) continue; // a sharp/flat — not part of the pool
      out.add(CelloNote(pitch, string, finger));
    }
  }
  return out;
}

/// [Pitch] for [midi] when it spells a natural, else null. Deliberately not
/// `Pitch.fromMidi`: that has to choose a spelling for the black keys, and here
/// "there is no natural" is the answer we want rather than an arbitrary sharp.
Pitch? _naturalOf(int midi) {
  const steps = <int, Step>{
    0: Step.c,
    2: Step.d,
    4: Step.e,
    5: Step.f,
    7: Step.g,
    9: Step.a,
    11: Step.b,
  };
  final step = steps[midi % 12];
  if (step == null) return null;
  return Pitch(step, octave: midi ~/ 12 - 1);
}

CelloString _stringOf(int index) => switch (index) {
      0 => CelloString.a,
      1 => CelloString.d,
      2 => CelloString.g,
      _ => CelloString.c,
    };
