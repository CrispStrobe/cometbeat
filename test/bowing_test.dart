// test/bowing_test.dart
//
// Bow direction. The interesting case is the retake: plain alternation is easy,
// and the thing that makes a printed bowing look printed is the bar whose
// downbeat would otherwise fall on an up-bow.

import 'package:comet_beat/core/notation/bowing.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// [counts] notes per bar, ids `n0`, `n1`, … in reading order.
Score _bars(List<int> counts, {List<Slur> slurs = const []}) {
  var i = 0;
  return Score(
    clef: Clef.bass,
    measures: [
      for (final count in counts)
        Measure([
          for (var k = 0; k < count; k++)
            NoteElement.note(
              const Pitch(Step.d, octave: 3),
              NoteDuration.quarter,
              id: 'n${i++}',
            ),
        ]),
    ],
    slurs: slurs,
  );
}

List<String> _pattern(
  Score score, {
  Map<String, Articulation> locked = const {},
}) {
  final bowing = bowingFor(score, locked: locked);
  final out = <String>[];
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is! NoteElement) continue;
      final mark = bowing[element.id];
      out.add(
        mark == null
            ? '.'
            : mark == Articulation.downBow
                ? 'D'
                : 'U',
      );
    }
  }
  return out;
}

void main() {
  test('the default is strict alternation, starting down', () {
    expect(_pattern(_bars([4])), ['D', 'U', 'D', 'U']);
  });

  test('an even bar keeps alternating across the barline', () {
    expect(_pattern(_bars([4, 4])), ['D', 'U', 'D', 'U', 'D', 'U', 'D', 'U']);
  });

  test('an odd bar forces a retake — two down-bows in a row', () {
    // Three notes leave the bow going up when the next bar starts, and the
    // downbeat wants a down-bow. The player retakes; editions print D D.
    expect(_pattern(_bars([3, 3])), ['D', 'U', 'D', 'D', 'U', 'D']);
  });

  test('a slur is one stroke: only its first note is marked', () {
    // Four notes, the middle two slurred: D (U for the pair) D.
    final score = _bars([4], slurs: const [Slur('n1', 'n2')]);
    expect(_pattern(score), ['D', 'U', '.', 'D']);
  });

  test('a slurred pair counts once for the alternation', () {
    // Without the slur this bar would end up-bow; with it, the pair eats one
    // stroke and the last note lands down.
    expect(_pattern(_bars([4])).last, 'U');
    expect(_pattern(_bars([4], slurs: const [Slur('n1', 'n2')])).last, 'D');
  });

  test('a rest resets the bow to a down-bow', () {
    final score = Score(
      clef: Clef.bass,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
            id: 'a',
          ),
          const RestElement(NoteDuration.quarter),
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
            id: 'b',
          ),
        ]),
      ],
    );
    final bowing = bowingFor(score);
    expect(bowing['a'], Articulation.downBow);
    // Without the reset this would be an up-bow.
    expect(bowing['b'], Articulation.downBow);
  });

  test('notes without ids are skipped rather than mis-marked', () {
    final score = Score(
      clef: Clef.bass,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
          ),
          NoteElement.note(
            const Pitch(Step.d, octave: 3),
            NoteDuration.quarter,
            id: 'kept',
          ),
        ]),
      ],
    );
    expect(bowingFor(score).keys, ['kept']);
  });

  test('an empty score bows nothing', () {
    expect(bowingFor(const Score(clef: Clef.bass, measures: [])), isEmpty);
  });

  group('a stroke the player locks (SE-C4)', () {
    test('the lock is obeyed, and the REST RE-FLOWS from it', () {
      // Unlocked this is D U D U. Lock note 1 to a down-bow and everything
      // after it must follow from that choice — not carry on as if nothing
      // had happened, which is what editing the mark by hand would leave.
      expect(_pattern(_bars([4])), ['D', 'U', 'D', 'U']);
      expect(
        _pattern(_bars([4]), locked: {'n1': Articulation.downBow}),
        ['D', 'D', 'U', 'D'],
        reason: 'a bowing is a chain: pin one link and the rest must move',
      );
    });

    test('a lock outranks the rule of the down-bow', () {
      // n3 is a downbeat, which normally forces a retake to D (see the odd-bar
      // test above). Asking for an up-bow there must WIN — a retake silently
      // undoing the player's decision is the failure this guards.
      expect(_pattern(_bars([3, 3])), ['D', 'U', 'D', 'D', 'U', 'D']);
      expect(
        _pattern(_bars([3, 3]), locked: {'n3': Articulation.upBow}),
        ['D', 'U', 'D', 'U', 'D', 'U'],
      );
    });

    test('the re-flow still resets after a rest', () {
      // Locking must bend the alternation, not switch off the other rules.
      final score = Score(
        clef: Clef.bass,
        measures: [
          Measure([
            NoteElement.note(
              const Pitch(Step.d, octave: 3),
              NoteDuration.quarter,
              id: 'n0',
            ),
            const RestElement(NoteDuration.quarter),
            NoteElement.note(
              const Pitch(Step.d, octave: 3),
              NoteDuration.quarter,
              id: 'n1',
            ),
          ]),
        ],
      );
      final bowing = bowingFor(score, locked: {'n0': Articulation.upBow});
      expect(bowing['n0'], Articulation.upBow);
      expect(
        bowing['n1'],
        Articulation.downBow,
        reason: 'the bow is back at the frog after the rest, lock or no lock',
      );
    });

    test('a lock on a note INSIDE a slur is ignored — it has no stroke to pick',
        () {
      // n2 is under the slur, so it carries no mark; locking it must not
      // invent one, and must not disturb the notes around it.
      final score = _bars([4], slurs: const [Slur('n1', 'n2')]);
      expect(_pattern(score), ['D', 'U', '.', 'D']);
      expect(
        _pattern(score, locked: {'n2': Articulation.downBow}),
        ['D', 'U', '.', 'D'],
      );
    });

    test('locking every note gives back exactly what was asked for', () {
      final locked = {
        'n0': Articulation.upBow,
        'n1': Articulation.upBow,
        'n2': Articulation.upBow,
        'n3': Articulation.downBow,
      };
      expect(_pattern(_bars([4]), locked: locked), ['U', 'U', 'U', 'D']);
    });

    test('locking a note to what it already was changes nothing', () {
      // The useful version of "an empty lock does nothing": a lock that AGREES
      // with the rules must be a no-op, or the re-flow would shuffle a part
      // every time a player confirmed a stroke they liked.
      expect(_pattern(_bars([3, 3])), ['D', 'U', 'D', 'D', 'U', 'D']);
      expect(
        _pattern(_bars([3, 3]), locked: {'n3': Articulation.downBow}),
        ['D', 'U', 'D', 'D', 'U', 'D'],
      );
    });
  });
}
