// pitchFromMidi — the MIDI→Pitch conversion behind capture, playback and the
// mic games. Locks the contract: it round-trips (the pitch reconstructs its
// midi number) across the whole MIDI range, hits the known anchors, and never
// throws on out-of-range input.

import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:crisp_notation/crisp_notation.dart' show Pitch, Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips: pitchFromMidi(m).midiNumber == m across 0..127', () {
    for (var m = 0; m <= 127; m++) {
      expect(pitchFromMidi(m).midiNumber, m, reason: 'midi $m');
    }
  });

  test('spells the well-known anchors', () {
    expect(pitchFromMidi(60), const Pitch(Step.c)); // middle C (octave 4)
    expect(pitchFromMidi(69), const Pitch(Step.a)); // A440 (octave 4)
    expect(pitchFromMidi(21).midiNumber, 21); // A0, the lowest piano key
    expect(pitchFromMidi(108).midiNumber, 108); // C8, the highest piano key
  });

  test('naturals stay natural; every octave lands on C', () {
    for (var octave = 0; octave <= 9; octave++) {
      final c = 12 * (octave + 1); // C-1=0, C4=60 …
      if (c > 127) break;
      final pitch = pitchFromMidi(c);
      expect(pitch.step, Step.c, reason: 'midi $c should be a C');
      expect(pitch.alter, 0, reason: 'midi $c should be natural');
      expect(pitch.octave, octave);
    }
  });

  test('never throws, even outside the MIDI range', () {
    for (var m = -24; m <= 200; m++) {
      expect(() => pitchFromMidi(m), returnsNormally, reason: 'midi $m');
    }
  });
}
