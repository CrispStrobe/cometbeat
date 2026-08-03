// test/chord_spec_test.dart
//
// BB-D1 acceptance + BB-Q3 (the symbol corpus test).
//
// The corpus below is the point of this file. The ladder card asks for "≥150 real
// symbol strings → expected pitch sets + canonical print, including the ugly
// ones", because a chord-symbol parser is exactly the kind of code that looks
// finished after twenty examples and then meets `C∆9`, `Cmi7(b5)` and `C7-5`.
// Every row is (what a musician types, what it must print back as, the semitones
// above the root it must sound).
//
// ⚠️ WHEN A NEW SYMBOL SHOWS UP IN THE WILD, ADD A ROW — do not "fix the
// parser". The card says an unparseable symbol is a test case, not a crash, and
// the last group here pins that behaviour.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Interval, IntervalQuality, Pitch, Step;
import 'package:flutter_test/flutter_test.dart';

/// One corpus row: the input, the canonical print, the intervals.
typedef Row = (String, String, List<int>);

/// The corpus. Grouped by what each group is actually testing, so a failure
/// names the family rather than a line number.
const Map<String, List<Row>> corpus = {
  'triads': [
    ('C', 'C', [0, 4, 7]),
    ('Cm', 'Cm', [0, 3, 7]),
    ('Cmin', 'Cm', [0, 3, 7]),
    ('Cmi', 'Cm', [0, 3, 7]),
    ('C-', 'Cm', [0, 3, 7]),
    ('CM', 'C', [0, 4, 7]),
    ('Cmaj', 'C', [0, 4, 7]),
    ('Cdim', 'Cdim', [0, 3, 6]),
    ('C°', 'Cdim', [0, 3, 6]),
    ('Caug', 'Caug', [0, 4, 8]),
    ('C+', 'Caug', [0, 4, 8]),
    ('C5', 'C5', [0, 7]),
  ],
  'suspensions': [
    ('Csus2', 'Csus2', [0, 2, 7]),
    ('Csus4', 'Csus4', [0, 5, 7]),
    ('Csus', 'Csus4', [0, 5, 7]),
    ('C4', 'Csus4', [0, 5, 7]),
    ('C2', 'Csus2', [0, 2, 7]),
    ('C7sus4', 'C7sus4', [0, 5, 7, 10]),
    ('C7sus', 'C7sus4', [0, 5, 7, 10]),
    ('C9sus4', 'C9sus4', [0, 5, 7, 10, 14]),
    ('Csus4add9', 'Csus4add9', [0, 5, 7, 14]),
  ],
  'sevenths': [
    ('C7', 'C7', [0, 4, 7, 10]),
    ('Cmaj7', 'Cmaj7', [0, 4, 7, 11]),
    ('CM7', 'Cmaj7', [0, 4, 7, 11]),
    ('CMaj7', 'Cmaj7', [0, 4, 7, 11]),
    ('Cma7', 'Cmaj7', [0, 4, 7, 11]),
    ('C∆', 'Cmaj7', [0, 4, 7, 11]),
    ('CΔ', 'Cmaj7', [0, 4, 7, 11]),
    ('C△', 'Cmaj7', [0, 4, 7, 11]),
    ('Cm7', 'Cm7', [0, 3, 7, 10]),
    ('Cmin7', 'Cm7', [0, 3, 7, 10]),
    ('Cmi7', 'Cm7', [0, 3, 7, 10]),
    ('C-7', 'Cm7', [0, 3, 7, 10]),
    ('CmMaj7', 'CmMaj7', [0, 3, 7, 11]),
    ('Cmmaj7', 'CmMaj7', [0, 3, 7, 11]),
    ('Cminmaj7', 'CmMaj7', [0, 3, 7, 11]),
    ('C-maj7', 'CmMaj7', [0, 3, 7, 11]),
    ('Caug7', 'Caug7', [0, 4, 8, 10]),
  ],
  'half-diminished and diminished — five spellings each': [
    ('Cm7b5', 'Cm7b5', [0, 3, 6, 10]),
    ('Cmin7b5', 'Cm7b5', [0, 3, 6, 10]),
    ('Cm7-5', 'Cm7b5', [0, 3, 6, 10]),
    ('Cø', 'Cm7b5', [0, 3, 6, 10]),
    ('Cø7', 'Cm7b5', [0, 3, 6, 10]),
    ('CØ7', 'Cm7b5', [0, 3, 6, 10]),
    ('Cdim7', 'Cdim7', [0, 3, 6, 9]),
    ('C°7', 'Cdim7', [0, 3, 6, 9]),
    ('Co7', 'Cdim7', [0, 3, 6, 9]),
    ('Cdimmaj7', 'Cdimmaj7', [0, 3, 6, 11]),
  ],
  'sixths': [
    ('C6', 'C6', [0, 4, 7, 9]),
    ('Cm6', 'Cm6', [0, 3, 7, 9]),
    ('C6/9', 'C6/9', [0, 4, 7, 9, 14]),
    ('C69', 'C6/9', [0, 4, 7, 9, 14]),
    ('Cm6/9', 'Cm6/9', [0, 3, 7, 9, 14]),
  ],
  'extensions': [
    ('C9', 'C9', [0, 4, 7, 10, 14]),
    ('Cm9', 'Cm9', [0, 3, 7, 10, 14]),
    ('Cmaj9', 'Cmaj9', [0, 4, 7, 11, 14]),
    ('CM9', 'Cmaj9', [0, 4, 7, 11, 14]),
    ('C∆9', 'Cmaj9', [0, 4, 7, 11, 14]),
    ('C11', 'C11', [0, 4, 7, 10, 14, 17]),
    ('Cm11', 'Cm11', [0, 3, 7, 10, 14, 17]),
    ('Cmaj11', 'Cmaj11', [0, 4, 7, 11, 14, 17]),
    // A 13th chord leaves out the 11th — see ChordSpec.intervals.
    ('C13', 'C13', [0, 4, 7, 10, 14, 21]),
    ('Cm13', 'Cm13', [0, 3, 7, 10, 14, 21]),
    ('Cmaj13', 'Cmaj13', [0, 4, 7, 11, 14, 21]),
    ('CM13', 'Cmaj13', [0, 4, 7, 11, 14, 21]),
  ],
  'alterations': [
    ('C7b5', 'C7b5', [0, 4, 6, 10]),
    ('C7-5', 'C7b5', [0, 4, 6, 10]),
    ('C7#5', 'C7#5', [0, 4, 8, 10]),
    ('C7+5', 'C7#5', [0, 4, 8, 10]),
    ('C7b9', 'C7b9', [0, 4, 7, 10, 13]),
    ('C7-9', 'C7b9', [0, 4, 7, 10, 13]),
    ('C7#9', 'C7#9', [0, 4, 7, 10, 15]),
    ('C7+9', 'C7#9', [0, 4, 7, 10, 15]),
    ('C7#11', 'C7#11', [0, 4, 7, 10, 18]),
    ('C7+11', 'C7#11', [0, 4, 7, 10, 18]),
    ('C7b13', 'C7b13', [0, 4, 7, 10, 20]),
    ('C7-13', 'C7b13', [0, 4, 7, 10, 20]),
    ('Cmaj7#11', 'Cmaj7#11', [0, 4, 7, 11, 18]),
    ('C7b9#11', 'C7b9#11', [0, 4, 7, 10, 13, 18]),
    ('C13#11', 'C13#11', [0, 4, 7, 10, 14, 18, 21]),
    ('Cm7b5b9', 'Cm7b5b9', [0, 3, 6, 10, 13]),
    // `alt` stays `alt` rather than decaying into its four alterations.
    ('C7alt', 'C7alt', [0, 4, 7, 10, 13, 15, 18, 20]),
    ('Calt', 'C7alt', [0, 4, 7, 10, 13, 15, 18, 20]),
  ],
  'adds and omissions': [
    ('Cadd9', 'Cadd9', [0, 4, 7, 14]),
    ('Cadd11', 'Cadd11', [0, 4, 7, 17]),
    ('Cadd13', 'Cadd13', [0, 4, 7, 21]),
    ('Cadd2', 'Cadd2', [0, 2, 4, 7]),
    ('Cadd4', 'Cadd4', [0, 4, 5, 7]),
    ('Cadd6', 'Cadd6', [0, 4, 7, 9]),
    ('Cmadd9', 'Cmadd9', [0, 3, 7, 14]),
    ('Cno3', 'Cno3', [0, 7]),
    ('Cno5', 'Cno5', [0, 4]),
    ('Comit3', 'Cno3', [0, 7]),
    ('Comit5', 'Cno5', [0, 4]),
    ('C7no5', 'C7no5', [0, 4, 10]),
  ],
  'roots, including the awkward spellings': [
    ('F#m7b5', 'F#m7b5', [0, 3, 6, 10]),
    ('Bb7', 'Bb7', [0, 4, 7, 10]),
    ('Ebmaj7', 'Ebmaj7', [0, 4, 7, 11]),
    ('Abm7', 'Abm7', [0, 3, 7, 10]),
    ('Db9', 'Db9', [0, 4, 7, 10, 14]),
    ('G#dim7', 'G#dim7', [0, 3, 6, 9]),
    ('A7', 'A7', [0, 4, 7, 10]),
    ('D7', 'D7', [0, 4, 7, 10]),
    ('E7#9', 'E7#9', [0, 4, 7, 10, 15]),
    ('B7alt', 'B7alt', [0, 4, 7, 10, 13, 15, 18, 20]),
    ('Cb', 'Cb', [0, 4, 7]),
    ('F##m', 'F##m', [0, 3, 7]),
    ('Bbb7', 'Bbb7', [0, 4, 7, 10]),
    ('G', 'G', [0, 4, 7]),
    ('Gm7', 'Gm7', [0, 3, 7, 10]),
  ],
  'slash bass': [
    ('C/G', 'C/G', [0, 4, 7]),
    ('C/E', 'C/E', [0, 4, 7]),
    ('Cm7/Bb', 'Cm7/Bb', [0, 3, 7, 10]),
    ('C7/E', 'C7/E', [0, 4, 7, 10]),
    ('Cmaj7/B', 'Cmaj7/B', [0, 4, 7, 11]),
    ('F#m7b5/C', 'F#m7b5/C', [0, 3, 6, 10]),
    ('Bb/D', 'Bb/D', [0, 4, 7]),
    ('Am7/G', 'Am7/G', [0, 3, 7, 10]),
    // The `/9` here is part of the name, not a bass — the trap this rule exists
    // for. If it ever regresses, C6/9 will read as a C6 over a 9th.
    ('C6/9', 'C6/9', [0, 4, 7, 9, 14]),
  ],
  'unicode, parentheses and whitespace': [
    ('F♯m7♭5', 'F#m7b5', [0, 3, 6, 10]),
    ('B♭7', 'Bb7', [0, 4, 7, 10]),
    ('E♭maj7', 'Ebmaj7', [0, 4, 7, 11]),
    ('C⁷', 'C7', [0, 4, 7, 10]),
    ('C7(b9)', 'C7b9', [0, 4, 7, 10, 13]),
    ('C7(♭9)', 'C7b9', [0, 4, 7, 10, 13]),
    ('C7(#11)', 'C7#11', [0, 4, 7, 10, 18]),
    ('C7[b9]', 'C7b9', [0, 4, 7, 10, 13]),
    ('Cmi7(b5)', 'Cm7b5', [0, 3, 6, 10]),
    ('C 7', 'C7', [0, 4, 7, 10]),
    ('  Cmaj7  ', 'Cmaj7', [0, 4, 7, 11]),
    ('C7(b9,#11)', 'C7b9#11', [0, 4, 7, 10, 13, 18]),
    ('C–7', 'Cm7', [0, 3, 7, 10]),
    ('C—7', 'Cm7', [0, 3, 7, 10]),
  ],
  'case': [
    ('CMAJ7', 'Cmaj7', [0, 4, 7, 11]),
    ('cmaj7', 'Cmaj7', [0, 4, 7, 11]),
    ('cm7', 'Cm7', [0, 3, 7, 10]),
    ('CDIM7', 'Cdim7', [0, 3, 6, 9]),
    ('CSUS4', 'Csus4', [0, 5, 7]),
    ('CAUG', 'Caug', [0, 4, 8]),
    ('CAdd9', 'Cadd9', [0, 4, 7, 14]),
    ('CMI7', 'Cm7', [0, 3, 7, 10]),
    ('CMin7', 'Cm7', [0, 3, 7, 10]),
    ('bb7', 'Bb7', [0, 4, 7, 10]),
    ('f#m', 'F#m', [0, 3, 7]),
  ],
  'a real 32-bar set of changes, read end to end': [
    ('Dm7', 'Dm7', [0, 3, 7, 10]),
    ('G7', 'G7', [0, 4, 7, 10]),
    ('Cmaj7', 'Cmaj7', [0, 4, 7, 11]),
    ('Em7b5', 'Em7b5', [0, 3, 6, 10]),
    ('A7b13', 'A7b13', [0, 4, 7, 10, 20]),
    ('Dm9', 'Dm9', [0, 3, 7, 10, 14]),
    ('Db7#11', 'Db7#11', [0, 4, 7, 10, 18]),
    ('Cmaj9', 'Cmaj9', [0, 4, 7, 11, 14]),
    ('Bbm7', 'Bbm7', [0, 3, 7, 10]),
    ('Eb7', 'Eb7', [0, 4, 7, 10]),
    ('Abmaj7', 'Abmaj7', [0, 4, 7, 11]),
    ('F7alt', 'F7alt', [0, 4, 7, 10, 13, 15, 18, 20]),
    ('Bmaj7', 'Bmaj7', [0, 4, 7, 11]),
    ('G#m7', 'G#m7', [0, 3, 7, 10]),
    ('C#7sus4', 'C#7sus4', [0, 5, 7, 10]),
    ('F#6/9', 'F#6/9', [0, 4, 7, 9, 14]),
  ],
};

