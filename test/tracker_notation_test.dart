// Tracker → Score notation bridge. Pure Dart: builds a crisp_notation Score from
// a tracker channel and checks the note model (held runs → tied notes decomposed
// into standard values, split at 4/4 bar lines).

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/synth.dart' show Instrument;
import 'package:klang_universum/core/audio/tracker_engine.dart';
import 'package:klang_universum/features/games/composition/tracker_notation.dart';

TrackerChannel _channel(int rows, List<(int, int)> notes) {
  final ch = TrackerChannel(
    id: 't',
    instrument: const AdditiveInstrument('piano', Instrument.piano),
    rows: rows,
  );
  for (final (row, midi) in notes) {
    ch.cells[row] = TrackerCell(midi: midi);
  }
  return ch;
}

void main() {
  group('pitchFromMidi', () {
    test('maps MIDI to scientific pitch (sharp spelling)', () {
      expect(pitchFromMidi(60).midiNumber, 60); // C4
      expect(pitchFromMidi(60).step, Step.c);
      expect(pitchFromMidi(60).octave, 4);
      expect(pitchFromMidi(61).step, Step.c);
      expect(pitchFromMidi(61).alter, 1); // C#4
      expect(pitchFromMidi(62).step, Step.d);
      // Round-trips for a range of notes.
      for (var m = 36; m <= 84; m++) {
        expect(pitchFromMidi(m).midiNumber, m);
      }
    });
  });

  group('trackerChannelToScore', () {
    const timing = TrackerTiming(rows: 8, stepsPerBeat: 2); // one 4/4 bar

    test('an empty channel is a bar of rest', () {
      final score = trackerChannelToScore(_channel(8, const []), timing);
      expect(score.measures.length, 1);
      final els = score.measures.first.elements;
      expect(els.length, 1);
      expect(els.first, isA<RestElement>());
      expect((els.first as RestElement).duration.base, DurationBase.whole);
    });

    test('a lone note rings to the bar end (whole note)', () {
      final score = trackerChannelToScore(_channel(8, const [(0, 60)]), timing);
      final els = score.measures.single.elements;
      expect(els.length, 1);
      final note = els.first as NoteElement;
      expect(note.duration.base, DurationBase.whole);
      expect(note.pitches.single.midiNumber, 60);
      expect(note.tieToNext, isFalse);
    });

    test('two notes split into their held durations', () {
      // C for 2 steps (quarter), then D for 6 steps (dotted half).
      final score =
          trackerChannelToScore(_channel(8, const [(0, 60), (2, 62)]), timing);
      final els = score.measures.single.elements.cast<NoteElement>();
      expect(els.length, 2);
      expect(els[0].duration.base, DurationBase.quarter);
      expect(els[0].duration.dots, 0);
      expect(els[1].duration.base, DurationBase.half);
      expect(els[1].duration.dots, 1);
    });

    test('a note across a bar line is split and tied', () {
      const twoBars = TrackerTiming(stepsPerBeat: 2);
      final score =
          trackerChannelToScore(_channel(16, const [(0, 60)]), twoBars);
      expect(score.measures.length, 2);
      final first = score.measures[0].elements.single as NoteElement;
      final second = score.measures[1].elements.single as NoteElement;
      expect(first.duration.base, DurationBase.whole);
      expect(first.tieToNext, isTrue); // ties into bar 2
      expect(second.duration.base, DurationBase.whole);
      expect(second.tieToNext, isFalse);
    });
  });
}
