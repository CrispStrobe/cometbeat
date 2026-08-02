import 'package:comet_beat/core/harmony/chart_analysis.dart';
import 'package:comet_beat/core/harmony/chart_reharm.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reharmonisation suggestions.
///
/// 🔴 The rule this file exists to keep: SUGGEST, NEVER REWRITE. The chart
/// belongs to whoever wrote it, so the first assertion here is that asking for
/// suggestions changes nothing.
List<ReharmSuggestion> suggest(String text) =>
    suggestReharmonisations(analyzeChart(parseChartText(text).chart));

List<ReharmSuggestion> ofKind(String text, ReharmKind kind) => [
      for (final s in suggest(text))
        if (s.kind == kind) s,
    ];

void main() {
  test('asking for suggestions does not change the chart', () {
    final chart = parseChartText('key: C\n| Dm7 | G7 | Cmaj7 |').chart;
    final before = [
      for (final bar in chart.barsInPlayOrder)
        for (final c in bar.chordsInOrder) c.chord.text,
    ];
    suggestReharmonisations(analyzeChart(chart));
    final after = [
      for (final bar in chart.barsInPlayOrder)
        for (final c in bar.chordsInOrder) c.chord.text,
    ];
    expect(after, before);
  });

  group('tritone sub', () {
    test('G7 suggests Db7', () {
      final subs = ofKind('key: C\n| G7 |', ReharmKind.tritoneSub);
      expect(subs.single.replacement, 'Db7');
      expect(subs.single.original, 'G7');
      expect(subs.single.isInsertion, isFalse, reason: 'it REPLACES');
    });

    test('it is spelled with flats, as ♭II7 conventionally is', () {
      // C7's tritone is F♯/G♭; the flat spelling is what a chart writes.
      expect(
        ofKind('key: F\n| C7 |', ReharmKind.tritoneSub).single.replacement,
        'Gb7',
      );
    });

    test('every dominant gets one', () {
      final subs =
          ofKind('key: C\n| E7 | A7 | D7 | G7 |', ReharmKind.tritoneSub);
      expect(subs.map((s) => s.replacement), ['Bb7', 'Eb7', 'Ab7', 'Db7']);
    });

    test('a chord that is NOT a dominant gets none', () {
      // The substitution rests on the tritone between third and seventh, which
      // a triad or a major seventh does not have.
      for (final chart in ['| C |', '| Cmaj7 |', '| Cm7 |', '| Cdim7 |']) {
        expect(
          ofKind('key: C\n$chart', ReharmKind.tritoneSub),
          isEmpty,
          reason: chart,
        );
      }
    });

    test('the reason explains the mechanism, not just the name', () {
      final why = ofKind('key: C\n| G7 |', ReharmKind.tritoneSub).single.why;
      expect(why, contains('third'));
      expect(why, contains('seventh'));
    });
  });

  group('relative ii–V', () {
    test('G7 suggests Dm7 in front of it', () {
      final subs = ofKind('key: C\n| G7 |', ReharmKind.relativeTwoFive);
      expect(subs.single.replacement, 'Dm7 G7');
      expect(subs.single.isInsertion, isTrue, reason: 'it ADDS a chord');
    });

    test('it is NOT suggested where the ii is already there', () {
      // Suggesting what is already written is noise.
      expect(
        ofKind('key: C\n| Dm7 | G7 |', ReharmKind.relativeTwoFive),
        isEmpty,
      );
    });

    test('a different minor chord before the dominant does not count', () {
      // Em7 is not the ii of G7; the suggestion still applies.
      expect(
        ofKind('key: C\n| Em7 | G7 |', ReharmKind.relativeTwoFive),
        hasLength(1),
      );
    });

    test('only dominants get one', () {
      expect(
        ofKind('key: C\n| Cmaj7 | Am7 |', ReharmKind.relativeTwoFive),
        isEmpty,
      );
    });
  });

  group('passing diminished', () {
    test('two chords a whole tone apart suggest one between', () {
      // C → D: C♯dim7 walks the bass up by half steps.
      final subs = ofKind('key: C\n| C | Dm7 |', ReharmKind.diminishedPassing);
      expect(subs.single.replacement, 'C#dim7');
      expect(subs.single.isInsertion, isTrue);
    });

    test('it is spelled with SHARPS, because it walks up', () {
      final subs = ofKind('key: F\n| F | Gm7 |', ReharmKind.diminishedPassing);
      expect(subs.single.replacement, 'F#dim7');
    });

    test('chords a semitone or a fourth apart get none', () {
      expect(
        ofKind('key: C\n| C | Db |', ReharmKind.diminishedPassing),
        isEmpty,
      );
      expect(
        ofKind('key: C\n| C | F |', ReharmKind.diminishedPassing),
        isEmpty,
      );
    });

    test('the last chord gets none — there is nothing to pass INTO', () {
      final subs = ofKind('key: C\n| C | D |', ReharmKind.diminishedPassing);
      expect(subs, hasLength(1));
      expect(subs.single.barNumber, 1);
    });

    test('the suggestion names both chords it sits between', () {
      final subs = ofKind('key: C\n| C | Dm7 |', ReharmKind.diminishedPassing);
      expect(subs.single.original, 'C → Dm7');
    });
  });

  group('shape', () {
    test('suggestions carry the bar they apply to', () {
      final subs = suggest('key: C\n| Cmaj7 | Am7 | Dm7 | G7 |');
      expect(subs.every((s) => s.barNumber >= 1 && s.barNumber <= 4), isTrue);
      expect(
        ofKind('key: C\n| Cmaj7 | Am7 | Dm7 | G7 |', ReharmKind.tritoneSub)
            .single
            .barNumber,
        4,
      );
    });

    test('an empty chart suggests nothing rather than throwing', () {
      expect(suggest(''), isEmpty);
    });

    test('a chart with no substitutable chord suggests nothing', () {
      expect(suggest('key: C\n| C | F | C |'), isEmpty);
    });

    test('a real turnaround produces the expected set', () {
      // C Am7 Dm7 G7: the G7 gets a tritone sub, and C→Dm7 is not adjacent, so
      // the only passing option is Am7 → ... which is a fourth. Just the sub
      // and no relative ii–V, because Dm7 already precedes G7.
      final subs = suggest('key: C\n| C | Am7 | Dm7 | G7 |');
      expect(subs.map((s) => s.kind).toSet(), {ReharmKind.tritoneSub});
    });

    test('toString reads as a substitution', () {
      final sub = ofKind('key: C\n| G7 |', ReharmKind.tritoneSub).single;
      expect(sub.toString(), 'G7 → Db7 (tritone sub)');
    });
  });
}
