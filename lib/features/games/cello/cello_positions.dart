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

/// Highest position these games offer. Fourth position is where the neck-position
/// repertoire a learner meets lives; above it the hand starts moving over the
/// shoulder of the instrument and the pedagogy changes.
const int kMaxGamePosition = 4;

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
