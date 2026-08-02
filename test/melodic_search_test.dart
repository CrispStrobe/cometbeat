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
  sungQueryTests();
  evidenceRankingTests();

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

// --- mode 2: a SUNG query ---------------------------------------------------

typedef _Note = ({int midi, double onMs, double offMs, double confidence});

_Note _n(int midi, double on, double off, [double conf = 0.9]) =>
    (midi: midi, onMs: on, offMs: off, confidence: conf);

void sungQueryTests() {
  group('a query longer than the incipit', () {
    test('a perfect match still scores 1.0 past the incipit length', () {
      // ⚠️ The regression this pins: `searchMelodies` used to truncate only the
      // CANDIDATE. A sung query easily runs past the catalog's 16-note incipit,
      // and every extra note then counted as an indel — a perfect match could
      // not score above ~0.7, so sung search would have looked broken while the
      // ranking was in fact right.
      final pool = [
        const MelodicCandidate('short', [60, 62, 64, 65]),
      ];
      final long = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79];
      final hits = searchMelodies(long, pool);
      expect(hits, isNotEmpty);
      expect(hits.first.score, 1.0);
    });

    test('a long query still discriminates between candidates', () {
      // Truncating to the common prefix must not make everything match.
      final pool = [
        const MelodicCandidate('right', [60, 62, 64, 65]),
        const MelodicCandidate('wrong', [60, 55, 70, 51]),
      ];
      final hits = searchMelodies(
        [60, 62, 64, 65, 67, 69, 71, 72],
        pool,
      );
      expect(hits.first.id, 'right');
      expect(hits.first.score, greaterThan(hits.last.score));
    });
  });

  group('melodyQueryFromNotes', () {
    test('keeps REPEATED pitches — they are the shape', () {
      // "C C G" is [0, +7]; "C G" is [+7]. Ode to Joy and Twinkle both open by
      // repeating a note, so collapsing repeats would delete their openings.
      final q = melodyQueryFromNotes([
        _n(60, 0, 400),
        _n(60, 400, 800),
        _n(67, 800, 1200),
      ]);
      expect(q, [60, 60, 67]);
    });

    test('drops the sub-100ms slides between pitches', () {
      // A glide artefact inserts an interval PAIR — in and out again — which
      // costs far more than the note is worth.
      final q = melodyQueryFromNotes([
        _n(60, 0, 400),
        _n(63, 400, 430), // 30 ms slide
        _n(67, 430, 900),
      ]);
      expect(q, [60, 67]);
    });

    test('drops low-confidence notes (breath, room noise)', () {
      final q = melodyQueryFromNotes([
        _n(60, 0, 400),
        _n(48, 400, 900, 0.2),
        _n(67, 900, 1400),
      ]);
      expect(q, [60, 67]);
    });

    test('caps the query at the incipit length', () {
      final many = [
        for (var i = 0; i < 40; i++)
          _n(60 + (i % 5), i * 300.0, i * 300.0 + 250),
      ];
      expect(melodyQueryFromNotes(many).length, kMaxSungQueryNotes);
    });

    test('silence in, nothing out', () {
      expect(melodyQueryFromNotes(const []), isEmpty);
      expect(melodyQueryFromNotes([_n(60, 0, 20)]), isEmpty);
    });
  });

  test('a sung Ode to Joy finds it end to end', () {
    // The whole mode-2 path minus the microphone: notes as a transcriber would
    // hand them over — transposed, with a slide artefact and a breath in it —
    // through the bridge and into the search.
    const ode = [64, 64, 65, 67, 67, 65, 64, 62];
    final pool = [
      const MelodicCandidate('ode', ode),
      const MelodicCandidate('scale', [60, 62, 64, 65, 67, 69, 71, 72]),
    ];
    final sung = <_Note>[
      _n(71, 0, 500), // sung a fifth up
      _n(71, 500, 1000),
      _n(74, 1000, 1020), // a slide, too short to count
      _n(72, 1020, 1500),
      _n(74, 1500, 2000),
      _n(40, 2000, 2400, 0.1), // a breath the detector pitched
      _n(74, 2400, 2900),
      _n(72, 2900, 3400),
      _n(71, 3400, 3900),
      _n(69, 3900, 4400),
    ];
    final query = melodyQueryFromNotes(sung);
    expect(query, [71, 71, 72, 74, 74, 72, 71, 69]);
    expect(searchMelodies(query, pool).first.id, 'ode');
  });
}

void evidenceRankingTests() {
  test('a thinly-evidenced row does not out-rank a well-evidenced one', () {
    // ⚠️ Measured, not hypothetical: scoring on the common prefix alone let
    // rows with a two-note incipit (ONE interval, which anything matches) flood
    // the top with 1.0s, and took an 8-note query from 51% top-1 to 34% on the
    // real 38k catalog. Equal score with less evidence must rank lower.
    final pool = [
      const MelodicCandidate('thin', [60, 62]), // one interval
      const MelodicCandidate('full', [60, 62, 64, 65, 67, 69]),
    ];
    final hits = searchMelodies([60, 62, 64, 65, 67, 69], pool);
    expect(hits.first.id, 'full');
    expect(hits.first.score, hits.last.score, reason: 'both match perfectly');
    expect(hits.first.matched, greaterThan(hits.last.matched));
  });

  test('evidence never overrides a better score', () {
    // The tie-break is a TIE-break. A long but wrong candidate must still lose
    // to a short exact one.
    final pool = [
      const MelodicCandidate('longWrong', [60, 40, 75, 41, 79, 45]),
      const MelodicCandidate('shortRight', [60, 62, 64]),
    ];
    final hits = searchMelodies([60, 62, 64], pool);
    expect(hits.first.id, 'shortRight');
  });
}
