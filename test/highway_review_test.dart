// test/highway_review_test.dart
//
// Matching a recording to the written music. This is the whole musical question
// behind record-and-review, so it is tested without a microphone or a model.

import 'package:comet_beat/core/audio/transcription/contracts.dart'
    show NoteEvent;
import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_grading.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/core/games/highway/highway_review.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEvent _heard(int midi, double onMs) =>
    (midi: midi, onMs: onMs, offMs: onMs + 200, confidence: 1);

const _events = [
  HighwayEvent(startBeat: 0, beats: 1, midi: 60),
  HighwayEvent(startBeat: 1, beats: 1, midi: 62),
  HighwayEvent(startBeat: 2, beats: 1, midi: 64),
];

Set<int> _match(List<NoteEvent> heard, {double windowMs = 250}) =>
    matchHeardToChart(
      events: _events,
      heard: heard,
      beatMs: 500,
      startOffsetMs: 2000, // a four-beat count-in at 120 bpm
      windowMs: windowMs,
    );

void main() {
  test('a take played correctly matches every note', () {
    expect(
      _match([_heard(60, 2000), _heard(62, 2500), _heard(64, 3000)]),
      {0, 1, 2},
    );
  });

  test(
      'the count-in offset is respected — the same notes played at t=0 match '
      'nothing', () {
    expect(_match([_heard(60, 0), _heard(62, 500)]), isEmpty);
  });

  test('a note played late beyond the window does not count', () {
    expect(_match([_heard(60, 2000 + 300)]), isEmpty);
    expect(_match([_heard(60, 2000 + 200)]), {0});
  });

  test('one heard note cannot answer for two written ones', () {
    const repeated = [
      HighwayEvent(startBeat: 0, beats: 1, midi: 60),
      HighwayEvent(startBeat: 0.2, beats: 1, midi: 60),
    ];
    final matched = matchHeardToChart(
      events: repeated,
      heard: [_heard(60, 2000)],
      beatMs: 500,
      startOffsetMs: 2000,
      windowMs: 250,
    );
    expect(matched.length, 1, reason: 'a single strike is a single note');
  });

  test('it goes to the NEAREST written note, not the first listed', () {
    const two = [
      HighwayEvent(startBeat: 0, beats: 1, midi: 60),
      HighwayEvent(startBeat: 0.4, beats: 1, midi: 60),
    ];
    final matched = matchHeardToChart(
      events: two,
      heard: [_heard(60, 2200)], // 0.4 beats in — the second one
      beatMs: 500,
      startOffsetMs: 2000,
      windowMs: 250,
    );
    expect(matched, {1});
  });

  test('extra notes the player added are ignored, not punished', () {
    // The transcriber also heard a pedal thump and a wrong note.
    expect(
      _match([_heard(60, 2000), _heard(71, 2100), _heard(62, 2500)]),
      {0, 1},
    );
  });

  test('a wrong pitch is simply not a match', () {
    expect(_match([_heard(61, 2000)]), isEmpty);
  });

  test('the grader takes the verdict for the whole take', () {
    const chart = HighwayChart(name: 'x', bpm: 120, events: _events);
    final grader = HighwayGrader(
      chart: chart,
      rules: HighwayRules.of(HighwayDifficulty.easy),
      laneMap: KeyboardLaneMap.forRange(48, 84),
    )..applyReview({0, 2});
    expect(grader.hits, 2);
    expect(grader.misses, 1);
    expect(grader.gradedNotes[1].state, HighwayNoteState.missed);
    expect(grader.finished, isTrue);
  });
}
