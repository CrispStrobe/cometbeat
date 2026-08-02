import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-Q1 — render → listen → assert.
///
/// The repo's proven acceptance pattern, applied to the band: render a chart to
/// audio, run the audio back through our own chord DETECTOR, and check it hears
/// the chords that were written. Everything else in the harmony suite asserts
/// on data structures; this is the only test that asserts the band actually
/// SOUNDS like the chart.
///
/// That matters because every silent-failure this arc shared one property — the
/// data looked right. A voicing that drops the third, a bass line on the wrong
/// root, a chord that never gets mixed in: all of those leave a perfectly
/// well-formed `BandPerformance` behind.
///
/// It runs headless, in-process, on the detector rather than by shelling out to
/// `bin/listen.dart` — same signal, no subprocess, and it works in CI.

/// The spans that are actually the TUNE.
///
/// ⚠️ `renderBand` realises a form, not a bar list: it prepends a COUNT-IN and
/// may append an ending, so `bars[0]` is not `| C |`. Indexing the raw list
/// made this file read the click as bar 1 and report the whole progression
/// shifted by one — which looked like a transposition bug and was not.
List<BandBarSpan> _tuneBars(BandPerformance performance) => [
      for (final span in performance.bars)
        if (span.bar.role == BarRole.tune) span,
    ];

/// The mono samples sounding during tune bar [barIndex] of [performance].
///
/// Trimmed at both ends: the attack transient and the decay into the next chord
/// are exactly where a chromagram gets confused, and the question here is "what
/// chord is sounding", not "how does it start".
Float64List _barSamples(
  BandPerformance performance,
  int barIndex, {
  double start = 0.25,
  double end = 0.85,
}) {
  final span = _tuneBars(performance)[barIndex];
  final mono = wavToMonoFloat(readWavPcm16(performance.wav));
  const rate = kSampleRate / 1000;
  final from = ((span.startMs + span.durationMs * start) * rate).round();
  final to = ((span.startMs + span.durationMs * end) * rate).round();
  return Float64List.fromList(
    mono.sublist(from.clamp(0, mono.length), to.clamp(0, mono.length)),
  );
}

/// Pitch classes, so an assertion reads in music rather than in numbers.
const _pc = {
  'C': 0, 'C#': 1, 'D': 2, 'Eb': 3, 'E': 4, 'F': 5, //
  'F#': 6, 'G': 7, 'Ab': 8, 'A': 9, 'Bb': 10, 'B': 11,
};

