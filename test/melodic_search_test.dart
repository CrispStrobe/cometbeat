// Melodic search over the corpus incipits.
//
// The corpus feature index has carried an `incipit` on 38,417 of the catalog's
// 38,427 score rows since the backfill, and nothing has ever read it. These
// tests pin the three decisions that decide whether searching it works on real
// input rather than only on input we generated ourselves — every one of them
// would still pass a naive "does it find an exact copy" test.

import 'package:comet_beat/core/music/melodic_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Twinkle, twinkle, little star" — C C G G A A G.
const _twinkle = [60, 60, 67, 67, 69, 69, 67];

/// "Frère Jacques" — C D E C.
const _frere = [60, 62, 64, 60];

/// "Ode to Joy" — E E F G G F E D.
const _ode = [64, 64, 65, 67, 67, 65, 64, 62];

List<MelodicCandidate> get _pool => const [
      MelodicCandidate('twinkle', _twinkle),
      MelodicCandidate('frere', _frere),
      MelodicCandidate('ode', _ode),
    ];

void main() {
  group('intervalsOf', () {
    test('is the diff, so it is one shorter than the input', () {
      expect(intervalsOf([60, 62, 64]), [2, 2]);
    });

    test('a single note has NO shape', () {
      // Returning [0] or [60] here would make every one-note row match
      // everything, which is worse than returning nothing.
      expect(intervalsOf([60]), isEmpty);
      expect(intervalsOf(const []), isEmpty);
    });
  });

  group('decision 1 — intervals, not pitches', () {
    test('a transposed query still finds the tune', () {
      // Someone hums where their voice sits. Matching absolute pitch would only
      // ever find the right key by accident.
      final up = [for (final p in _twinkle) p + 7];
      final hits = searchMelodies(up, _pool);
      expect(hits.first.id, 'twinkle');
      expect(hits.first.score, 1.0);
    });

    test('every transposition scores identically', () {
      final scores = <double>{
        for (final shift in [-24, -5, 0, 3, 11])
          searchMelodies([for (final p in _ode) p + shift], _pool).first.score,
      };
      expect(scores.length, 1, reason: 'transposition changed the score');
    });
  });

  group('decision 2 — edit distance, not equality', () {
    test('a DROPPED note still finds the tune', () {
      final dropped = [..._twinkle]..removeAt(3);
      expect(searchMelodies(dropped, _pool).first.id, 'twinkle');
    });

    test('an ADDED passing note still finds the tune', () {
      final added = [..._twinkle]..insert(3, 68);
      expect(searchMelodies(added, _pool).first.id, 'twinkle');
    });

    test('an exact query beats an edited one on score', () {
      final exact = searchMelodies(_ode, _pool).first.score;
      final edited = searchMelodies([..._ode]..removeAt(2), _pool).first.score;
      expect(exact, greaterThan(edited));
    });
  });

  group('decision 3 — a near miss is cheaper than a wrong note', () {
    test('a semitone-flat note ranks above a wrong-direction leap', () {
      final flat = [..._ode]..[2] = 64; // F -> E, one semitone out
      final wrong = [..._ode]..[2] = 55; // F -> G below, a wrong leap
      final flatScore = searchMelodies(flat, _pool).first.score;
      final wrongScore = searchMelodies(wrong, _pool).first.score;
      expect(flatScore, greaterThan(wrongScore));
    });

    test('substitution cost grows with distance but is capped', () {
      expect(substitutionCost(2, 2), 0);
      expect(substitutionCost(2, 3), lessThan(substitutionCost(2, 6)));
      // Capped, so one wild note cannot dominate an otherwise good match.
      expect(substitutionCost(2, 40), substitutionCost(2, 80));
    });
  });

  group('short queries — "I only remember the first few notes"', () {
    test('four notes are enough to identify a tune', () {
      // The query is matched against the candidate PREFIX. Compared against a
      // whole 16-note incipit instead, the notes the user never sang would
      // dominate and every short query would score alike.
      expect(searchMelodies(_frere, _pool).first.id, 'frere');
    });

    test('a short query is not penalised for being short', () {
      final short = searchMelodies(_ode.sublist(0, 4), _pool).first;
      expect(short.id, 'ode');
      expect(short.score, 1.0);
    });

    test('a long catalog incipit does not out-rank a matching short one', () {
      final pool = [
        const MelodicCandidate('short', [60, 62, 64]),
        // Same opening, then wanders off.
        const MelodicCandidate('long', [60, 62, 64, 80, 40, 75, 41, 79]),
      ];
      final hits = searchMelodies([60, 62, 64], pool);
      expect(hits.first.score, 1.0);
      expect(hits.map((h) => h.id), containsAll(['short', 'long']));
    });
  });

  group('ranking and limits', () {
    test('results are sorted best-first', () {
      final hits = searchMelodies(_twinkle, _pool);
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
      }
    });

    test('limit is honoured', () {
      expect(searchMelodies(_twinkle, _pool, limit: 2).length, 2);
    });

    test('minScore filters the tail', () {
      final all = searchMelodies(_twinkle, _pool);
      final strict = searchMelodies(_twinkle, _pool, minScore: 0.99);
      expect(strict.length, lessThan(all.length));
      expect(strict.first.id, 'twinkle');
    });

    test('an empty or single-note query returns nothing, not everything', () {
      expect(searchMelodies(const [], _pool), isEmpty);
      expect(searchMelodies(const [60], _pool), isEmpty);
    });

    test('a candidate with no usable incipit is skipped, not crashed on', () {
      final pool = [
        const MelodicCandidate('empty', []),
        const MelodicCandidate('one', [60]),
        const MelodicCandidate('ode', _ode),
      ];
      final hits = searchMelodies(_ode, pool);
      expect(hits.map((h) => h.id), ['ode']);
    });
  });

  group('melodicDistance', () {
    test('is zero for identical sequences and symmetric', () {
      expect(melodicDistance([2, 2, -1], [2, 2, -1]), 0);
      expect(
        melodicDistance([2, 2], [2, 3, 2]),
        melodicDistance([2, 3, 2], [2, 2]),
      );
    });

    test('an empty side costs one indel per element', () {
      expect(melodicDistance(const [], [1, 2, 3]), 3 * kIndelCost);
    });
  });
}
