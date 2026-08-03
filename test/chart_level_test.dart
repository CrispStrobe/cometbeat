import 'package:comet_beat/core/harmony/chart_level.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart';
import 'package:comet_beat/core/harmony/chart_share.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;
import 'package:flutter_test/flutter_test.dart';

/// The beginner↔expert dial (BB-U6).
///
/// The card names ONE invariant and everything else is detail: the dial gates
/// the SURFACE and never the model, the codec or playback. So the first group
/// is that invariant, asserted against a chart that uses every awkward thing
/// at once — altered dominants, a repeat, and a 5/4 bar.

/// A chart that a beginner could not WRITE, to prove they can still play it.
const _hardChart = 'title: Hard\n'
    'key: C\n'
    'meter: 5/4\n'
    'tempo: 132\n'
    '[A]\n'
    '| C7b9 | F#m7b5 | Bb13 | Cmaj7#11 |\n'
    '[B]\n'
    '| Dm7 | G7alt | Cmaj7 | % |';

void main() {
  group('the invariant: the dial gates the SURFACE, never the music', () {
    test('the same chart loads identically at every level', () {
      // The level is not an argument to the parser at all, which is the
      // structural reason this holds — asserted anyway, because the card's
      // whole risk is someone later "simplifying" by passing it in.
      final chart = parseChartText(_hardChart).chart;
      expect(chart.totalBars, 8);
      expect(chart.meter.beats, 5);
      expect(
        [
          for (final bar in chart.barsInPlayOrder)
            for (final c in bar.chordsInOrder) c.chord.text,
        ],
        ['C7b9', 'F#m7b5', 'Bb13', 'Cmaj7#11', 'Dm7', 'G7alt', 'Cmaj7'],
      );
    });

    test('the hard chart plays in FULL — nothing is dropped or quietened', () {
      // ⚠️ Honest scope: `ChartLevel` is not a parameter of `parseChartText`,
      // `resolveChartPlayback` or the codec, and that — not this test — is
      // what actually enforces the invariant. A loop calling the same function
      // once per level would look like proof and assert nothing.
      //
      // What IS worth pinning is that the awkward chart plays completely: if
      // anyone ever does thread a level into playback, the altered chords are
      // where it would show, and this says what they must keep sounding.
      final chart = parseChartText(_hardChart).chart;
      final playback = resolveChartPlayback(chart);

      expect(playback.bars, hasLength(8));
      expect(playback.comp, hasLength(8), reason: 'every bar sounds');
      expect(playback.bass, isNotEmpty);
      for (final (midis, ms) in playback.comp) {
        expect(midis, isNotEmpty, reason: 'a silent bar means a dropped chord');
        expect(ms, greaterThan(0));
      }
      // 8 bars x 5 beats at 132bpm. Asserted against the EXACT clock, not
      // against `beatMs * 40`.
      //
      // ⚠️ It used to say `beatMs * 40` = 18200, which encoded the DRIFT as the
      // expectation: the integer 455ms beat is 0.455ms fast, so forty of them
      // overshoot the true 18181.8ms by 18ms. BB-Q4's error-diffusion fix made
      // this test fail, correctly. A test written against a buggy
      // implementation defends the bug.
      expect(playback.beatMs, (60000 / 132).round(), reason: 'the click');
      expect(playback.totalMs, (8 * 5 * 60000 / 132).round());
      // The ♭9 really is in the voicing — the altered note is not smoothed
      // away by the voice-leading, which would be a silent quality loss.
      final firstBar = playback.comp.first.$1.map((m) => m % 12).toSet();
      expect(firstBar, contains(1), reason: 'C7b9 must sound its D♭');
    });

    test('it survives the codec at every level', () {
      final chart = parseChartText(_hardChart).chart;
      final reopened = decodeChartToken(encodeChartToken(chart))!;
      expect(
        [
          for (final bar in reopened.barsInPlayOrder)
            for (final c in bar.chordsInOrder) c.chord.text,
        ],
        [
          for (final bar in chart.barsInPlayOrder)
            for (final c in bar.chordsInOrder) c.chord.text,
        ],
      );
      expect(reopened.meter, chart.meter);
    });

    test('a beginner PRINTS an expert chord correctly, just plainly', () {
      // Printing must stay truthful — only the CONVENTION changes. A chord a
      // beginner cannot type still reads as the chord it is.
      const altered = ChordSpec(
        root: Pitch(Step.f, alter: 1),
        triad: ChordTriad.minor,
        seventh: ChordSeventh.minor,
        alterations: {ChordAlteration.flatFive},
      );
      expect(
        altered.format(style: ChartLevel.beginner.symbolStyle),
        'F#m7b5',
      );
      // Expert prints the engraved spelling — `ø` absorbing the `m`, the `7`
      // and the `♭5`. This IS the dial's "print convention" axis: the same
      // chord, named the way each reader expects.
      expect(
        altered.format(style: ChartLevel.expert.symbolStyle),
        'F♯ø7',
      );
    });
  });

  group('what each level offers', () {
    test('the vocabulary widens, it never narrows', () {
      // Each level must be a SUPERSET of the one below, or moving the dial up
      // would take something away.
      expect(
        ChartLevel.learner.qualities.containsAll(ChartLevel.beginner.qualities),
        isTrue,
      );
      for (final label in ChartLevel.learner.qualities) {
        expect(ChartLevel.expert.offersQuality(label), isTrue);
      }
    });

    test('a beginner is not offered the altered vocabulary', () {
      expect(ChartLevel.beginner.offersQuality('m7b5'), isFalse);
      expect(ChartLevel.beginner.offersExtras, isFalse);
      expect(ChartLevel.beginner.showsRomanNumerals, isFalse);
      expect(ChartLevel.beginner.editsForm, isFalse);
    });

    test('an expert is offered everything', () {
      for (final label in ['m7b5', 'dim7', '7sus4', 'aug', 'anything at all']) {
        expect(ChartLevel.expert.offersQuality(label), isTrue);
      }
      expect(ChartLevel.expert.offersExtras, isTrue);
      expect(ChartLevel.expert.editsForm, isTrue);
    });
  });

  group('narrowing the style list', () {
    const all = ['straight', 'swing', 'ballad', 'bossa', 'waltz', 'rock'];

    test('a beginner sees a short list, an expert sees all of them', () {
      expect(ChartLevel.beginner.stylesFrom(all), hasLength(2));
      expect(ChartLevel.learner.stylesFrom(all), hasLength(4));
      expect(ChartLevel.expert.stylesFrom(all), all);
    });

    test("the chart's CURRENT style is kept even when it is off the list", () {
      // Otherwise opening a bossa chart on a beginner device would silently
      // re-style it — gating the music, which is the one forbidden thing.
      final shown = ChartLevel.beginner.stylesFrom(all, keep: 'bossa');
      expect(shown, contains('bossa'));
      expect(shown, hasLength(3));
    });

    test('keeping a style that does not exist adds nothing', () {
      expect(
        ChartLevel.beginner.stylesFrom(all, keep: 'nonsense'),
        hasLength(2),
      );
    });

    test('intensity never exceeds what the style actually has', () {
      expect(ChartLevel.expert.intensityCount(2), 2);
      expect(ChartLevel.learner.intensityCount(2), 2);
      expect(ChartLevel.learner.intensityCount(4), 3);
      expect(ChartLevel.beginner.intensityCount(4), 1);
      // A style with one level gives one, at every dial setting.
      expect(ChartLevel.beginner.intensityCount(1), 1);
      expect(ChartLevel.expert.intensityCount(1), 1);
    });
  });

  group('persistence', () {
    test('a level round-trips by NAME', () {
      for (final level in ChartLevel.values) {
        expect(ChartLevel.fromName(level.name), level);
      }
    });

    test('an unknown or missing name falls back to learner', () {
      // Not to beginner: an install whose setting is unreadable should land on
      // the useful middle, not on the most restricted surface.
      expect(ChartLevel.fromName(null), ChartLevel.learner);
      expect(ChartLevel.fromName(''), ChartLevel.learner);
      expect(ChartLevel.fromName('wizard'), ChartLevel.learner);
      // …and specifically NOT an index, which reordering would reinterpret.
      expect(ChartLevel.fromName('0'), ChartLevel.learner);
    });
  });
}