void main() {
  final detector = ChordDetector();

  group('the band plays the chords that were written', () {
    test('a plain major progression comes back as itself', () {
      final chart = parseChartText(
        'key: C\ntempo: 100\n| C | F | G | C |',
      ).chart;
      final performance = renderBand(chart, style: styleFor('straight'));
      expect(performance, isNotNull, reason: 'the band must render');

      const expected = ['C', 'F', 'G', 'C'];
      final heard = <String>[];
      for (var i = 0; i < expected.length; i++) {
        final reading = detector.analyze(_barSamples(performance!, i));
        heard.add(
          reading.candidates.isEmpty
              ? '-'
              : _nameOf(reading.candidates.first.rootPc),
        );
      }
      expect(heard, expected, reason: 'the band did not play the chart');
    });

    test('the bass plays the CHORD, not merely something consonant', () {
      // A chromagram folds away the octave, so `C` and `C/E` are the same
      // twelve numbers — the bass reading is the only thing that can tell a
      // real bass line from a wash at the right pitch classes.
      //
      // ⚠️ The assertion is "a chord tone", NOT "the root", and that is the
      // musically correct one. `straight`'s intensity levels run root →
      // twoFeel → walking, and a walking line is SUPPOSED to leave the root
      // and approach the next chord. My first two attempts asserted the root
      // across the bar and then on the downbeat; both read a third or an
      // approach note, which was the music being right and the test being
      // wrong. Chasing a narrower window would have been tuning the test until
      // it agreed with me.
      final chart = parseChartText(
        'key: C\ntempo: 100\n| C | F | G | Am |',
      ).chart;
      final performance = renderBand(chart, style: styleFor('straight'))!;

      // Root, third and fifth of each written chord.
      const tones = {
        0: [0, 4, 7], // C
        1: [5, 9, 0], // F
        2: [7, 11, 2], // G
        3: [9, 0, 4], // Am
      };
      for (var i = 0; i < 4; i++) {
        final reading = detector.analyze(_barSamples(performance, i));
        expect(reading.bassPc, isNotNull, reason: 'bar ${i + 1}: no bass');
        expect(
          tones[i],
          contains(reading.bassPc),
          reason: 'bar ${i + 1}: the bass is outside the chord',
        );
      }
    });

    test('a minor chord is heard as minor, not as its relative major', () {
      // The classic confusion: Am and C share two of three notes. If the third
      // is dropped from the voicing, or the bass lands on C, this fails — and
      // the data structure would look perfect either way.
      final chart = parseChartText(
        'key: C\ntempo: 100\n| Am | Dm | Em | Am |',
      ).chart;
      final performance = renderBand(chart, style: styleFor('straight'))!;

      const expected = ['A', 'D', 'E', 'A'];
      for (var i = 0; i < expected.length; i++) {
        final reading = detector.analyze(_barSamples(performance, i));
        expect(reading.candidates, isNotEmpty, reason: 'bar ${i + 1} silent');
        expect(
          _nameOf(reading.candidates.first.rootPc),
          expected[i],
          reason: 'bar ${i + 1}',
        );
        expect(
          reading.candidates.first.suffix,
          contains('m'),
          reason: 'bar ${i + 1} lost its minor third',
        );
      }
    });
  });

  group('the chart really is transposed, audibly', () {
    test('the same shape a tone up ROTATES the chroma by two semitones', () {
      // Transposition is asserted structurally elsewhere; here it has to be
      // true of the AUDIO, which is the only thing the player hears.
      //
      // ⚠️ Asserted as a ROTATION rather than as chord names, deliberately. A
      // chromagram cannot always name a two-bar excerpt — my first version
      // expected `A` and got `E`, its fifth, which says more about the
      // detector than about the band. The rotation is detector-independent:
      // whatever the twelve numbers are for the C chart, the D chart's must be
      // the same numbers moved round by two.
      final inC = parseChartText('key: C\ntempo: 100\n| C | G |').chart;
      final inD = parseChartText('key: D\ntempo: 100\n| D | A |').chart;

      final chromaC = detector
          .analyze(
            _barSamples(renderBand(inC, style: styleFor('straight'))!, 0),
          )
          .chroma;
      final chromaD = detector
          .analyze(
            _barSamples(renderBand(inD, style: styleFor('straight'))!, 0),
          )
          .chroma;

      /// How well [a] matches [b] rotated by [semitones].
      double agreement(List<double> a, List<double> b, int semitones) {
        var dot = 0.0;
        var na = 0.0;
        var nb = 0.0;
        for (var i = 0; i < 12; i++) {
          final rotated = b[(i - semitones + 12) % 12];
          dot += a[i] * rotated;
          na += a[i] * a[i];
          nb += rotated * rotated;
        }
        return (na <= 0 || nb <= 0) ? 0 : dot / (math.sqrt(na) * math.sqrt(nb));
      }

      // The best rotation must be the two semitones we transposed by.
      var best = 0;
      for (var shift = 0; shift < 12; shift++) {
        if (agreement(chromaD, chromaC, shift) >
            agreement(chromaD, chromaC, best)) {
          best = shift;
        }
      }
      expect(
        best,
        2,
        reason: 'the D chart should be the C chart rotated up a tone, '
            'but the closest rotation was $best semitones',
      );
      expect(
        agreement(chromaD, chromaC, 2),
        greaterThan(0.8),
        reason: 'the rotated chromas should look alike, not merely closest',
      );
    });
  });

  group('the audio is well-formed', () {
    test('it is not silent, and it does not clip', () {
      // Two failures that make everything above meaningless: an empty mix reads
      // as "no chord detected", and a clipped one distorts the harmonics the
      // detector scores.
      final chart = parseChartText(
        'key: F\ntempo: 120\n| F | Bb | C7 | F |',
      ).chart;
      final performance = renderBand(chart, style: styleFor('swing'))!;
      final mono = wavToMonoFloat(readWavPcm16(performance.wav));

      var peak = 0.0;
      var sum = 0.0;
      for (final sample in mono) {
        final magnitude = sample.abs();
        if (magnitude > peak) peak = magnitude;
        sum += sample * sample;
      }
      final rms = sum <= 0 ? 0.0 : (sum / mono.length);

      expect(peak, greaterThan(0.05), reason: 'the band is essentially silent');
      expect(peak, lessThanOrEqualTo(1.0), reason: 'clipped');
      expect(rms, greaterThan(1e-6), reason: 'no sustained sound');
    });

    test('every bar of a long chart carries sound', () {
      // A dropped bar mid-song is the kind of thing that only shows up when
      // someone plays the whole tune.
      final chart = parseChartText(
        'key: C\ntempo: 160\n| C | Am | Dm7 | G7 | C | Am | Dm7 | G7 |',
      ).chart;
      final performance = renderBand(chart, style: styleFor('straight'))!;
      for (var i = 0; i < _tuneBars(performance).length; i++) {
        final samples = _barSamples(performance, i);
        final peak = samples.fold<double>(
          0,
          (best, s) => s.abs() > best ? s.abs() : best,
        );
        expect(peak, greaterThan(0.01), reason: 'bar ${i + 1} is silent');
      }
    });
  });
}

String _nameOf(int pc) =>
    _pc.entries.firstWhere((entry) => entry.value == pc).key;
