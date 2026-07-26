// The chords-db loader/converter: chords-db positions (low→high, baseFret-
// relative) → our ChordDiagram (high→low, absolute), and lookup by root+quality.

import 'package:comet_beat/features/games/composition/chord_db.dart';
import 'package:flutter_test/flutter_test.dart';

// A tiny chords-db-shaped fixture: C with an open and a barre "major" position.
final _fixture = {
  'keys': ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'],
  'suffixes': ['major', 'minor'],
  'chords': {
    'C': [
      {
        'key': 'C',
        'suffix': 'major',
        'positions': [
          {
            'frets': [-1, 3, 2, 0, 1, 0],
            'baseFret': 1,
            'barres': [],
          },
          {
            'frets': [-1, 1, 3, 3, 3, 1],
            'baseFret': 3,
            'barres': [1],
          },
        ],
      },
    ],
  },
};

void main() {
  test('an open position converts to our high→low absolute order', () {
    final d = diagramFromChordDbPosition(
      {
        'frets': [-1, 3, 2, 0, 1, 0],
        'baseFret': 1,
        'barres': [],
      },
      name: 'C',
    );
    expect(d.frets, [0, 1, 0, 2, 3, -1]); // the standard open C
    expect(d.name, 'C');
  });

  test('a barre position applies baseFret and the barre fret', () {
    final d = diagramFromChordDbPosition(
      {
        'frets': [-1, 1, 3, 3, 3, 1],
        'baseFret': 3,
        'barres': [1],
      },
      name: 'C',
    );
    // low→high [-1,1,3,3,3,1] @baseFret 3 → absolute [-1,3,5,5,5,3] → reversed:
    expect(d.frets, [3, 5, 5, 5, 3, -1]);
    expect(d.baseFret, 3);
    expect(d.barreFret, 3); // barre at fret 1 of the box → absolute fret 3
  });

  test('ChordDb.voicings finds curated positions by root + quality', () {
    final db = ChordDb.fromJson(_fixture);
    final cMaj = db.voicings(0, 'maj'); // C major
    expect(cMaj, hasLength(2)); // the two positions
    expect(cMaj.first.frets, [0, 1, 0, 2, 3, -1]);
    expect(cMaj.first.name, 'C'); // major → bare root name

    // A quality the fixture lacks → empty (caller falls back to algorithmic).
    expect(db.voicings(0, 'm7'), isEmpty);
    // A root the fixture lacks → empty.
    expect(db.voicings(2, 'maj'), isEmpty); // D not in the fixture
  });

  test('the quality→suffix map covers every builder quality it should', () {
    // Spot-check the important mappings (minor uses "minor", not "m").
    expect(kQualityToChordDbSuffix['m'], 'minor');
    expect(kQualityToChordDbSuffix['maj'], 'major');
    expect(kQualityToChordDbSuffix['m7♭5'], 'm7b5');
  });
}
