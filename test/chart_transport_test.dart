import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/harmony/chart_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// BB-T2 — the chart transport, driven headlessly through
/// `TransportService.advance` (no wall clock anywhere).

List<BandBarSpan> _bars(int bpm) => planBand(
      parseChartText(
        'tempo: $bpm\n[A]\n| C | F | G | C |\n[B]\n| Am | Dm | G | C |',
      ).chart,
      style: styleFor('straight'),
      form: const FormOptions(countIn: false, ending: false),
    )!
        .bars;

/// Advances in 50 ms ticks for [ms], keeping one bar queued ahead (as the
/// streamed band does), and returns the bars heard start, in order.
List<int> _run(ChartTransport t, double ms) {
  final heard = <int>[];
  QueuedBar? last = t.current;
  for (var elapsed = 0.0; elapsed < ms; elapsed += 50) {
    while (t.queuedAheadMs < 1500 && t.enqueueNext() != null) {}
    t.transport.advance(50);
    final now = t.current;
    if (now != null && !identical(now, last)) heard.add(now.bar);
    last = now;
  }
  return heard;
}

void main() {
  test('plays straight through, bar by bar on the clock', () {
    final t = ChartTransport(TransportService())..start(_bars(120));
    // 8 bars of 4/4 at 120 = 16 s.
    final heard = _run(t, 17000);
    expect(heard, [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(t.finished, isTrue);
  });

  test('play → loop wrap → jump → tempo change → stop', () {
    final t = ChartTransport(TransportService())..start(_bars(120));
    // Loop the A section twice, then play on.
    t.setLoop(0, 3, times: 2);
    final first = _run(t, 15950); // two passes of 4 bars at 2 s, minus a tick
    expect(first, [0, 1, 2, 3, 0, 1, 2, 3]);

    // Jump to bar 6 — it lands on a bar line: the bar already queued still
    // plays out first, and the jump never starts mid-bar.
    t.jumpTo(6);
    final jumped = _run(t, 5000);
    expect(jumped.first, 4, reason: 'already queued, plays out');
    expect(jumped, containsAllInOrder([6, 7]));
    for (final q in t.queue) {
      expect(q.durationMs, greaterThan(0));
    }
    // Every queued bar starts exactly where the previous one ended.
    for (var i = 1; i < t.queue.length; i++) {
      expect(t.queue[i].startMs, t.queue[i - 1].endMs);
    }

    // Tempo change: bars queued afterwards take the new length.
    t
      ..setLoop(0, 7)
      ..setBars(_bars(60));
    _run(t, 6000);
    final slow = t.queue.where((q) => q.generation == t.generation).toList();
    expect(slow, isNotEmpty);
    expect(slow.first.durationMs, 4000, reason: '4/4 at 60 = 4 s a bar');
    expect(
      ChartTransport.isDiscontinuity(
        t.queue[t.queue.indexOf(slow.first) - 1],
        slow.first,
      ),
      isTrue,
      reason: 'a re-plan is a splice point for the audio',
    );

    t.stop();
    expect(t.transport.isPlaying, isFalse);
    expect(t.queue, isEmpty);
  });

  test('a loop without a count repeats until cleared', () {
    final t = ChartTransport(TransportService())..start(_bars(120));
    t.setLoop(2, 3);
    final heard = _run(t, 20000);
    expect(heard.take(2), [0, 1]);
    expect(heard.skip(2).take(6), [2, 3, 2, 3, 2, 3]);
    t.clearLoop();
    final after = _run(t, 12000);
    expect(after, containsAllInOrder([4, 5]));
  });

  test('discontinuities are wraps, jumps and re-plans only', () {
    QueuedBar q(int bar, int gen) =>
        QueuedBar(bar: bar, startMs: 0, durationMs: 1, generation: gen);
    expect(ChartTransport.isDiscontinuity(null, q(0, 1)), isFalse);
    expect(ChartTransport.isDiscontinuity(q(2, 1), q(3, 1)), isFalse);
    expect(ChartTransport.isDiscontinuity(q(3, 1), q(0, 1)), isTrue);
    expect(ChartTransport.isDiscontinuity(q(3, 1), q(4, 2)), isTrue);
  });
}
