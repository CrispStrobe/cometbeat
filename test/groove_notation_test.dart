// Groove → Score engraving (the Loop Mixer's live-notation bridge). Pure
// model tests: pitch spelling, bar packing, duration decomposition, and the
// progression path producing 4 bars.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/features/games/composition/groove_notation.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart' hide isEmpty;

void main() {
  test('pitchFromMidi spells the groove range', () {
    expect(pitchFromMidi(60), const Pitch(Step.c));
    expect(pitchFromMidi(69), const Pitch(Step.a));
    expect(pitchFromMidi(36), const Pitch(Step.c, octave: 2));
    expect(pitchFromMidi(71), const Pitch(Step.b));
    expect(pitchFromMidi(61), const Pitch(Step.c, alter: 1));
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
}
