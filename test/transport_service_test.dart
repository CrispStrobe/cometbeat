// WS-W2 — the shared transport.
//
// The card's acceptance is two things: a headless drive through
// play → loop wrap → stop with bar/beat asserted against TempoMap at each edge,
// and the cross-surface one — "pressing play in the Tracker moves the Loop
// Studio playhead" — which is what actually proves the gap is closed.

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 120 BPM → a beat is 500 ms, a 4/4 bar is 2000 ms. Every number below is
/// derived from those two rather than written out, so a reader can check them.
const double beatMs = 500;
const double barMs = beatMs * 4;

void main() {
  group('position and musical readout', () {
    test('beat and bar follow TempoMap, not a constant', () {
      // 120 BPM for two bars, then 60 BPM (a beat becomes 1000 ms).
      final tempo = TempoMap([
        const TempoChange(ms: 0, bpm: 120),
        const TempoChange(ms: barMs * 2, bpm: 60),
      ]);
      final t = TransportService(tempo: tempo);

      t.seekMs(barMs * 2);
      expect(t.beat, closeTo(8, 1e-9));
      expect(t.bar, 2);
      expect(t.bpm, 60);

      // One more beat now takes 1000 ms, not 500. A transport that assumed a
      // constant tempo would read this as beat 10.
      t.seekMs(barMs * 2 + 1000);
      expect(t.beat, closeTo(9, 1e-9));
      expect(t.barBeatLabel, '3.2');
    });

    test('barBeatLabel is 1-based, because that is how musicians count', () {
      final t = TransportService();
      expect(t.barBeatLabel, '1.1');
      t.seekBeat(4);
      expect(t.barBeatLabel, '2.1');
      t.seekBeat(6.5);
      expect(t.barBeatLabel, '2.3');
    });

    test('beatsPerBar changes the bar, not the beat', () {
      final t = TransportService()..seekBeat(6);
      expect(t.bar, 1);
      t.beatsPerBar = 3;
      expect(t.beat, closeTo(6, 1e-9));
      expect(t.bar, 2);
    });

    test('seek cannot put the playhead before the start', () {
      final t = TransportService()..seekMs(-5000);
      expect(t.positionMs, 0);
    });
  });

  group('play → loop wrap → stop', () {
    test('the full drive, with bar/beat asserted at each edge', () {
      final t = TransportService()
        ..setLoop(0, barMs * 2)
        ..setLoopEnabled(true);

      expect(t.isPlaying, isFalse);
      t.play();
      expect(t.isPlaying, isTrue);

      // Edge 1: three beats in.
      var report = t.advance(beatMs * 3);
      expect(t.beat, closeTo(3, 1e-9));
      expect(t.bar, 0);
      expect(report.looped, isFalse);
      expect(report.beatsCrossed, [1, 2, 3]);

      // Edge 2: cross the bar line.
      report = t.advance(beatMs * 2);
      expect(t.bar, 1);
      expect(t.barBeatLabel, '2.2');
      expect(report.beatsCrossed, [4, 5]);

      // Edge 3: past the loop end — wraps rather than running on.
      report = t.advance(beatMs * 4);
      expect(report.looped, isTrue);
      expect(t.positionMs, closeTo(beatMs, 1e-9));
      expect(t.bar, 0);

      // Edge 4: stop returns to the loop start, not to zero.
      t.stop();
      expect(t.isPlaying, isFalse);
      expect(t.positionMs, 0);
    });

    test('stop with no loop returns to zero', () {
      final t = TransportService()..play();
      t.advance(barMs);
      t.stop();
      expect(t.positionMs, 0);
    });

    test('stop returns to the loop START, so a section stays under the hands',
        () {
      final t = TransportService()
        ..setLoop(barMs * 4, barMs * 8)
        ..setLoopEnabled(true)
        ..seekMs(barMs * 5)
        ..play();
      t.advance(beatMs);
      t.stop();
      expect(t.positionMs, barMs * 4);
    });

    test('an advance LONGER than the loop wraps by modulo, not by one lap', () {
      // The dropped-frame case. Subtracting the loop length once would leave
      // the playhead past the loop end — a bug that only appears on a slow
      // device, which is exactly where it must not appear.
      final t = TransportService()
        ..setLoop(0, barMs)
        ..setLoopEnabled(true)
        ..play();

      final report = t.advance(barMs * 3 + beatMs);
      expect(report.looped, isTrue);
      expect(t.positionMs, closeTo(beatMs, 1e-9));
      expect(t.positionMs, lessThan(t.loopEndMs));
    });

    test('one advance that wraps repeatedly reports looped ONCE', () {
      final t = TransportService()
        ..setLoop(0, beatMs)
        ..setLoopEnabled(true)
        ..play();
      final report = t.advance(beatMs * 10);
      expect(
        report.looped,
        isTrue,
        reason: 'a listener re-triggers on this flag; four laps in one '
            'dropped frame is still one wrap to react to',
      );
    });

    test('an inverted or empty loop range is inert, not an error', () {
      final t = TransportService()
        ..setLoop(barMs * 2, barMs * 2)
        ..setLoopEnabled(true)
        ..play();
      expect(t.hasUsableLoop, isFalse);
      final report = t.advance(barMs * 4);
      expect(report.looped, isFalse);
      expect(t.positionMs, closeTo(barMs * 4, 1e-9));
    });

    test('setLoop normalises a backwards drag instead of rejecting it', () {
      final t = TransportService()..setLoop(barMs * 3, barMs);
      expect(t.loopStartMs, barMs);
      expect(t.loopEndMs, barMs * 3);
    });
  });

  group('advance guards', () {
    test('does nothing while stopped', () {
      final t = TransportService();
      expect(t.advance(barMs).beatsCrossed, isEmpty);
      expect(t.positionMs, 0);
    });

    test('a zero or non-finite delta is a no-op, not an error', () {
      // A Ticker's first callback legitimately reports zero elapsed.
      final t = TransportService()..play();
      expect(t.advance(0).beatsCrossed, isEmpty);
      expect(t.advance(double.nan).beatsCrossed, isEmpty);
      expect(t.advance(-10).beatsCrossed, isEmpty);
      expect(t.positionMs, 0);
    });

    test('a beat is never reported twice across two advances', () {
      final t = TransportService()..play();
      final first = t.advance(beatMs);
      final second = t.advance(beatMs);
      expect(first.beatsCrossed, [1]);
      expect(second.beatsCrossed, [2]);
    });

    test('landing exactly on a downbeat clicks on THAT frame', () {
      final t = TransportService()..play();
      expect(t.advance(beatMs).beatsCrossed, [1]);
    });

    test('a pathological delta cannot allocate without bound', () {
      final t = TransportService()..play();
      final report = t.advance(60000 * 60);
      expect(report.beatsCrossed.length, lessThanOrEqualTo(4096));
    });
  });

  group('syncTo — tracking an authority instead of accumulating', () {
    test('sets the position and reports the beats crossed', () {
      final t = TransportService();
      final report = t.syncTo(beatMs * 3);
      expect(t.positionMs, closeTo(beatMs * 3, 1e-9));
      expect(report.beatsCrossed, [1, 2, 3]);
    });

    test('does NOT drift, where accumulating deltas would', () {
      // The whole reason it exists. The Tracker and Loop Studio keep musical
      // phase in a monotonic Stopwatch and play a pre-rendered looping WAV;
      // accumulating per-frame deltas there trades a drift-proof clock for a
      // drifting one, one dropped frame at a time.
      final synced = TransportService();
      final accumulated = TransportService()..play();

      // An authority at a steady 10 ms, but the UI only manages to report 9.9.
      var authority = 0.0;
      for (var frame = 0; frame < 500; frame++) {
        authority += 10;
        synced.syncTo(authority);
        accumulated.advance(9.9);
      }

      expect(synced.positionMs, closeTo(5000, 1e-9));
      expect(
        accumulated.positionMs,
        closeTo(4950, 1e-9),
        reason: 'accumulation is 50 ms behind after five seconds',
      );
    });

    test('going backwards is a wrap, not negative beats', () {
      // The authority looped, or the user scrubbed. Clicking every beat between
      // the two would be a burst of metronome on beats nobody played through.
      final t = TransportService()..syncTo(barMs * 2);
      final report = t.syncTo(beatMs);
      expect(report.looped, isTrue);
      expect(report.beatsCrossed, isEmpty);
      expect(t.positionMs, closeTo(beatMs, 1e-9));
    });

    test('works while stopped — the authority may run without our play state',
        () {
      final t = TransportService();
      expect(t.isPlaying, isFalse);
      t.syncTo(barMs);
      expect(t.positionMs, closeTo(barMs, 1e-9));
    });

    test('the same position twice is a no-op and does not notify', () {
      final t = TransportService()..syncTo(barMs);
      var notifications = 0;
      t.addListener(() => notifications++);
      expect(t.syncTo(barMs).beatsCrossed, isEmpty);
      expect(notifications, 0);
    });

    test('a negative or non-finite authority is clamped, not propagated', () {
      final t = TransportService()..syncTo(barMs);
      t.syncTo(-100);
      expect(t.positionMs, 0);
      t.syncTo(double.nan);
      expect(t.positionMs, 0);
    });
  });

  group('count-in', () {
    test('holds the position, then releases it', () {
      final t = TransportService()
        ..beatsPerBar = 4
        ..countInBars = 1;
      t.play();
      expect(t.isPlaying, isTrue);
      expect(t.isCountingIn, isTrue);
      expect(t.countInRemainingMs, closeTo(barMs, 1e-9));

      // Half a bar of count-in: still counting, playhead has not moved.
      var report = t.advance(beatMs * 2);
      expect(t.isCountingIn, isTrue);
      expect(
        t.positionMs,
        0,
        reason: 'a count-in delays the start, it does '
            'not rewind the timeline',
      );
      expect(report.countInEnded, isFalse);

      // The rest of the count-in plus one beat of music.
      report = t.advance(beatMs * 2 + beatMs);
      expect(report.countInEnded, isTrue);
      expect(t.isCountingIn, isFalse);
      expect(t.positionMs, closeTo(beatMs, 1e-9));
    });

    test('count-in beats are numbered negatively, so "three, four" is legible',
        () {
      final t = TransportService()..countInBars = 1;
      t.play();
      final report = t.advance(barMs);
      expect(report.beatsCrossed, isNotEmpty);
      expect(
        report.beatsCrossed.every((b) => b <= 0),
        isTrue,
        reason: 'the count-in runs before beat 0',
      );
    });

    test('no count-in configured means play starts immediately', () {
      final t = TransportService()..play();
      expect(t.isCountingIn, isFalse);
      t.advance(beatMs);
      expect(t.positionMs, closeTo(beatMs, 1e-9));
    });

    test('play is idempotent, so a shortcut and a button cannot restart it',
        () {
      final t = TransportService()..countInBars = 2;
      t.play();
      t.advance(beatMs);
      final left = t.countInRemainingMs;
      t.play();
      expect(t.countInRemainingMs, left);
    });

    test('pause abandons the count-in rather than resuming mid-count', () {
      final t = TransportService()..countInBars = 1;
      t.play();
      t.advance(beatMs);
      t.pause();
      expect(t.isCountingIn, isFalse);
      t.play();
      expect(t.countInRemainingMs, closeTo(barMs, 1e-9));
    });
  });

  group('record arm', () {
    test('arming before play lights the button without rolling', () {
      final t = TransportService()..setRecordArmed(true);
      expect(t.isRecordArmed, isTrue);
      expect(t.isRecording, isFalse);
      t.play();
      expect(t.isRecording, isTrue);
    });

    test('stopping ends the recording but keeps the arm', () {
      final t = TransportService()..setRecordArmed(true);
      t.play();
      t.stop();
      expect(t.isRecording, isFalse);
      expect(t.isRecordArmed, isTrue);
    });

    test('disarming mid-roll stops recording without stopping playback', () {
      final t = TransportService()..setRecordArmed(true);
      t.play();
      t.setRecordArmed(false);
      expect(t.isRecording, isFalse);
      expect(t.isPlaying, isTrue);
    });
  });

  group('the cross-surface guarantee', () {
    test('pressing play in one surface moves the other surface playhead', () {
      // The gap this task exists to close: three private clocks, none able to
      // follow another. Two surfaces holding ONE service is the whole fix, so
      // the test is written the way the surfaces will be — each keeps its own
      // view of the position, refreshed from the notifier.
      final transport = TransportService();

      double trackerPlayhead = -1;
      double loopStudioPlayhead = -1;
      transport.addListener(() => trackerPlayhead = transport.positionMs);
      transport.addListener(() => loopStudioPlayhead = transport.positionMs);

      // "The Tracker" presses play and drives the clock from its own Ticker.
      transport.play();
      transport.advance(barMs);

      expect(trackerPlayhead, closeTo(barMs, 1e-9));
      expect(
        loopStudioPlayhead,
        closeTo(barMs, 1e-9),
        reason: 'Loop Studio never called play or advance — it followed',
      );
      expect(trackerPlayhead, loopStudioPlayhead);
    });

    test('a surface that seeks moves every other surface too', () {
      final transport = TransportService();
      var seen = -1.0;
      transport.addListener(() => seen = transport.positionMs);
      transport.seekBeat(8);
      expect(seen, closeTo(barMs * 2, 1e-9));
    });

    test('every state change notifies, and a no-op change does not', () {
      // A transport bar rebuilds on every notify; notifying when nothing moved
      // is how a shared widget becomes the frame budget.
      final t = TransportService();
      var notifications = 0;
      t.addListener(() => notifications++);

      t.setLoopEnabled(true);
      t.setLoopEnabled(true);
      expect(notifications, 1);

      t.beatsPerBar = 4;
      expect(notifications, 1, reason: '4 was already the value');

      t.seekMs(0);
      expect(notifications, 1, reason: 'already at 0');

      t.seekMs(barMs);
      expect(notifications, 2);
    });

    test('stop from a settled state does not notify', () {
      final t = TransportService();
      var notifications = 0;
      t.addListener(() => notifications++);
      t.stop();
      expect(notifications, 0);
    });
  });
}
