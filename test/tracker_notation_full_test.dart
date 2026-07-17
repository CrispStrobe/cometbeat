// Maximal Tracker ↔ Score — the contract/spec for the multi-channel notation
// bridge. The Score agent ADDS these functions to tracker_notation.dart (leaving
// the existing trackerChannelToScore / scoreToTrackerCells intact):
//
//   List<Score> trackerToScoreParts(List<TrackerChannel> channels,
//       TrackerTiming timing);
//     • One Score per PITCHED channel that has notes (empty channels and
//       PercussionInstrument channels are skipped). The 'bass' channel uses
//       Clef.bass; all others Clef.treble. Reuse trackerChannelToScore per part.
//
//   List<List<TrackerCell>> scoreToChannels(Score score, TrackerTiming timing,
//       {int channelCount = 4, bool snapToScale = true});
//     • Split polyphony across channels: for each element, its pitches sorted
//       HIGH→LOW fill channels 0,1,2,… (channel 0 = the top voice). Monophonic
//       notes go to channel 0 only. Same quantize + pentatonic-snap rules as
//       scoreToTrackerCells. Returns exactly [channelCount] cell-lists, each of
//       length timing.rows.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/synth.dart' show Instrument;
import 'package:klang_universum/core/audio/tracker_engine.dart';
import 'package:klang_universum/features/games/composition/tracker_notation.dart';

TrackerChannel _ch(
  String id,
  Instrument inst,
  int rows,
  List<(int, int)> notes,
) {
  final c = TrackerChannel(
    id: id,
    instrument: AdditiveInstrument(id, inst),
    rows: rows,
  );
  for (final (row, midi) in notes) {
    c.cells[row] = TrackerCell(midi: midi);
  }
  return c;
}

void main() {
  const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);

  group('trackerToScoreParts (all channels → notation)', () {
    test('one Score per pitched non-empty channel; bass gets a bass clef', () {
      final channels = [
        _ch('melody', Instrument.piano, 8, const [(0, 60)]),
        _ch('bass', Instrument.cello, 8, const [(0, 48)]),
        _ch('pad', Instrument.flute, 8, const []), // empty → skipped
        TrackerChannel(
          id: 'drums',
          instrument: const PercussionInstrument('drums'),
          rows: 8,
        )..cells[0] = const TrackerCell(midi: 0), // percussion → skipped
      ];
      final parts = trackerToScoreParts(channels, timing);
      expect(parts.length, 2); // melody + bass only
      expect(parts[0].measures.first.elements.first, isA<NoteElement>());
      expect(
        (parts[0].measures.first.elements.first as NoteElement)
            .pitches
            .single
            .midiNumber,
        60,
      );
      expect(parts[1].clef, Clef.bass);
    });
  });

  group('scoreToChannels (polyphony → channels)', () {
    Score chordScore() => const Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement(
                pitches: [Pitch(Step.c), Pitch(Step.e), Pitch(Step.g)],
                duration: NoteDuration.quarter,
              ),
              RestElement(NoteDuration.quarter),
              RestElement(NoteDuration.half),
            ]),
          ],
        );

    test('a chord splits top→down across channels', () {
      final chans = scoreToChannels(chordScore(), timing, channelCount: 3);
      expect(chans.length, 3);
      for (final c in chans) {
        expect(c.length, 8);
      }
      expect(chans[0][0].midi, 67); // G4 (top)
      expect(chans[1][0].midi, 64); // E4
      expect(chans[2][0].midi, 60); // C4
    });

    test('a monophonic score fills only channel 0', () {
      const mono = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(pitches: [Pitch(Step.g)], duration: NoteDuration.whole),
          ]),
        ],
      );
      final chans = scoreToChannels(mono, timing, channelCount: 3);
      expect(chans[0][0].midi, 67);
      expect(chans[1].every((c) => c.isEmpty), isTrue);
      expect(chans[2].every((c) => c.isEmpty), isTrue);
    });
  });
}
