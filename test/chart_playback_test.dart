import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// Resolving a `Chart` to sound.
///
/// The assertions that matter here are about TIME, not about notes: the screen
/// highlights the bar under the playhead, so a timeline that drifts from the
/// audio is the failure a user actually sees. The chord content is checked only
/// where the projection makes a decision of its own (holding across an empty
/// bar, the slash bass).
ChordSpec chord(String s) {
  final cell = parseChartCell(s);
  return (cell as ChordCell).chord;
}

Chart chartOf(List<String?> barSymbols, {int tempoBpm = 120}) => Chart(
      tempoBpm: tempoBpm,
      sections: [
        ChartSection(
          bars: [
            for (final s in barSymbols)
              ChartBar(
                chords:
                    s == null ? const [] : [ChartBeatChord(chord: chord(s))],
              ),
          ],
        ),
      ],
    );

void main() {
  group('timeline', () {
    test('bars are contiguous — no gaps, no overlaps', () {
      final p = resolveChartPlayback(chartOf(['C', 'F', 'G', 'C']));
      expect(p.bars, hasLength(4));
      for (var i = 1; i < p.bars.length; i++) {
        expect(
          p.bars[i].startMs,
          p.bars[i - 1].endMs,
          reason: 'bar $i does not start where bar ${i - 1} ends',
        );
      }
      expect(p.bars.last.endMs, p.totalMs);
    });

    test('a 4/4 bar at 120bpm is two seconds', () {
      final p = resolveChartPlayback(chartOf(['C']));
      expect(p.beatMs, 500);
      expect(p.bars.single.durationMs, 2000);
    });

    test('meter is read in quarters, so 6/8 is three beats not six', () {
      // Tempo is quarter-note BPM everywhere in the app. Reading 6/8 as six
      // beats would play it at half speed.
      expect(barBeats(const TimeSignature(4, 4)), 4);
      expect(barBeats(const TimeSignature(6, 8)), 3);
      expect(barBeats(const TimeSignature(2, 2)), 4);
    });

    test('a per-bar meter change changes only that bar', () {
      final c = Chart(
        sections: [
          ChartSection(
            bars: [
              ChartBar(chords: [ChartBeatChord(chord: chord('C'))]),
              ChartBar(
                chords: [ChartBeatChord(chord: chord('F'))],
                meterChange: const TimeSignature(2, 4),
              ),
              ChartBar(chords: [ChartBeatChord(chord: chord('G'))]),
            ],
          ),
        ],
      );
      final p = resolveChartPlayback(c);
      expect(p.bars[0].durationMs, 2000);
      expect(p.bars[1].durationMs, 1000);
      expect(p.bars[2].durationMs, 2000);
    });

    test('barAt finds the bar under the playhead, and nothing past the end',
        () {
      final p = resolveChartPlayback(chartOf(['C', 'F']));
      expect(p.barAt(0)!.index, 0);
      expect(p.barAt(1999)!.index, 0);
      expect(p.barAt(2000)!.index, 1);
      expect(p.barAt(p.totalMs), isNull);
    });

    test('repeats are expanded, and each bar knows which pass it is', () {
      final c = Chart(
        sections: [
          ChartSection(
            label: 'A',
            repeatCount: 2,
            bars: [
              ChartBar(chords: [ChartBeatChord(chord: chord('C'))]),
              ChartBar(chords: [ChartBeatChord(chord: chord('G'))]),
            ],
          ),
        ],
      );
      final p = resolveChartPlayback(c);
      expect(p.bars, hasLength(4));
      expect(p.bars.map((b) => b.pass), [0, 0, 1, 1]);
      expect(p.bars.every((b) => b.sectionIndex == 0), isTrue);
    });

    test('the section index tracks across sections', () {
      final c = Chart(
        sections: [
          ChartSection(
            label: 'A',
            bars: [
              ChartBar(chords: [ChartBeatChord(chord: chord('C'))]),
            ],
          ),
          ChartSection(
            label: 'B',
            bars: [
              ChartBar(chords: [ChartBeatChord(chord: chord('F'))]),
            ],
          ),
        ],
      );
      final p = resolveChartPlayback(c);
      expect(p.bars.map((b) => b.sectionIndex), [0, 1]);
    });
  });

  group('sounding content', () {
    test('an empty bar holds the previous chord rather than going silent', () {
      final p = resolveChartPlayback(chartOf(['C', null, null, null]));
      expect(p.comp, hasLength(4), reason: 'every bar should sound');
      // All four are the same chord, re-struck once per bar.
      final pcs = p.comp.map((e) => e.$1.map((m) => m % 12).toSet()).toList();
      expect(
        pcs.every((s) => s.containsAll({0, 4, 7})),
        isTrue,
        reason: 'held bars must keep sounding C major',
      );
    });

    test('a chart starting with an empty bar simply has nothing to hold', () {
      final p = resolveChartPlayback(chartOf([null, 'C']));
      // One sounding slot, but still two bars on the timeline.
      expect(p.comp, hasLength(1));
      expect(p.bars, hasLength(2));
    });

    test('two chords in a bar split it', () {
      final c = Chart(
        sections: [
          ChartSection(
            bars: [
              ChartBar(
                chords: [
                  ChartBeatChord(chord: chord('C')),
                  ChartBeatChord(chord: chord('G'), beat: 2),
                ],
              ),
            ],
          ),
        ],
      );
      final p = resolveChartPlayback(c);
      expect(p.comp, hasLength(2));
      expect(p.comp[0].$2, 1000);
      expect(p.comp[1].$2, 1000);
    });

    test('a slash bass sounds the written bass note, not the root', () {
      final p = resolveChartPlayback(chartOf(['C/G']));
      expect(p.bass.single.$1.single % 12, 7, reason: 'G, not C');
    });

    test('the bass follows the root when there is no slash', () {
      final p = resolveChartPlayback(chartOf(['F']));
      expect(p.bass.single.$1.single % 12, 5);
    });

    test('comp and bass cover the same total time', () {
      final p = resolveChartPlayback(chartOf(['C', 'Am', 'Dm7', 'G7']));
      final compMs = p.comp.fold<int>(0, (a, e) => a + e.$2);
      final bassMs = p.bass.fold<int>(0, (a, e) => a + e.$2);
      expect(compMs, bassMs);
      expect(compMs, p.totalMs);
    });

    test('chords outside the groove engine vocabulary still play', () {
      // The whole reason this path exists rather than chart_to_groove: none of
      // these is a diatonic triad of the key.
      final p = resolveChartPlayback(chartOf(['F#m7b5', 'Bb7', 'Ebmaj9']));
      expect(p.comp, hasLength(3));
      expect(p.comp.every((e) => e.$1.isNotEmpty), isTrue);
    });

    test('every sounding voicing is in MIDI range and ascending', () {
      final p = resolveChartPlayback(
        chartOf(['C', 'Am7', 'Dm7', 'G13', 'Cmaj7', 'Ab7#11']),
      );
      for (final (midis, _) in p.comp) {
        expect(midis.every((m) => m >= 0 && m <= 127), isTrue);
        for (var i = 1; i < midis.length; i++) {
          expect(midis[i], greaterThan(midis[i - 1]));
        }
      }
    });
  });

  group('degenerate input', () {
    test('an empty chart resolves to silence, not a crash', () {
      final p = resolveChartPlayback(const Chart());
      expect(p.isEmpty, isTrue);
      expect(p.totalMs, 0);
      expect(p.barAt(0), isNull);
    });

    test('a nonsense tempo cannot divide by zero', () {
      final p = resolveChartPlayback(chartOf(['C'], tempoBpm: 0));
      expect(p.beatMs, greaterThan(0));
      expect(p.totalMs, greaterThan(0));
    });
  });
}
