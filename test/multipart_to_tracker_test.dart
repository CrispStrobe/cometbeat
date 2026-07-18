// The shared MultiPartScore -> TrackerSong bridge (used by the Advanced Tracker
// score import AND the Loop Mixer "open in Tracker" interconnection).

import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Score melody() => const Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch(Step.c)],
              duration: NoteDuration.quarter,
            ),
            NoteElement(
              pitches: [Pitch(Step.e)],
              duration: NoteDuration.quarter,
            ),
          ]),
        ],
      );

  test('one channel per part, notes carried', () {
    final song = trackerSongFromMultiPart(
      MultiPartScore([melody(), melody()]),
    );
    expect(song.channels.length, 2);
    final notes = song.patterns
        .expand((p) => p.cells)
        .expand((c) => c)
        .where((c) => c.midi != null)
        .length;
    expect(notes, greaterThan(0));
  });

  test('a single part -> one channel with notes', () {
    final song = trackerSongFromMultiPart(MultiPartScore([melody()]));
    expect(song.channels.length, 1);
    expect(
      song.patterns
          .expand((p) => p.cells)
          .expand((c) => c)
          .where((c) => c.midi != null),
      isNotEmpty,
    );
  });
}
