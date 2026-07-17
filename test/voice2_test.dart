// Voice 2 — a second engraved voice per part (`Measure.voice2`; crisp_notation
// engraves voices 1 and 2 only). The flat document keeps two element streams that
// share one bar grid: every edit/selection command targets the ACTIVE voice; the
// render/persist paths address a voice explicitly. An empty voice 2 renders
// byte-for-byte as a single-voice score (guarded by the packing goldens).

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);

void main() {
  test('voice 2 packs onto the shared bar grid', () {
    final d = ScoreDocument(); // 4/4
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _quarter); // voice 1: one full bar
    }
    d.setActiveVoice(1);
    d.insertNote(_p(Step.e), _half);
    d.insertNote(_p(Step.g), _half); // voice 2: same bar (two halves)

    final measures = d.buildScore().measures;
    expect(measures, hasLength(1));
    expect(measures[0].elements, hasLength(4), reason: 'voice 1');
    expect(measures[0].voice2, hasLength(2), reason: 'voice 2 on the same bar');
  });

  test('byte-identity: an empty voice 2 stamps no Measure.voice2', () {
    final d = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _quarter);
    }
    expect(
      d.buildScore().measures.every((m) => m.voice2.isEmpty),
      isTrue,
    );
  });

  group('active voice routing', () {
    test('entry targets the active voice; the other is untouched', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _quarter); // voice 1
      d.setActiveVoice(1);
      expect(d.activeVoice, 1);
      d.insertNote(_p(Step.e), _quarter); // voice 2
      d.insertNote(_p(Step.g), _quarter); // voice 2

      final m = d.buildScore().measures[0];
      expect(m.elements, hasLength(1), reason: 'voice 1 kept its single note');
      expect(m.voice2, hasLength(2), reason: 'both new notes went to voice 2');
    });

    test('switching voice clears the selection', () {
      final d = ScoreDocument();
      d.insertNote(_p(Step.c), _quarter);
      expect(d.hasSelection, isTrue);
      d.setActiveVoice(1);
      expect(d.hasSelection, isFalse);
    });

    test('setActiveVoice ignores out-of-range / unchanged values', () {
      final d = ScoreDocument();
      d.setActiveVoice(0); // unchanged
      expect(d.activeVoice, 0);
      d.setActiveVoice(2); // out of range (only 0/1)
      expect(d.activeVoice, 0);
    });
  });

  test('hasVoice2 reflects whether voice 2 has content', () {
    final d = ScoreDocument();
    d.insertNote(_p(Step.c), _quarter);
    expect(d.hasVoice2, isFalse);
    d.setActiveVoice(1);
    d.insertNote(_p(Step.e), _quarter);
    expect(d.hasVoice2, isTrue);
  });

  test('undo restores voice 2 across the voice boundary', () {
    final d = ScoreDocument();
    d.insertNote(_p(Step.c), _quarter);
    d.setActiveVoice(1);
    d.insertNote(_p(Step.e), _quarter);
    expect(d.buildScore().measures[0].voice2, hasLength(1));

    d.undo(); // undoes the voice-2 insert
    expect(d.buildScore().measures[0].voice2, isEmpty);
  });

  test('isEmpty is true only when both voices are empty', () {
    final d = ScoreDocument();
    d.setActiveVoice(1);
    d.insertNote(_p(Step.e), _quarter); // only voice 2 has content
    expect(d.isEmpty, isFalse);
  });

  test('MusicXML round-trip (save → reopen) preserves voice 2', () {
    final src = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      src.insertNote(_p(Step.c), _quarter);
    }
    src.setActiveVoice(1);
    src.insertNote(_p(Step.e), _half);
    src.insertNote(_p(Step.g), _half);

    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);
    final m = reopened.buildScore().measures;
    expect(m[0].elements, hasLength(4), reason: 'voice 1 survives');
    expect(
      m[0].voice2,
      hasLength(2),
      reason: 'voice 2 survives the round-trip',
    );
  });
}
