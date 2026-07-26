// A0 — the round-trip scoreboard for the Tab Editor parity effort
// (docs/TAB_EDITOR_PARITY.md). Guitar-tab interchange (.gp / MusicXML / MIDI)
// and our `Score` model carry far more than the editor's `TabDocument` can
// represent, so `import → edit → export` silently drops whatever the editor
// doesn't model. This test runs the editor round-trip
//   Score → TabDocument.fromScore → TabDocument.toScore → Score
// and pins exactly what survives. Each later parity step (A2, A3, C1, …) flips
// one "still lost" assertion below from absent to preserved.

import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One quarter-note on the (open) high-E string, tagged [id].
NoteElement _n(String id) => NoteElement(
      pitches: const [Pitch(Step.e)],
      duration: NoteDuration.quarter,
      id: id,
    );

Score _roundTrip(Score src) =>
    TabDocument.fromScore(src, Tuning.standardGuitar).toScore();

void main() {
  group('A0 round-trip — techniques survive import→edit→export', () {
    // Eight notes, each carrying (at most) one technique via the score-level
    // decoration lists — exactly what a `.gp`/MusicXML import produces.
    final src = Score(
      clef: Clef.treble,
      measures: [
        Measure([for (var i = 0; i < 8; i++) _n('n$i')]),
      ],
      bends: const [Bend('n0')],
      glissandos: const [Glissando('n1', 'n2')], // slide n1→n2
      vibratos: const [Vibrato('n3')],
      slurs: const [Slur('n4', 'n5')], // hammer n4→n5
      tabNoteMarks: const [
        TabNoteMark('n6', TabNoteStyle.dead),
        TabNoteMark('n7', TabNoteStyle.harmonic),
      ],
    );

    test('bend / slide / vibrato / hammer / dead / harmonic all preserved', () {
      final out = _roundTrip(src);
      expect(out.bends, isNotEmpty, reason: 'bend lost');
      expect(out.glissandos, isNotEmpty, reason: 'slide lost');
      expect(out.vibratos, isNotEmpty, reason: 'vibrato lost');
      expect(out.slurs, isNotEmpty, reason: 'hammer lost');
      expect(out.tabNoteMarks, isNotEmpty, reason: 'dead/harmonic marks lost');
    });

    test('an untagged note stays plain (no spurious techniques)', () {
      final plain = Score(
        clef: Clef.treble,
        measures: [
          Measure([_n('a'), _n('b')]),
        ],
      );
      final out = _roundTrip(plain);
      expect(out.bends, isEmpty);
      expect(out.glissandos, isEmpty);
      expect(out.vibratos, isEmpty);
      expect(out.slurs, isEmpty);
      expect(out.tabNoteMarks, isEmpty);
    });
  });

  group('A0 scoreboard — preserved (each flipped as its step landed)', () {
    // These document features that now survive the editor round-trip. When a
    // step is done, its matcher flips from isEmpty/absent to preserved.
    test('C1 per-note dynamics survive (velocity quantised to a level)', () {
      const src = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch(Step.e)],
              duration: NoteDuration.quarter,
              velocity: 30,
              id: 'a',
            ),
          ]),
        ],
      );
      final out = _roundTrip(src);
      // The raw velocity is inferred to the nearest dynamic level and re-emitted
      // as both a DynamicMarking and a note velocity — no longer dropped.
      expect(out.dynamics, isNotEmpty);
      expect(
        out.measures
            .expand((m) => m.elements)
            .whereType<NoteElement>()
            .every((n) => n.velocity != null),
        isTrue,
      );
    });

    test('C2 a second voice survives', () {
      final src = Score(
        clef: Clef.treble,
        measures: [
          Measure(
            [_n('a')],
            voice2: [_n('b')],
          ),
        ],
      );
      final out = _roundTrip(src);
      expect(
        out.measures.any((m) => m.voice2.isNotEmpty),
        isTrue,
        reason: 'C2 carries a second voice',
      );
    });
  });
}
