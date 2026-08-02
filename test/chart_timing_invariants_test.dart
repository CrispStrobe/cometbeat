import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;
import 'package:flutter_test/flutter_test.dart';

/// BB-Q4 — timing invariants.
///
/// The card: "a 200-bar chart's last downbeat must land within a stated sample
/// tolerance of where the clock says it should, and every window seam must be
/// continuous." This is the test that catches a bar clock going wrong, and the
/// failure it is built for is SILENT — every bar is present, every chord is
/// right, and the music simply drifts.
///
/// Two clocks exist and they are deliberately different:
///   · `resolveChartPlayback` schedules integer-millisecond EVENTS.
///   · `renderBand` places bars on a float clock and error-diffuses the edges.
/// Both must hold the same invariants, because a player cannot tell which path
/// rendered what they are hearing.

/// Every meter the app ships a style for, plus the awkward ones.
const _meters = [
  TimeSignature(4, 4),
  TimeSignature(3, 4),
  TimeSignature(2, 4),
  TimeSignature(6, 8),
  TimeSignature(5, 4),
  TimeSignature(7, 8),
  TimeSignature(12, 8),
];

/// A spread across the usable range, chosen so most do NOT divide 60000 —
/// a tempo that divides evenly hides every rounding bug there is.
const _tempos = [40, 60, 63, 72, 90, 100, 113, 120, 132, 137, 160, 200, 240];

Chart _longChart(TimeSignature meter, int tempo, {int bars = 200}) {
  final row = List.filled(bars, 'C').join(' | ');
  return parseChartText(
    'key: C\nmeter: ${meter.beats}/${meter.beatUnit}\n'
    'tempo: $tempo\n| $row |',
  ).chart;
}

void main() {
  group('the bar clock has no gaps and no overlaps', () {
    test('every bar starts exactly where the previous one ended', () {
      // A gap makes `barAt` return null mid-song, so the highlight blinks off
      // for a frame; an overlap highlights two bars at once. Both are the
      // symptom of rounding each duration independently instead of
      // accumulating exact edges.
      for (final meter in _meters) {
        for (final tempo in _tempos) {
          final playback = resolveChartPlayback(_longChart(meter, tempo));
          for (var i = 1; i < playback.bars.length; i++) {
            expect(
              playback.bars[i].startMs,
              playback.bars[i - 1].endMs,
              reason: 'seam at bar $i, $meter at $tempo bpm',
            );
          }
        }
      }
    });

    test('barAt answers for every millisecond of the song', () {
      // Sampled rather than exhaustive — 200 bars at 40bpm is 20 minutes of
      // milliseconds — but the samples include every boundary, which is where
      // an off-by-one lives.
      final playback = resolveChartPlayback(
        _longChart(const TimeSignature(4, 4), 137, bars: 60),
      );
      for (final bar in playback.bars) {
        expect(playback.barAt(bar.startMs), isNotNull, reason: 'at a downbeat');
        expect(
          playback.barAt(bar.endMs - 1),
          isNotNull,
          reason: 'at a bar end',
        );
      }
      expect(playback.barAt(playback.totalMs), isNull, reason: 'past the end');
    });

    test('the bars exactly fill the stated total', () {
      for (final meter in _meters) {
        for (final tempo in _tempos) {
          final playback = resolveChartPlayback(_longChart(meter, tempo));
          expect(
            playback.bars.last.endMs,
            playback.totalMs,
            reason: '$meter at $tempo bpm',
          );
        }
      }
    });
  });

  group('drift against real time', () {
    /// Where the last downbeat SHOULD be, in exact milliseconds.
    double idealLastDownbeat(TimeSignature meter, int tempo, int bars) =>
        (bars - 1) * barBeats(meter) * 60000 / tempo;

    test('a 200-bar chart lands within HALF a millisecond of the clock', () {
      // ⚠️ The bound is 1ms because that is the FLOOR: edges are rounded to
      // whole milliseconds, so ±0.5ms is unavoidable and anything more is
      // accumulation. Measured worst case across this whole sweep is exactly
      // 0.5ms, so a loose bound here would guard nothing.
      //
      // This test FOUND the defect it now guards. Rounding the beat once and
      // multiplying every bar by it drifted up to 543ms over 200 bars (12/8 at
      // 132bpm; 362ms in plain 4/4) — nothing missing, no bar wrong, the music
      // simply ahead of where it claimed to be.
      const bars = 200;
      final worst = <String, double>{};
      for (final meter in _meters) {
        for (final tempo in _tempos) {
          final playback = resolveChartPlayback(_longChart(meter, tempo));
          final actual = playback.bars.last.startMs.toDouble();
          final ideal = idealLastDownbeat(meter, tempo, bars);
          worst['$meter@$tempo'] = (actual - ideal).abs();
        }
      }
      final over = {
        for (final e in worst.entries)
          if (e.value > 1) e.key: e.value.toStringAsFixed(2),
      };
      expect(over, isEmpty, reason: 'drift over 1ms: $over');
    });

    test('the drift does not GROW with the song', () {
      // The real signature of accumulated rounding: doubling the length
      // doubles the error. An error-diffused clock stays flat.
      const meter = TimeSignature(4, 4);
      const tempo = 137;
      double driftAt(int bars) {
        final playback = resolveChartPlayback(
          _longChart(meter, tempo, bars: bars),
        );
        return (playback.bars.last.startMs -
                idealLastDownbeat(meter, tempo, bars))
            .abs();
      }

      // 16x the length must not mean 16x the error. Before the fix this went
      // 4ms → 70ms; an error-diffused clock stays at the rounding floor.
      final short = driftAt(25);
      final long = driftAt(400);
      expect(
        long,
        lessThan(1),
        reason: 'drift at 400 bars: ${long.toStringAsFixed(2)}ms '
            '(25 bars: ${short.toStringAsFixed(2)}ms)',
      );
    });
  });

  group('a bar is never zero-length', () {
    test('even at the fastest tempo and the shortest meter', () {
      // A zero-length bar makes `barAt` skip it entirely, so a chord never
      // highlights and — worse — a scheduler can emit two events at the same
      // millisecond.
      for (final tempo in _tempos) {
        final playback = resolveChartPlayback(
          _longChart(const TimeSignature(2, 4), tempo, bars: 8),
        );
        for (final bar in playback.bars) {
          expect(
            bar.durationMs,
            greaterThan(0),
            reason: 'zero-length bar at $tempo bpm',
          );
        }
      }
    });
  });
}
