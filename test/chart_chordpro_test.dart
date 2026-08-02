import 'package:comet_beat/core/harmony/chart_chordpro.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// ChordPro → chart.
///
/// The card's acceptance is that a text grid and a ChordPro file import to the
/// SAME chart for the same tune — which is the last test here, and the one the
/// rest exists to make possible.
List<String> symbols(ChordProImport i) => [
      for (final bar in i.chart.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

void main() {
  group('chords', () {
    test('inline brackets become bars, in order', () {
      final i = chartFromChordPro('[C]Twinkle [F]twinkle [G7]little [C]star');
      expect(symbols(i), ['C', 'F', 'G7', 'C']);
    });

    test('one chord is one bar, and the result SAYS it inferred that', () {
      // ChordPro has no barlines; claiming a structure it never had would be
      // worse than admitting the guess.
      final i = chartFromChordPro('[C]a [F]b');
      expect(i.chart.totalBars, 2);
      expect(i.barsAreInferred, isTrue);
    });

    test('chords across several lines accumulate', () {
      final i = chartFromChordPro('[C]one\n[Am]two\n[F]three');
      expect(symbols(i), ['C', 'Am', 'F']);
    });

    test('a chord alone on a line works', () {
      expect(symbols(chartFromChordPro('[Dm7]\n[G7]')), ['Dm7', 'G7']);
    });

    test('an empty bracket is skipped rather than becoming a bar', () {
      expect(chartFromChordPro('[C]a [] b [F]c').chart.totalBars, 2);
    });

    test('N.C. becomes a silent bar', () {
      final i = chartFromChordPro('[C]a [N.C.]b [F]c');
      expect(i.chart.totalBars, 3);
      expect(i.chart.barsInPlayOrder[1].chords, isEmpty);
    });

    test('an unreadable chord is KEPT and reported', () {
      // A chart short of a bar is worse than one with a visible best guess.
      final i = chartFromChordPro('[C]a [wat]b [F]c');
      expect(i.chart.totalBars, 3);
      expect(i.unreadable, ['wat']);
    });

    test('a slash chord and an extension survive', () {
      expect(
        symbols(chartFromChordPro('[C/G]a [F#m7b5]b [Bb13]c')),
        ['C/G', 'F#m7b5', 'Bb13'],
      );
    });
  });

  group('section directives', () {
    test('verse and chorus become sections', () {
      final i = chartFromChordPro(
        '{sov}\n[C]one [F]two\n{eov}\n{soc}\n[G]three [C]four\n{eoc}',
      );
      expect(i.chart.sections.map((s) => s.label), ['Verse', 'Chorus']);
      expect(i.chart.sections.map((s) => s.bars.length), [2, 2]);
    });

    test('the long spellings work too', () {
      final i = chartFromChordPro(
        '{start_of_verse}\n[C]a\n{start_of_chorus}\n[F]b\n'
        '{start_of_bridge}\n[G]c',
      );
      expect(
        i.chart.sections.map((s) => s.label),
        ['Verse', 'Chorus', 'Bridge'],
      );
    });

    test('a directive with a value names the section', () {
      final i = chartFromChordPro('{soc: Chorus 2}\n[C]a');
      expect(i.chart.sections.single.label, 'Chorus 2');
    });

    test('bars before any directive still land in a section', () {
      final i = chartFromChordPro('[C]a\n{soc}\n[F]b');
      expect(i.chart.sections.map((s) => s.label), ['', 'Chorus']);
    });

    test('an end directive closes without opening an empty one', () {
      final i = chartFromChordPro('{soc}\n[C]a\n{eoc}\n');
      expect(i.chart.sections, hasLength(1));
    });
  });

  group('header directives', () {
    test('title, artist, tempo, time and key', () {
      final i = chartFromChordPro(
        '{title: Blue Bossa}\n{artist: Kenny Dorham}\n{tempo: 148}\n'
        '{time: 3/4}\n{key: Cm}\n[Cm]a',
      );
      expect(i.chart.title, 'Blue Bossa');
      expect(i.chart.composer, 'Kenny Dorham');
      expect(i.chart.tempoBpm, 148);
      expect(i.chart.meter, const TimeSignature(3, 4));
      expect(i.chart.keyFifths, -3);
      expect(i.chart.minor, isTrue);
    });

    test('the short spellings work', () {
      final i = chartFromChordPro('{t: Tune}\n{st: Someone}\n[C]a');
      expect(i.chart.title, 'Tune');
      expect(i.chart.composer, 'Someone');
    });

    test('a bad meter is refused rather than asserted', () {
      // TimeSignature asserts a power-of-two unit.
      final i = chartFromChordPro('{time: 4/3}\n[C]a');
      expect(i.chart.meter, const TimeSignature(4, 4));
    });

    test('an unknown directive is skipped, not guessed at', () {
      final i = chartFromChordPro(
        '{capo: 3}\n{columns: 2}\n{comment: play twice}\n[C]a',
      );
      expect(i.chart.totalBars, 1);
      expect(i.chart.title, isEmpty);
    });

    test('a comment line is ignored', () {
      expect(chartFromChordPro('# just a note\n[C]a').chart.totalBars, 1);
    });
  });

  group('degenerate input', () {
    test('an empty file is an empty chart, not a throw', () {
      expect(chartFromChordPro('').isEmpty, isTrue);
      expect(chartFromChordPro('   \n\n  ').isEmpty, isTrue);
    });

    test('lyrics with no chords produce no bars', () {
      expect(chartFromChordPro('just some words\nand more').isEmpty, isTrue);
    });

    test('directives with no chords produce no sections', () {
      expect(chartFromChordPro('{soc}\n{eoc}').chart.sections, isEmpty);
    });

    test('an unterminated bracket does not hang or throw', () {
      expect(() => chartFromChordPro('[C]a [F'), returnsNormally);
    });
  });

  group("the card's acceptance", () {
    test('a ChordPro file and a text grid give the SAME chart', () {
      final fromPro = chartFromChordPro(
        '{title: Tune}\n{key: C}\n{tempo: 120}\n'
        '{sov}\n[C]one [Am]two [Dm7]three [G7]four\n',
      ).chart;
      final fromGrid = parseChartText(
        'title: Tune\nkey: C\ntempo: 120\n[Verse]\n| C | Am | Dm7 | G7 |',
      ).chart;

      expect(fromPro.title, fromGrid.title);
      expect(fromPro.keyFifths, fromGrid.keyFifths);
      expect(fromPro.tempoBpm, fromGrid.tempoBpm);
      expect(fromPro.meter, fromGrid.meter);
      expect(fromPro.totalBars, fromGrid.totalBars);
      expect(
        fromPro.barsInPlayOrder
            .map((b) => b.chordsInOrder.single.chord.text)
            .toList(),
        fromGrid.barsInPlayOrder
            .map((b) => b.chordsInOrder.single.chord.text)
            .toList(),
      );
      expect(fromPro.sections.single.label, fromGrid.sections.single.label);
    });
  });
}
