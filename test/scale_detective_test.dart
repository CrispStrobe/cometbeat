// Scale Detective round generation. Regression: at 3★ the game uses harmonic
// minor, whose raised 7th is the ONLY note carrying a note-level accidental (it
// is not in the key signature). The old code could pick that note as the "odd
// one out" and neutralize its accidental (G♯ → G in A minor), leaving a plain,
// valid natural-minor scale with NO accidental anywhere — an UNSOLVABLE round
// that marks any tap wrong. buildDetectiveRound now excludes it.

import 'dart:math';

import 'package:comet_beat/features/games/scales/scale_detective_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

// The minor tonics the game uses (single sharp/flat once the 7th is raised).
const _minorTonics = [Step.a, Step.e, Step.d, Step.b, Step.g, Step.c];

/// A note shows an accidental on the rendered staff iff its alteration differs
/// from what the key signature already provides for its step.
bool _visible(Pitch p, KeySignature sig) => p.alter != sig.alterFor(p.step);

void main() {
  test('harmonic-minor rounds always have exactly the odd note visible', () {
    for (final tonic in _minorTonics) {
      final key = Key.minor(Pitch(tonic));
      final sig = key.signature;
      final scale = Scale(Pitch(tonic), ScaleType.harmonicMinor).pitches;

      for (var seed = 0; seed < 200; seed++) {
        final round = buildDetectiveRound(
          tonic,
          ScaleType.harmonicMinor,
          key,
          Random(seed),
        );

        // Never the tonic endpoints.
        expect(round.wrongIndex, greaterThan(0));
        expect(round.wrongIndex, lessThan(scale.length - 1));

        // Never the raised leading tone: the note it replaced rendered PLAIN
        // for this key (no note-level accidental). This is the exact index the
        // old code could hit to produce an all-plain, unsolvable scale.
        expect(
          _visible(scale[round.wrongIndex], sig),
          isFalse,
          reason: '$tonic: targeted a note-level accidental at '
              '${round.wrongIndex}',
        );

        // The injected note is visibly altered — the child can see it.
        final wrong = round.pitches[round.wrongIndex];
        expect(
          _visible(wrong, sig),
          isTrue,
          reason: '$tonic seed $seed: odd note ${wrong.step.name}'
              '${wrong.alter} is invisible → unsolvable',
        );

        // It actually differs from the correct scale note.
        expect(wrong.midiNumber, isNot(scale[round.wrongIndex].midiNumber));

        // The raised leading tone is still present (the intended distractor).
        final leadingTone = scale[scale.length - 2];
        expect(
          round.pitches.any((p) => p.midiNumber == leadingTone.midiNumber),
          isTrue,
          reason: '$tonic: the raised 7th distractor must remain',
        );
      }
    }
  });

  test('major rounds still alter an interior note visibly', () {
    for (final tonic in [Step.c, Step.g, Step.f, Step.d]) {
      final key = Key.major(Pitch(tonic));
      final sig = key.signature;
      final scale = Scale(Pitch(tonic), ScaleType.major).pitches;
      for (var seed = 0; seed < 50; seed++) {
        final round =
            buildDetectiveRound(tonic, ScaleType.major, key, Random(seed));
        expect(round.wrongIndex, inInclusiveRange(1, scale.length - 2));
        expect(_visible(round.pitches[round.wrongIndex], sig), isTrue);
      }
    }
  });
}
