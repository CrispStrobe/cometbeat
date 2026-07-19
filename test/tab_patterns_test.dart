// Generative tab patterns — strum/arpeggio/scale generators (tab_patterns.dart).
// Pure: no widgets, no mic. Verifies the columns a chord or scale expands into.

import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_patterns.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guitar = Tuning.standardGuitar;
  const q = NoteDuration.quarter;
  final cMajor = kGuitarChords['C']!; // [0, 1, 0, 2, 3, -1]

  test('chordVoices drops muted strings, keeps index order', () {
    // Index 5 (low E) is muted (-1) in an open C; the rest sound.
    expect(chordVoices(cMajor), [0, 1, 2, 3, 4]);
  });

  test('strum is one column of every sounding string, chord attached', () {
    final cols = strumColumns(cMajor, q);
    expect(cols, hasLength(1));
    expect(cols.single.frets.keys.toSet(), {0, 1, 2, 3, 4});
    expect(cols.single.frets[3], 2); // string 3 → fret 2
    expect(cols.single.chord?.name, 'C');
    expect(cols.single.duration, q);
  });

  test('arpeggio up ascends in pitch, one string per column', () {
    final cols = arpeggioColumns(cMajor, ArpStyle.up, q);
    expect(cols, hasLength(5));
    // Every column sounds exactly one string, no chord badge.
    expect(cols.every((c) => c.frets.length == 1), isTrue);
    expect(cols.every((c) => c.chord == null), isTrue);
    // Reconstruct each note's pitch; "up" must be strictly ascending.
    final midis = [
      for (final c in cols)
        guitar.strings[c.frets.keys.first].midiNumber + c.frets.values.first,
    ];
    for (var i = 1; i < midis.length; i++) {
      expect(midis[i], greaterThan(midis[i - 1]));
    }
  });

  test('arpeggio down is the reverse of up', () {
    final up = arpeggioColumns(cMajor, ArpStyle.up, q);
    final down = arpeggioColumns(cMajor, ArpStyle.down, q);
    expect(
      down.map((c) => c.frets.keys.first).toList(),
      up.reversed.map((c) => c.frets.keys.first).toList(),
    );
  });

  test('up-down bounces without repeating the turning note', () {
    final voices = chordVoices(cMajor); // 5 strings
    final ud = arpeggioColumns(cMajor, ArpStyle.upDown, q);
    // up (5) + down minus the shared peak (4) = 9.
    expect(ud, hasLength(voices.length * 2 - 1));
    // First and last are the low string; the peak (high string) appears once.
    expect(ud.first.frets.keys.first, ud.last.frets.keys.first);
  });

  test('scale run ascends by the interval set and lands on the octave', () {
    // C major from C3 (MIDI 48), one octave.
    final cols = scaleColumns(guitar, 48, kScales['Major']!, q);
    final midis = [
      for (final c in cols)
        guitar.strings[c.frets.keys.first].midiNumber + c.frets.values.first,
    ];
    // 7 scale degrees + the closing octave, all reachable on a guitar.
    expect(midis, [48, 50, 52, 53, 55, 57, 59, 60]);
    expect(cols.every((c) => c.frets.length == 1), isTrue);
    expect(cols.every((c) => c.duration == q), isTrue);
  });

  test('scale descending reverses the run', () {
    final up = scaleColumns(guitar, 48, kScales['Minor pentatonic']!, q);
    final down = scaleColumns(
      guitar,
      48,
      kScales['Minor pentatonic']!,
      q,
      descending: true,
    );
    int midi(TabColumn c) =>
        guitar.strings[c.frets.keys.first].midiNumber + c.frets.values.first;
    expect(down.map(midi).toList(), up.map(midi).toList().reversed.toList());
  });

  test('two octaves spans a wider range', () {
    final one = scaleColumns(guitar, 48, kScales['Major pentatonic']!, q);
    final two =
        scaleColumns(guitar, 48, kScales['Major pentatonic']!, q, octaves: 2);
    expect(two.length, greaterThan(one.length));
  });
}
