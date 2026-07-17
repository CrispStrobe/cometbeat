// Voice-2 tuplets. A tuplet made while voice 2 is active used to be doubly
// broken: _withVoice2's reflow omitted durationScale (a triplet mis-packed and
// overflowed the bar) and _withTuplets positioned only voice-1 members (no
// bracket). Now voice 2's reflow scales its tuplet members and _withVoice2 emits
// TupletSpans with voice: 1 (crisp_notation draws inner-voice tuplet brackets).

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _eighth = NoteDuration(DurationBase.eighth);
const _quarter = NoteDuration(DurationBase.quarter);

/// The document with one 4/4 voice-1 bar and a voice-2 eighth-triplet followed
/// by three quarters — the triplet sounds as a quarter, so 1/4 + 3×1/4 fills the
/// bar exactly (it would spill if the members weren't scaled).
ScoreDocument _twoVoiceWithV2Triplet() {
  final d = ScoreDocument();
  for (var i = 0; i < 4; i++) {
    d.insertNote(_p(Step.c), _quarter); // voice 1: a full 4/4 bar
  }
  d.setActiveVoice(1);
  final t = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.e), _eighth)];
  d.addTuplet(t); // 3:2 triplet in voice 2
  for (var i = 0; i < 3; i++) {
    d.insertNote(_p(Step.g), _quarter);
  }
  return d;
}

List<TupletSpan> _v2Spans(Score s) => [
      for (final m in s.measures)
        for (final span in m.tuplets)
          if (span.voice == 1) span,
    ];

void main() {
  test('a voice-2 triplet packs at its sounding duration and brackets voice 2',
      () {
    final bars = _twoVoiceWithV2Triplet().buildScore().measures;
    expect(
      bars,
      hasLength(1),
      reason: 'v2 triplet(=1/4) + 3 quarters = one 4/4 bar; unscaled it spills',
    );
    expect(
      bars.single.voice2,
      hasLength(6),
      reason: 'voice 2: the three triplet eighths + three quarters',
    );
    final spans = bars.single.tuplets.where((s) => s.voice == 1).toList();
    expect(spans, hasLength(1));
    expect((spans.single.actual, spans.single.normal), (3, 2));
    expect(spans.single.startIndex, 0);
    expect(spans.single.endIndex, 2);
  });

  test('a voice-2 tuplet survives save → reopen', () {
    final d = _twoVoiceWithV2Triplet();
    final rebuilt = (ScoreDocument()..loadScore(d.buildScore())).buildScore();
    final spans = _v2Spans(rebuilt);
    expect(spans, hasLength(1), reason: 'the voice-2 tuplet came back');
    expect((spans.single.actual, spans.single.normal), (3, 2));
    expect(spans.single.startIndex, 0);
    expect(spans.single.endIndex, 2);
  });

  test('voice-1 tuplets are unaffected (voice 0, no phantom voice-2 span)', () {
    final d = ScoreDocument();
    final t = [for (var i = 0; i < 3; i++) d.insertNote(_p(Step.c), _eighth)];
    d.addTuplet(t);
    final all = [for (final m in d.buildScore().measures) ...m.tuplets];
    expect(all, hasLength(1));
    expect(all.single.voice, 0);
  });
}
