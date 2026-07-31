import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// Reading and writing text charts.
///
/// The contract that matters: **nothing throws and nothing is silently lost.**
/// A chart that quietly dropped the one chord you mistyped is worse than one
/// that keeps it and says which.
void main() {
  List<String> barTexts(Chart c) => [
        for (final bar in c.barsInPlayOrder)
          bar.chords.isEmpty
              ? '%'
              : bar.chordsInOrder.map((e) => e.chord.text).join(' '),
      ];

  group('bars', () {
    test('a simple row of bars', () {
      final r = parseChartText('| C | Am | F | G |');
      expect(r.isClean, isTrue);
      expect(barTexts(r.chart), ['C', 'Am', 'F', 'G']);
    });

    test('the outer pipes are optional', () {
      expect(
        barTexts(parseChartText('C | Am | F | G').chart),
        ['C', 'Am', 'F', 'G'],
      );
      expect(barTexts(parseChartText('| C | Am |').chart), ['C', 'Am']);
    });

    test('an inner empty bar is a HELD bar, not a separator artefact', () {
      // `| C || G |` — the middle cell is a real bar that holds C.
      final r = parseChartText('| C || G |');
      expect(barTexts(r.chart), ['C', '%', 'G']);
    });

    test('% and an empty cell both mean the chord continues', () {
      final r = parseChartText('| C | % |  | G |');
      expect(barTexts(r.chart), ['C', '%', '%', 'G']);
    });

    test('two chords split the bar evenly', () {
      final r = parseChartText('| Dm7 G7 |');
      final bar = r.chart.barsInPlayOrder.single;
      expect(bar.chordsInOrder.map((c) => c.beat), [0, 2]);
    });

    test('three chords divide the bar without inventing an accent', () {
      final r = parseChartText('| C F G |');
      final beats = r.chart.barsInPlayOrder.single.chordsInOrder
          .map((c) => c.beat)
          .toList();
      expect(beats.first, 0);
      expect(beats[1], closeTo(4 / 3, 1e-9));
      expect(beats[2], closeTo(8 / 3, 1e-9));
    });

    test('a split bar respects the meter', () {
      final r = parseChartText('meter: 3/4\n| C G |');
      expect(
        r.chart.barsInPlayOrder.single.chordsInOrder.map((c) => c.beat),
        [0, 1.5],
      );
    });

    test('N.C. is silence, which is not the same as a held bar', () {
      final r = parseChartText('| C | N.C. | G |');
      final bars = r.chart.barsInPlayOrder;
      expect(bars[1].chords, isEmpty);
      // …and it reads as clean: N.C. is understood, not unreadable.
      expect(r.isClean, isTrue);
    });

    test('multiple rows accumulate', () {
      final r = parseChartText('| C | Am |\n| F | G |');
      expect(barTexts(r.chart), ['C', 'Am', 'F', 'G']);
    });
  });

  group('sections', () {
    test('[A] starts a section', () {
      final r = parseChartText('[A]\n| C | G |\n[B]\n| F | C |');
      expect(r.chart.sections.map((s) => s.label), ['A', 'B']);
      expect(r.chart.sections.first.bars, hasLength(2));
    });

    test('a repeat count expands in play order', () {
      final r = parseChartText('[A] x2\n| C | G |');
      expect(r.chart.sections.single.passes, 2);
      expect(r.chart.totalBars, 4);
    });

    test('A: is an accepted spelling of a section label', () {
      final r = parseChartText('A:\n| C |\nB:\n| G |');
      expect(r.chart.sections.map((s) => s.label), ['A', 'B']);
    });

    test('a label with no bars under it is not emitted as a section', () {
      final r = parseChartText('[A]\n[B]\n| C |');
      expect(r.chart.sections, hasLength(1));
      expect(r.chart.sections.single.label, 'B');
    });

    test('bars before any label still land in a section', () {
      final r = parseChartText('| C | G |');
      expect(r.chart.sections, hasLength(1));
      expect(r.chart.sections.single.label, '');
    });
  });

  group('header fields', () {
    test('title, composer, tempo', () {
      final r = parseChartText(
        'title: Blue Bossa\ncomposer: Kenny Dorham\ntempo: 148\n| Cm |',
      );
      expect(r.chart.title, 'Blue Bossa');
      expect(r.chart.composer, 'Kenny Dorham');
      expect(r.chart.tempoBpm, 148);
    });

    test('meter', () {
      expect(
        parseChartText('meter: 3/4\n| C |').chart.meter,
        const TimeSignature(3, 4),
      );
      expect(
        parseChartText('time: 6/8\n| C |').chart.meter,
        const TimeSignature(6, 8),
      );
    });

    test('a meter with a non-power-of-two unit is refused, not asserted', () {
      // TimeSignature asserts a power-of-two unit; the parser must not hand it
      // one, or a typed "4/3" crashes in debug instead of being ignored.
      final r = parseChartText('meter: 4/3\n| C |');
      expect(r.chart.meter, const TimeSignature(4, 4));
    });

    test('keys, major and minor', () {
      expect(parseChartText('key: Bb\n| C |').chart.keyFifths, -2);
      expect(parseChartText('key: C\n| C |').chart.keyFifths, 0);
      expect(parseChartText('key: F#\n| C |').chart.keyFifths, 6);

      final am = parseChartText('key: Am\n| C |').chart;
      expect(am.minor, isTrue);
      expect(am.keyFifths, 0, reason: 'A minor shares C major signature');

      final cm = parseChartText('key: C minor\n| C |').chart;
      expect(cm.minor, isTrue);
      expect(cm.keyFifths, -3);
    });

    test('an out-of-range key is ignored rather than clamped', () {
      // Gb minor would be -9 fifths; there is no such signature.
      final r = parseChartText('key: Gbm\n| C |');
      expect(r.chart.keyFifths, 0);
      expect(r.chart.minor, isFalse);
    });

    test('defaults carry through so editing does not reset the header', () {
      const base = Chart(title: 'Kept', tempoBpm: 90, styleId: 'bossa');
      final r = parseChartText('| C |', defaults: base);
      expect(r.chart.title, 'Kept');
      expect(r.chart.tempoBpm, 90);
      expect(r.chart.styleId, 'bossa');
    });
  });

  group('comments', () {
    test('// and # comment to end of line', () {
      final r = parseChartText('| C | G | // the turnaround\n| F | # later');
      expect(barTexts(r.chart), ['C', 'G', 'F']);
    });

    test('a sharp glued to a chord is NOT a comment', () {
      // The whole reason `#` only counts at a word boundary.
      final r = parseChartText('| C#m7 | F#7 |');
      expect(r.isClean, isTrue);
      expect(barTexts(r.chart), ['C#m7', 'F#7']);
    });
  });

  group('unreadable input', () {
    test('junk is kept and reported, never dropped', () {
      final r = parseChartText('| C | wat | G |');
      expect(r.isClean, isFalse);
      expect(r.problems.single.text, 'wat');
      expect(r.problems.single.barNumber, 2);
      // The bar still exists, so the chart does not silently shorten.
      expect(r.chart.totalBars, 3);
    });

    test('a problem carries the line it was typed on', () {
      final r = parseChartText('| C |\n| ??? |');
      expect(r.problems.single.line, 2);
    });

    test('empty input is an empty chart, not a crash', () {
      final r = parseChartText('');
      expect(r.chart.isEmpty, isTrue);
      expect(r.isClean, isTrue);
    });

    test('nothing but comments is also empty', () {
      expect(
        parseChartText('// nothing here\n# nor here').chart.isEmpty,
        isTrue,
      );
    });
  });

  group('round trip', () {
    test('format then parse preserves the bars', () {
      final source = parseChartText(
        'title: Tune\nkey: F\nmeter: 3/4\ntempo: 96\n'
        '[A] x2\n| C | Am | Dm7 G7 | C |\n[B]\n| F | % | G7 | C |',
      ).chart;

      final round = parseChartText(formatChartText(source)).chart;

      expect(round.title, source.title);
      expect(round.keyFifths, source.keyFifths);
      expect(round.minor, source.minor);
      expect(round.meter, source.meter);
      expect(round.tempoBpm, source.tempoBpm);
      expect(
        round.sections.map((s) => s.label),
        source.sections.map((s) => s.label),
      );
      expect(
        round.sections.map((s) => s.passes),
        source.sections.map((s) => s.passes),
      );
      expect(barTexts(round), barTexts(source));
    });

    test('a minor key survives the round trip', () {
      final source = parseChartText('key: C minor\n| Cm |').chart;
      final round = parseChartText(formatChartText(source)).chart;
      expect(round.minor, isTrue);
      expect(round.keyFifths, -3);
    });

    test('rows longer than four bars are re-wrapped, not lost', () {
      final source = parseChartText('| C | D | E | F | G | A |').chart;
      final round = parseChartText(formatChartText(source)).chart;
      expect(round.totalBars, 6);
      expect(barTexts(round), barTexts(source));
    });
  });
}
