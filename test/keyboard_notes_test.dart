// test/keyboard_notes_test.dart
//
// The computer-keyboard piano, shared by the Advanced Tracker and the Note
// Highway. It was a private const in the tracker until a second surface needed
// it; these tests exist so the two can never drift apart about which key plays
// which note.

import 'package:comet_beat/shared/keyboard_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lower row is the naturals of the base octave', () {
    // Z X C V B N M , = C D E F G A B C — a piano's white keys.
    expect(midiForKey('z', baseOctave: 4), 60); // C4
    expect(midiForKey('x', baseOctave: 4), 62);
    expect(midiForKey('c', baseOctave: 4), 64);
    expect(midiForKey('v', baseOctave: 4), 65);
    expect(midiForKey('b', baseOctave: 4), 67);
    expect(midiForKey('n', baseOctave: 4), 69);
    expect(midiForKey('m', baseOctave: 4), 71);
    expect(midiForKey(',', baseOctave: 4), 72);
  });

  test('the row above carries the sharps, where a piano puts them', () {
    expect(midiForKey('s', baseOctave: 4), 61); // C#4, above Z and X
    expect(midiForKey('d', baseOctave: 4), 63);
    expect(midiForKey('g', baseOctave: 4), 66);
    // …and there is deliberately no key between E and F, as on a piano.
    expect(semitoneForKey('f'), isNull);
  });

  test('QWERTY is the octave above', () {
    expect(midiForKey('q', baseOctave: 4), 72); // C5
    expect(midiForKey('i', baseOctave: 4), 84); // C6
  });

  test('the anchor moves the whole keyboard', () {
    expect(midiForKey('z', baseOctave: 2), 36);
    expect(midiForKey('z', baseOctave: 6), 84);
  });

  test('caps lock is not a musical decision', () {
    expect(midiForKey('Z', baseOctave: 4), midiForKey('z', baseOctave: 4));
  });

  test('a key that plays nothing says so, and nothing goes out of range', () {
    expect(midiForKey('/', baseOctave: 4), isNull);
    expect(midiForKey('i', baseOctave: 8), isNull, reason: 'past MIDI 127');
  });

  test('the label is the key nearest the hand where two rows overlap', () {
    // C5 is both ',' +12 on the lower row and 'q' on the upper one.
    expect(keyLabelForMidi(72, baseOctave: 4), ',');
    expect(keyLabelForMidi(60, baseOctave: 4), 'Z');
    expect(keyLabelForMidi(59, baseOctave: 4), isNull);
  });
}
