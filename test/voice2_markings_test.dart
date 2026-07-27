// Voice-2 markings — dynamics and lyrics on a second-voice note. crisp_notation
// resolves DynamicMarking/Lyric by element id across voices, so the document has
// to harvest BOTH voices into Score.dynamics/lyrics (buildScore) and re-anchor
// them onto voice 2 on reopen (loadScore). Before this fix a dynamic/lyric set
// while voice 2 was active was stored but never rendered, and lost on reopen.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

void main() {
  test('voice-2 dynamic + lyric reach the rendered Score', () {
    final d = ScoreDocument();
    d.insertNote(_p(Step.c), _quarter); // voice 1
    d.setActiveVoice(1);
    final v2id = d.insertNote(_p(Step.e), _quarter); // voice 2 note (selected)
    d.setDynamicOfSelected(DynamicLevel.f);
    d.setLyricFor(v2id, 'la');

    final score = d.buildScore();
    expect(
      score.dynamics
          .any((m) => m.elementId == v2id && m.level == DynamicLevel.f),
      isTrue,
      reason: 'the voice-2 dynamic reaches Score.dynamics',
    );
    expect(
      score.lyrics.any((l) => l.elementId == v2id && l.text == 'la'),
      isTrue,
      reason: 'the voice-2 lyric reaches Score.lyrics',
    );
  });

  test('dynamics + lyrics reach the grand-staff view on the right staff', () {
    final d = ScoreDocument();
    final v1id = d.insertNote(_p(Step.c), _quarter); // voice 1 → treble
    d.setLyricFor(v1id, 'do');
    d.setActiveVoice(1);
    final v2id = d.insertNote(_p(Step.e, octave: 2), _quarter); // v2 → bass
    d.setDynamicOfSelected(DynamicLevel.f);
    d.setLyricFor(v2id, 'la');

    final gs = d.buildGrandStaff();
    // Voice 2's dynamic + lyric ride on the bass staff (not dropped).
    expect(
      gs.lower.dynamics
          .any((m) => m.elementId == v2id && m.level == DynamicLevel.f),
      isTrue,
      reason: 'the voice-2 dynamic reaches the bass staff',
    );
    expect(
      gs.lower.lyrics.any((l) => l.elementId == v2id && l.text == 'la'),
      isTrue,
      reason: 'the voice-2 lyric reaches the bass staff',
    );
    // Voice 1's lyric rides on the treble staff.
    expect(
      gs.upper.lyrics.any((l) => l.elementId == v1id && l.text == 'do'),
      isTrue,
      reason: 'the voice-1 lyric reaches the treble staff',
    );
  });

  test('slurs + hairpins land on the grand staff by the voice that owns them',
      () {
    final d = ScoreDocument();
    final a = d.insertNote(_p(Step.c), _quarter); // voice 1 → treble
    final b = d.insertNote(_p(Step.d), _quarter);
    d.selectByIds([a, b]);
    d.slurSelected(); // a voice-1 slur
    d.hairpinSelected(HairpinType.crescendo); // and a voice-1 hairpin
    d.setActiveVoice(1);
    final c = d.insertNote(_p(Step.e, octave: 2), _quarter); // voice 2 → bass
    final e = d.insertNote(_p(Step.f, octave: 2), _quarter);
    d.selectByIds([c, e]);
    d.slurSelected(); // a voice-2 slur

    final gs = d.buildGrandStaff();
    // Voice-1 spans on the treble, voice-2 span on the bass — none dropped,
    // none cross-staff.
    expect(gs.upper.slurs.map((s) => (s.startId, s.endId)), [(a, b)]);
    expect(gs.upper.hairpins.map((h) => (h.startId, h.endId)), [(a, b)]);
    expect(gs.lower.slurs.map((s) => (s.startId, s.endId)), [(c, e)]);
    expect(gs.lower.hairpins, isEmpty);
  });

  test('voice-2 dynamic + lyric survive save → reopen', () {
    final d = ScoreDocument();
    d.insertNote(_p(Step.c), _quarter);
    d.setActiveVoice(1);
    final v2id = d.insertNote(_p(Step.e), _quarter);
    d.setDynamicOfSelected(DynamicLevel.f);
    d.setLyricFor(v2id, 'la');

    // The real Save/Open path: reopen the built Score into a fresh document.
    // Ids are reassigned on load, so match the recovered voice-2 note by its
    // new id and confirm the marking re-anchored onto it.
    final rebuilt = (ScoreDocument()..loadScore(d.buildScore())).buildScore();
    final voice2 = rebuilt.measures.first.voice2;
    expect(voice2, hasLength(1), reason: 'the voice-2 note came back');
    final noteId = (voice2.first as NoteElement).id!;
    expect(
      rebuilt.dynamics
          .any((m) => m.elementId == noteId && m.level == DynamicLevel.f),
      isTrue,
      reason: 'the dynamic re-anchored onto the reopened voice-2 note',
    );
    expect(
      rebuilt.lyrics.any((l) => l.elementId == noteId && l.text == 'la'),
      isTrue,
      reason: 'the lyric re-anchored onto the reopened voice-2 note',
    );
  });

  test('undo removes a voice-2 dynamic', () {
    final d = ScoreDocument();
    d.setActiveVoice(1);
    final v2id = d.insertNote(_p(Step.e), _quarter);
    d.setDynamicOfSelected(DynamicLevel.f);
    expect(
      d.buildScore().dynamics.any((m) => m.elementId == v2id),
      isTrue,
    );
    d.undo();
    expect(
      d.buildScore().dynamics.any((m) => m.elementId == v2id),
      isFalse,
      reason: 'undo restored the pre-dynamic snapshot',
    );
  });

  test('voice-1 markings are unchanged when voice 2 is empty', () {
    final d = ScoreDocument();
    final id = d.insertNote(_p(Step.c), _quarter);
    d.setDynamicOfSelected(DynamicLevel.mf);
    d.setLyricFor(id, 'do');

    final s = d.buildScore();
    // Exactly one of each — the harvest doesn't duplicate voice-1 markings.
    expect(s.dynamics, hasLength(1));
    expect(s.dynamics.single.elementId, id);
    expect(s.lyrics, hasLength(1));
    expect(s.lyrics.single.text, 'do');
  });
}
