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

  test('travis roll alternates bass and treble over eight eighths', () {
    final cols = patternColumns(cMajor, PickPattern.travis);
    expect(cols, hasLength(8));
    expect(cols.every((c) => c.duration == NoteDuration.eighth), isTrue);
    // Even steps are the bass (lowest string = highest index in an open C);
    // odd steps are treble (a higher string / lower index).
    final voices = chordVoices(cMajor);
    final low = voices.last;
    for (var i = 0; i < cols.length; i += 2) {
      expect(
        cols[i].frets.keys.single,
        greaterThanOrEqualTo(voices[voices.length - 2]),
        reason: 'step $i should be a bass string',
      );
    }
    expect(cols[0].frets.keys.single, low); // first pluck is the root bass
    expect(cols[1].frets.keys.single, voices.first); // then the top string
  });

  test('boom-chuck is bass, strum, alt-bass, strum in quarters', () {
    final cols = patternColumns(cMajor, PickPattern.boomChuck);
    expect(cols, hasLength(4));
    expect(cols.every((c) => c.duration == NoteDuration.quarter), isTrue);
    expect(cols[0].frets.length, 1); // boom = single bass
    expect(cols[1].frets.length, greaterThan(1)); // chuck = full strum
    expect(cols[3].frets.length, greaterThan(1));
  });

  test('eighths strum is eight full chords', () {
    final cols = patternColumns(cMajor, PickPattern.strumEighths);
    final voices = chordVoices(cMajor);
    expect(cols, hasLength(8));
    expect(cols.every((c) => c.frets.length == voices.length), isTrue);
    expect(cols.every((c) => c.duration == NoteDuration.eighth), isTrue);
  });

  test('island strum leaves rests in the syncopation', () {
    final cols = patternColumns(cMajor, PickPattern.islandStrum);
    expect(cols, hasLength(8));
    // Pattern D · D U · U D U → two rests (empty columns) at steps 1 and 4.
    final rests = [
      for (var i = 0; i < cols.length; i++)
        if (cols[i].frets.isEmpty) i,
    ];
    expect(rests, [1, 4]);
  });

  test('chordStyleColumns routes each style to its generator', () {
    expect(
      chordStyleColumns(cMajor, ChordStyle.strum, q).length,
      strumColumns(cMajor, q).length,
    );
    expect(
      chordStyleColumns(cMajor, ChordStyle.up, q).length,
      arpeggioColumns(cMajor, ArpStyle.up, q).length,
    );
    expect(
      chordStyleColumns(cMajor, ChordStyle.travis, q).length,
      patternColumns(cMajor, PickPattern.travis).length,
    );
  });

  test('progression strums one column per chord, repeated', () {
    final pop = kProgressions['Pop (C–G–Am–F)']!; // 4 chords
    final once = progressionColumns(pop, kGuitarChords, ChordStyle.strum, q);
    expect(once, hasLength(4));
    expect(once.every((c) => c.chord != null), isTrue); // strum keeps the badge
    final twice =
        progressionColumns(pop, kGuitarChords, ChordStyle.strum, q, repeat: 2);
    expect(twice, hasLength(8));
    // Repeats must be fresh instances, never shared (later edits mutate frets).
    expect(identical(twice[0], twice[4]), isFalse);
  });

  test('progression skips chords missing from the library', () {
    final cols = progressionColumns(
      ['C', 'Zz', 'G'],
      kGuitarChords,
      ChordStyle.strum,
      q,
    );
    expect(cols, hasLength(2)); // Zz dropped
  });

  test('new dominant-7th voicings spell the right chord tones', () {
    Set<int> pcs(String name) {
      final col = strumColumns(kGuitarChords[name]!, q).single;
      return {
        for (final e in col.frets.entries)
          (guitar.strings[e.key].midiNumber + e.value) % 12,
      };
    }

    expect(pcs('G7'), {7, 11, 2, 5}); // G B D F
    expect(pcs('C7'), {0, 4, 10}); // C E B♭ (5th omitted — common open voicing)
    expect(pcs('B7'), {11, 3, 6, 9}); // B D♯ F♯ A
  });

  test('blues in E uses the B7 dominant and strums 12 bars', () {
    final e = kProgressions['Blues in E (12-bar)']!;
    expect(e, contains('B7'));
    final cols = progressionColumns(e, kGuitarChords, ChordStyle.strum, q);
    expect(cols, hasLength(12));
  });

  test('every built-in progression resolves to real chords', () {
    for (final chords in kProgressions.values) {
      expect(
        chords.every(kGuitarChords.containsKey),
        isTrue,
        reason: 'a progression names a chord not in the library',
      );
    }
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
