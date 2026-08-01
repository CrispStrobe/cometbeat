import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chart_transpose.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Interval;
import 'package:flutter_test/flutter_test.dart';

/// Transposition, on both axes.
///
/// The card's acceptance is precise and this asserts it directly: a B♭
/// instrument reading a chart that SOUNDS B♭ prints C; a capo-3 display on a
/// chart in E♭ prints C shapes; and transposing twice by inverse intervals
/// returns the original SPELLING, not merely the original pitch.
Chart chart(String text) => parseChartText(text).chart;

List<String> symbols(Chart c) => [
      for (final bar in c.barsInPlayOrder)
        for (final chord in bar.chordsInOrder) chord.chord.text,
    ];

void main() {
  group("the card's acceptance", () {
    test('a B♭ instrument reading a B♭ chart prints C', () {
      // The tune sounds in B♭; the trumpeter reads C.
      final source = chart('key: Bb\n| Bb | Eb | F7 | Bb |');
      final printed = displayChart(
        source,
        const ChartTransposition(instrument: TransposingInstrument.bFlat),
      );
      expect(symbols(printed), ['C', 'F', 'G7', 'C']);
      expect(printed.keyFifths, 0, reason: 'C major');
    });

    test('capo 3 on a chart in E♭ prints C shapes', () {
      final source = chart('key: Eb\n| Eb | Ab | Bb7 | Eb |');
      final printed = displayChart(source, const ChartTransposition(capo: 3));
      expect(symbols(printed), ['C', 'F', 'G7', 'C']);
      expect(printed.keyFifths, 0);
    });

    test('transposing by inverse intervals returns the original SPELLING', () {
      // Not merely the original pitch: A♭ must come back as A♭, never G♯.
      // Keys that stay INSIDE the circle both ways. A key that leaves it
      // cannot round-trip and must not: see the off-circle test below.
      for (final source in [
        chart('key: Ab\n| Ab | Db | Eb7 | Ab |'),
        chart('key: D\n| D | Bm | Em7 | A7 |'),
        chart('key: C\n| C | Am | Dm7 | G7 |'),
      ]) {
        for (final interval in [
          Interval.majorSecond,
          Interval.minorThird,
          Interval.perfectFifth,
          Interval.majorSixth,
        ]) {
          final round = transposeChart(
            transposeChart(source, interval),
            interval,
            descending: true,
          );
          expect(
            symbols(round),
            symbols(source),
            reason: '${source.keyFifths} fifths through $interval',
          );
          expect(round.keyFifths, source.keyFifths);
        }
      }
    });
  });

  group('the two axes are independent', () {
    test('a display transposition does NOT change what sounds', () {
      // The bug this whole file exists to prevent.
      final source = chart('key: C\n| C | Am | Dm7 | G7 |');
      const t = ChartTransposition(
        instrument: TransposingInstrument.bFlat,
        capo: 3,
      );
      expect(symbols(soundingChart(source, t)), symbols(source));
      expect(soundingChart(source, t).keyFifths, source.keyFifths);
      // …while the print really did move.
      expect(symbols(displayChart(source, t)), isNot(symbols(source)));
    });

    test('a sounding transposition changes BOTH', () {
      final source = chart('key: C\n| C | G7 |');
      const t = ChartTransposition(soundingSemitones: 2);
      expect(symbols(soundingChart(source, t)), ['D', 'A7']);
      expect(symbols(displayChart(source, t)), ['D', 'A7']);
    });

    test('sounding and reading compose', () {
      // A B♭ player on a tune taken up a step reads both moves.
      final source = chart('key: C\n| C |');
      final printed = displayChart(
        source,
        const ChartTransposition(
          soundingSemitones: 2,
          instrument: TransposingInstrument.bFlat,
        ),
      );
      expect(symbols(printed), ['E'], reason: 'C +2 = D, D +M2 = E');
    });

    test('identity is reported and is a no-op', () {
      const t = ChartTransposition();
      expect(t.isIdentity, isTrue);
      expect(t.soundsUnchanged, isTrue);
      final source = chart('| C | G |');
      expect(identical(soundingChart(source, t), source), isTrue);
      expect(identical(displayChart(source, t), source), isTrue);
    });

    test('soundsUnchanged is true for display-only settings', () {
      // What lets a caller reuse already-rendered audio.
      const display = ChartTransposition(
        instrument: TransposingInstrument.eFlat,
        capo: 5,
      );
      expect(display.soundsUnchanged, isTrue);
      expect(display.isIdentity, isFalse);
      expect(
        const ChartTransposition(soundingSemitones: 1).soundsUnchanged,
        isFalse,
      );
    });
  });

  group('the instruments', () {
    test('each reads the right interval above concert', () {
      expect(readingInterval(TransposingInstrument.concert), isNull);
      expect(
        readingInterval(TransposingInstrument.bFlat),
        Interval.majorSecond,
      );
      expect(readingInterval(TransposingInstrument.eFlat), Interval.majorSixth);
      expect(readingInterval(TransposingInstrument.f), Interval.perfectFifth);
    });

    test('an E♭ alto reading a concert C tune prints A', () {
      final printed = displayChart(
        chart('key: C\n| C | F | G7 |'),
        const ChartTransposition(instrument: TransposingInstrument.eFlat),
      );
      expect(symbols(printed), ['A', 'D', 'E7']);
    });

    test('an F horn reading a concert C tune prints G', () {
      final printed = displayChart(
        chart('key: C\n| C | F | G7 |'),
        const ChartTransposition(instrument: TransposingInstrument.f),
      );
      expect(symbols(printed), ['G', 'C', 'D7']);
    });
  });

  group('spelling', () {
    test('up a major third from Ab is C, not B#', () {
      // The reason this is interval-based and not semitone-based: a semitone
      // count cannot tell those apart.
      final up = transposeChart(chart('key: Ab\n| Ab |'), Interval.majorThird);
      expect(symbols(up), ['C']);
    });

    test('the key signature follows the chords', () {
      expect(transposeChartBySemitones(chart('key: C\n| C |'), 2).keyFifths, 2);
      expect(
        transposeChartBySemitones(chart('key: C\n| C |'), -2).keyFifths,
        -2,
      );
      expect(transposeChartBySemitones(chart('key: F\n| F |'), 7).keyFifths, 0);
    });

    test('a minor key stays minor and keeps its own signature', () {
      final up = transposeChartBySemitones(chart('key: Am\n| Am | E7 |'), 3);
      expect(up.minor, isTrue);
      expect(symbols(up), ['Cm', 'G7']);
      expect(up.keyFifths, -3, reason: 'C minor');
    });

    test('a slash bass transposes with its chord', () {
      final up = transposeChartBySemitones(chart('key: C\n| C/G |'), 2);
      expect(symbols(up), ['D/A']);
    });

    test('extensions and alterations survive', () {
      final up = transposeChartBySemitones(
        chart('key: C\n| Cmaj9#11 | F#m7b5 | Bb13sus4 |'),
        2,
      );
      expect(symbols(up), ['Dmaj9#11', 'G#m7b5', 'C13sus4']);
    });
  });

  group('structure is preserved', () {
    test('sections, repeats, meter, tempo and split bars all survive', () {
      final source = chart(
        'title: Tune\ncomposer: Nobody\nmeter: 3/4\ntempo: 132\n'
        '[A] x2\n| C | Am |\n[B]\n| Dm7 G7 | % |',
      );
      final up = transposeChartBySemitones(source, 4);

      expect(up.title, source.title);
      expect(up.composer, source.composer);
      expect(up.meter, source.meter);
      expect(up.tempoBpm, source.tempoBpm);
      expect(
        up.sections.map((s) => s.label),
        source.sections.map((s) => s.label),
      );
      expect(
        up.sections.map((s) => s.passes),
        source.sections.map((s) => s.passes),
      );
      expect(up.totalBars, source.totalBars);

      // The split bar keeps both chords AND their beats.
      final split = up.sections[1].bars.first.chordsInOrder;
      expect(split.map((c) => c.chord.text), ['F#m7', 'B7']);
      expect(split.map((c) => c.beat), [0, 1.5]);

      // The held bar stays held rather than gaining a chord.
      expect(up.sections[1].bars[1].chords, isEmpty);
    });

    test('the style id is not disturbed', () {
      final source = chart('| C |');
      final styled = Chart(sections: source.sections, styleId: 'bossa');
      expect(transposeChartBySemitones(styled, 5).styleId, 'bossa');
    });
  });

  group('edge cases', () {
    test('a whole octave is a no-op, not a respell', () {
      final source = chart('key: Ab\n| Ab | Db |');
      expect(symbols(transposeChartBySemitones(source, 12)), symbols(source));
      expect(transposeChartBySemitones(source, 12).keyFifths, -4);
    });

    test('an empty chart transposes to an empty chart', () {
      expect(transposeChartBySemitones(const Chart(), 3).isEmpty, isTrue);
    });

    test('a key with no signature is RESPELLED, not clamped', () {
      // F♯ major up a major second is G♯ major — eight sharps, which does not
      // exist. Clamping would land on an unrelated key; the right answer is the
      // enharmonic one, A♭ major, with every chord spelled in flats to match.
      final up =
          transposeChartBySemitones(chart('key: F#\n| F# | B | C#7 |'), 2);
      expect(up.keyFifths, -4, reason: 'A♭ major, not a clamped 7');
      expect(symbols(up), ['Ab', 'Db', 'Eb7']);
    });

    test('the respelled key and its chords agree on accidentals', () {
      // The failure this prevents is a chart whose key says flats while its
      // chords say sharps.
      final up = transposeChartBySemitones(chart('key: F#\n| F# | B |'), 2);
      final sharps = symbols(up).where((s) => s.contains('#')).length;
      final flats = symbols(up).where((s) => s.contains('b')).length;
      expect(up.keyFifths, lessThan(0));
      expect(flats, greaterThan(0));
      expect(sharps, 0);
    });

    test('every key transposes to a signature that exists', () {
      for (var fifths = -7; fifths <= 7; fifths++) {
        for (var semis = -11; semis <= 11; semis++) {
          final source = Chart(
            keyFifths: fifths,
            sections: chart('| C |').sections,
          );
          final out = transposeChartBySemitones(source, semis);
          expect(
            out.keyFifths,
            inInclusiveRange(-7, 7),
            reason: 'from $fifths by $semis',
          );
        }
      }
    });

    test('intervalForSemitones covers every step and wraps', () {
      for (var i = 0; i < 12; i++) {
        expect(intervalForSemitones(i).semitones % 12, i % 12, reason: '$i');
      }
      expect(intervalForSemitones(14).semitones % 12, 2);
      expect(intervalForSemitones(-1).semitones % 12, 11);
    });
  });
}
