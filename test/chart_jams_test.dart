import 'dart:convert';

import 'package:comet_beat/core/harmony/chart_chordpro.dart';
import 'package:comet_beat/core/harmony/chart_jams.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// JAMS → chart.
///
/// The card's acceptance is that a text grid, a ChordPro file and a JAMS
/// annotation all import to the SAME chart for the same tune. The first two are
/// asserted in `chart_chordpro_test.dart`; this file closes the third, and pins
/// what the JAMS path loses on the way — which is more than the ChordPro one.
List<String> symbols(ChordProImport i) => [
      for (final bar in i.chart.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

/// A JAMS file carrying one chord annotation in [namespace].
String jams(
  List<(double, double, String)> chords, {
  String namespace = 'chord',
  String? title,
}) =>
    jsonEncode({
      'file_metadata': {if (title != null) 'title': title, 'duration': 30.0},
      'annotations': [
        {
          'namespace': namespace,
          'data': [
            for (final (time, duration, value) in chords)
              {'time': time, 'duration': duration, 'value': value},
          ],
        },
      ],
    });

void main() {
  group('reading an annotation', () {
    test('Harte labels become chords, in order', () {
      final i = chartFromJams(
        jams([
          (0.0, 2.0, 'C:maj'),
          (2.0, 2.0, 'F:maj'),
          (4.0, 2.0, 'G:7'),
          (6.0, 2.0, 'C:maj'),
        ]),
      );
      expect(symbols(i), ['C', 'F', 'G7', 'C']);
    });

    test('the file title becomes the chart title', () {
      final i = chartFromJams(jams([(0.0, 2.0, 'C:maj')], title: 'Blue Bossa'));
      expect(i.chart.title, 'Blue Bossa');
    });

    test('a no-chord label is DROPPED, not kept as a silent bar', () {
      // `N` breaks the run in `jams.dart` by parsing to null, and a null
      // observation is skipped — so unlike ChordPro's `[N.C.]`, which does
      // become a silent bar, a JAMS no-chord leaves no bar behind at all.
      final i = chartFromJams(
        jams([
          (0.0, 2.0, 'C:maj'),
          (2.0, 2.0, 'N'),
          (4.0, 2.0, 'F:maj'),
        ]),
      );
      expect(symbols(i), ['C', 'F']);
      expect(i.chart.totalBars, 2, reason: 'the N leaves no bar');
    });

    test('the other dialects read too', () {
      // The five dialects live in `jams.dart`; this asserts the seam reaches
      // them, not that they each work — that is `jams_test.dart`'s job.
      expect(
        symbols(
          chartFromJams(
            jams(
              // music21 spells a flat with `-`, so `B-` is B flat.
              [(0.0, 2.0, 'C'), (2.0, 2.0, 'B-')],
              namespace: 'chord_m21_leadsheet',
            ),
          ),
        ),
        ['C', 'Bb'],
      );
    });
  });

  group('what the seam costs', () {
    test('a REPEATED chord collapses to one bar', () {
      // ⚠️ The surprising loss, and the reason a JAMS import is not simply a
      // better text grid. `_collapseRuns` in `jams.dart` keeps chord CHANGES,
      // so a chord held over four bars arrives as one. Pinned here so that if
      // the seam ever reads observation durations instead, this test fails and
      // says why.
      final i = chartFromJams(
        jams([
          (0.0, 2.0, 'C:maj'),
          (2.0, 2.0, 'C:maj'),
          (4.0, 2.0, 'C:maj'),
          (6.0, 2.0, 'F:maj'),
        ]),
      );
      expect(symbols(i), ['C', 'F']);
      expect(i.chart.totalBars, 2, reason: 'three bars of C arrive as one');
    });

    test('the bars are inferred, and the result SAYS so', () {
      // JAMS times are in SECONDS with no meter, so the bar structure is this
      // importer's reading rather than the file's — exactly as for ChordPro.
      final i = chartFromJams(jams([(0.0, 2.0, 'C:maj')]));
      expect(i.barsAreInferred, isTrue);
    });
  });

  group('degenerate input', () {
    test('a file with no chord annotation is empty, not a throw', () {
      final noChords = jsonEncode({
        'annotations': [
          {
            'namespace': 'beat',
            'data': [
              {'time': 0.0, 'duration': 0.0, 'value': 1},
            ],
          },
        ],
      });
      expect(chartFromJams(noChords).isEmpty, isTrue);
    });

    test('input that is not JAMS at all is empty, not a throw', () {
      // A user picks an arbitrary file; a crash is never the right answer.
      for (final bad in ['', 'not json', '{}', '[]', '{"annotations": 3}']) {
        expect(
          () => chartFromJams(bad),
          returnsNormally,
          reason: 'refused to handle: $bad',
        );
        expect(chartFromJams(bad).isEmpty, isTrue);
      }
    });
  });

  group("the card's acceptance", () {
    test('a JAMS annotation and a text grid give the SAME chords', () {
      // One chord per bar, which is where the two formats can agree — see the
      // collapsing test above for where they cannot.
      final fromJams = chartFromJams(
        jams(
          [
            (0.0, 2.0, 'C:maj'),
            (2.0, 2.0, 'A:min'),
            (4.0, 2.0, 'D:min7'),
            (6.0, 2.0, 'G:7'),
          ],
          title: 'Tune',
        ),
      ).chart;
      final fromGrid = parseChartText(
        'title: Tune\n| C | Am | Dm7 | G7 |',
      ).chart;

      expect(fromJams.title, fromGrid.title);
      expect(fromJams.totalBars, fromGrid.totalBars);
      expect(
        fromJams.barsInPlayOrder
            .map((b) => b.chordsInOrder.single.chord.text)
            .toList(),
        fromGrid.barsInPlayOrder
            .map((b) => b.chordsInOrder.single.chord.text)
            .toList(),
      );
    });
  });
}
