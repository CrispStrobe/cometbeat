// test/highway_chart_test.dart
//
// The highway's data model: a score becomes polyphonic falling blocks with
// their hands intact, and a chart can be re-tempoed, filtered by hand, and
// turned into a gap-accurate backing track.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-measure score: a C-major triad on beat 1 (voice 1) and two quarter
/// notes in voice 2, with ids assigned as builders must.
Score _twoVoiceScore() => const Score(
      clef: Clef.treble,
      measures: [
        Measure(
          [
            NoteElement(
              id: 'e0',
              pitches: [
                Pitch(Step.c),
                Pitch(Step.e),
                Pitch(Step.g),
              ],
              duration: NoteDuration(DurationBase.half),
            ),
            NoteElement(
              id: 'e1',
              pitches: [Pitch(Step.d)],
              duration: NoteDuration(DurationBase.half),
            ),
          ],
          voice2: [
            NoteElement(
              id: 'e2',
              pitches: [Pitch(Step.c, octave: 3)],
              duration: NoteDuration(DurationBase.quarter),
            ),
            RestElement(
              NoteDuration(DurationBase.quarter),
              id: 'e3',
            ),
            NoteElement(
              id: 'e4',
              pitches: [Pitch(Step.g, octave: 2)],
              duration: NoteDuration(DurationBase.half),
            ),
          ],
        ),
      ],
      timeSignature: TimeSignature(4, 4),
      tempo: Tempo(80),
    );

