// Exporting one instrument's part from an ensemble score: the part alone,
// its silent stretches drawn as multi-bar rests as a player's part prints.

import 'package:comet_beat/shared/music_io/music_export.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Score _part(List<bool> playing) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        for (var b = 0; b < playing.length; b++)
          Measure([
            if (playing[b])
              NoteElement.note(
                const Pitch(Step.c, octave: 5),
                NoteDuration.whole,
                id: 'b$b',
              )
            else
              RestElement(NoteDuration.whole, id: 'r$b'),
          ]),
      ],
    );

void main() {
  final duet = MultiPartScore([
    _part([true, true, true, true, true]),
    _part([true, false, false, false, true]),
  ]);

  test('a part exports alone', () {
    final part = partForExport(duet, 1);
    expect(part.parts, hasLength(1));
  });

  test('its silent bars print as one multi-bar rest', () {
    final bars = partForExport(duet, 1).parts.single.measures;
    expect([for (final m in bars) m.multiRest], [null, 3, null]);
  });

  test('a part that always plays is unchanged', () {
    final bars = partForExport(duet, 0).parts.single.measures;
    expect(bars, hasLength(5));
  });
}
