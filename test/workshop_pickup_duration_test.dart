// An anacrusis must declare how long it is.
//
// `reflow` already packs the opening bar short and flags it `pickup: true`, and
// that is enough for the RENDERER, which reads the flag. It is not enough for
// anything that measures musical time, because crisp_notation advances a bar by
// `actualDuration ?? meter` (`playback/tempo_map.dart`) — a short bar with no
// `actualDuration` therefore advances a FULL bar.
//
// The visible consequence is that every tempo change after an anacrusis is
// placed late, by exactly (full bar − pickup). Nothing throws and the score
// looks right; only the timing is wrong, which is why it survived this long.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// `count` quarter notes (C4 — `Pitch` defaults to octave 4), ids `e0…`, so
/// `reflow` has something to pack.
List<MusicElement> _quarters(int count) => [
      for (var i = 0; i < count; i++)
        NoteElement.note(
          const Pitch(Step.c),
          const NoteDuration(DurationBase.quarter),
          id: 'e$i',
        ),
    ];

void main() {
  group('the opening bar declares its real length', () {
    test('a pickup bar carries actualDuration', () {
      final bars = reflow(
        _quarters(9),
        timeSignature: TimeSignature.fourFour,
        pickup: const NoteDuration(DurationBase.quarter),
      );

      expect(bars.first.pickup, isTrue, reason: 'still flagged as a pickup');
      expect(
        bars.first.actualDuration,
        Fraction(1, 4),
        reason: 'a one-quarter anacrusis is a quarter long, not a whole bar',
      );
    });

    test('a dotted pickup carries its dotted length', () {
      // A dotted quarter of capacity, filled by a dotted quarter of music.
      final bars = reflow(
        [
          NoteElement.note(
            const Pitch(Step.c),
            const NoteDuration(DurationBase.quarter, dots: 1),
            id: 'p0',
          ),
          ..._quarters(8),
        ],
        timeSignature: TimeSignature.fourFour,
        pickup: const NoteDuration(DurationBase.quarter, dots: 1),
      );
      expect(bars.first.actualDuration, Fraction(3, 8));
    });

    test('a half-written anacrusis declares what it HOLDS, not what was asked',
        () {
      // The user chose a dotted-quarter pickup but only a quarter of music fits
      // before the bar has to close. Stamping the requested 3/8 would claim an
      // eighth of music that is not there and push everything after it late —
      // the same failure this whole change exists to remove. The contents are
      // the honest answer, and they are what `_pickupOf` reads back.
      final bars = reflow(
        _quarters(9),
        timeSignature: TimeSignature.fourFour,
        pickup: const NoteDuration(DurationBase.quarter, dots: 1),
      );
      expect(bars.first.actualDuration, Fraction(1, 4));
      expect(bars.first.pickup, isTrue, reason: 'still an anacrusis');
    });

    test('bars after the pickup declare nothing — they are full', () {
      // `actualDuration` means "this bar is NOT the meter's length". Stamping it
      // on ordinary bars would be noise, and would freeze them against a later
      // meter change.
      final bars = reflow(
        _quarters(9),
        timeSignature: TimeSignature.fourFour,
        pickup: const NoteDuration(DurationBase.quarter),
      );
      for (final bar in bars.skip(1)) {
        expect(bar.actualDuration, isNull);
      }
    });

    test('with no pickup nothing is stamped at all', () {
      final bars = reflow(
        _quarters(8),
        timeSignature: TimeSignature.fourFour,
      );
      expect(bars.first.pickup, isFalse);
      expect(bars.every((b) => b.actualDuration == null), isTrue);
    });
  });

  group('musical time now advances correctly across an anacrusis', () {
    test('a tempo change after a pickup lands on its real onset', () {
      // One quarter of pickup, then two full 4/4 bars. The second full bar
      // starts at 1/4 + 1 = 5/4 whole notes. Read as a full opening bar it would
      // have come out at 2 — three quarter notes late.
      final bars = reflow(
        _quarters(9),
        timeSignature: TimeSignature.fourFour,
        pickup: const NoteDuration(DurationBase.quarter),
      );

      final measures = <Measure>[
        bars[0],
        bars[1],
        bars[2].copyWith(tempoChange: const Tempo(90)),
      ];
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: measures,
        tempo: const Tempo(120),
      );

      final map = tempoMapOf(score);
      final changed = map.spans.where((s) => s.quarterBpm == 90).toList();
      expect(changed, hasLength(1), reason: 'the tempo change went missing');
      expect(
        changed.single.at,
        Fraction(5, 4),
        reason: 'the pickup advanced a whole bar instead of a quarter',
      );
    });
  });

  group('save and reopen', () {
    test('a pickup survives a document round trip and keeps its length', () {
      // `_pickupOf` recovers the anacrusis by re-measuring the flagged bar, so
      // the two representations have to agree — the flag, and the length.
      final doc = ScoreDocument()
        ..timeSignature = TimeSignature.fourFour
        ..pickup = const NoteDuration(DurationBase.quarter);
      doc.insertMelody([
        for (var i = 0; i < 9; i++)
          (const Pitch(Step.c), const NoteDuration(DurationBase.quarter)),
      ]);

      final score = doc.buildScore();
      expect(score.measures.first.pickup, isTrue);
      expect(score.measures.first.actualDuration, Fraction(1, 4));

      final reopened = ScoreDocument()..loadScore(score);
      expect(reopened.pickup, const NoteDuration(DurationBase.quarter));
      expect(
        reopened.buildScore().measures.first.actualDuration,
        Fraction(1, 4),
      );
    });
  });
}
