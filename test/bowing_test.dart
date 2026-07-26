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

List<String> _pattern(Score score) {
  final bowing = bowingFor(score);
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
}
