import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_nashville.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Nashville Number System.
///
/// The point of the format is that the same numbers serve every key, so the
/// assertions that matter are: the same numbers realise differently in
/// different keys, and a chart printed to numbers and read back is unchanged.
Chart chart(String text) => parseChartText(text).chart;

List<String> symbols(Chart c) => [
      for (final bar in c.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

void main() {
  group('reading numbers', () {
    test('the same numbers realise into whatever key is asked for', () {
      const numbers = '| 1 | 4 | 5 | 1 |';
      expect(
        symbols(chartFromNashville(numbers).chart),
        ['C', 'F', 'G', 'C'],
      );
      expect(
        symbols(chartFromNashville(numbers, keyFifths: -2).chart),
        ['Bb', 'Eb', 'F', 'Bb'],
      );
      expect(
        symbols(chartFromNashville(numbers, keyFifths: 3).chart),
        ['A', 'D', 'E', 'A'],
      );
    });

    test('a bare number means the DIATONIC chord, not a major triad', () {
      // The format's one real ambiguity, resolved in the header of the file.
      expect(
        symbols(chartFromNashville('| 1 | 2 | 3 | 6 | 7 |').chart),
        ['C', 'Dm', 'Em', 'Am', 'Bdim'],
      );
    });

    test('maj overrides the implied quality', () {
      expect(symbols(chartFromNashville('| 6maj | 2M |').chart), ['A', 'D']);
    });

    test('an explicit suffix is kept', () {
      expect(
        symbols(chartFromNashville('| 2m7 | 57 | 1maj7 |').chart),
        ['Dm7', 'G7', 'Cmaj7'],
      );
    });

    test('an accidental degree spells the way it was ASKED for', () {
      // The degree's own accidental wins over the key signature: `b7` in C
      // major is B♭, not the A♯ the sharp-side spelling would give.
      expect(symbols(chartFromNashville('| b7 |').chart), ['Bb']);
      expect(symbols(chartFromNashville('| #4 |').chart), ['F#']);
      // …and it still wins in a key whose signature points the other way.
      expect(symbols(chartFromNashville('| b7 |', keyFifths: 3).chart), ['G']);
      expect(symbols(chartFromNashville('| b2 |', keyFifths: 3).chart), ['Bb']);
    });

    test('an accidental degree is measured from the key, not from C', () {
      // #4 of E♭ is A natural, because degree 4 of E♭ is A♭.
      expect(symbols(chartFromNashville('| #4 |', keyFifths: -3).chart), ['A']);
    });

    test('a minor key uses the minor scale degrees', () {
      // fifths 0 + minor is A minor, not C minor — the signature is shared.
      expect(
        symbols(chartFromNashville('| 1 | 4 | 5 | 7 |', minor: true).chart),
        ['Am', 'Dm', 'Em', 'G'],
      );
      // C minor is three flats, and its 7 is already flat: B♭.
      expect(
        symbols(
          chartFromNashville('| 1 | 4 | 7 |', keyFifths: -3, minor: true).chart,
        ),
        ['Cm', 'Fm', 'Bb'],
      );
    });

    test('a header sets the key, overriding the argument', () {
      final imported = chartFromNashville('key: D\n| 1 | 5 |');
      expect(symbols(imported.chart), ['D', 'A']);
      expect(imported.chart.keyFifths, 2);
    });

    test('sections, meter and tempo read like the text grid', () {
      final imported = chartFromNashville(
        'title: Tune\ntempo: 96\nmeter: 3/4\n[A]\n| 1 | 5 |\n[B]\n| 4 | 1 |',
      );
      expect(imported.chart.title, 'Tune');
      expect(imported.chart.tempoBpm, 96);
      expect(imported.chart.meter.beats, 3);
      expect(imported.chart.sections.map((s) => s.label), ['A', 'B']);
    });

    test('a split bar splits its beats', () {
      final bar = chartFromNashville('| 2m7 5 |').chart.barsInPlayOrder.single;
      expect(bar.chordsInOrder.map((c) => c.beat), [0, 2]);
    });

    test('a non-number is reported, not silently dropped', () {
      final imported = chartFromNashville('| 1 | wat | 5 |');
      expect(imported.isClean, isFalse);
      expect(imported.unreadable, ['wat']);
      expect(imported.chart.totalBars, 3);
    });

    test('a held bar stays held', () {
      final imported = chartFromNashville('| 1 | % | 5 |');
      expect(imported.chart.barsInPlayOrder[1].chords, isEmpty);
      expect(imported.isClean, isTrue, reason: '% is notation, not an error');
    });
  });

  group('writing numbers', () {
    test('a diatonic chart prints as bare numbers', () {
      final text = chartToNashville(chart('key: C\n| C | F | G | C |'));
      expect(text, contains('| 1 | 4 | 5 | 1 |'));
    });

    test('an implied quality is left OFF', () {
      // `2m` in C is what a bare `2` already means; printing it would be noise.
      final text = chartToNashville(chart('key: C\n| Dm | Em | Am |'));
      expect(text, contains('| 2 | 3 | 6 |'));
    });

    test('a quality the number does NOT imply is written', () {
      final text = chartToNashville(chart('key: C\n| Dm7 | G7 | Cmaj7 |'));
      expect(text, contains('| 2m7 | 57 | 1maj7 |'));
    });

    test('a major triad on a minor degree says so', () {
      // Otherwise it would read back as the diatonic minor.
      expect(chartToNashville(chart('key: C\n| A |')), contains('| 6maj |'));
    });

    test('an accidental degree prints with its accidental', () {
      expect(chartToNashville(chart('key: C\n| Bb |')), contains('| b7 |'));
    });

    test('a held bar prints as %', () {
      expect(
        chartToNashville(chart('key: C\n| C | % |')),
        contains('| 1 | % |'),
      );
    });
  });

  group('round trip', () {
    test('numbers → chart → numbers is unchanged', () {
      const numbers = 'key: C\nmeter: 4/4\ntempo: 120\n'
          '[A]\n| 1 | 6 | 2m7 | 57 |';
      final once = chartFromNashville(numbers).chart;
      final printed = chartToNashville(once);
      final twice = chartFromNashville(printed).chart;
      expect(symbols(twice), symbols(once));
    });

    test('a chart → numbers → chart keeps every chord', () {
      final before = chart('key: F\n| F | Dm | Bb | C7 | Gm7 | F |');
      final after = chartFromNashville(chartToNashville(before)).chart;
      expect(symbols(after), symbols(before));
      expect(after.keyFifths, before.keyFifths);
    });

    test('the numbers are key-independent, which is the whole point', () {
      // Print a chart in one key, read it back in another: the SHAPE survives.
      final inC = chart('key: C\n| C | Am | Dm7 | G7 |');
      final numbers = chartToNashville(inC);
      final inEb = chartFromNashville(numbers, keyFifths: -3).chart;
      // The header in the printed text names C, so an explicit header wins —
      // strip it to ask for a different key.
      final headerless =
          numbers.split('\n').where((l) => !l.startsWith('key:')).join('\n');
      final really = chartFromNashville(headerless, keyFifths: -3).chart;
      expect(symbols(inEb), symbols(inC), reason: 'the header set the key');
      expect(symbols(really), ['Eb', 'Cm', 'Fm7', 'Bb7']);
    });
  });

  group('degenerate input', () {
    test('empty text is an empty chart', () {
      expect(chartFromNashville('').chart.isEmpty, isTrue);
    });

    test('an empty chart prints a header and no bars', () {
      final text = chartToNashville(const Chart());
      expect(text, contains('key:'));
      expect(text, isNot(contains('|')));
    });

    test('degree 0 and 8 are not numbers', () {
      final imported = chartFromNashville('| 0 | 8 |');
      expect(imported.unreadable, ['0', '8']);
    });
  });
}
