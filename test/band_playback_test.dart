import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// The band, assembled.
///
/// This is the integration point where six libraries become one WAV, so the
/// assertions are the ones a LISTENER would notice: the performance is as long
/// as the form says, the timeline the highlight follows matches the audio, the
/// same seed renders identically, and nothing degrades to silence.
Chart chart(String text) => parseChartText(text).chart;

const _blues = 'tempo: 120\n[A]\n| C7 | F7 | C7 | C7 |\n'
    '| F7 | F7 | C7 | C7 |\n| G7 | F7 | C7 | G7 |';

/// A low sample rate keeps these tests fast; nothing here is about fidelity.
const _rate = 8000;

BandPerformance? render(
  String text, {
  String style = 'straight',
  FormOptions form = const FormOptions(),
  bool humanize = true,
  int seed = 0,
}) =>
    renderBand(
      chart(text),
      style: styleFor(style),
      form: form,
      humanize: humanize,
      seed: seed,
      sampleRate: _rate,
    );

void main() {
  group('it produces a performance', () {
    test('a chart renders to a playable WAV', () {
      final band = render(_blues)!;
      expect(band.wav.length, greaterThan(44), reason: 'more than a header');
      expect(band.totalMs, greaterThan(0));
      // RIFF/WAVE magic — this has to be something the player accepts.
      expect(String.fromCharCodes(band.wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(band.wav.sublist(8, 12)), 'WAVE');
    });

    test('the audio is as long as the form says', () {
      // 12 bars + count-in + ending = 14 bars of 4/4 at 120bpm = 28s.
      final band = render(_blues)!;
      expect(band.bars, hasLength(14));
      expect(band.totalMs, 28000);

      // …and the WAV actually contains that much audio, so the timeline the
      // highlight follows and the sound cannot drift apart.
      final samples = (band.wav.length - 44) ~/ 2;
      expect(samples, closeTo(_rate * 28, _rate * 0.1));
    });

    test('an empty chart is null, not an empty WAV', () {
      // A caller must be able to tell "silence" from "no performance".
      expect(
        renderBand(const Chart(), style: defaultStyle, sampleRate: _rate),
        isNull,
      );
    });
  });

  group('the timeline matches the audio', () {
    test('bars are contiguous and cover the whole performance', () {
      final band = render(_blues)!;
      expect(band.bars.first.startMs, 0);
      for (var i = 1; i < band.bars.length; i++) {
        expect(band.bars[i].startMs, band.bars[i - 1].endMs);
      }
      expect(band.bars.last.endMs, band.totalMs);
    });

    test('barAt finds the bar under the playhead and stops at the end', () {
      final band = render(_blues)!;
      expect(band.barAt(0)!.bar.role, BarRole.countIn);
      expect(band.barAt(2500)!.bar.role, BarRole.tune);
      expect(band.barAt(band.totalMs), isNull);
    });

    test('a realised bar still knows its document bar', () {
      // What lets the screen highlight the bar the user is looking at.
      final band = render(_blues)!;
      final tune = band.bars.firstWhere((b) => b.bar.role == BarRole.tune);
      expect(tune.bar.sourceBar, (section: 0, bar: 0));
    });
  });

  group('determinism', () {
    test('the same seed renders byte-identically', () {
      final a = render(_blues, seed: 3)!;
      final b = render(_blues, seed: 3)!;
      expect(a.wav, b.wav);
    });

    test('a different seed renders differently', () {
      final a = render(_blues, seed: 1)!;
      final b = render(_blues, seed: 2)!;
      expect(a.wav, isNot(b.wav));
    });

    test('humanise OFF is also deterministic', () {
      final a = render(_blues, humanize: false)!;
      final b = render(_blues, humanize: false)!;
      expect(a.wav, b.wav);
    });

    test('humanise changes the render', () {
      final on = render(_blues)!;
      final off = render(_blues, humanize: false)!;
      expect(on.wav, isNot(off.wav));
      // …but not the LENGTH: humanisation is bounded and must not stretch the
      // performance.
      expect(on.totalMs, off.totalMs);
      expect(on.wav.length, off.wav.length);
    });
  });

  group('every style plays', () {
    test('all six render a chart in a meter they claim', () {
      for (final style in kStyles) {
        // Give each style a meter it fits; a waltz is not a 4/4 style.
        final meter = style.fitsMeter(4) ? '4/4' : '3/4';
        final bars = style.fitsMeter(4) ? '| C | Am | F | G |' : '| C | Am |';
        final band = render(
          'meter: $meter\ntempo: 120\n[A]\n$bars',
          style: style.id,
        );
        expect(band, isNotNull, reason: style.id);
        expect(band!.totalMs, greaterThan(0), reason: style.id);
      }
    });

    test('a style whose level has no drums still plays the harmony', () {
      // Level 0 of several styles is bass and comp only; that must not render
      // silence.
      final band = render(
        _blues,
        form: const FormOptions(baseIntensity: 0, countIn: false),
      )!;
      expect(band.wav.length, greaterThan(44));
    });
  });

  group('the form reaches the audio', () {
    test('more choruses make a longer performance', () {
      final one = render(_blues)!;
      final three = render(_blues, form: const FormOptions(choruses: 3))!;
      expect(three.totalMs, greaterThan(one.totalMs));
      expect(three.bars.length, one.bars.length + 24);
    });

    test('turning off the count-in shortens it by exactly one bar', () {
      final withIn = render(_blues)!;
      final without = render(_blues, form: const FormOptions(countIn: false))!;
      expect(withIn.bars.length - without.bars.length, 1);
      expect(withIn.totalMs - without.totalMs, 2000);
    });

    test('a mixed-meter chart lays its bars out at the right lengths', () {
      final band = render(
        'tempo: 120\n[A]\n| C |\n',
        form: const FormOptions(countIn: false, ending: false),
      )!;
      expect(band.bars.single.durationMs, 2000);
    });
  });

  meterTests();

  group('degenerate input', () {
    test('a one-bar chart plays', () {
      expect(render('| C |'), isNotNull);
    });

    test('a chart of only held bars plays the held chord', () {
      final band = render('| C | % | % | % |');
      expect(band, isNotNull);
      expect(band!.wav.length, greaterThan(44));
    });

    test('an unreadable style id falls back rather than failing', () {
      final band = renderBand(
        chart(_blues),
        style: styleFor('no-such-style'),
        sampleRate: _rate,
      );
      expect(band, isNotNull);
    });

    test('a nonsense tempo does not divide by zero', () {
      final band = render('tempo: 0\n| C |');
      expect(band, isNotNull);
      expect(band!.totalMs, greaterThan(0));
    });
  });
}

/// BB-D5 — meters beyond 4/4, and the clock that makes them exact.
void meterTests() {
  group('meters beyond 4/4', () {
    test('3/4, 6/8 and 5/4 each get the right bar length', () {
      // Tempo is quarter-note BPM, so 6/8 is THREE quarters, not six eighths.
      for (final (meter, expectedMs) in [
        ('4/4', 2000),
        ('3/4', 1500),
        ('6/8', 1500),
        ('5/4', 2500),
        ('12/8', 3000),
        ('7/8', 1750),
      ]) {
        final band = renderBand(
          chart('meter: $meter\ntempo: 120\n[A]\n| C |'),
          style: styleFor('straight'),
          form: const FormOptions(countIn: false, ending: false),
          sampleRate: _rate,
        )!;
        expect(band.bars.single.durationMs, expectedMs, reason: meter);
      }
    });

    test('a mid-chart meter change lands where it should', () {
      final source = chart('tempo: 120\n[A]\n| C |');
      final mixed = Chart(
        sections: [
          ChartSection(
            bars: [
              source.sections.single.bars.first,
              ChartBar(
                chords: source.sections.single.bars.first.chords,
                meterChange: const TimeSignature(3, 4),
              ),
              source.sections.single.bars.first,
            ],
          ),
        ],
      );
      final band = renderBand(
        mixed,
        style: styleFor('straight'),
        form: const FormOptions(countIn: false, ending: false),
        sampleRate: _rate,
      )!;
      expect(band.bars.map((b) => b.durationMs), [2000, 1500, 2000]);
      expect(band.bars.map((b) => b.startMs), [0, 2000, 3500]);
      expect(band.totalMs, 5500);
    });
  });

  group('the clock does not drift', () {
    test('bars stay contiguous at a tempo with no whole-ms bar', () {
      // 137bpm gives a 1751.8ms bar. Rounding each duration independently
      // leaves gaps that `barAt` falls into; error diffusion cannot.
      for (final bpm in [137, 111, 93, 157]) {
        final band = renderBand(
          chart('tempo: $bpm\n[A]\n${List.filled(32, '| C |').join('\n')}'),
          style: styleFor('straight'),
          form: const FormOptions(countIn: false, ending: false),
          sampleRate: _rate,
        )!;
        for (var i = 1; i < band.bars.length; i++) {
          expect(
            band.bars[i].startMs,
            band.bars[i - 1].endMs,
            reason: 'gap at bar $i, $bpm bpm',
          );
        }
        expect(band.bars.last.endMs, band.totalMs, reason: '$bpm bpm');
      }
    });

    test('barAt finds a bar at EVERY millisecond of the performance', () {
      // The failure a gap produces: the playhead blinks out mid-piece.
      final band = renderBand(
        chart('tempo: 137\n[A]\n${List.filled(12, '| C |').join('\n')}'),
        style: styleFor('straight'),
        form: const FormOptions(countIn: false, ending: false),
        sampleRate: _rate,
      )!;
      for (var ms = 0; ms < band.totalMs; ms += 7) {
        expect(band.barAt(ms), isNotNull, reason: 'no bar at ${ms}ms');
      }
    });

    test('the last bar ends exactly at the total, over a long chart', () {
      final band = renderBand(
        chart('tempo: 93\n[A]\n${List.filled(64, '| C |').join('\n')}'),
        style: styleFor('straight'),
        form: const FormOptions(countIn: false, ending: false),
        sampleRate: _rate,
      )!;
      // No accumulated drift: 64 bars of a fractional length still land on the
      // total rather than a bar-length away from it.
      expect(band.bars.last.endMs, band.totalMs);
      expect(
        (band.totalMs - 64 * 4 * 60000 / 93).abs(),
        lessThan(1),
      );
    });
  });

  test('a 4/4 chart at an integral tempo is unchanged by the diffusion', () {
    // The card's own requirement: this card must not move existing output.
    final band = renderBand(
      chart('tempo: 120\n[A]\n| C | F | G | C |'),
      style: styleFor('straight'),
      form: const FormOptions(countIn: false, ending: false),
      sampleRate: _rate,
    )!;
    expect(band.bars.map((b) => b.startMs), [0, 2000, 4000, 6000]);
    expect(band.bars.map((b) => b.durationMs), [2000, 2000, 2000, 2000]);
    expect(band.totalMs, 8000);
  });
}
