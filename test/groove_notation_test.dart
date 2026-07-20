// Groove → Score engraving (the Loop Mixer's live-notation bridge). Pure
// model tests: pitch spelling, bar packing, duration decomposition, and the
// progression path producing 4 bars.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart' hide isEmpty;

DrumRowsPattern _pattern(Map<Drum, String> rows) {
  final map = {
    for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
  };
  rows.forEach((drum, s) {
    for (var i = 0; i < s.length && i < kPatternSteps; i++) {
      map[drum]![i] = s[i] == 'x';
    }
  });
  return DrumRowsPattern(map);
}

void main() {
  test('pitchFromMidi spells the groove range', () {
    expect(pitchFromMidi(60), const Pitch(Step.c));
    expect(pitchFromMidi(69), const Pitch(Step.a));
    expect(pitchFromMidi(36), const Pitch(Step.c, octave: 2));
    expect(pitchFromMidi(71), const Pitch(Step.b));
    expect(pitchFromMidi(61), const Pitch(Step.c, alter: 1));
  });

  test('drumGrooveScore reduces a beat to one rhythm staff', () {
    // Kick + hat together on step 0; snare on step 4; silent after.
    final pattern = _pattern({
      Drum.kick: 'x',
      Drum.hat: 'x',
      Drum.snare: '....x',
    });
    final score = drumGrooveScore(pattern);
    // 16 eighth-steps = two 4/4 bars.
    expect(score.measures, hasLength(2));
    // Step 0 is a two-note chord (kick F2 + hat G5), not two separate notes.
    final first = score.measures.first.elements.first;
    expect(first, isA<NoteElement>());
    expect((first as NoteElement).pitches, hasLength(2));
    // The snare (C4) lands as a note within bar 1.
    final bar1Notes = score.measures.first.elements.whereType<NoteElement>();
    expect(
      bar1Notes.any((n) => n.pitches.contains(const Pitch(Step.c))),
      isTrue,
    );
    // Bar 2 is all silence → only rests.
    expect(
      score.measures[1].elements.every((e) => e is RestElement),
      isTrue,
    );
  });

  test('cells pack into 4/4 bars with greedy durations', () {
    final score = grooveScore(const [
      (midis: [60], steps: 8), // a whole-note bar
      (midis: null, steps: 3), // dotted-quarter rest
      (midis: [64, 67], steps: 2), // a quarter dyad
      (midis: [69], steps: 3),
    ]);
    expect(score.measures.length, 2);
    final bar1 = score.measures.first.elements;
    expect(bar1.length, 1);
    expect((bar1.first as NoteElement).duration, NoteDuration.whole);

    final bar2 = score.measures[1].elements;
    expect(bar2.first, isA<RestElement>());
    expect(
      (bar2.first as RestElement).duration,
      const NoteDuration(DurationBase.quarter, dots: 1),
    );
    final dyad = bar2[1] as NoteElement;
    expect(dyad.pitches.length, 2);
    expect(dyad.duration, NoteDuration.quarter);
  });

  test('a cell crossing the barline is split', () {
    final score = grooveScore(const [
      (midis: null, steps: 6),
      (midis: [60], steps: 4), // 2 steps in bar 1 + 2 steps in bar 2
      (midis: null, steps: 6),
    ]);
    expect(score.measures.length, 2);
    final tail = score.measures.first.elements.last as NoteElement;
    expect(tail.duration, NoteDuration.quarter);
    final head = score.measures[1].elements.first as NoteElement;
    expect(head.duration, NoteDuration.quarter);
  });

  test('engine cells engrave: vamp = 2 bars, progression = 4 bars', () {
    final engine = LoopEngine();
    final vamp = grooveScore(engine.cellsFor('melody')!);
    expect(vamp.measures.length, 2);

    engine.progression = kProgressions.first;
    final song = grooveScore(engine.cellsFor('bass')!, clef: Clef.bass);
    expect(song.measures.length, 4);
    expect(song.clef, Clef.bass);
    // Bar 2 sits on V: its first note is G2.
    final bar2 = song.measures[1].elements.first as NoteElement;
    expect(bar2.pitches.single, const Pitch(Step.g, octave: 2));

    // Drums are unpitched — nothing to engrave.
    expect(engine.cellsFor('drums'), isNull);
  });

  group('grooveParts (multi-part export)', () {
    String upper(String id) => id.toUpperCase();

    test('no pitched track enabled → null', () {
      final engine = LoopEngine();
      expect(grooveParts(engine, nameOf: upper), isNull);
      // Drums are unpitched: enabling them still engraves nothing.
      engine.toggle('drums');
      expect(grooveParts(engine, nameOf: upper), isNull);
    });

    test('enabled pitched tracks become ordered parts (vamp = 2 bars each)',
        () {
      final engine = LoopEngine();
      // Enable out of priority order; the export must reorder to
      // voice · melody · chords · sparkle · bass.
      engine.toggle('bass');
      engine.toggle('melody');
      engine.toggle('drums'); // unpitched — skipped

      final result = grooveParts(engine, nameOf: upper)!;
      expect(result.partNames, ['MELODY', 'BASS']);
      expect(result.score.parts.length, 2);

      final melody = result.score.parts[0];
      final bass = result.score.parts[1];
      expect(melody.clef, Clef.treble);
      expect(bass.clef, Clef.bass);
      // A free vamp engraves 2 bars per part.
      expect(melody.measures.length, 2);
      expect(bass.measures.length, 2);
    });

    test('a 4-bar progression engraves 4 bars in every part', () {
      final engine = LoopEngine();
      engine.toggle('melody');
      engine.toggle('bass');
      engine.progression = kProgressions.first;

      final result = grooveParts(engine, nameOf: upper)!;
      expect(result.score.parts.length, 2);
      for (final part in result.score.parts) {
        expect(
          part.measures.length,
          4,
          reason: 'progression resolves every part to 4 bars',
        );
      }
    });

    test('the parts round-trip through the multi-part MusicXML writer', () {
      final engine = LoopEngine();
      engine.toggle('melody');
      engine.toggle('chords');

      final result = grooveParts(engine, nameOf: upper)!;
      final xml = multiPartToMusicXml(
        result.score,
        partNames: result.partNames,
      );
      expect(xml, contains('<score-partwise'));
      // Both parts survive as named parts.
      expect(xml, contains('MELODY'));
      expect(xml, contains('CHORDS'));
      // Re-reading the first part yields an engravable score.
      expect(scoreFromMusicXml(xml).measures, isNotEmpty);
    });
  });

  group('drumParts (beat → rhythm-line score)', () {
    String label(Drum d) => d.name;

    test('an empty pattern → null', () {
      expect(drumParts(_pattern(const {}), nameOf: label), isNull);
    });

    test('one part per drum that has a hit, in Drum order', () {
      final result = drumParts(
        _pattern(const {
          Drum.kick: 'x.......x.......',
          Drum.hat: '..x...x...x...x.',
        }),
        nameOf: label,
      )!;

      // snare has no hits → skipped; kick before hat (Drum order).
      expect(result.partNames, ['kick', 'hat']);
      expect(result.score.parts.length, 2);
      // 16 eighth steps = two 4/4 bars per part.
      expect(result.score.parts[0].measures.length, 2);

      // The kick part carries exactly its two hits as notes.
      final kickNotes = result.score.parts[0].measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .length;
      expect(kickNotes, 2);
    });

    test('exports to MusicXML with a part per drum', () {
      final result = drumParts(
        _pattern(const {Drum.kick: 'x...x...x...x...'}),
        nameOf: label,
      )!;
      final xml = multiPartToMusicXml(
        result.score,
        partNames: result.partNames,
      );
      expect(xml, contains('<score-partwise'));
      expect(scoreFromMusicXml(xml).measures, isNotEmpty);
    });
  });

  group('grooveNoteIdAtStep (LM-UX3 highlight)', () {
    test('maps each step to the note sounding then, null on rests', () {
      // C (2 steps) · rest (2) · G (2) · rest (2) = one bar.
      final score = grooveScore(const [
        (midis: [60], steps: 2),
        (midis: null, steps: 2),
        (midis: [67], steps: 2),
        (midis: null, steps: 2),
      ]);
      final id0 = grooveNoteIdAtStep(score, 0);
      expect(id0, isNotNull);
      expect(grooveNoteIdAtStep(score, 1), id0); // still the first note
      expect(grooveNoteIdAtStep(score, 2), isNull); // a rest
      final id4 = grooveNoteIdAtStep(score, 4);
      expect(id4, isNotNull);
      expect(id4, isNot(id0)); // a different note
      expect(grooveNoteIdAtStep(score, -1), isNull);
    });
  });
}
