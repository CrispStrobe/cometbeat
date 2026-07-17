// lib/core/audio/melody_recorder.dart
//
// Turns a live stream of PitchReadings into a monophonic melody — the transcribe
// half of "free sing": sing a tune, get back a list of (midi, ms) notes you can
// replay on the synth. Pure Dart, testable headlessly. A note is emitted when
// the detected pitch changes (or goes silent), provided it was held at least
// [minNoteMs] (so vibrato wobble and onset transients don't spawn blips).

import 'package:comet_beat/core/audio/pitch_analysis.dart';

class MelodyRecorder {
  MelodyRecorder({this.minNoteMs = 120});

  /// Ignore any held pitch shorter than this (transients / passing wobble).
  final int minNoteMs;

  /// The captured notes so far, as (midi, durationMs).
  final List<(int midi, int ms)> notes = [];

  int? _curMidi; // the note currently being held (null = silence/rest)
  double _startMs = 0;
  double _lastMs = 0;

  /// Feed the latest reading at wall-clock [elapsedMs].
  void update({required double elapsedMs, required PitchReading reading}) {
    final midi = reading.hasPitch ? reading.nearestMidi : null;
    if (midi != _curMidi) {
      _flush(elapsedMs);
      _curMidi = midi;
      _startMs = elapsedMs;
    }
    _lastMs = elapsedMs;
  }

  void _flush(double nowMs) {
    if (_curMidi != null) {
      final dur = (nowMs - _startMs).round();
      if (dur >= minNoteMs) notes.add((_curMidi!, dur));
    }
  }

  /// Finalize the in-progress note (call when recording stops).
  void finish() {
    _flush(_lastMs);
    _curMidi = null;
  }

  void reset() {
    notes.clear();
    _curMidi = null;
    _startMs = 0;
    _lastMs = 0;
  }
}
