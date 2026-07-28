// test/playability_test.dart
//
// SE-C3. The claims worth pinning: a warning is only ever a warning, the name
// matching survives the orthography the corpus actually contains, and a note is
// flagged ONCE with the reason a player can act on.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/core/notation/playability.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

Score _score(List<int> midi, {Clef clef = Clef.bass}) {
  var n = 0;
  return Score(
    clef: clef,
    measures: [
      Measure([
        for (final m in midi)
          NoteElement.note(
            Pitch.fromMidi(m),
            NoteDuration.quarter,
            id: 'e${n++}',
          ),
      ]),
    ],
  );
}

void main() {
  const celloRange = (lowMidi: 36, highMidi: 81);

  group('resolving an instrument from its name', () {
    test('the plain names, in both app languages', () {
      expect(canonicalBowedName('Cello'), 'cello');
      expect(canonicalBowedName('Violoncello'), 'cello');
      expect(canonicalBowedName('Violine'), 'violin');
      expect(canonicalBowedName('Viola'), 'viola');
      expect(canonicalBowedName('Bratsche'), 'viola');
      expect(canonicalBowedName('Kontrabass'), 'doubleBass');
    });

    test('a longer name that CONTAINS a shorter one resolves to the longer',
        () {
      // The trap this ordering exists for: every cello is a "violon…", and
      // every contrabass is a "…bass".
      expect(canonicalBowedName('Violoncello'), isNot('violin'));
      expect(canonicalBowedName('Contrabasso'), 'doubleBass');
    });

    test('period orthography still matches — the long s cost us 11 files once',
        () {
      expect(canonicalBowedName('Baſso.'), 'doubleBass');
      expect(canonicalBowedName('Violoncello e Baſſo'), 'cello');
    });

    test('a name that is not a bowed instrument resolves to nothing', () {
      expect(canonicalBowedName('Soprano'), isNull);
      expect(canonicalBowedName('Piano'), isNull);
      expect(canonicalBowedName(''), isNull);
      expect(canonicalBowedName(null), isNull);
    });
  });

  group('the range check', () {
    test('a part inside its compass is not flagged', () {
      // C3 G3 C4 — comfortably within a cello.
      final w = checkPlayability(_score([48, 55, 60]), range: celloRange);
      expect(w, isEmpty);
    });

    test('flags what is below and above, and says which', () {
      // B1 (below C2) · C4 (fine) · C6 (above A5).
      final w = checkPlayability(_score([35, 60, 84]), range: celloRange);
      expect(w, hasLength(2));
      expect(w.first.elementId, 'e0');
      expect(w.first.issue, PlayabilityIssue.belowRange);
      expect(w.last.elementId, 'e2');
      expect(w.last.issue, PlayabilityIssue.aboveRange);
    });

    test('the boundary notes themselves are IN range', () {
      final w = checkPlayability(_score([36, 81]), range: celloRange);
      expect(w, isEmpty, reason: 'the compass is inclusive at both ends');
    });

    test('a chord is judged by its extremes, not its first pitch', () {
      final score = Score(
        clef: Clef.bass,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch.fromMidi(60), Pitch.fromMidi(90)], // C4 + F#6
              duration: NoteDuration.quarter,
              id: 'c0',
            ),
          ]),
        ],
      );
      final w = checkPlayability(score, range: celloRange);
      expect(w, hasLength(1));
      expect(w.single.issue, PlayabilityIssue.aboveRange);
      expect(w.single.midi, 90);
    });
  });

  group('the reach check', () {
    test('a first-position player is warned about a passage that shifts', () {
      // A4 (69) is well inside a cello but nowhere near first position.
      //
      // ⚠ This is the case that showed the FIRST design of this check was
      // measuring nothing: the skill limits are soft costs, so the arranger
      // returns a fingering here — in 7th position — and "did the arranger
      // place it?" answers yes for almost every note in range. The question
      // that means something is whether the fingering STAYED IN the level.
      final w = checkPlayability(
        _score([69]),
        range: celloRange,
        instrument: BowedInstrument.cello,
        skill: BowedSkill.firstPosition,
      );
      expect(w, hasLength(1));
      expect(w.single.issue, PlayabilityIssue.outOfReach);
    });

    test('…and the SAME passage is fine for a player who shifts', () {
      final w = checkPlayability(
        _score([69]),
        range: celloRange,
        instrument: BowedInstrument.cello,
        skill: BowedSkill.advanced,
      );
      expect(
        w,
        isEmpty,
        reason: 'out-of-reach is a statement about the PLAYER, not the note',
      );
    });

    test('a note off the instrument is flagged once, for the reason that acts',
        () {
      // B1 is below the C string: "and it is also unreachable" helps nobody.
      final w = checkPlayability(
        _score([35]),
        range: celloRange,
        instrument: BowedInstrument.cello,
        skill: BowedSkill.firstPosition,
      );
      expect(w, hasLength(1));
      expect(w.single.issue, PlayabilityIssue.belowRange);
    });

    test('without an instrument, only the range is judged', () {
      // No arranger profile (violin/viola) ⇒ no reach claim at all, rather
      // than a claim made with the wrong instrument's hand.
      final w = checkPlayability(_score([69]), range: celloRange);
      expect(w, isEmpty);
    });
  });

  group('what it refuses to do', () {
    test('it never changes the score — a warning is not a correction', () {
      final score = _score([35, 84]);
      final before = score.measures.first.elements
          .whereType<NoteElement>()
          .map((n) => n.pitches.first.midiNumber)
          .toList();
      checkPlayability(
        score,
        range: celloRange,
        instrument: BowedInstrument.cello,
        skill: BowedSkill.firstPosition,
      );
      final after = score.measures.first.elements
          .whereType<NoteElement>()
          .map((n) => n.pitches.first.midiNumber)
          .toList();
      expect(after, before);
    });

    test('an empty score, and notes without ids, yield nothing', () {
      expect(checkPlayability(_score(const []), range: celloRange), isEmpty);
      final anon = Score(
        clef: Clef.bass,
        measures: [
          Measure([NoteElement.note(Pitch.fromMidi(20), NoteDuration.quarter)]),
        ],
      );
      expect(checkPlayability(anon, range: celloRange), isEmpty);
    });

    test('with no range and no instrument it claims nothing', () {
      expect(checkPlayability(_score([1, 2, 127])), isEmpty);
    });
  });
}
