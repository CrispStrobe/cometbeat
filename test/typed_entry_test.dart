// Typed entry: an older pupil types music as text — ABC, note names,
// LilyPond — instead of clicking notes in; importTypedMusic recognises which.

import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _midi(MultiPartScore mp) => [
      for (final m in mp.parts.first.measures)
        for (final e in m.elements)
          if (e is NoteElement) e.pitches.first.midiNumber,
    ];

void main() {
  test('note names read as crisp_notation note strings', () {
    final mp = importTypedMusic('c4:q d4 e4 f4 | g4:w');
    expect(_midi(mp), [60, 62, 64, 65, 67]);
    expect(mp.parts.first.measures, hasLength(2));
  });

  test('a full ABC tune reads with its header', () {
    final mp = importTypedMusic('X:1\nT:Scale\nM:4/4\nL:1/4\nK:G\nGABc|d4|');
    expect(_midi(mp), [67, 69, 71, 72, 74]);
  });

  test('ABC notes without a header read in C major', () {
    final mp = importTypedMusic('CDEF GABc|');
    expect(_midi(mp), [60, 62, 64, 65, 67, 69, 71, 72]);
  });

  test('LilyPond reads', () {
    final mp = importTypedMusic(r"\relative c' { c4 d e f }");
    expect(_midi(mp), [60, 62, 64, 65]);
  });

  test('scanner tokens still read', () {
    final mp = importTypedMusic('**kern <b> 4c <b> 4d <b> *-');
    expect(mp.parts, hasLength(1));
  });

  test('nothing typed is an error', () {
    expect(() => importTypedMusic('   '), throwsFormatException);
  });
}
