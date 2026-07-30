// BB-D2 — the chart document and its codec.
//
// The card's acceptance is a round trip "with every construct present", plus the
// rule that an unknown section/repeat token in a stored file is preserved
// verbatim. That second half is the one worth being careful about, because its
// failure mode is invisible: a newer build writes a chart using something this
// build lacks, this build opens it and saves, and the construct is gone. Nothing
// throws, nothing looks wrong, and the file is quietly poorer.
//
// The chord encoding is also verified rather than assumed. Chords are stored as
// SYMBOLS on the strength of `ChordSpec`'s documented invariant — `parse(format(
// x)) == x` — so these tests check that claim against a corpus rather than
// trusting the comment, and check that the structural fallback works for the day
// it stops holding.

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_codec.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Step, TimeSignature;
import 'package:flutter_test/flutter_test.dart';

ChartBeatChord _c(String symbol, {double beat = 0, double beats = 1}) =>
    ChartBeatChord(chord: parseChordSpec(symbol)!, beat: beat, beats: beats);

/// A chart using every construct the document models.
Chart _everything() => Chart(
      title: 'All Of It',
      composer: 'Nobody',
      keyFifths: -3,
      minor: true,
      meter: const TimeSignature(7, 8),
      tempoBpm: 132,
      styleId: 'bossa',
      pickupBeats: 1.5,
      sections: [
        ChartSection(
          label: 'Intro',
          repeatCount: 2,
          feel: 'swing',
          tempoScale: 0.5,
          intensity: 0.25,
          bars: [
            ChartBar(
              chords: [_c('Cmaj7'), _c('F#m7b5', beat: 2, beats: 1.5)],
              barline: ChartBarline.repeatStart,
              endingNumber: 1,
              navigation: ChartNavigation.segno,
            ),
            ChartBar(
              chords: [_c('Bb7#11/D')],
              meterChange: const TimeSignature(2, 4),
              barline: ChartBarline.repeatEnd,
            ),
          ],
        ),
        ChartSection(
          label: 'A',
          bars: [
            const ChartBar(),
            ChartBar(
              chords: [_c('Csus4'), _c('C5'), _c('Caug'), _c('Cdim')],
              barline: ChartBarline.end,
              navigation: ChartNavigation.dcAlFine,
            ),
          ],
        ),
      ],
    );

