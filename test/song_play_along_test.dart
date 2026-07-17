// chartFromScore — derive a sing-along PlayAlongChart from a song's notation.
// Melody = the top pitch of each sounded note; timing in quarter-beats from the
// playback timeline (rests leave gaps); tempo from the score, octave-agnostic.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/games/songs/song_play_along.dart';

const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);

Score _score(List<MusicElement> elements, {Tempo? tempo}) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      tempo: tempo,
      measures: [Measure(elements)],
    );

void main() {
  test('a note, a rest, then a chord → two targets with a gap', () {
    final score = _score(
      [
        NoteElement(pitches: [_p(Step.c)], duration: _quarter, id: 'e0'),
        const RestElement(_quarter, id: 'e1'),
        NoteElement(
          pitches: [_p(Step.e), _p(Step.g)], // a chord
          duration: _half,
          id: 'e2',
        ),
      ],
      tempo: const Tempo(90),
    );

    final chart = chartFromScore(score, name: 'Test');

    expect(chart.notes, hasLength(2), reason: 'the rest is not a target');
    // The C quarter: beat 0, one quarter-beat long.
    expect(chart.notes[0].midi, 60); // C4
    expect(chart.notes[0].startBeat, 0);
    expect(chart.notes[0].beats, 1);
    // The chord: the melody is its TOP pitch (G4), after C(1) + rest(1) = beat 2,
    // a half note = 2 quarter-beats.
    expect(chart.notes[1].midi, 67, reason: 'top of the chord is the melody');
    expect(chart.notes[1].startBeat, 2);
    expect(chart.notes[1].beats, 2);
  });

  test('playing an instrument targets the written octave', () {
    final chart = chartFromScore(
      _score(
        [
          NoteElement(pitches: [_p(Step.d)], duration: _quarter, id: 'e0'),
        ],
      ),
      name: 'Test',
      octaveAgnostic: false,
    );
    expect(
      chart.octaveAgnostic,
      isFalse,
      reason: 'the written octave IS the target when playing',
    );
  });

  test('tempo comes from the score; singing is octave-agnostic', () {
    final chart = chartFromScore(
      _score(
        [
          NoteElement(pitches: [_p(Step.d)], duration: _quarter, id: 'e0'),
        ],
        tempo: const Tempo(72),
      ),
      name: 'Test',
    );
    expect(chart.bpm, 72);
    expect(chart.octaveAgnostic, isTrue);
  });

  test('no tempo → 100 bpm; an override wins', () {
    final notes = [
      NoteElement(pitches: [_p(Step.d)], duration: _quarter, id: 'e0'),
    ];
    expect(chartFromScore(_score(notes), name: 'x').bpm, 100);
    expect(
      chartFromScore(_score(notes), name: 'x', bpmOverride: 140).bpm,
      140,
    );
  });

  test('an all-rest score yields no singable targets', () {
    final chart = chartFromScore(
      _score(const [
        RestElement(_quarter, id: 'e0'),
        RestElement(_quarter, id: 'e1'),
      ]),
      name: 'Test',
    );
    expect(chart.notes, isEmpty);
  });
}
