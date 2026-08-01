import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// Form realisation — the ONE answer to "what sounds at bar 17".
///
/// Bass, drums, comp and the playhead all read this list, so the assertions
/// that matter are the ones that would let two of them disagree: bar counts,
/// where a phrase ends, and which chorus a bar belongs to.
Chart chart(String text) => parseChartText(text).chart;

List<RealizedBar> tuneBars(List<RealizedBar> bars) =>
    bars.where((b) => b.role == BarRole.tune).toList();

void main() {
  const blues = '[A]\n| C7 | F7 | C7 | C7 |\n| F7 | F7 | C7 | C7 |\n'
      '| G7 | F7 | C7 | G7 |';

  group('bar counts', () {
    test('one chorus, no extras, is exactly the chart', () {
      final bars = realizeForm(
        chart(blues),
        options: const FormOptions(countIn: false, ending: false),
      );
      expect(bars, hasLength(12));
      expect(bars.every((b) => b.role == BarRole.tune), isTrue);
    });

    test('a count-in and an ending add exactly one bar each', () {
      final bars = realizeForm(chart(blues));
      expect(bars, hasLength(14));
      expect(bars.first.role, BarRole.countIn);
      expect(bars.last.role, BarRole.ending);
    });

    test('choruses multiply the tune, not the count-in', () {
      final bars = realizeForm(
        chart(blues),
        options: const FormOptions(choruses: 3),
      );
      expect(tuneBars(bars), hasLength(36));
      expect(bars.where((b) => b.role == BarRole.countIn), hasLength(1));
      expect(bars.where((b) => b.role == BarRole.ending), hasLength(1));
    });

    test('a section repeat is expanded once per chorus', () {
      final bars = realizeForm(
        chart('[A] x2\n| C | G |'),
        options: const FormOptions(choruses: 2, countIn: false, ending: false),
      );
      expect(bars, hasLength(8), reason: '2 bars × 2 passes × 2 choruses');
    });

    test('an empty chart realises to nothing rather than a count-in alone', () {
      expect(realizeForm(const Chart()), isEmpty);
    });
  });

  group('phrases', () {
    test('a phrase ends every four bars, counted within the chorus', () {
      final bars = tuneBars(
        realizeForm(
          chart(blues),
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      final ends = [
        for (var i = 0; i < bars.length; i++)
          if (bars[i].isPhraseEnd) i,
      ];
      expect(ends, [3, 7, 11]);
    });

    test('phrases RESTART each chorus rather than drifting', () {
      // A 12-bar form over 3 choruses: if phrase ends were counted from the
      // start of the timeline they would land at 3,7,11,15,… which is
      // mid-phrase from bar 13 on. This is the reason barInChorus exists.
      final bars = tuneBars(
        realizeForm(
          chart(blues),
          options: const FormOptions(
            choruses: 3,
            countIn: false,
            ending: false,
          ),
        ),
      );
      final ends = [
        for (var i = 0; i < bars.length; i++)
          if (bars[i].isPhraseEnd) i,
      ];
      // Same shape in each chorus, offset by 12.
      expect(ends, [3, 7, 11, 15, 19, 23, 27, 31, 35]);
    });

    test('the last bar of a section is always a phrase end', () {
      // A 6-bar section does not divide by four, but its end is still a place
      // a drummer fills.
      final bars = tuneBars(
        realizeForm(
          chart('[A]\n| C | D | E | F | G | A |\n[B]\n| C |'),
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars[5].isPhraseEnd, isTrue);
      expect(bars[5].isSectionEnd, isTrue);
    });

    test('a section end is the LAST pass, not each pass', () {
      final bars = tuneBars(
        realizeForm(
          chart('[A] x2\n| C | G |'),
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars.map((b) => b.isSectionEnd), [false, false, false, true]);
    });
  });

  group('intensity', () {
    test('the last chorus lifts', () {
      final bars = tuneBars(
        realizeForm(
          chart(blues),
          options: const FormOptions(choruses: 2, countIn: false),
        ),
      );
      expect(bars.first.intensity, 2);
      expect(bars.last.intensity, 3);
    });

    test('a SINGLE chorus does not lift', () {
      // Otherwise "the last chorus lifts" would just mean "always louder".
      final bars = tuneBars(realizeForm(chart(blues)));
      expect(bars.every((b) => b.intensity == 2), isTrue);
    });

    test('a section intensity overrides the base', () {
      final source = chart('[A]\n| C |');
      final withIntensity = Chart(
        meter: source.meter,
        tempoBpm: source.tempoBpm,
        sections: [
          ChartSection(
            label: 'A',
            bars: source.sections.single.bars,
            intensity: 1,
          ),
        ],
      );
      final bars = tuneBars(
        realizeForm(
          withIntensity,
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars.single.intensity, 3, reason: '1.0 × 3 levels');
    });

    test('intensity never leaves 0..3 even when lifted from the top', () {
      final source = chart('[A]\n| C |');
      final loud = Chart(
        sections: [
          ChartSection(bars: source.sections.single.bars, intensity: 1),
        ],
      );
      final bars = tuneBars(
        realizeForm(loud, options: const FormOptions(choruses: 2)),
      );
      expect(bars.every((b) => b.intensity <= 3), isTrue);
    });
  });

  group('the generated bars', () {
    test('the ending holds the tune\'s last chord, not an invented one', () {
      final bars = realizeForm(chart(blues));
      final ending = bars.last;
      expect(ending.role, BarRole.ending);
      expect(ending.chords.single.chord.text, 'G7');
    });

    test('exactly one bar is flagged last, and it is the final one', () {
      final bars = realizeForm(chart(blues));
      expect(bars.where((b) => b.isLastBar), hasLength(1));
      expect(bars.last.isLastBar, isTrue);
    });

    test('with no ending, the last TUNE bar is the last bar', () {
      final bars = realizeForm(
        chart(blues),
        options: const FormOptions(ending: false),
      );
      expect(bars.last.role, BarRole.tune);
      expect(bars.last.isLastBar, isTrue);
    });

    test('the count-in carries no chords', () {
      expect(realizeForm(chart(blues)).first.chords, isEmpty);
    });
  });

  group('bars point back at the document', () {
    test('a tune bar knows which section and bar it came from', () {
      final bars = tuneBars(
        realizeForm(
          chart('[A]\n| C | G |\n[B]\n| F |'),
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars.map((b) => b.sourceBar), [
        (section: 0, bar: 0),
        (section: 0, bar: 1),
        (section: 1, bar: 0),
      ]);
    });

    test('a repeat points every pass at the SAME document bar', () {
      // The highlight must land on the bar the user is looking at.
      final bars = tuneBars(
        realizeForm(
          chart('[A] x2\n| C | G |'),
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars.map((b) => b.sourceBar?.bar), [0, 1, 0, 1]);
    });

    test('generated bars have no source', () {
      final bars = realizeForm(chart(blues));
      expect(bars.first.sourceBar, isNull);
      expect(bars.last.sourceBar, isNull);
    });
  });

  group('meter', () {
    test('a per-bar meter change survives realisation', () {
      final source = chart('[A]\n| C | G |');
      final mixed = Chart(
        sections: [
          ChartSection(
            bars: [
              source.sections.single.bars.first,
              ChartBar(
                chords: source.sections.single.bars[1].chords,
                meterChange: const TimeSignature(3, 4),
              ),
            ],
          ),
        ],
      );
      final bars = tuneBars(
        realizeForm(
          mixed,
          options: const FormOptions(countIn: false, ending: false),
        ),
      );
      expect(bars[0].meter, const TimeSignature(4, 4));
      expect(bars[1].meter, const TimeSignature(3, 4));
    });
  });

  group('chord lookahead', () {
    test('nextChordAfter skips held bars to find the real next chord', () {
      final bars = realizeForm(
        chart('| C | % | % | G |'),
        options: const FormOptions(countIn: false, ending: false),
      );
      expect(nextChordAfter(bars, 0)?.text, 'G');
      expect(nextChordAfter(bars, 3), isNull);
    });

    test('chordAt looks BACKWARD through held bars', () {
      final bars = realizeForm(
        chart('| C | % | % | G |'),
        options: const FormOptions(countIn: false, ending: false),
      );
      expect(chordAt(bars, 2)?.text, 'C');
    });
  });

  test('the same options realise identically', () {
    final a =
        realizeForm(chart(blues), options: const FormOptions(choruses: 3));
    final b =
        realizeForm(chart(blues), options: const FormOptions(choruses: 3));
    expect(
      a.map((x) => '${x.index}${x.intensity}${x.isPhraseEnd}'),
      b.map((x) => '${x.index}${x.intensity}${x.isPhraseEnd}'),
    );
  });
}
