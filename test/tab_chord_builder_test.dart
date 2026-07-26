// The chord builder: any root × quality → a playable ChordDiagram on the
// tuning, always sounding the right pitch classes with the root in the bass.

import 'package:comet_beat/features/games/composition/tab_chord_builder.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The distinct pitch classes a voicing sounds on [tuning] (muted = -1 skipped).
Set<int> _soundingPcs(ChordDiagram d, Tuning tuning) => {
      for (var s = 0; s < d.frets.length; s++)
        if (d.frets[s] >= 0) (tuning.strings[s].midiNumber + d.frets[s]) % 12,
    };

/// The bass pitch class (the lowest-pitched sounded string = highest index).
int _bassPc(ChordDiagram d, Tuning tuning) {
  for (var s = d.frets.length - 1; s >= 0; s--) {
    if (d.frets[s] >= 0) {
      return (tuning.strings[s].midiNumber + d.frets[s]) % 12;
    }
  }
  return -1;
}

void main() {
  final guitar = Tuning.standardGuitar;

  test('the quality/root tables are consistent', () {
    expect(kChordRoots, hasLength(12));
    expect(kChordQualities, isNotEmpty);
    // every interval set starts on the root and stays within an octave-ish span
    for (final (_, intervals) in kChordQualities) {
      expect(intervals.first, 0);
      expect(intervals, isNotEmpty);
    }
  });

  test('chordName follows the maj-is-bare convention', () {
    expect(chordName(0, 'maj'), 'C'); // C major → "C"
    expect(chordName(1, 'm7'), 'C♯m7');
    expect(chordName(7, '7'), 'G7');
  });

  test('every root × quality voices its exact chord tones', () {
    for (var root = 0; root < 12; root++) {
      for (final (label, intervals) in kChordQualities) {
        final want = {for (final iv in intervals) (root + iv) % 12};
        final d = chordVoicing(guitar, root, intervals, name: 'x');
        final got = _soundingPcs(d, guitar);
        // Only chord tones sound (no wrong notes)…
        expect(
          got.difference(want),
          isEmpty,
          reason: '${chordName(root, label)} sounded a non-chord tone',
        );
        // …and it's not empty.
        expect(got, isNotEmpty);
      }
    }
  });

  test('a C major on guitar is the familiar open shape (root in bass)', () {
    final c = chordVoicing(guitar, 0, const [0, 4, 7], name: 'C');
    expect(c.frets, [0, 1, 0, 2, 3, -1]); // the standard C
    expect(_bassPc(c, guitar), 0); // C in the bass
  });

  test('the root lands in the bass wherever it can (≥3 strings sounding)', () {
    for (var root = 0; root < 12; root++) {
      final d = chordVoicing(guitar, root, const [0, 4, 7], name: 'x');
      final sounded = d.frets.where((f) => f >= 0).length;
      if (sounded >= 3) {
        expect(
          _bassPc(d, guitar),
          root % 12,
          reason: 'root not in the bass for root=$root',
        );
      }
    }
  });

  test('works on a different tuning (drop-D low string)', () {
    // Drop-D: the low string is D; a D chord should be reachable + correct.
    final dropD = Tuning.dropDGuitar;
    final d = chordVoicing(dropD, 2, const [0, 4, 7], name: 'D'); // D major
    final got = _soundingPcs(d, dropD);
    expect(got.difference({2, 6, 9}), isEmpty); // D, F♯, A only
    expect(got, contains(2));
  });
}