void main() {
  group('BB-Q3 — the chord-symbol corpus', () {
    test('has at least the 150 rows the card asks for', () {
      final total = corpus.values.fold(0, (a, rows) => a + rows.length);
      expect(
        total,
        greaterThanOrEqualTo(150),
        reason: 'corpus has $total rows',
      );
    });

    corpus.forEach((family, rows) {
      group(family, () {
        for (final (input, canonical, intervals) in rows) {
          test('"$input" reads, prints "$canonical", sounds $intervals', () {
            final spec = parseChordSpec(input);
            expect(spec, isNotNull, reason: '"$input" did not parse');
            expect(spec!.format(), canonical);
            expect(spec.intervals, intervals);
          });
        }
      });
    });
  });

  group('BB-D1 — the parser never fails', () {
    test('unreadable text is preserved VERBATIM and still voices', () {
      for (final junk in ['Cxyz', 'Cm7b5x', 'C7qq', 'Cwibble']) {
        final cell = parseChartCell(junk);
        expect(cell, isA<UnreadableCell>(), reason: junk);
        final u = cell as UnreadableCell;
        expect(u.text, junk, reason: 'the user must see what they typed');
        expect(
          u.fallback.intervals,
          isNotEmpty,
          reason: 'it must make a sound',
        );
      }
    });

    test('the fallback guesses minor from the quality, like the old table did',
        () {
      expect(
        (parseChartCell('Cmwibble') as UnreadableCell).fallback.triad,
        ChordTriad.minor,
      );
      expect(
        (parseChartCell('Cmajwibble') as UnreadableCell).fallback.triad,
        ChordTriad.major,
      );
      // The root survives even when the quality does not.
      expect(
        (parseChartCell('Ebwibble') as UnreadableCell).fallback.root.step,
        Step.e,
      );
    });

    test('text with no note name at all is unreadable, not a crash', () {
      for (final junk in ['wibble', '???', 'x', 'Z7']) {
        expect(parseChartCell(junk), isA<UnreadableCell>(), reason: junk);
      }
    });

    test('N.C. is a silence and % is a continuation — and they differ', () {
      for (final nc in ['N.C.', 'NC', 'n.c.', 'N.C', 'no chord']) {
        expect(parseChartCell(nc), isA<NoChordCell>(), reason: nc);
      }
      for (final rep in ['%', '', '   ']) {
        expect(parseChartCell(rep), isA<RepeatCell>(), reason: '"$rep"');
      }
      expect(const NoChordCell() == const RepeatCell(), isFalse);
    });
  });

  group('BB-D1 — round trip', () {
    // Four combinations are deliberately NOT representable as a symbol, and each
    // is a fact about how chords are named rather than a gap in the model:
    //   • a diminished seventh only occurs on a diminished triad;
    //   • a diminished triad with a MINOR seventh is spelled `m7b5`, which this
    //     model states as a minor triad with a flat five;
    //   • a stack height needs a seventh under it (`C9` vs `Cadd9`);
    //   • `alt` is a DOMINANT modifier — "the altered dominant" — so it needs a
    //     minor seventh under it. `Calt` is read as `C7alt`, not as an altered
    //     major triad, which is not a thing.
    // The generator below skips exactly those and the next test pins them.
    test('parse(format(x)) == x across the whole model', () {
      const roots = [
        Pitch(Step.c),
        Pitch(Step.f, alter: 1),
        Pitch(Step.b, alter: -1),
        Pitch(Step.a),
      ];
      const alterationSets = <Set<ChordAlteration>>[
        {},
        {ChordAlteration.flatFive},
        {ChordAlteration.sharpFive},
        {ChordAlteration.flatNine},
        {ChordAlteration.sharpNine, ChordAlteration.sharpEleven},
        {ChordAlteration.flatThirteen},
        {ChordAlteration.altered},
        {ChordAlteration.flatNine, ChordAlteration.altered},
      ];
      var checked = 0;
      for (final root in roots) {
        for (final triad in ChordTriad.values) {
          for (final seventh in ChordSeventh.values) {
            if (seventh == ChordSeventh.diminished &&
                triad != ChordTriad.diminished) {
              continue;
            }
            if (triad == ChordTriad.diminished &&
                seventh == ChordSeventh.minor) {
              continue;
            }
            for (final extension in const [0, 9, 11, 13]) {
              if (extension > 0 &&
                  seventh != ChordSeventh.minor &&
                  seventh != ChordSeventh.major) {
                continue;
              }
              for (final alterations in alterationSets) {
                if (alterations.contains(ChordAlteration.altered) &&
                    seventh != ChordSeventh.minor) {
                  continue;
                }
                for (final added in const <Set<int>>[
                  {},
                  {9},
                  {11, 13},
                ]) {
                  for (final omitted in const <Set<int>>[
                    {},
                    {3},
                    {5},
                  ]) {
                    for (final bass in const [null, Pitch(Step.g)]) {
                      final spec = ChordSpec(
                        root: root,
                        triad: triad,
                        seventh: seventh,
                        extension: extension,
                        alterations: alterations,
                        added: added,
                        omitted: omitted,
                        bass: bass,
                      );
                      final printed = spec.format();
                      final back = parseChordSpec(printed);
                      expect(
                        back,
                        isNotNull,
                        reason: 'printed "$printed" and could not read it',
                      );
                      expect(back, spec, reason: 'via "$printed"');
                      checked++;
                    }
                  }
                }
              }
            }
          }
        }
      }
      expect(checked, greaterThan(2000), reason: 'only checked $checked');
    });

    test('the four non-representable combinations, stated explicitly', () {
      // A diminished triad with a minor seventh prints as `dim7`, which reads
      // back as the diminished seventh it looks like. Use m7b5 for a half-dim.
      const halfDimWrong = ChordSpec(
        root: Pitch(Step.c),
        triad: ChordTriad.diminished,
        seventh: ChordSeventh.minor,
      );
      expect(
        parseChordSpec(halfDimWrong.format())!.seventh,
        ChordSeventh.diminished,
      );
      // The model's own spelling of a half-diminished round-trips fine.
      const halfDimRight = ChordSpec(
        root: Pitch(Step.c),
        triad: ChordTriad.minor,
        seventh: ChordSeventh.minor,
        alterations: {ChordAlteration.flatFive},
      );
      expect(parseChordSpec(halfDimRight.format()), halfDimRight);
      // A stack height with no seventh under it has no symbol; it is `add`.
      const noSeventh = ChordSpec(root: Pitch(Step.c), extension: 9);
      expect(parseChordSpec(noSeventh.format())!.extension, 0);
      // `alt` names the altered DOMINANT, so reading it back supplies the
      // seventh the spelling implies. An "altered major triad" is not a chord.
      const altNoSeventh = ChordSpec(
        root: Pitch(Step.c),
        alterations: {ChordAlteration.altered},
      );
      expect(altNoSeventh.format(), 'Calt');
      expect(parseChordSpec('Calt')!.seventh, ChordSeventh.minor);
    });
  });

  group('BB-D1 — notes and invariants', () {
    test('the root is always present and intervals are sorted and unique', () {
      for (final rows in corpus.values) {
        for (final (input, _, _) in rows) {
          final spec = parseChordSpec(input)!;
          final iv = spec.intervals;
          expect(iv.first, 0, reason: input);
          expect(iv.toSet().length, iv.length, reason: '$input has duplicates');
          final sorted = [...iv]..sort();
          expect(iv, sorted, reason: '$input is unsorted');
        }
      }
    });

    test('guide tones are the third and the seventh, and are chord tones', () {
      expect(parseChordSpec('C7')!.guideTones, [4, 10]);
      expect(parseChordSpec('Cmaj7')!.guideTones, [4, 11]);
      expect(parseChordSpec('Cm7b5')!.guideTones, [3, 10]);
      expect(parseChordSpec('C6')!.guideTones, [4, 9]);
      expect(parseChordSpec('Csus4')!.guideTones, [5]);
      // A power chord has no quality to guide with, and says so.
      expect(parseChordSpec('C5')!.guideTones, isEmpty);
      for (final rows in corpus.values) {
        for (final (input, _, _) in rows) {
          final spec = parseChordSpec(input)!;
          expect(spec.intervals, containsAll(spec.guideTones), reason: input);
        }
      }
    });

    test('pitch classes reduce the stack, and the bass is separate', () {
      expect(parseChordSpec('C9')!.pitchClasses, {0, 4, 7, 10, 2});
      expect(parseChordSpec('Cdim7')!.pitchClasses, hasLength(4));
      expect(parseChordSpec('C5')!.pitchClasses, {0, 7});
      final slash = parseChordSpec('C/G')!;
      expect(slash.pitchClasses, {0, 4, 7});
      expect(slash.pitchClassesWithBass, {0, 4, 7});
      final over = parseChordSpec('C/A')!;
      expect(over.pitchClasses.contains(9), isFalse);
      expect(over.pitchClassesWithBass.contains(9), isTrue);
    });

    test('midis stack from the root, and a slash bass sits below it', () {
      expect(parseChordSpec('C7')!.midis(), [60, 64, 67, 70]);
      expect(parseChordSpec('Cmaj7')!.midis(rootMidi: 48), [48, 52, 55, 59]);
      // C/G: the G is the fifth BELOW middle C, not the one above it.
      expect(parseChordSpec('C/G')!.bassMidi(), 55);
      expect(parseChordSpec('C/E')!.bassMidi(), 52);
      expect(parseChordSpec('C')!.bassMidi(), isNull);
    });
  });

  group('BB-D1 — printing conventions', () {
    test('jazz glyphs', () {
      const jazz = ChordSymbolStyle.jazz;
      expect(parseChordSpec('Cmaj7')!.format(style: jazz), 'C∆7');
      expect(parseChordSpec('Cdim7')!.format(style: jazz), 'C°7');
      // `ø` absorbs the `m`, the `7` and the `♭5` in one glyph.
      expect(parseChordSpec('F#m7b5')!.format(style: jazz), 'F♯ø7');
      expect(parseChordSpec('Cm9b5')!.format(style: jazz), 'Cø9');
      // …but only for a genuine half-diminished. A true diminished seventh
      // keeps `°`, and a plain minor seventh keeps `m`.
      expect(parseChordSpec('Cdim7')!.format(style: jazz), 'C°7');
      expect(parseChordSpec('Cm7')!.format(style: jazz), 'Cm7');
      expect(parseChordSpec('Bb7#11')!.format(style: jazz), 'B♭7♯11');
    });

    test('a jazz-printed symbol reads back — the two styles agree', () {
      for (final rows in corpus.values) {
        for (final (input, _, _) in rows) {
          final spec = parseChordSpec(input)!;
          expect(
            parseChordSpec(spec.format(style: ChordSymbolStyle.jazz)),
            spec,
            reason: input,
          );
        }
      }
    });

    test('German note names are opt-in, and B still means B flat', () {
      const de = ChordSymbolStyle.german;
      // Read: H is the natural B, a bare B is B flat.
      expect(parseChordSpec('H7', style: de)!.root.step, Step.b);
      expect(parseChordSpec('H7', style: de)!.root.alter, 0);
      expect(parseChordSpec('B7', style: de)!.root.alter, -1);
      // …but `Bb` is still B flat, not B double flat: German charts mix the two
      // conventions and this is the reading that never surprises.
      expect(parseChordSpec('Bb7', style: de)!.root.alter, -1);
      // Print: the same chord, two conventions.
      final bNatural = parseChordSpec('B7')!;
      expect(bNatural.format(), 'B7');
      expect(bNatural.format(style: de), 'H7');
      expect(parseChordSpec('Bb7')!.format(style: de), 'B7');
      // H is NOT a note internationally.
      expect(parseChordSpec('H7'), isNull);
      expect(parseChartCell('H7'), isA<UnreadableCell>());
    });
  });

  group('BB-D1 — transposition keeps the spelling', () {
    test('up a minor third, flats stay flats', () {
      const minorThird = Interval(IntervalQuality.minor, 3);
      final dm7 = parseChordSpec('Dm7')!;
      expect(dm7.transposedBy(minorThird).format(), 'Fm7');
      final bb7 = parseChordSpec('Bb7')!;
      expect(bb7.transposedBy(minorThird).format(), 'Db7');
    });

    test('the slash bass travels with the chord', () {
      const perfectFourth = Interval(IntervalQuality.perfect, 4);
      expect(
        parseChordSpec('C/G')!.transposedBy(perfectFourth).format(),
        'F/C',
      );
    });

    test('up then down the SAME interval returns the original spelling', () {
      const fifth = Interval(IntervalQuality.perfect, 5);
      for (final input in ['Cmaj7', 'Ebm7', 'F#7alt', 'Bb6/9', 'Am7/G']) {
        final spec = parseChordSpec(input)!;
        final round =
            spec.transposedBy(fifth).transposedBy(fifth, descending: true);
        expect(round.format(), spec.format(), reason: input);
      }
    });

    test('up a fifth then DOWN A FOURTH is up a second, not a round trip', () {
      // Pinned because I got this wrong while writing the test above. The
      // inverse of "up a perfect fifth" is "down a perfect fifth";
      // up-a-fifth-then-down-a-fourth composes to up a major second. If this
      // ever starts returning its input, transposition has stopped composing.
      const fifth = Interval(IntervalQuality.perfect, 5);
      const fourth = Interval(IntervalQuality.perfect, 4);
      final c = parseChordSpec('Cmaj7')!;
      expect(
        c.transposedBy(fifth).transposedBy(fourth, descending: true).format(),
        'Dmaj7',
      );
    });
  });

  group('BB-D1 — equality ignores the octave, as a symbol must', () {
    test('a parsed chord equals a hand-built one', () {
      const built = ChordSpec(
        root: Pitch(Step.c, octave: 2),
        triad: ChordTriad.minor,
        seventh: ChordSeventh.minor,
        alterations: {ChordAlteration.flatFive},
      );
      expect(parseChordSpec('Cm7b5'), built);
      expect(parseChordSpec('Cm7b5').hashCode, built.hashCode);
    });

    test('ChordCell equality follows the chord', () {
      expect(parseChartCell('Cmaj7'), parseChartCell(' CMaj7 '));
      expect(parseChartCell('Cmaj7') == parseChartCell('Cm7'), isFalse);
    });
  });

  group('the vocabulary stays pure Dart', () {
    // Same discipline as `project_codec_test.dart`: purity is invisible until it
    // is gone, so it is asserted rather than trusted. It is what lets the CLI and
    // a headless test read a chart, and BB-D4a (a pasted text grid on the
    // critical path) depends on it. `package:crisp_notation/` is named alongside
    // Flutter because that barrel DEPENDS on Flutter — the pure half is
    // `crisp_notation_core`, which is what these files import for `Pitch`.
    const pureFiles = [
      'lib/core/harmony/chord_spec.dart',
      'lib/core/harmony/chord_spec_parser.dart',
    ];

    for (final path in pureFiles) {
      test('$path imports no Flutter', () {
        final source = File(path).readAsStringSync();
        for (final line in source.split('\n')) {
          final t = line.trimLeft();
          if (!t.startsWith('import ') && !t.startsWith('export ')) continue;
          expect(
            t.contains('package:flutter/') ||
                t.contains('package:crisp_notation/'),
            isFalse,
            reason: '$path pulls in Flutter via: ${t.trim()}',
          );
        }
      });
    }
  });

  group('BB-Q3 — the corpus we actually ship', () {
    // The card asks that the hand-written rows above be EXTENDED from real
    // data: "every distinct <harmony> and JAMS label we can reach becomes a
    // row". The reachable corpus in this repo is the chord-shape databases the
    // app itself browses — 1,380 names across guitar and ukulele.
    //
    // ⚠️ This found a real gap on its first run. `assets/chords/ukulele.json`
    // uses the suffix `minor` spelled out, and the parser accepted `min`, `mi`
    // and `-` but not `minor`: matching is longest-token-first, so `min`
    // matched and left a stranded "or". Fourteen names in our OWN shipped data
    // did not parse. A hand-written corpus cannot find that — only the real
    // data can, which is the whole point of this group.
    List<String> namesFrom(String instrument) {
      final decoded = jsonDecode(
        File('assets/chords/$instrument.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final chords = decoded['chords'] as Map<String, dynamic>;
      return [
        for (final entries in chords.values)
          for (final entry in entries as List)
            '${(entry as Map<String, dynamic>)['key']}'
                '${entry['suffix'] == 'major' ? '' : entry['suffix']}',
      ];
    }

    for (final instrument in ['guitar', 'ukulele']) {
      test('every $instrument chord name we ship parses', () {
        final names = namesFrom(instrument);
        expect(names, isNotEmpty, reason: 'the database should not be empty');
        final unparsed = <String>{
          for (final name in names)
            if (parseChordSpec(name) == null) name,
        };
        expect(
          unparsed,
          isEmpty,
          reason: 'names in our own shipped data that will not parse',
        );
      });

      test('every $instrument chord name round-trips through its print', () {
        // Stronger than "it parses": what we print must read back as the same
        // chord, or the browser and the chart would disagree about a shape the
        // user is looking at.
        for (final name in namesFrom(instrument).toSet()) {
          final parsed = parseChordSpec(name);
          if (parsed == null) continue; // covered by the test above
          expect(
            parseChordSpec(parsed.text),
            parsed,
            reason: '$name printed as "${parsed.text}" and read back different',
          );
        }
      });
    }

    test('the spelled-out qualities parse, and mean what they say', () {
      // Pinned separately from the sweep so the intent survives even if the
      // shipped data changes.
      expect(parseChordSpec('Cminor')?.text, 'Cm');
      expect(parseChordSpec('Cmajor')?.text, 'C');
      expect(parseChordSpec('C#minor')?.text, 'C#m');
      expect(parseChordSpec('Bbminor')?.text, 'Bbm');
      // …and they compose with what follows, rather than swallowing it.
      expect(parseChordSpec('Cminor7')?.text, 'Cm7');
      expect(parseChordSpec('Cmajor7')?.text, 'Cmaj7');
    });
  });
}
