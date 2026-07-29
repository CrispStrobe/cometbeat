// lib/shared/keyboard_notes.dart
//
// The computer keyboard as a piano — ONE map, shared.
//
// This table started life as a private const inside the Advanced Tracker. When
// the Note Highway needed the same thing (a desktop player has a keyboard, not
// six fingers on glass), the choice was to copy it or to lift it. Copying is
// how two surfaces drift into disagreeing about which key plays a D#, and it is
// the same mistake as authoring the drum grooves twice — so it lives here and
// both import it.
//
// The layout is the FastTracker-2 one every tracker and most DAWs use, and that
// familiarity is the point: two rows of the keyboard span two octaves, with the
// "black keys" on the row above, exactly where they sit on a piano.
//
//     upper octave   2 3   5 6 7        (sharps)
//                   Q W E R T Y U I     (naturals, +12)
//     lower octave   S D   G H J        (sharps)
//                   Z X C V B N M ,     (naturals, +0)
//
// Pure Dart — no Flutter — so anything can use it.

/// Typed character → semitone offset from the current base octave.
const Map<String, int> kKeyToSemitone = <String, int>{
  // Lower octave.
  'z': 0, 's': 1, 'x': 2, 'd': 3, 'c': 4, 'v': 5,
  'g': 6, 'b': 7, 'h': 8, 'n': 9, 'j': 10, 'm': 11, ',': 12,
  // Upper octave.
  'q': 12, '2': 13, 'w': 14, '3': 15, 'e': 16, 'r': 17,
  '5': 18, 't': 19, '6': 20, 'y': 21, '7': 22, 'u': 23, 'i': 24,
};

/// The semitone [character] plays, or null if that key is not part of the
/// keyboard-piano. Case-insensitive, because a player with caps lock on is
/// still trying to play a note.
int? semitoneForKey(String character) =>
    kKeyToSemitone[character.toLowerCase()];

/// The MIDI note [character] plays when the keyboard is anchored at
/// [baseOctave] (0 = the octave starting at C0, so 4 → C4 = MIDI 60).
int? midiForKey(String character, {required int baseOctave}) {
  final semitone = semitoneForKey(character);
  if (semitone == null) return null;
  final midi = (baseOctave + 1) * 12 + semitone;
  return midi < 0 || midi > 127 ? null : midi;
}

/// The letter printed on the key that plays [midi] at [baseOctave], or null
/// when no key does. The FIRST key wins where two overlap (the lower row's C
/// an octave up is also the upper row's C), which is what a player expects to
/// see on the key nearest their hand.
String? keyLabelForMidi(int midi, {required int baseOctave}) {
  final wanted = midi - (baseOctave + 1) * 12;
  for (final entry in kKeyToSemitone.entries) {
    if (entry.value == wanted) return entry.key.toUpperCase();
  }
  return null;
}
