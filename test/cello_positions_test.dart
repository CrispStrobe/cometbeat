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
  _positionNameTests();
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

/// Position NAMES, added 2026-07-27 after Becker's `7. Fingersatz. Positionen`
/// showed our slot indices are not what a cellist says.
void _positionNameTests() {
  group('position names are diatonic, not semitone-counted', () {
    test('slots 1-4 are 1st, 2nd, raised-2nd and 3rd position', () {
      expect(celloPositionName(1), (number: 1, raised: false));
      expect(celloPositionName(2), (number: 2, raised: false));
      expect(celloPositionName(3), (number: 2, raised: true));
      // The one that used to mislead: slot 4 is THIRD position, not fourth.
      expect(celloPositionName(4), (number: 3, raised: false));
    });

    test(
      'there is no raised 1st or raised 4th — the letters are a semitone apart',
      () {
        // B->C and E->F leave no chromatic step to name, which is exactly Becker's
        // argument for the scheme being diatonic.
        final names = [for (var p = 1; p <= 10; p++) celloPositionName(p)];
        expect(names.any((n) => n.number == 1 && n.raised), isFalse);
        expect(names.any((n) => n.number == 4 && n.raised), isFalse);
        // ...but raised 2nd, 3rd, 5th and 6th all exist.
        for (final n in [2, 3, 5, 6]) {
          expect(
            names.any((m) => m.number == n && m.raised),
            isTrue,
            reason: 'expected a raised $n',
          );
        }
      },
    );

    test('the chip label marks raised positions and is never empty', () {
      expect(celloPositionLabel(1), '1');
      expect(celloPositionLabel(3), '2♯');
      expect(celloPositionLabel(4), '3');
      for (var p = 1; p <= kMaxGamePosition; p++) {
        expect(celloPositionLabel(p), isNotEmpty);
      }
    });

    test(
      'slot 4 names third position AND holds third position, consistently',
      () {
        // The label must describe the notes the slot actually teaches: in third
        // position D is the FIRST finger, which is what the old numbering got wrong.
        final notes = celloNotesInPosition(4);
        final dOnA = notes.firstWhere(
          (n) => n.string == CelloString.a && n.pitch.step == Step.d,
        );
        expect(dOnA.finger, 1);
        expect(celloPositionName(4).number, 3);
      },
    );
  });
}
