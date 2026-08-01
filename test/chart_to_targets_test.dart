import 'package:comet_beat/core/audio/chord_progression.dart';
import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chart_to_targets.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grading a player against a real chart.
///
/// The assertion that matters most is UNSCORABILITY: `TargetChord.matches`
/// needs the detector's suffix exactly, so a target the detector cannot emit is
/// a bar the player can never score. Every projected target must therefore be
/// in the detector's vocabulary, and every narrowing must be reported.
void main() {
  group('the vocabulary contract', () {
    test('kScorableSuffixes agrees with the detector templates', () {
      // The set is duplicated deliberately so this file states its dependency;
      // this is the test that keeps the duplicate honest.
      expect(
        kScorableSuffixes,
        kChordTemplates.map((t) => t.suffix).toSet(),
      );
    });

    test('EVERY projected target is scorable, whatever the chart says', () {
      // A target outside the vocabulary is a bar nobody can hit.
      final chart = parseChartText(
        '| Cmaj9#11 | F#m7b5 | Bb13sus4 | Ebmaj7/G |\n'
        '| C5 | Dsus2 | Am6 | G7alt |\n'
        '| Cdim7 | Caug | CmMaj7 | Cadd9 |',
      ).chart;
      final result = targetsFromChart(chart);
      expect(result.value.chords, isNotEmpty);
      for (final target in result.value.chords) {
        expect(
          kScorableSuffixes,
          contains(target.suffix),
          reason: 'unscorable suffix "${target.suffix}"',
        );
      }
    });

    test('a scorable target really does match a detector candidate', () {
      // End to end: what the projection emits is what the detector can say.
      final result = targetsFromChart(parseChartText('| C | Am | G7 |').chart);
      for (final target in result.value.chords) {
        final candidate = ChordCandidate(
          rootPc: target.rootPc,
          suffix: target.suffix,
          score: 1,
        );
        expect(target.matches(candidate), isTrue);
      }
    });
  });

  group('placement', () {
    test('targets run consecutively across bars', () {
      final result = targetsFromChart(
        parseChartText('tempo: 120\n| C | Am | F | G |').chart,
      );
      expect(result.value.chords.map((c) => c.startBeat), [0, 4, 8, 12]);
      expect(result.value.chords.every((c) => c.beats == 4), isTrue);
      expect(result.value.totalBeats, 16);
    });

    test('a split bar splits its beats', () {
      final result = targetsFromChart(parseChartText('| Dm7 G7 |').chart);
      expect(result.value.chords.map((c) => c.startBeat), [0, 2]);
      expect(result.value.chords.map((c) => c.beats), [2, 2]);
    });

    test('a held bar produces no target but still takes its time', () {
      // The next chord must not slide earlier, or the whole exercise drifts.
      final result = targetsFromChart(parseChartText('| C | % | G |').chart);
      expect(result.value.chords.map((c) => c.startBeat), [0, 8]);
    });

    test('a meter change changes the spacing', () {
      final result = targetsFromChart(
        parseChartText('meter: 3/4\n| C | G |').chart,
      );
      expect(result.value.chords.map((c) => c.startBeat), [0, 3]);
    });

    test('the tempo comes from the chart', () {
      final result = targetsFromChart(parseChartText('tempo: 96\n| C |').chart);
      expect(result.value.bpm, 96);
      expect(result.value.beatMs, closeTo(625, 0.001));
    });

    test('the title names the exercise', () {
      expect(
        targetsFromChart(parseChartText('title: Blues\n| C |').chart)
            .value
            .name,
        'Blues',
      );
      expect(
        targetsFromChart(parseChartText('| C |').chart).value.name,
        'Chart',
      );
    });
  });

  group('the form is expanded, and non-tune bars carry no target', () {
    test('repeats produce repeated targets', () {
      final result = targetsFromChart(
        parseChartText('[A] x2\n| C | G |').chart,
      );
      expect(result.value.chords, hasLength(4));
      expect(result.value.chords.map((c) => c.rootPc), [0, 7, 0, 7]);
    });

    test('a count-in is not scored, and does not shift the first target', () {
      // Nobody should be graded on a bar that exists to set the tempo — and
      // the exercise must still start at beat 0.
      final bars = realizeForm(
        parseChartText('| C | G |').chart,
      );
      expect(bars.first.role, BarRole.countIn);
      final result = targetsFromRealizedBars(bars, name: 'x', bpm: 120);
      expect(result.value.chords, hasLength(2));
      expect(
        result.value.chords.first.startBeat,
        4,
        reason: 'the count-in bar still occupies its four beats',
      );
    });

    test('an ending bar carries no target either', () {
      final bars = realizeForm(
        parseChartText('| C | G |').chart,
        options: const FormOptions(countIn: false),
      );
      expect(bars.last.role, BarRole.ending);
      expect(
        targetsFromRealizedBars(bars, name: 'x', bpm: 120).value.chords,
        hasLength(2),
      );
    });
  });

  group('the loss report', () {
    test('a chord the detector knows reports nothing', () {
      for (final symbol in [
        'C',
        'Cm',
        'C7',
        'Cm7',
        'Cmaj7',
        'Csus4',
        'Cdim',
        'Caug',
      ]) {
        final result = targetsFromChart(parseChartText('| $symbol |').chart);
        expect(result.isExact, isTrue, reason: symbol);
      }
    });

    test('an extension is reported, and the target stays scorable', () {
      final result = targetsFromChart(parseChartText('| Cmaj9 |').chart);
      expect(result.isExact, isFalse);
      expect(result.losses.single.detail, contains('9th'));
      expect(result.value.chords.single.suffix, 'maj7');
    });

    test('a slash bass is reported — the detector hears the chord, not it', () {
      final result = targetsFromChart(parseChartText('| C/G |').chart);
      expect(result.losses.single.detail, contains('slash bass'));
      expect(result.value.chords.single.rootPc, 0, reason: 'still C');
    });

    test('sus2 is reported as heard-as-sus4', () {
      final result = targetsFromChart(parseChartText('| Csus2 |').chart);
      expect(result.losses.single.detail, contains('sus2'));
      expect(result.value.chords.single.suffix, 'sus4');
    });

    test('a minor triad with a flat five is DIM, and not over-reported', () {
      // The detector knows `dim`; the ♭5 is absorbed rather than listed, the
      // same way the score bridge absorbs it.
      final result = targetsFromChart(parseChartText('| Cmb5 |').chart);
      expect(result.value.chords.single.suffix, 'dim');
      expect(result.isExact, isTrue);
    });

    test('m7b5 keeps its root and reports only the seventh', () {
      final result = targetsFromChart(parseChartText('| Cm7b5 |').chart);
      expect(result.value.chords.single.suffix, 'dim');
      expect(result.losses.single.detail, contains('seventh'));
    });

    test('the report carries the bar number of the TUNE, not the timeline', () {
      final bars = realizeForm(
        parseChartText('| C | Am | Cmaj9 |').chart,
      );
      final result = targetsFromRealizedBars(bars, name: 'x', bpm: 120);
      expect(
        result.losses.single.barNumber,
        3,
        reason: 'the count-in must not shift the numbering',
      );
    });
  });

  group('the shipped scorer is untouched', () {
    test('a projected chart is the same SHAPE as a hand-written one', () {
      // The card's acceptance: a chart projects to the beat-list a hand-written
      // ChordChart would.
      final projected = targetsFromChart(
        parseChartText('tempo: 60\n| C | F | G7 | C |').chart,
      ).value;

      const handWritten = ChordChart(
        name: 'Cadence in C',
        bpm: 60,
        chords: [
          TargetChord(rootPc: 0, suffix: '', startBeat: 0, beats: 4),
          TargetChord(rootPc: 5, suffix: '', startBeat: 4, beats: 4),
          TargetChord(rootPc: 7, suffix: '7', startBeat: 8, beats: 4),
          TargetChord(rootPc: 0, suffix: '', startBeat: 12, beats: 4),
        ],
      );

      expect(projected.bpm, handWritten.bpm);
      expect(projected.totalBeats, handWritten.totalBeats);
      expect(
        projected.chords.map((c) => '${c.rootPc}${c.suffix}@${c.startBeat}'),
        handWritten.chords.map((c) => '${c.rootPc}${c.suffix}@${c.startBeat}'),
      );
    });

    test('the built-in charts still read as they always did', () {
      // Nothing here modified chord_progression.dart; this is the guard that
      // says so.
      expect(ChordCharts.cadenceInC.chords, isNotEmpty);
      expect(ChordCharts.cadenceInC.bpm, greaterThan(0));
    });
  });

  group('degenerate input', () {
    test('an empty chart projects to an empty exercise', () {
      final result = targetsFromChart(parseChartText('').chart);
      expect(result.value.chords, isEmpty);
      expect(result.isExact, isTrue);
    });

    test('a nonsense tempo cannot divide by zero', () {
      final result = targetsFromChart(parseChartText('tempo: 0\n| C |').chart);
      expect(result.value.bpm, greaterThan(0));
    });
  });
}
