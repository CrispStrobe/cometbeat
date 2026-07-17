// Tempo marks — a document-level initial tempo (`Score.tempo`) plus mid-score
// tempo changes (`Measure.tempoChange`) built on the same element-id-anchor
// mechanism as the clef/key stamps (docs/WORKSHOP_NEXT_HANDOVER.md). A change is
// stored against an element id, not a bar number, so it rides re-barring;
// buildScore stamps it onto whichever bar that element lands in. Feeds
// crisp_notation's `TempoMap`, so this is the prerequisite for real playback.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

/// The tempoChange stamped on each bar (null = none), in order.
List<Tempo?> _tempoChangesPerBar(ScoreDocument d) =>
    [for (final m in d.buildScore().measures) m.tempoChange];

void main() {
  // Fills [count] quarter notes and returns their ids in order.
  List<String> fill(ScoreDocument d, int count) =>
      [for (var i = 0; i < count; i++) d.insertNote(_p(Step.c), _quarter)];

  group('initial (document-start) tempo', () {
    test('feeds Score.tempo', () {
      final d = ScoreDocument();
      fill(d, 4);
      expect(d.buildScore().tempo, isNull, reason: 'unset by default');

      d.setInitialTempo(const Tempo(120));
      expect(d.buildScore().tempo, const Tempo(120));
    });

    test('set / clear / undo', () {
      final d = ScoreDocument();
      fill(d, 4);
      d.setInitialTempo(const Tempo(96));
      expect(d.tempo, const Tempo(96));

      d.setInitialTempo(null); // clear
      expect(d.tempo, isNull);
      expect(d.buildScore().tempo, isNull);

      d.undo(); // brings it back
      expect(d.tempo, const Tempo(96));
      expect(d.buildScore().tempo, const Tempo(96));
    });

    test('an unchanged value is a no-op (no undo entry)', () {
      final d = ScoreDocument();
      fill(d, 4);
      d.setInitialTempo(const Tempo(120));
      d.setInitialTempo(const Tempo(120)); // same → no snapshot
      d.undo(); // undoes the ONE real change
      expect(d.tempo, isNull);
    });
  });

  group('mid-score tempo change', () {
    test('a tempo change lands on the bar of its anchor element', () {
      final d = ScoreDocument(); // 4/4 → 4 quarters per bar
      final ids = fill(d, 8); // two bars
      d.setTempoChangeAt(ids[4], const Tempo(90)); // first note of bar 1

      expect(_tempoChangesPerBar(d), [null, const Tempo(90)]);
      expect(
        d.buildScore().measures[1].tempoChange,
        const Tempo(90),
        reason: 'the change is drawn where bar 1 begins',
      );
    });

    test('the anchor rides re-barring', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setTempoChangeAt(ids[4], const Tempo(90));
      d.selectIndex(0);
      d.insertNote(_p(Step.d), _quarter); // shift everything right

      final bars = d.buildScore().measures;
      final anchorBar =
          bars.indexWhere((m) => m.elements.any((e) => e.id == ids[4]));
      expect(bars[anchorBar].tempoChange, const Tempo(90));
      expect(
        bars.where((m) => m.tempoChange == const Tempo(90)),
        hasLength(1),
        reason: 'exactly one bar carries the change',
      );
    });

    test('a redundant change (same as the running tempo) is not drawn', () {
      final d = ScoreDocument()..setInitialTempo(const Tempo(120));
      final ids = fill(d, 8);
      d.setTempoChangeAt(ids[4], const Tempo(120)); // same as the initial tempo
      expect(
        _tempoChangesPerBar(d),
        [null, null],
        reason: 'no bar draws a 120→120 change',
      );
    });

    test('only the changing bar is marked; the tempo carries forward', () {
      final d = ScoreDocument();
      final ids = fill(d, 12); // three bars
      d.setTempoChangeAt(ids[4], const Tempo(90)); // bar 1 → 90
      expect(_tempoChangesPerBar(d), [null, const Tempo(90), null]);
    });

    test('a non-default beat unit round-trips through quarterBpm', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      // A dotted-quarter at 80 == 120 quarter-bpm.
      const dottedQuarter = Tempo(80, dots: 1);
      d.setTempoChangeAt(ids[4], dottedQuarter);
      expect(d.buildScore().measures[1].tempoChange, dottedQuarter);
      expect(dottedQuarter.quarterBpm, 120);
    });

    test('setting, clearing, and undo', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setTempoChangeAt(ids[4], const Tempo(90));
      expect(d.tempoChanges, {ids[4]: const Tempo(90)});
      expect(d.tempoChangeAt(ids[4]), const Tempo(90));

      d.setTempoChangeAt(ids[4], null); // clear
      expect(d.tempoChanges, isEmpty);
      expect(_tempoChangesPerBar(d), [null, null]);

      d.undo(); // brings the change back
      expect(d.tempoChanges, {ids[4]: const Tempo(90)});
      expect(d.buildScore().measures[1].tempoChange, const Tempo(90));
    });

    test('an unknown anchor id is ignored', () {
      final d = ScoreDocument();
      fill(d, 4);
      d.setTempoChangeAt('does-not-exist', const Tempo(90));
      expect(d.tempoChanges, isEmpty);
    });

    test('tempo, clef and key can all land on the same bar', () {
      final d = ScoreDocument();
      final ids = fill(d, 8);
      d.setTempoChangeAt(ids[4], const Tempo(90));
      d.setClefChangeAt(ids[4], Clef.bass);
      d.setKeyChangeAt(ids[4], const KeySignature(1));

      final bar1 = d.buildScore().measures[1];
      expect(bar1.tempoChange, const Tempo(90));
      expect(bar1.clefChange, Clef.bass);
      expect(bar1.keyChange, const KeySignature(1));
    });
  });

  test('no tempo marks → buildScore is untouched (goldens stay valid)', () {
    final d = ScoreDocument();
    fill(d, 8);
    final score = d.buildScore();
    expect(score.tempo, isNull);
    expect(score.measures.every((m) => m.tempoChange == null), isTrue);
  });

  test('clearAll drops mid-score tempo changes', () {
    final d = ScoreDocument();
    final ids = fill(d, 8);
    d.setTempoChangeAt(ids[4], const Tempo(90));
    d.clearAll();
    expect(d.tempoChanges, isEmpty);
  });

  test('save → reopen preserves the initial tempo and a mid-score change', () {
    // An initial tempo is set alongside the change: the MusicXML reader treats
    // the first metronome it sees as the score's initial tempo, so a document
    // with only a later change would read that change back AS the initial tempo.
    // Real scores carry an opening tempo, which makes the round-trip exact.
    final src = ScoreDocument()..setInitialTempo(const Tempo(120));
    final ids = fill(src, 8);
    src.setTempoChangeAt(ids[4], const Tempo(90));

    // Through MusicXML, the real Save → Open path.
    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);

    expect(reopened.tempo, const Tempo(120), reason: 'initial tempo survives');
    expect(
      reopened.buildScore().measures[1].tempoChange,
      const Tempo(90),
      reason: 'the mid-score change survives the round-trip',
    );
  });
}
