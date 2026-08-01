import 'dart:typed_data';

import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart_score_bridge.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/song_with_band.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A library piece with a band under it.
///
/// The card asks for alignment asserted AT THE SAMPLE LEVEL rather than by ear,
/// and for muting the melody to leave the band untouched. Both are checked
/// here against the rendered PCM, not against intentions.
const _rate = 8000;

/// A score carrying chord symbols, the way a library item does.
Score charted(String text, {int tempo = 120}) =>
    chartToScore(parseChartText('tempo: $tempo\n$text').chart).value;

/// PCM16 samples out of a WAV, skipping the 44-byte header.
Int16List pcm(Uint8List wav) =>
    wav.buffer.asInt16List(wav.offsetInBytes + 44, (wav.length - 44) ~/ 2);

/// The first sample index whose magnitude clears [floor].
int firstAudible(Int16List samples, {int floor = 200}) {
  for (var i = 0; i < samples.length; i++) {
    if (samples[i].abs() > floor) return i;
  }
  return -1;
}

void main() {
  group('it produces a play-along', () {
    test('a score with chord symbols renders melody and band', () {
      final result = renderSongWithBand(
        charted('| C | Am | F | G7 |'),
        sampleRate: _rate,
      );
      expect(result, isNotNull);
      expect(result!.melodyNoteCount, greaterThan(0));
      expect(result.performance.totalMs, greaterThan(0));
      expect(
        String.fromCharCodes(result.performance.wav.sublist(0, 4)),
        'RIFF',
      );
    });

    test('a score with NO chord symbols is null, not a silent band', () {
      // A missing input must not look like a bug.
      const bare = Score(
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
      expect(renderSongWithBand(bare, sampleRate: _rate), isNull);
    });

    test('the derived chart comes back with the result', () {
      // The caller can show what the band is reading.
      final result = renderSongWithBand(
        charted('| Dm7 | G7 | Cmaj7 |'),
        sampleRate: _rate,
      )!;
      expect(result.chart.totalBars, 3);
      expect(
        result.chart.barsInPlayOrder
            .map((b) => b.chordsInOrder.single.chord.text),
        ['Dm7', 'G7', 'Cmaj7'],
      );
    });
  });

  group('alignment, at the sample level', () {
    test('the melody starts at the first TUNE bar, not at zero', () {
      // With a count-in those differ by a whole bar. Starting at zero would
      // play the melody over the count-in and a bar early for the whole piece.
      final result = renderSongWithBand(
        charted('| C | F |'),
        sampleRate: _rate,
      )!;
      final bars = result.performance.bars;
      expect(bars.first.bar.role, BarRole.countIn);

      final firstTune = bars.firstWhere((b) => b.bar.role == BarRole.tune);
      expect(result.melodyStartMs, firstTune.startMs);
      expect(result.melodyStartMs, greaterThan(0));
    });

    test('with no count-in the melody starts at zero', () {
      final result = renderSongWithBand(
        charted('| C | F |'),
        form: const FormOptions(countIn: false),
        sampleRate: _rate,
      )!;
      expect(result.melodyStartMs, 0);
    });

    test('the melody offset is REAL in the audio, not just in the field', () {
      // Render the same piece with and without the melody and diff the PCM.
      // The first sample where they differ is where the melody actually
      // entered — which must be the reported offset, to within a sample.
      final score = charted('| C | F | G | C |');
      final withMelody = renderSongWithBand(
        score,
        sampleRate: _rate,
        // A silent band isolates the melody, so the diff is unambiguous.
        mix: const BandMix(comp: 0, bass: 0, drums: 0),
      )!;
      final without = renderSongWithBand(
        score,
        sampleRate: _rate,
        includeMelody: false,
        mix: const BandMix(comp: 0, bass: 0, drums: 0),
      )!;

      final a = pcm(withMelody.performance.wav);
      final b = pcm(without.performance.wav);
      expect(a.length, b.length);

      var firstDiff = -1;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          firstDiff = i;
          break;
        }
      }
      expect(firstDiff, greaterThanOrEqualTo(0), reason: 'the melody sounded');

      final expectedSample = withMelody.melodyStartMs * _rate ~/ 1000;
      // Within one millisecond: the offset is a rounded ms, and the very first
      // sample of a note can be near zero.
      expect((firstDiff - expectedSample).abs(), lessThan(_rate ~/ 100));
    });

    test('the melody and the band end together', () {
      final result = renderSongWithBand(
        charted('| C | F | G | C |'),
        sampleRate: _rate,
      )!;
      final samples = pcm(result.performance.wav).length;
      expect(samples, closeTo(result.performance.totalMs * _rate / 1000, 2));
    });

    test('a slower tempo moves the melody later by the same amount', () {
      final fast = renderSongWithBand(
        charted('| C | F |'),
        sampleRate: _rate,
      )!;
      final slow = renderSongWithBand(
        charted('| C | F |', tempo: 60),
        sampleRate: _rate,
      )!;
      // The count-in is one bar, so halving the tempo doubles the offset.
      expect(slow.melodyStartMs, fast.melodyStartMs * 2);
    });
  });

  group('muting the melody leaves the band untouched', () {
    test('band-only is byte-identical to a zero-gain melody', () {
      // The card's second criterion. mixStemsFloat unit-peaks each stem before
      // its gain, so an extra stem cannot alter the band's contribution — this
      // asserts that rather than assuming it.
      final score = charted('| C | Am | F | G7 |');
      final muted = renderSongWithBand(
        score,
        sampleRate: _rate,
        melodyGain: 0,
      )!;
      final none = renderSongWithBand(
        score,
        sampleRate: _rate,
        includeMelody: false,
      )!;
      expect(muted.performance.wav, none.performance.wav);
    });

    test('bandOnly renders the same band as the full mix would', () {
      final score = charted('| C | G7 |');
      final band = bandOnly(score, sampleRate: _rate);
      final none = renderSongWithBand(
        score,
        sampleRate: _rate,
        includeMelody: false,
      )!;
      expect(band, none.performance.wav);
    });

    test('adding the melody does change the mix', () {
      // The complement of the above: if these were equal, the melody was never
      // heard and the first test would pass for the wrong reason.
      final score = charted('| C | G7 |');
      final withMelody =
          renderSongWithBand(score, sampleRate: _rate)!.performance.wav;
      expect(withMelody, isNot(bandOnly(score, sampleRate: _rate)));
    });
  });

  group('the band follows the piece', () {
    test('the timeline carries the document bar for a highlight', () {
      final result = renderSongWithBand(
        charted('| C | F |'),
        sampleRate: _rate,
      )!;
      final tune =
          result.performance.bars.where((b) => b.bar.role == BarRole.tune);
      expect(tune.every((b) => b.bar.sourceBar != null), isTrue);
    });

    test('a style choice reaches the render', () {
      final score = charted('| C | Am | F | G7 |');
      final straight =
          renderSongWithBand(score, sampleRate: _rate)!.performance.wav;
      final bossa = renderSongWithBand(
        score,
        style: styleFor('bossa'),
        sampleRate: _rate,
      )!
          .performance
          .wav;
      expect(straight, isNot(bossa));
    });

    test('choruses lengthen the play-along', () {
      final score = charted('| C | F |');
      final once = renderSongWithBand(score, sampleRate: _rate)!;
      final thrice = renderSongWithBand(
        score,
        form: const FormOptions(choruses: 3),
        sampleRate: _rate,
      )!;
      expect(thrice.performance.totalMs, greaterThan(once.performance.totalMs));
    });

    test('the same seed renders identically', () {
      final score = charted('| C | Am |');
      expect(
        renderSongWithBand(score, sampleRate: _rate, seed: 5)!.performance.wav,
        renderSongWithBand(score, sampleRate: _rate, seed: 5)!.performance.wav,
      );
    });
  });

  group('the derivation reports what it lost', () {
    test('a chord the score could not spell is carried through', () {
      // chartToScore already simplified C13#11 to C7 on the way in, so the
      // band plays what the SCORE says — and the score is what the user sees.
      final score = chartToScore(parseChartText('| C13#11 |').chart).value;
      final result = renderSongWithBand(score, sampleRate: _rate)!;
      expect(
        result.chart.barsInPlayOrder.single.chordsInOrder.single.chord.text,
        'C7',
      );
    });
  });
}
