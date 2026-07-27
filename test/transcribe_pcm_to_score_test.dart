// transcribePcmToScore — the mono-PCM → Score entry a DAW clip uses to get notes
// back from audio (the "render to audio then transcribe back" path). Pure-Dart
// monophonic by default, so it runs with no model download. A clean sustained
// tone must come back as at least one note near that pitch.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [seconds]-long sine at [freq] Hz.
Float64List _tone(double freq, {double seconds = 1.5, int sampleRate = 44100}) {
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.6 * sin(2 * pi * freq * i / sampleRate);
  }
  return out;
}

Iterable<NoteElement> _notes(Score s) =>
    s.measures.expand((m) => m.elements).whereType<NoteElement>();

int _noteCount(Score s) => _notes(s).length;

void main() {
  test('a sustained A4 tone transcribes to at least one note near A4',
      () async {
    final score = await transcribePcmToScore(_tone(440));
    expect(_noteCount(score), greaterThanOrEqualTo(1));
    // The detected pitch should be in the A4 neighbourhood (±2 semitones covers
    // grid/quantiser slack), not silence or an octave error.
    final midis =
        _notes(score).expand((n) => n.pitches).map((p) => p.midiNumber);
    expect(
      midis.any((m) => (m - 69).abs() <= 2),
      isTrue,
      reason: 'A4 = MIDI 69',
    );
  });

  test('near-silence transcribes without throwing (few or no notes)', () async {
    final score = await transcribePcmToScore(Float64List(44100));
    expect(_noteCount(score), lessThanOrEqualTo(1));
  });
}
