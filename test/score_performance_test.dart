// test/score_performance_test.dart
//
// SE-C5. The claims worth pinning: a plain note is untouched (so no existing
// render changes), an ornament DECORATES rather than replaces its note, and the
// neighbours are diatonic — which is the half of this that a fixed interval
// would get wrong about half the time.

import 'package:comet_beat/core/audio/score_performance.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _quarter = 500; // ms, i.e. 120 bpm

NoteElement _note(
  int midi, {
  Ornament? ornament,
  int? tremolo,
  NoteDuration duration = NoteDuration.quarter,
}) =>
    NoteElement(
      pitches: [Pitch.fromMidi(midi)],
      duration: duration,
      ornament: ornament,
      tremolo: tremolo,
      id: 'n0',
    );

void main() {
  group('a plain note is left alone', () {
    test('one attack, the full written length', () {
      final a = attacksFor(_note(60), 500, quarterMs: _quarter);
      expect(a, hasLength(1));
      expect(a.single.midi, 60);
      expect(a.single.atMs, 0);
      expect(a.single.lengthMs, 500);
    });

    test('a note with no pitches, or no length, yields nothing', () {
      expect(attacksFor(_note(60), 0, quarterMs: _quarter), isEmpty);
      expect(
        attacksFor(
          const NoteElement(pitches: [], duration: NoteDuration.quarter),
          500,
          quarterMs: _quarter,
        ),
        isEmpty,
      );
    });
  });

  group('diatonic neighbours', () {
    test('the step size depends on WHERE you are in the key, not a constant',
        () {
      // C major. A trill on A goes to B — a whole step. On B it goes to C — a
      // half step. This is the case a fixed whole-step neighbour gets wrong.
      expect(diatonicNeighbour(69, fifths: 0, up: true), 71); // A→B
      expect(diatonicNeighbour(71, fifths: 0, up: true), 72); // B→C
      expect(diatonicNeighbour(64, fifths: 0, up: true), 65); // E→F
      expect(diatonicNeighbour(60, fifths: 0, up: false), 59); // C→B
    });

    test('it follows the key signature', () {
      // G major (one sharp): F♯. The note above E is F♯, not F.
      expect(diatonicNeighbour(64, fifths: 1, up: true), 66);
      // F major (one flat): B♭. The note above A is B♭.
      expect(diatonicNeighbour(69, fifths: -1, up: true), 70);
    });

    test('a neighbour is never the note itself', () {
      for (var midi = 48; midi < 72; midi++) {
        for (final fifths in [-3, 0, 2]) {
          expect(
            diatonicNeighbour(midi, fifths: fifths, up: true),
            greaterThan(midi),
          );
          expect(
            diatonicNeighbour(midi, fifths: fifths, up: false),
            lessThan(midi),
          );
        }
      }
    });
  });

  group('tremolo', () {
    test('three beams over a quarter is eight thirty-seconds of that pitch',
        () {
      final a = attacksFor(_note(60, tremolo: 3), 500, quarterMs: _quarter);
      expect(a, hasLength(8));
      expect(a.every((x) => x.midi == 60), isTrue);
      // They TILE the note exactly — no gap, no overhang, no drift. (62.5 ms
      // does not divide evenly, so the lengths differ by a millisecond; what
      // must hold is that they join up and end on the note's end.)
      for (var i = 1; i < a.length; i++) {
        expect(a[i].atMs, a[i - 1].atMs + a[i - 1].lengthMs);
      }
      expect(a.first.atMs, 0);
      expect(a.last.atMs + a.last.lengthMs, 500);
    });

    test('one beam is eighths', () {
      final a = attacksFor(_note(60, tremolo: 1), 500, quarterMs: _quarter);
      expect(a, hasLength(2));
    });

    test('a subdivision longer than the note stays one attack', () {
      // An eighth tremolo on a note shorter than an eighth cannot repeat.
      final a = attacksFor(_note(60, tremolo: 1), 100, quarterMs: _quarter);
      expect(a, hasLength(1));
      expect(a.single.lengthMs, 100);
    });
  });

  group('ornaments decorate the note, they do not replace it', () {
    test('a mordent is main-lower-main, and the MAIN NOTE holds the rest', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.mordent),
        500,
        quarterMs: _quarter,
      );
      expect([for (final x in a) x.midi], [60, 59, 60]);
      // The last note runs to the end of the written duration — otherwise an
      // ornament would shorten the music it decorates.
      expect(a.last.atMs + a.last.lengthMs, 500);
      expect(a.last.lengthMs, greaterThan(a.first.lengthMs));
    });

    test('an upper mordent uses the note ABOVE', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.shortTrill),
        500,
        quarterMs: _quarter,
      );
      expect([for (final x in a) x.midi], [60, 62, 60]);
    });

    test('a turn is four notes, from above', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.turn),
        500,
        quarterMs: _quarter,
      );
      expect([for (final x in a) x.midi], [62, 60, 59, 60]);
    });

    test('an inverted turn is the same figure from below', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.invertedTurn),
        500,
        quarterMs: _quarter,
      );
      expect([for (final x in a) x.midi], [59, 60, 62, 60]);
    });

    test('a trill alternates and FILLS its note', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.trill),
        500,
        quarterMs: _quarter,
      );
      expect(a.length, greaterThan(4));
      expect(a.first.midi, 60, reason: 'a modern trill starts on the note');
      expect(a[1].midi, 62);
      expect(a.last.atMs + a.last.lengthMs, 500);
    });

    test('a trill with an accidental OVERRIDES the key for its auxiliary', () {
      // G major: the note above E is F♯. A trill-natural cancels it, and taking
      // the key's neighbour would play the sharp the composer struck out.
      final plain = attacksFor(
        _note(64, ornament: Ornament.trill),
        500,
        quarterMs: _quarter,
        fifths: 1,
      );
      expect(plain[1].midi, 66, reason: 'F sharp, from the key');

      final natural = attacksFor(
        _note(64, ornament: Ornament.trillNatural),
        500,
        quarterMs: _quarter,
        fifths: 1,
      );
      expect(natural[1].midi, 65, reason: 'F natural, as written');

      final sharp = attacksFor(
        _note(64, ornament: Ornament.trillSharp),
        500,
        quarterMs: _quarter,
      );
      expect(
        sharp[1].midi,
        66,
        reason: 'F sharp even in C major (fifths defaults to 0)',
      );
    });

    test('an ornament on a very short note still fits inside it', () {
      final a = attacksFor(
        _note(60, ornament: Ornament.turn),
        30,
        quarterMs: _quarter,
      );
      expect(a, isNotEmpty);
      for (final x in a) {
        expect(x.atMs, lessThan(30));
        expect(x.atMs + x.lengthMs, lessThanOrEqualTo(30));
      }
    });
  });
}
