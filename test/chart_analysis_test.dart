import 'package:comet_beat/core/harmony/chart_analysis.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show HarmonicFunction;
import 'package:flutter_test/flutter_test.dart';

/// The chart, explained.
///
/// The card asks for a TABLE of known progressions against expected roman
/// numerals and expected ii–V detections, plus one thing asserted end to end:
/// a secondary dominant reads as a DOMINANT, not as a key change.
ChartAnalysis analyze(String text) => analyzeChart(parseChartText(text).chart);

List<String> numerals(ChartAnalysis a) =>
    [for (final c in a.chords) c.numeral.symbol];

List<String> phraseLabels(ChartAnalysis a) =>
    [for (final p in a.phrases) p.label];

void main() {
  group('the table of known progressions', () {
    const cases = <(String name, String chart, List<String> expected)>[
      (
        'I–IV–V–I in C',
        'key: C\n| C | F | G | C |',
        ['I', 'IV', 'V', 'I'],
      ),
      (
        'ii–V–I in C',
        'key: C\n| Dm7 | G7 | Cmaj7 |',
        // The library renders a major seventh `M7`, not `maj7` — its
        // convention, and this table follows it rather than the chart's.
        ['ii7', 'V7', 'IM7'],
      ),
      (
        'the doo-wop changes',
        'key: C\n| C | Am | F | G |',
        ['I', 'vi', 'IV', 'V'],
      ),
      (
        'a minor ii–V–i',
        'key: Am\n| Bm7b5 | E7 | Am |',
        ['iiø7', 'V7', 'i'],
      ),
      (
        'a flat-seven borrowed chord',
        'key: C\n| C | Bb | F | C |',
        ['I', 'bVII', 'IV', 'I'],
      ),
    ];

    for (final (name, chart, expected) in cases) {
      test(name, () => expect(numerals(analyze(chart)), expected));
    }
  });

  group('a secondary dominant is a DOMINANT, not a key change', () {
    test('A7 in C reads as V7/ii and stays a dominant', () {
      // The card names this explicitly. A chart that redrew its key every time
      // an applied dominant appeared would be unreadable.
      final a = analyze('key: C\n| C | A7 | Dm7 | G7 |');
      final applied = a.chords[1];

      expect(applied.numeral.symbol, 'V7/ii');
      expect(applied.isSecondary, isTrue);
      expect(applied.function, HarmonicFunction.dominant);
      // The key never moved.
      expect(a.key.tonic.step.name, 'c');
      expect(a.key.isMajor, isTrue);
    });

    test('every applied dominant in a chain is still a dominant', () {
      final a = analyze('key: C\n| E7 | A7 | D7 | G7 |');
      expect(
        a.chords.map((c) => c.function),
        everyElement(HarmonicFunction.dominant),
      );
      expect(a.chords.take(3).every((c) => c.isSecondary), isTrue);
      expect(a.chords.last.isSecondary, isFalse, reason: 'G7 IS the dominant');
    });

    test('a diatonic chord is not marked secondary', () {
      final a = analyze('key: C\n| Dm7 | G7 | Cmaj7 |');
      expect(a.chords.every((c) => !c.isSecondary), isTrue);
    });
  });

  group('ii–V detection', () {
    test('a plain ii–V–I is found and named by its target', () {
      final a = analyze('key: C\n| Dm7 | G7 | Cmaj7 |');
      expect(phraseLabels(a), contains('ii–V–I in C'));
    });

    test('an unresolved ii–V is found, and reported as unresolved', () {
      final a = analyze('key: C\n| Dm7 | G7 |');
      expect(phraseLabels(a), contains('ii–V in C'));
      expect(phraseLabels(a), isNot(contains('ii–V–I in C')));
    });

    test('an APPLIED ii–V is found too', () {
      // `Em7 A7` in C is a ii–V of D, which numerals alone would not surface —
      // the detection works on the root interval for exactly this reason.
      final a = analyze('key: C\n| Em7 | A7 | Dm7 | G7 |');
      expect(phraseLabels(a), contains('ii–V–I in D'));
    });

    test('two ii–Vs in a row are both found', () {
      final a = analyze('key: C\n| Dm7 | G7 | Em7 | A7 |');
      final twoFives = a.phrases.where(
        (p) => p.kind == PhraseKind.twoFive || p.kind == PhraseKind.twoFiveOne,
      );
      expect(twoFives.length, greaterThanOrEqualTo(2));
    });

    test('a major-ii is NOT a ii–V', () {
      // ii must be minor; `D7 G7` is a chain of dominants, not a ii–V.
      final a = analyze('key: C\n| D7 | G7 |');
      expect(
        a.phrases.where((p) => p.kind == PhraseKind.twoFive),
        isEmpty,
      );
    });

    test('the phrase spans the right bars', () {
      final a = analyze('key: C\n| C | Dm7 | G7 | Cmaj7 |');
      final phrase =
          a.phrases.firstWhere((p) => p.kind == PhraseKind.twoFiveOne);
      expect(phrase.fromBar, 2);
      expect(phrase.toBar, 4);
    });
  });

  group('cadences', () {
    test('V–I is a perfect cadence', () {
      expect(
        phraseLabels(analyze('key: C\n| G | C |')),
        contains('perfect cadence'),
      );
    });

    test('IV–I is plagal', () {
      expect(
        phraseLabels(analyze('key: C\n| F | C |')),
        contains('plagal cadence'),
      );
    });

    test('V–vi is deceptive', () {
      expect(
        phraseLabels(analyze('key: C\n| G | Am |')),
        contains('deceptive cadence'),
      );
    });

    test('ending on V is a half cadence', () {
      expect(
        phraseLabels(analyze('key: C\n| C | F | G |')),
        contains('half cadence'),
      );
    });

    test('a turnaround is named when the last four lead back', () {
      expect(
        phraseLabels(analyze('key: C\n| C | Am | Dm7 | G7 |')),
        contains('turnaround'),
      );
    });
  });

  group('per-chord advice', () {
    test('the scale follows the DEGREE, not just the chord', () {
      // The same minor seventh means different things on different degrees.
      final a = analyze('key: C\n| Dm7 | Em7 | Am7 |');
      expect(a.chords[0].scale, 'D dorian');
      expect(a.chords[1].scale, 'E phrygian');
      expect(a.chords[2].scale, 'A aeolian');
    });

    test('a dominant gets mixolydian, an altered one gets altered', () {
      expect(analyze('key: C\n| G7 |').chords.single.scale, 'G mixolydian');
      expect(analyze('key: C\n| G7alt |').chords.single.scale, 'G altered');
    });

    test('IV gets lydian, I gets major', () {
      final a = analyze('key: C\n| C | F |');
      expect(a.chords[0].scale, 'C major');
      expect(a.chords[1].scale, 'F lydian');
    });

    test('a half-diminished gets locrian, a dim7 gets diminished', () {
      expect(analyze('key: C\n| Bm7b5 |').chords.single.scale, 'B locrian');
      expect(analyze('key: C\n| Bdim7 |').chords.single.scale, 'B diminished');
    });

    test('guide tones are the third and the seventh', () {
      final g7 = analyze('key: C\n| G7 |').chords.single;
      expect(g7.guideTones, [4, 10]);
      final c = analyze('key: C\n| C |').chords.single;
      expect(c.guideTones, [4]);
    });
  });

  group('shape', () {
    test('every bar with a chord gets a reading', () {
      final a = analyze('key: C\n| C | Am | F | G |');
      expect(a.chords, hasLength(4));
      expect(a.chords.map((c) => c.barNumber), [1, 2, 3, 4]);
    });

    test('a held bar contributes no reading but does not shift numbering', () {
      final a = analyze('key: C\n| C | % | G |');
      expect(a.chords.map((c) => c.barNumber), [1, 3]);
    });

    test('a split bar gets a reading per chord', () {
      final a = analyze('key: C\n| Dm7 G7 |');
      expect(a.chords, hasLength(2));
      expect(a.chords.every((c) => c.barNumber == 1), isTrue);
    });

    test('phrasesAt finds what touches a bar', () {
      final a = analyze('key: C\n| Dm7 | G7 | Cmaj7 |');
      expect(a.phrasesAt(2), isNotEmpty);
      expect(a.phrasesAt(99), isEmpty);
    });

    test('an empty chart analyses to nothing rather than throwing', () {
      final a = analyze('');
      expect(a.isEmpty, isTrue);
      expect(a.phrases, isEmpty);
    });

    test('repeats are analysed in play order', () {
      final a = analyze('[A] x2\nkey: C\n| C | G |');
      expect(a.chords, hasLength(4));
      expect(numerals(a), ['I', 'V', 'I', 'V']);
    });
  });
}
