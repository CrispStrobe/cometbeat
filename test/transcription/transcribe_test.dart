// S5 integration — NoteEvents + RhythmGrid → a crisp_notation Score, and on to
// MusicXML. Synthetic notes on a known grid, asserting bar packing, durations,
// rests, barline splits and a valid MusicXML render.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEvent _n(
  int midi,
  double on,
  double off, {
  int program = gmProgramUnknown,
}) =>
    (midi: midi, onMs: on, offMs: off, confidence: 1.0, program: program);

// One 4/4 bar at 120 BPM: beats at 0, 500, 1000, 1500, 2000 ms.
const _grid = (
  bpm: 120.0,
  beatMs: [0.0, 500.0, 1000.0, 1500.0, 2000.0],
  onsetMs: <double>[],
);

void main() {
  test('four quarter notes fill one 4/4 bar', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 1500),
        _n(65, 1500, 2000),
      ],
      _grid,
    );

    expect(score.measures, hasLength(1));
    final els = score.measures.first.elements;
    final noteEls = els.whereType<NoteElement>().toList();
    expect(noteEls, hasLength(4));
    expect(
      noteEls.every((n) => n.duration.base == DurationBase.quarter),
      isTrue,
    );
    expect(noteEls.first.pitches.single, const Pitch(Step.c)); // C4
    expect(score.timeSignature?.beats, 4);
    expect(score.tempo?.bpm, 120);
  });

  test('a gap becomes a rest and an eighth is half a beat', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 250), // an eighth on beat 0
        _n(62, 500, 1000), // then a quarter on beat 1 (a gap between)
      ],
      _grid,
    );
    final els = score.measures.first.elements;
    expect(els.first, isA<NoteElement>());
    expect((els.first as NoteElement).duration.base, DurationBase.eighth);
    expect(els.any((e) => e is RestElement), isTrue, reason: 'the gap');
  });

  test('a note across the barline splits into two measures', () {
    const grid2 = (
      bpm: 120.0,
      beatMs: <double>[0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000],
      onsetMs: <double>[],
    );
    // A note from beat 3 to beat 5 crosses the 4/4 barline.
    final score = transcribeToScore([_n(60, 1500, 2500)], grid2);
    expect(score.measures.length, greaterThanOrEqualTo(2));

    // It splits into two note-heads TIED across the barline (one held sound),
    // not two separately re-attacked notes.
    final noteEls = [
      for (final m in score.measures)
        for (final e in m.elements)
          if (e is NoteElement) e,
    ];
    expect(noteEls.length, greaterThanOrEqualTo(2));
    expect(noteEls.first.tieToNext, isTrue, reason: 'held into the next bar');
    expect(noteEls.last.tieToNext, isFalse, reason: 'the note ends here');
  });

  test('the transcribed Score renders valid MusicXML', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 2000),
      ],
      _grid,
    );
    final xml = multiPartToMusicXml(
      MultiPartScore([score]),
      partNames: const ['Melody'],
    );
    expect(xml, contains('<score-partwise'));
    expect(xml, contains('<step>C</step>'));
  });

  test('no notes yields an empty score, never throws', () {
    expect(transcribeToScore(const [], _grid).measures, isEmpty);
  });

  test('simultaneous notes engrave as ONE chord note-head', () {
    // A C-major triad struck together for a beat (the polyphonic case).
    final score = transcribeToScore(
      [_n(60, 0, 500), _n(64, 0, 500), _n(67, 0, 500)],
      _grid,
    );
    final noteEls =
        score.measures.first.elements.whereType<NoteElement>().toList();
    expect(noteEls, hasLength(1), reason: 'one chord, not three notes');
    expect(noteEls.first.pitches, hasLength(3));
    expect(
      noteEls.first.pitches.map((p) => p.midiNumber).toSet(),
      {60, 64, 67},
    );
  });

  test('a sustained note under a moving one is read as chords', () {
    // Bass C held for the whole bar; melody E then G on top.
    final score = transcribeToScore(
      [_n(48, 0, 2000), _n(64, 0, 1000), _n(67, 1000, 2000)],
      _grid,
    );
    final chords = [
      for (final m in score.measures)
        for (final e in m.elements)
          if (e is NoteElement) e.pitches.map((p) => p.midiNumber).toList(),
    ];
    // The bass sounds under both halves: {C,E} then {C,G}.
    expect(chords, contains(unorderedEquals([48, 64])));
    expect(chords, contains(unorderedEquals([48, 67])));
  });

  test('the transcribed Score exports non-silent MIDI (element ids present)',
      () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 1500),
        _n(65, 1500, 2000),
      ],
      _grid,
    );

    // Every pitched element carries an id — scoreToMidi only emits notes it can
    // find by id, so without ids the MIDI export is silent. Regression guard.
    final noteEls =
        score.measures.expand((m) => m.elements).whereType<NoteElement>();
    expect(noteEls, isNotEmpty);
    expect(noteEls.every((n) => n.id != null), isTrue, reason: 'ids for MIDI');

    // Round-trip through a Standard MIDI File: the four pitches read back.
    final back = scoreFromMidi(scoreToMidi(score));
    final pitches = back.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .map((n) => n.pitches.single.midiNumber)
        .toList();
    expect(pitches, [60, 62, 64, 65]);
  });

  test('the transcribed Score serializes to ABC', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 1500),
        _n(65, 1500, 2000),
      ],
      _grid,
    );
    final abc = scoreToAbc(score, title: 'Tune');
    expect(abc, contains('X:1'));
    expect(abc, contains('T:Tune'));
    // Four quarters at the default L:1/8 → each note is 2 units.
    expect(abc, contains('C2 D2 E2 F2'));
  });
}
