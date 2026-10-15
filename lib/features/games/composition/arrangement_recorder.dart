// lib/features/games/composition/arrangement_recorder.dart
//
// WS-W7 — session ⇄ arrangement: Loop Studio's live scene launching, written
// down as a linear arrangement the Audio Editor can hold.
//
// Loop Studio is a session view: sections are launched live, at loop seams.
// The Audio Editor is an arrangement view: clips on a timeline. This records
// the first as the second. Every loop pass that finishes while recording is
// logged with the mix that actually played (whatever was launched, toggled or
// tweaked), consecutive identical passes are merged, and the result is a list
// the screen lays out end to end on one Audio Editor track.
//
// Pure: no clock, no audio. The screen calls [passEnded] from its seam
// handler.
library;

import 'package:comet_beat/core/audio/loop_engine.dart' show GrooveSpec;

/// A run of identical loop passes.
class RecordedRun {
  const RecordedRun({
    required this.spec,
    required this.passes,
    required this.passMs,
  });

  /// The mix that played.
  final GrooveSpec spec;

  /// How many times through, back to back.
  final int passes;

  /// One pass's length (the loop at that tempo).
  final int passMs;

  int get durationMs => passes * passMs;

  RecordedRun plusOne() =>
      RecordedRun(spec: spec, passes: passes + 1, passMs: passMs);
}

class ArrangementRecorder {
  final List<RecordedRun> _runs = [];
  bool _recording = false;

  bool get isRecording => _recording;

  /// What has been recorded, in play order.
  List<RecordedRun> get runs => List.unmodifiable(_runs);

  bool get isEmpty => _runs.isEmpty;

  /// Total length of the recording.
  int get durationMs => _runs.fold(0, (sum, r) => sum + r.durationMs);

  /// Starts a fresh recording (the previous one is discarded).
  void start() {
    _runs.clear();
    _recording = true;
  }

  /// Stops recording; what was recorded is kept.
  void stop() => _recording = false;

  /// A pass of [spec], [passMs] long, just finished. Ignored unless recording.
  void passEnded(GrooveSpec spec, int passMs) {
    if (!_recording || passMs <= 0) return;
    final last = _runs.isEmpty ? null : _runs.last;
    if (last != null &&
        last.passMs == passMs &&
        last.spec.cacheKey == spec.cacheKey) {
      _runs[_runs.length - 1] = last.plusOne();
    } else {
      _runs.add(RecordedRun(spec: spec, passes: 1, passMs: passMs));
    }
  }
}
