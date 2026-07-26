// test/cello_positions_test.dart
//
// The derived position pools. First position is checked against the hand-typed
// method-book table — that table is an independent witness (a book wrote it), so
// reproducing it exactly is the real proof the frame model is right.

import 'package:comet_beat/features/games/cello/cello_first_position.dart';
import 'package:comet_beat/features/games/cello/cello_positions.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

String _show(CelloNote n) =>
    '${n.pitch.step.name}${n.pitch.octave}/${n.string.name}${n.finger}';

void main() {
  test('first position reproduces the hand-typed table exactly', () {
    expect(
      celloNotesInPosition(1).map(_show).toList(),
      kCelloFirstPosition.map(_show).toList(),
    );
  });

  test('higher positions are real, and higher', () {
    for (var p = 2; p <= kMaxGamePosition; p++) {
      final notes = celloNotesInPosition(p);
      expect(notes, isNotEmpty, reason: 'position $p');
      // No open strings above first position.
      expect(notes.every((n) => n.finger != 0), isTrue, reason: 'position $p');
      // Every note is above the string it is played on.
      for (final n in notes) {
        expect(
          n.pitch.midiNumber,
          greaterThan(n.string.openPitch.midiNumber),
          reason: '${_show(n)} in position $p',
        );
      }
    }
  });

  test('the hand climbs one semitone per position', () {
    // The same finger on the same string sounds a semitone higher each position.
    int? midiOf(int position, CelloString string, int finger) {
      for (final n in celloNotesInPosition(position)) {
        if (n.string == string && n.finger == finger) return n.pitch.midiNumber;
      }
      return null; // that finger lands on a sharp in this position
    }

    // D string, first finger: E (pos 1) → F (pos 2) → F♯ is not a natural, so
    // position 3 has no first-finger natural there — the gap is the point.
    expect(
      midiOf(1, CelloString.d, 1),
      const Pitch(Step.e, octave: 3).midiNumber,
    );
    expect(
      midiOf(2, CelloString.d, 1),
      const Pitch(Step.f, octave: 3).midiNumber,
    );
    expect(midiOf(3, CelloString.d, 1), isNull);
    expect(
      midiOf(4, CelloString.d, 1),
      const Pitch(Step.g, octave: 3).midiNumber,
    );
  });

  test('naturals only — no accidental ever reaches a quiz', () {
    for (var p = 1; p <= kMaxGamePosition; p++) {
      for (final n in celloNotesInPosition(p)) {
        expect(n.pitch.alter, 0, reason: _show(n));
      }
    }
  });

  test('every note is unique within a position', () {
    for (var p = 1; p <= kMaxGamePosition; p++) {
      final shown = celloNotesInPosition(p).map(_show).toList();
      expect(shown.toSet().length, shown.length, reason: 'position $p');
    }
  });
}