void main() {
  group('highwayChartFromScore', () {
    test('keeps every pitch of a chord, not just the top note', () {
      final chart = highwayChartFromScore(_twoVoiceScore(), name: 'x');
      final onBeatZero = chart.events
          .where((e) => e.startBeat == 0 && e.voice == 0)
          .map((e) => e.midi)
          .toList()
        ..sort();
      expect(onBeatZero, [60, 64, 67]); // C4 E4 G4 — a real chord, not a line
    });

    test('separates the written voices, so hands stay distinguishable', () {
      final chart = highwayChartFromScore(_twoVoiceScore(), name: 'x');
      expect(chart.voices, [0, 1]);
      final low = chart.events.where((e) => e.voice == 1).map((e) => e.midi);
      expect(low, containsAll([48, 43]));
    });

    test('rests leave gaps rather than blocks', () {
      final chart = highwayChartFromScore(_twoVoiceScore(), name: 'x');
      // Voice 2: C3 at beat 0, rest at 1, G2 at 2.
      final v2 = chart.events.where((e) => e.voice == 1).toList()
        ..sort((a, b) => a.startBeat.compareTo(b.startBeat));
      expect(v2.map((e) => e.startBeat), [0, 2]);
    });

    test('takes tempo and meter from the score', () {
      final chart = highwayChartFromScore(_twoVoiceScore(), name: 'x');
      expect(chart.bpm, 80);
      expect(chart.beatsPerBar, 4);
    });

    test('an override wins over the score tempo', () {
      final chart =
          highwayChartFromScore(_twoVoiceScore(), name: 'x', bpmOverride: 60);
      expect(chart.bpm, 60);
    });

    test('an empty score yields an empty chart, not a crash', () {
      final chart = highwayChartFromScore(
        const Score(clef: Clef.treble, measures: [Measure([])]),
        name: 'empty',
      );
      expect(chart.isEmpty, isTrue);
      expect(chart.lowMidi, isNull);
      expect(chart.totalBeats, 0);
    });
  });

  group('HighwayChart', () {
    const chart = HighwayChart(
      name: 'c',
      bpm: 120,
      events: [
        HighwayEvent(startBeat: 0, beats: 1, midi: 60),
        HighwayEvent(startBeat: 0, beats: 1, midi: 64),
        HighwayEvent(startBeat: 2, beats: 2, midi: 67, voice: 1),
      ],
    );

    test('columns group simultaneous notes into chords', () {
      final columns = chart.columns();
      expect(columns.length, 2);
      expect(columns.first.length, 2);
      expect(columns.last.single.midi, 67);
    });

    test('atTempo changes only the tempo, never the music', () {
      final slow = chart.atTempo(60);
      expect(slow.bpm, 60);
      expect(slow.events, same(chart.events));
      expect(slow.totalBeats, chart.totalBeats);
    });

    test('onlyVoices keeps the original timing of what is left', () {
      final right = chart.onlyVoices({1});
      expect(right.events.length, 1);
      expect(right.events.single.startBeat, 2); // not re-zeroed
    });

    test('eventsAt reports what is sounding, for the key lighting', () {
      expect(chart.eventsAt(0.5).length, 2);
      expect(chart.eventsAt(1.5), isEmpty);
      expect(chart.eventsAt(2.0).single.midi, 67);
    });

    test('timedChords renders the gap between notes as a rest', () {
      final timed = chart.timedChords();
      // chord (1 beat = 500 ms) · rest (1 beat) · note (2 beats)
      expect(timed.length, 3);
      expect(timed[0].$1..sort(), [60, 64]);
      expect(timed[0].$2, 500);
      expect(timed[1].$1, isEmpty);
      expect(timed[1].$2, 500);
      expect(timed[2].$1, [67]);
      expect(timed[2].$2, 1000);
    });

    test('columns survive a chart written one voice after another', () {
      // How a two-hand piece is actually authored: the melody, then the
      // accompaniment — NOT in time order.
      const unordered = HighwayChart(
        name: 'hands',
        bpm: 60,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 72),
          HighwayEvent(startBeat: 1, beats: 1, midi: 74),
          HighwayEvent(startBeat: 0, beats: 1, midi: 48, voice: 1),
          HighwayEvent(startBeat: 1, beats: 1, midi: 50, voice: 1),
        ],
      );
      final columns = unordered.columns();
      expect(columns.length, 2, reason: 'one column per beat, not per hand');
      expect(columns.first.map((e) => e.midi).toSet(), {72, 48});
      expect(columns.last.map((e) => e.midi).toSet(), {74, 50});
      // …and therefore the backing track is in time order too.
      expect(unordered.timedChords().length, 2);
    });

    test('timedChords can play one hand — the other one you are practising',
        () {
      final backing = chart.timedChords(keep: {1});
      expect(backing.map((e) => e.$1).expand((e) => e), [67]);
    });
  });

  group('sections (drilling a few bars)', () {
    const piece = HighwayChart(
      name: 'four bars',
      bpm: 100,
      events: [
        HighwayEvent(startBeat: 0, beats: 1, midi: 60), // bar 1
        HighwayEvent(startBeat: 4, beats: 1, midi: 62), // bar 2
        HighwayEvent(startBeat: 8, beats: 1, midi: 64), // bar 3
        HighwayEvent(startBeat: 12, beats: 1, midi: 65), // bar 4
      ],
    );

    test('counts its bars', () {
      expect(piece.barCount, 4);
      expect(piece.beatOfBar(1), 0);
      expect(piece.beatOfBar(3), 8);
    });

    test('takes exactly the bars asked for, inclusive', () {
      final middle = piece.section(2, 3);
      expect(middle.events.map((e) => e.midi), [62, 64]);
    });

    test('does NOT re-zero the timing — a section stays in the piece’s own '
        'coordinates so it still lines up with the whole', () {
      final middle = piece.section(2, 3);
      expect(middle.events.first.startBeat, 4);
      expect(middle.beatsPerBar, piece.beatsPerBar);
      expect(middle.bpm, piece.bpm);
    });

    test('a one-bar section is legal, and an empty one is not a crash', () {
      expect(piece.section(4, 4).events.map((e) => e.midi), [65]);
      expect(piece.section(9, 12).isEmpty, isTrue);
    });

    test('a pickup counts as part of bar 1', () {
      const withPickup = HighwayChart(
        name: 'anacrusis',
        bpm: 100,
        pickupBeats: 1,
        events: [
          HighwayEvent(startBeat: 0, beats: 1, midi: 67), // the pickup
          HighwayEvent(startBeat: 1, beats: 1, midi: 60), // bar 1 downbeat
          HighwayEvent(startBeat: 5, beats: 1, midi: 62), // bar 2
        ],
      );
      expect(withPickup.beatOfBar(1), 1);
      expect(withPickup.section(1, 1).events.map((e) => e.midi), [60]);
    });
  });

  group('highwayChartFromParts', () {
    test('gives each part its own voice, so the colours separate', () {
      const part = Score(
        clef: Clef.treble,
        measures: [
          Measure(
            [
              NoteElement(
                id: 'a',
                pitches: [Pitch(Step.c)],
                duration: NoteDuration(DurationBase.whole),
              ),
            ],
          ),
        ],
      );
      const other = Score(
        clef: Clef.bass,
        measures: [
          Measure(
            [
              NoteElement(
                id: 'b',
                pitches: [Pitch(Step.g, octave: 2)],
                duration: NoteDuration(DurationBase.whole),
              ),
            ],
          ),
        ],
      );
      final chart = highwayChartFromParts([part, other], name: 'duo');
      expect(chart.voices, [0, 1]);
      expect(
        chart.events.firstWhere((e) => e.voice == 1).midi,
        43,
      );
    });

    test('no parts is an empty chart', () {
      expect(highwayChartFromParts(const [], name: 'x').isEmpty, isTrue);
    });
  });
}
