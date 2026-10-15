// lib/features/harmony/chart_transport.dart
//
// BB-T2 — the transport a player actually needs: loop a range of bars (or a
// tapped section) N times or until cleared, jump on the next bar line, change
// tempo while playing.
//
// The band plays a QUEUE of realised bars, decided one bar at a time just
// before each is rendered. Normally that is bar 0, 1, 2 …; a loop sends the
// bar after its last back to its first, a jump replaces the next bar, a tempo
// change gives every bar queued afterwards the new tempo's length. Because a
// bar is only queued shortly before it sounds, every one of these lands on the
// next bar line and never mid-bar.
//
// THE CLOCK is a `TransportService` — the app's one clock implementation —
// advanced by the screen with the audio's own elapsed time. Each queued bar is
// stamped with where it starts on that clock, so "which bar is sounding" is a
// lookup of `transport.positionMs` in the queue; nothing here measures time.
// The transport's own loop stays off: looping is the queue's job, and a
// transport that also wrapped would fold the timeline under the queue.
//
// Pure Dart over plain data: a headless test drives the whole thing through
// `TransportService.advance(ms)`.
library;

import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/services/transport_service.dart';

/// One bar in the play queue: which realised bar, and when it sounds on the
/// transport clock.
class QueuedBar {
  const QueuedBar({
    required this.bar,
    required this.startMs,
    required this.durationMs,
    required this.generation,
  });

  /// Index into the realised bars of the plan it was queued from.
  final int bar;
  final double startMs;
  final double durationMs;

  /// Which plan (tempo) it was queued from; bumps on every [ChartTransport.setBars].
  final int generation;

  double get endMs => startMs + durationMs;
}

/// A loop over realised bars [first]..[last] inclusive.
typedef BarLoop = ({int first, int last});

class ChartTransport {
  ChartTransport(this.transport);

  final TransportService transport;

  List<BandBarSpan> _bars = const [];
  int _generation = 0;
  final List<QueuedBar> _queue = [];

  BarLoop? _loop;
  int? _loopTimes;
  int _loopPasses = 0;
  int? _pendingJump;

  /// Everything queued so far, oldest first.
  List<QueuedBar> get queue => List.unmodifiable(_queue);

  BarLoop? get loop => _loop;

  /// Starts a run over [bars] (the plan's realised bars) from the top.
  void start(List<BandBarSpan> bars) {
    _bars = bars;
    _generation++;
    _queue.clear();
    _loop = null;
    _loopTimes = null;
    _loopPasses = 0;
    _pendingJump = null;
    transport
      ..setLoopEnabled(false)
      ..stop()
      ..play();
  }

  /// A re-plan (a tempo change, say): bars queued from now on take their
  /// lengths from [bars]. Bars already queued keep theirs — they are already
  /// rendered and on their way.
  void setBars(List<BandBarSpan> bars) {
    _bars = bars;
    _generation++;
  }

  int get generation => _generation;

  /// Loops bars [first]..[last]. [times] passes through it before playing on,
  /// or null to loop until [clearLoop].
  void setLoop(int first, int last, {int? times}) {
    if (_bars.isEmpty) return;
    final a = first.clamp(0, _bars.length - 1);
    final b = last.clamp(0, _bars.length - 1);
    _loop = (first: a < b ? a : b, last: a < b ? b : a);
    _loopTimes = times;
    _loopPasses = 0;
  }

  void clearLoop() {
    _loop = null;
    _loopTimes = null;
  }

  /// Plays [bar] next — on the next bar line.
  void jumpTo(int bar) {
    if (_bars.isEmpty) return;
    _pendingJump = bar.clamp(0, _bars.length - 1);
  }

  /// The bar that would be queued next, or null at the end.
  int? peekNext() {
    final jump = _pendingJump;
    if (jump != null) return jump;
    final last = _queue.isEmpty ? null : _queue.last.bar;
    if (last == null) return _bars.isEmpty ? null : 0;
    final loop = _loop;
    if (loop != null && last == loop.last) {
      final times = _loopTimes;
      if (times == null || _loopPasses + 1 < times) return loop.first;
    }
    final next = last + 1;
    return next < _bars.length ? next : null;
  }

  /// Queues the next bar and returns it, or null at the end.
  QueuedBar? enqueueNext() {
    final next = peekNext();
    if (next == null) return null;
    final last = _queue.isEmpty ? null : _queue.last;
    final loop = _loop;
    if (_pendingJump != null) {
      _pendingJump = null;
    } else if (loop != null && last != null && last.bar == loop.last) {
      if (next == loop.first) {
        _loopPasses++;
      } else {
        clearLoop(); // the repeats are done; play on
      }
    }
    final queued = QueuedBar(
      bar: next,
      startMs: last?.endMs ?? 0,
      durationMs: _bars[next].durationMs.toDouble(),
      generation: _generation,
    );
    _queue.add(queued);
    return queued;
  }

  /// Whether the bar after [previous] was not simply its successor in the same
  /// plan — a loop wrap, a jump, or a re-plan. The audio must splice there.
  static bool isDiscontinuity(QueuedBar? previous, QueuedBar next) =>
      previous != null &&
      (next.bar != previous.bar + 1 || next.generation != previous.generation);

  /// The queued bar sounding now, by the transport's position; null before the
  /// first or after the last.
  QueuedBar? get current {
    final ms = transport.positionMs;
    for (final q in _queue) {
      if (ms >= q.startMs && ms < q.endMs) return q;
    }
    return null;
  }

  /// How far the queue reaches ahead of the playhead, in ms.
  double get queuedAheadMs =>
      _queue.isEmpty ? 0 : _queue.last.endMs - transport.positionMs;

  /// Nothing more will be queued and the playhead has passed the last bar.
  bool get finished =>
      _queue.isNotEmpty &&
      peekNext() == null &&
      transport.positionMs >= _queue.last.endMs;

  void stop() {
    transport.stop();
    _queue.clear();
    clearLoop();
    _pendingJump = null;
  }
}
