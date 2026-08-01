import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_score_bridge.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chart ↔ score bridge.
///
/// The two vocabularies are not the same size — `ChordSpec` is compositional,
/// `ChordSymbolKind` is a closed list of 15 — so the assertions that matter are
/// about the LOSS REPORT. Picking the nearest kind quietly is the failure this
/// whole file exists to prevent.
Chart chart(String text) => parseChartText(text).chart;

List<String> chartSymbols(Chart c) => [
      for (final bar in c.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

void main() {
  group('chart → score', () {
    test('every bar becomes a measure, and every chord a symbol', () {
      final result = chartToScore(chart('| C | Am | F | G7 |'));
      expect(result.value.measures, hasLength(4));
      expect(result.value.chordSymbols, hasLength(4));
      expect(result.isExact, isTrue);
      expect(
        result.value.chordSymbols.map((s) => s.text),
        ['C', 'Am', 'F', 'G7'],
      );
    });

    test('every symbol is anchored to a note that exists', () {
      // The anchor is synthesised here; a symbol pointing at nothing makes
      // `_layoutAnnotations` THROW rather than skip.
      final result = chartToScore(chart('| C | Dm7 G7 | % | Cmaj7 |'));
      final ids = result.value.measures
          .expand((m) => m.elements.whereType<NoteElement>())
          .map((n) => n.id)
          .toSet();
      expect(result.value.chordSymbols, isNotEmpty);
      for (final symbol in result.value.chordSymbols) {
        expect(ids, contains(symbol.elementId), reason: symbol.text);
      }
    });

    test('a held bar keeps its place with a rest', () {
      // Bar 17 must mean the same thing on both sides of the bridge.
      final result = chartToScore(chart('| C | % | % | G |'));
      expect(result.value.measures, hasLength(4));
      expect(result.value.measures[1].elements.single, isA<RestElement>());
      expect(result.value.chordSymbols, hasLength(2));
    });

    test('a split bar produces one note per chord', () {
      final result = chartToScore(chart('| Dm7 G7 |'));
      final notes =
          result.value.measures.single.elements.whereType<NoteElement>();
      expect(notes, hasLength(2));
      // Two chords in 4/4 are half notes each.
      expect(notes.first.duration.toFraction(), Fraction(1, 2));
    });

    test('the TEMPO travels with it', () {
      // Without this a round trip silently reset to the default 120, which a
      // play-along exposes at once: the band plays at the wrong speed and the
      // melody with it.
      final result = chartToScore(chart('tempo: 76\n| C |'));
      expect(result.value.tempo?.quarterBpm, 76);
      expect(chartFromScore(result.value).value.tempoBpm, 76);
    });

    test('a score with no tempo mark falls back to the chart default', () {
      const bare = Score(
        clef: Clef.treble,
        measures: [
          Measure([RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );
      expect(chartFromScore(bare).value.tempoBpm, const Chart().tempoBpm);
    });

    test('the key, meter and title travel with it', () {
      final result = chartToScore(
        chart('title: Blues\ncomposer: Nobody\nkey: Bb\nmeter: 3/4\n| Bb |'),
      );
      expect(result.value.keySignature.fifths, -2);
      expect(result.value.timeSignature, const TimeSignature(3, 4));
      expect(result.value.metadata.title, 'Blues');
      expect(result.value.metadata.composer, 'Nobody');
    });

    test('a slash bass survives', () {
      final result = chartToScore(chart('| C/G |'));
      expect(result.value.chordSymbols.single.bass?.step, Step.g);
    });
  });

  group('the loss report', () {
    test('an exact chord reports nothing', () {
      for (final symbol in [
        'C', 'Cm', 'Cdim', 'Caug', 'C7', 'Cmaj7', 'Cm7', //
        'Cm7b5', 'Cdim7', 'CmMaj7', 'C6', 'Cm6', 'C9', 'Csus4', 'Csus2',
      ]) {
        final result = chartToScore(chart('| $symbol |'));
        expect(result.isExact, isTrue, reason: '$symbol should be exact');
      }
    });

    test('an unrepresentable extension is reported, with what was kept', () {
      final result = chartToScore(chart('| C13#11 |'));
      expect(result.isExact, isFalse);
      final loss = result.losses.single;
      expect(loss.barNumber, 1);
      expect(loss.symbol, 'C13#11');
      expect(loss.detail, contains('13th'));
      expect(loss.detail, contains('♯11'));
      // The report says what a musician will actually see on the page.
      expect(loss.keptAs, 'C7');
    });

    test('the chord is still WRITTEN, not dropped', () {
      // A simplified chord is better than a missing one; the report is what
      // makes that honest rather than silent.
      final result = chartToScore(chart('| C13#11 | Am |'));
      expect(result.value.chordSymbols, hasLength(2));
      expect(
        result.value.chordSymbols.first.quality,
        ChordSymbolKind.dominantSeventh,
      );
    });

    test('a power chord reports its missing third', () {
      final result = chartToScore(chart('| C5 |'));
      expect(result.losses.single.detail, contains('third'));
      expect(result.value.chordSymbols.single.quality, ChordSymbolKind.major);
    });

    test('an added or omitted tone is reported', () {
      expect(chartToScore(chart('| Cadd9 |')).isExact, isFalse);
      expect(chartToScore(chart('| Cno3 |')).isExact, isFalse);
    });

    test('the report carries the right bar number', () {
      final result = chartToScore(chart('| C | Am | Bb7alt | F |'));
      expect(result.losses.single.barNumber, 3);
    });

    test('the summary counts rather than lists', () {
      // Forty altered chords must not produce a forty-line dialog.
      final result = chartToScore(chart('| C7b9 | F7#9 | G13 |'));
      expect(result.summary, '3 chords simplified.');
      expect(chartToScore(chart('| C |')).summary, contains('Every chord'));
      expect(chartToScore(chart('| C7b9 |')).summary, '1 chord simplified.');
    });

    test('half-diminished maps exactly — the closed list IS richer here', () {
      // A diminished triad with a minor seventh has its own kind, which a naive
      // triad×seventh product would miss.
      final result = chartToScore(chart('| Cm7b5 |'));
      expect(result.isExact, isTrue);
      expect(
        result.value.chordSymbols.single.quality,
        ChordSymbolKind.halfDiminishedSeventh,
      );
    });
  });

  group('score → chart', () {
    test('a score with chord symbols imports with the right chord per bar', () {
      final source = chart('key: F\n| F | Bb | C7 | F |');
      final imported = chartFromScore(chartToScore(source).value);
      expect(chartSymbols(imported.value), ['F', 'Bb', 'C7', 'F']);
      expect(imported.value.keyFifths, -1);
    });

    test('a measure with no symbol becomes a HELD bar', () {
      // That is what an unmarked bar means on a lead sheet.
      final imported =
          chartFromScore(chartToScore(chart('| C | % | G |')).value);
      expect(imported.value.totalBars, 3);
      expect(imported.value.barsInPlayOrder[1].chords, isEmpty);
    });

    test('a chord lands on the beat its note sounds on, not its index', () {
      // The moment a bar holds unequal values, index-based placement is wrong.
      final source = chart('| Dm7 G7 |');
      final imported = chartFromScore(chartToScore(source).value);
      final beats = imported.value.barsInPlayOrder.single.chordsInOrder
          .map((c) => c.beat);
      expect(beats, [0, 2]);
    });

    test('score → chart is lossless, because the richer type absorbs it', () {
      final imported = chartFromScore(chartToScore(chart('| Cm7b5 |')).value);
      expect(imported.isExact, isTrue);
    });

    test('the title and composer come across', () {
      final source = chart('title: Tune\ncomposer: Nobody\n| C |');
      final imported = chartFromScore(chartToScore(source).value);
      expect(imported.value.title, 'Tune');
      expect(imported.value.composer, 'Nobody');
    });

    test('an explicit title wins over the score metadata', () {
      final source = chart('title: Old\n| C |');
      final imported = chartFromScore(chartToScore(source).value, title: 'New');
      expect(imported.value.title, 'New');
    });
  });

  group('round trip', () {
    test('everything representable survives a chart → score → chart', () {
      const source = 'key: Eb\nmeter: 4/4\n'
          '| Eb | Cm | Fm7 | Bb7 |\n| Eb | Ab | Eb | Bb7 |';
      final before = chart(source);
      final round = chartFromScore(chartToScore(before).value).value;

      expect(chartSymbols(round), chartSymbols(before));
      expect(round.keyFifths, before.keyFifths);
      expect(round.meter, before.meter);
      expect(round.totalBars, before.totalBars);
    });

    test('an unrepresentable chord comes back SIMPLIFIED, and was reported',
        () {
      // The round trip is not lossless and must not pretend to be — but it
      // told us exactly which chord and what it became.
      final before = chart('| C13#11 |');
      final out = chartToScore(before);
      final round = chartFromScore(out.value).value;

      expect(chartSymbols(round), ['C7']);
      expect(out.losses.single.keptAs, 'C7');
    });

    test('every exactly-representable quality round-trips', () {
      for (final symbol in [
        'C', 'Cm', 'Cdim', 'Caug', 'C7', 'Cmaj7', 'Cm7', //
        'Cm7b5', 'Cdim7', 'C6', 'Cm6', 'C9', 'Csus4', 'Csus2',
      ]) {
        final round = chartFromScore(chartToScore(chart('| $symbol |')).value);
        expect(chartSymbols(round.value), [symbol], reason: symbol);
      }
    });
  });

  group('degenerate input', () {
    test('an empty chart makes an empty score', () {
      final result = chartToScore(const Chart());
      expect(result.value.measures, isEmpty);
      expect(result.isExact, isTrue);
    });

    test('a score with no symbols makes a chart of held bars', () {
      const score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch(Step.c)],
              duration: NoteDuration(DurationBase.whole),
              id: 'n0',
            ),
          ]),
        ],
      );
      final imported = chartFromScore(score);
      expect(imported.value.totalBars, 1);
      expect(imported.value.barsInPlayOrder.single.chords, isEmpty);
    });

    test('a chord parser fallback still bridges rather than throwing', () {
      final result = chartToScore(parseChartText('| wat |').chart);
      expect(result.value.chordSymbols, hasLength(1));
    });
  });
}
