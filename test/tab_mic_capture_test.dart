// TabMicCapture — turning live pitch readings into (string, fret) placements.
// Pure: synthetic PitchReadings, no microphone.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/features/games/composition/tab_mic_capture.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clean, confident reading for [midi] (equal temperament, A4 = 440).
PitchReading _tone(int midi) => PitchReading(
      frequency: 440.0 * math.pow(2, (midi - 69) / 12.0),
      clarity: 0.99,
      a4: 440,
      rms: 0.2,
    );

void main() {
  final guitar = Tuning.standardGuitar;
  final lowE = guitar.strings[5].midiNumber; // bottom string, open

  test('commits only after enough consecutive agreeing frames', () {
    final cap = TabMicCapture(guitar);
    expect(cap.accept(_tone(lowE)), isNull);
    expect(cap.accept(_tone(lowE)), isNull);
    final placed = cap.accept(_tone(lowE));
    expect(placed, isNotNull);
    expect(placed!.$1, 5); // bottom string
    expect(placed.$2, 0); // open
  });

  test('a held note commits once', () {
    final cap = TabMicCapture(guitar, framesToCommit: 2);
    cap.accept(_tone(lowE));
    expect(cap.accept(_tone(lowE)), isNotNull);
    // Still holding — no repeat.
    expect(cap.accept(_tone(lowE)), isNull);
    expect(cap.accept(_tone(lowE)), isNull);
  });

  test('silence re-arms, so the same note played again commits again', () {
    final cap = TabMicCapture(guitar, framesToCommit: 2);
    cap.accept(_tone(lowE));
    expect(cap.accept(_tone(lowE)), isNotNull);

    expect(cap.accept(PitchReading.silent()), isNull); // gap
    cap.accept(_tone(lowE));
    expect(cap.accept(_tone(lowE)), isNotNull); // second strike
  });

  test('an unstable stream never commits', () {
    final cap = TabMicCapture(guitar);
    for (var i = 0; i < 6; i++) {
      expect(cap.accept(_tone(lowE + (i.isEven ? 0 : 7))), isNull);
    }
  });

  test('low clarity or low level is ignored', () {
    final cap = TabMicCapture(guitar, framesToCommit: 2);
    const noisy = PitchReading(
      frequency: 82.41,
      clarity: 0.2, // below the gate
      a4: 440,
      rms: 0.2,
    );
    const quiet = PitchReading(
      frequency: 82.41,
      clarity: 0.99,
      a4: 440,
      rms: 0.0001, // below the gate
    );
    expect(cap.accept(noisy), isNull);
    expect(cap.accept(noisy), isNull);
    expect(cap.accept(quiet), isNull);
    expect(cap.accept(quiet), isNull);
  });

  test('a pitch below the tuning is unreachable and never placed', () {
    final cap = TabMicCapture(guitar, framesToCommit: 2);
    final tooLow = lowE - 12; // an octave under the bottom string
    cap.accept(_tone(tooLow));
    expect(cap.accept(_tone(tooLow)), isNull);
  });

  test('reset() clears the in-flight candidate', () {
    final cap = TabMicCapture(guitar);
    cap.accept(_tone(lowE));
    cap.accept(_tone(lowE));
    cap.reset();
    expect(cap.accept(_tone(lowE)), isNull); // count restarted
  });
}