void main() {
  group('round trip', () {
    test('every construct survives, field by field', () {
      final before = _everything();
      final after = chartFromJsonString(chartToJsonString(before))!;

      expect(after.title, before.title);
      expect(after.composer, before.composer);
      expect(after.keyFifths, before.keyFifths);
      expect(after.minor, before.minor);
      expect(after.meter.beats, 7);
      expect(after.meter.beatUnit, 8);
      expect(after.tempoBpm, before.tempoBpm);
      expect(after.styleId, before.styleId);
      expect(after.pickupBeats, before.pickupBeats);
      expect(after.sections, hasLength(2));

      final intro = after.sections.first;
      expect(intro.label, 'Intro');
      expect(intro.repeatCount, 2);
      expect(intro.feel, 'swing');
      expect(intro.tempoScale, 0.5);
      expect(intro.intensity, 0.25);

      final bar0 = intro.bars.first;
      expect(bar0.barline, ChartBarline.repeatStart);
      expect(bar0.endingNumber, 1);
      expect(bar0.navigation, ChartNavigation.segno);
      expect(bar0.chords, hasLength(2));
      expect(bar0.chords[1].beat, 2);
      expect(bar0.chords[1].beats, 1.5);

      expect(intro.bars[1].meterChange!.beats, 2);
      expect(after.sections[1].bars.first.isEmpty, isTrue);
      expect(after.sections[1].bars[1].navigation, ChartNavigation.dcAlFine);
    });

    test('every CHORD survives as the same spec', () {
      final before = _everything();
      final after = chartFromJsonString(chartToJsonString(before))!;
      List<ChordSpec> chords(Chart c) => [
            for (final s in c.sections)
              for (final b in s.bars)
                for (final ch in b.chords) ch.chord,
          ];
      expect(chords(after), chords(before));
    });

    test('the codec writes its version', () {
      expect(chartToJson(_everything())['v'], kChartCodecVersion);
    });

    test('an empty chart round-trips as empty rather than as null', () {
      final after = chartFromJsonString(chartToJsonString(const Chart()))!;
      expect(after.sections, isEmpty);
      expect(after.isEmpty, isTrue);
    });
  });

  group('chords are stored as symbols, and that is verified', () {
    test("ChordSpec's parse(format(x)) == x invariant holds on a corpus", () {
      // The reason a chart file can say "Cmaj7" instead of eleven fields. Tested
      // rather than trusted, because the whole encoding rests on it.
      const corpus = [
        'C',
        'Cm',
        'C7',
        'Cmaj7',
        'Cm7',
        'Cm7b5',
        'Cdim',
        'Cdim7',
        'Caug',
        'C6',
        'C9',
        'C11',
        'C13',
        'Csus2',
        'Csus4',
        'C5',
        'Cadd9',
        'C7b5',
        'C7#5',
        'C7b9',
        'C7#11',
        'Cm9',
        'Cmaj9',
        'C/G',
        'Cm7/Bb',
        'F#m7b5',
        'Bb7#11/D',
        'Ebmaj7',
        'G#dim7',
        'Dbsus4',
      ];
      for (final symbol in corpus) {
        final spec = parseChordSpec(symbol);
        expect(spec, isNotNull, reason: symbol);
        expect(
          parseChordSpec(spec!.text),
          spec,
          reason: '$symbol formatted as "${spec.text}" and did not come back',
        );
      }
    });

    test('so the encoder never needs its structural fallback today', () {
      // If this ever fails the file is still CORRECT — the fallback caught it —
      // and this test is how we find out rather than shipping wrong chords.
      final json = chartToJson(_everything());
      final sections = json['sections'] as List;
      for (final section in sections) {
        for (final bar in (section as Map)['bars'] as List) {
          for (final chord in ((bar as Map)['chords'] as List?) ?? const []) {
            expect(
              (chord as Map).containsKey('c'),
              isTrue,
              reason: 'fell back to the structural form: $chord',
            );
          }
        }
      }
    });

    test('but the structural fallback decodes when it IS present', () {
      // Hand-built, since the encoder will not produce one today.
      final chart = chartFromJson({
        'v': 1,
        'sections': [
          {
            'bars': [
              {
                'chords': [
                  {
                    'spec': {
                      'root': {'step': 'e', 'alter': -1, 'octave': 4},
                      'triad': 'minor',
                      'seventh': 'minor',
                      'ext': 9,
                      'alt': ['flatFive'],
                      'add': [11],
                      'omit': [5],
                      'bass': {'step': 'g', 'octave': 3},
                    },
                    'beats': 2,
                  },
                ],
              },
            ],
          },
        ],
      })!;
      final spec = chart.sections.single.bars.single.chords.single.chord;
      expect(spec.root.step, Step.e);
      expect(spec.root.alter, -1);
      expect(spec.triad, ChordTriad.minor);
      expect(spec.seventh, ChordSeventh.minor);
      expect(spec.extension, 9);
      expect(spec.added, {11});
      expect(spec.omitted, {5});
      expect(spec.bass, isNotNull);
    });
  });

  group('unknown content is preserved, not deleted', () {
    // The rule that stops an older build silently stripping a newer file's form.
    Map<String, dynamic> withUnknowns() => {
          'v': 99,
          'tempo': 100,
          'meter': {'beats': 4, 'unit': 4},
          'futureChartField': {'anything': 3},
          'sections': [
            {
              'label': 'A',
              'futureSectionToken': 'coda-in-brackets',
              'bars': [
                {
                  'chords': [
                    {'c': 'C', 'futureChordField': 'microtonal'},
                  ],
                  'futureBarToken': 'D.S.S. al Coda 2',
                },
              ],
            },
          ],
        };

    test('an unknown key at every level survives a decode + encode', () {
      final chart = chartFromJson(withUnknowns())!;
      final out = chartToJson(chart);

      expect(out['futureChartField'], {'anything': 3});
      final section = (out['sections'] as List).single as Map;
      expect(section['futureSectionToken'], 'coda-in-brackets');
      final bar = (section['bars'] as List).single as Map;
      expect(bar['futureBarToken'], 'D.S.S. al Coda 2');
      final chord = (bar['chords'] as List).single as Map;
      expect(chord['futureChordField'], 'microtonal');
    });

    test(
        'and it survives TWO round trips — the second save is the dangerous one',
        () {
      // One round trip can pass by accident if `extra` is merely carried in
      // memory. This is the scenario that actually loses data: open, save, open,
      // save.
      final once = chartFromJson(withUnknowns())!;
      final twice = chartFromJsonString(chartToJsonString(once))!;
      final out = chartToJson(twice);
      expect(out['futureChartField'], isNotNull);
      expect(
        ((out['sections'] as List).single as Map)['futureSectionToken'],
        'coda-in-brackets',
      );
    });

    test('a key this build DOES own is not duplicated into extra', () {
      final chart = chartFromJson({
        'v': 1,
        'tempo': 90,
        'meter': {'beats': 3, 'unit': 4},
        'sections': const [],
      })!;
      expect(chart.extra, isNull, reason: 'nothing unrecognised was present');
      expect(chartToJson(chart)['tempo'], 90);
    });
  });

  group('a broken or hostile file does not take the app with it', () {
    test('nonsense reads as "not a chart" rather than throwing', () {
      expect(chartFromJsonString('not json at all'), isNull);
      expect(chartFromJson(42), isNull);
      expect(chartFromJson(null), isNull);
    });

    test('a chord symbol this build cannot read costs one chord, not the file',
        () {
      final chart = chartFromJson({
        'sections': [
          {
            'bars': [
              {
                'chords': [
                  {'c': 'C'},
                  {'c': '???unreadable???'},
                ],
              },
            ],
          },
        ],
      })!;
      final chords = chart.sections.single.bars.single.chords;
      expect(chords, hasLength(1), reason: 'the bar and the chart survived');
      expect(chords.single.chord.text, 'C');
    });

    test('a garbage meter falls back rather than refusing the chart', () {
      final chart = chartFromJson({
        'meter': {'beats': 0, 'unit': -4},
        'sections': const [],
      })!;
      expect(chart.meter.beats, 4);
      expect(chart.meter.beatUnit, 4);
    });

    test('a repeat count of 0 plays once instead of vanishing', () {
      final chart = chartFromJson({
        'sections': [
          {
            'repeat': 0,
            'bars': [
              {
                'chords': [
                  {'c': 'C'},
                ],
              },
            ],
          },
        ],
      })!;
      expect(chart.sections.single.passes, 1);
      expect(chart.totalBars, 1);
    });
  });

  group('the document answers "what plays when" exactly once', () {
    test('barsInPlayOrder expands repeats', () {
      final chart = Chart(
        sections: [
          ChartSection(
            label: 'A',
            repeatCount: 3,
            bars: [
              ChartBar(chords: [_c('C')]),
            ],
          ),
          ChartSection(
            label: 'B',
            bars: [
              ChartBar(chords: [_c('G')]),
            ],
          ),
        ],
      );
      expect(chart.totalBars, 4);
      expect(
        chart.barsInPlayOrder.map((b) => b.chords.single.chord.text),
        ['C', 'C', 'C', 'G'],
      );
    });

    test('the tonic comes from the fifths, and cannot disagree with them', () {
      expect(const Chart().tonicPitchClass, 0);
      expect(const Chart(keyFifths: 1).tonicPitchClass, 7, reason: 'G');
      expect(const Chart(keyFifths: -1).tonicPitchClass, 5, reason: 'F');
      expect(const Chart(keyFifths: 2).tonicPitchClass, 2, reason: 'D');
      expect(
        const Chart(minor: true).tonicPitchClass,
        9,
        reason: '0 fifths minor is A minor',
      );
      expect(
        const Chart(keyFifths: -3, minor: true).tonicPitchClass,
        0,
        reason: 'three flats minor is C minor',
      );
    });

    test('chords in a bar are readable in beat order however they were stored',
        () {
      final bar = ChartBar(chords: [_c('G', beat: 2), _c('C')]);
      expect(bar.chordsInOrder.map((c) => c.chord.text), ['C', 'G']);
      expect(
        bar.chords.map((c) => c.chord.text),
        ['G', 'C'],
        reason: 'the stored order is left as the file had it',
      );
    });
  });
}
