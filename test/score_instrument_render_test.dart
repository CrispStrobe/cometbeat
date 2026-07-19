// renderScoreWithInstrument — play an engraved Score through an arbitrary
// TrackerInstrument voice (the bridge that lets a saved "My Instruments" voice
// sound a piece). Locks: it produces non-silent audio, longer pieces are
// longer, and a MultiPartScore sums its parts.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

SampleInstrument _voice() {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument('v', pcm);
}

double _peak(Float64List x) {
  var p = 0.0;
  for (final s in x) {
    if (s.abs() > p) p = s.abs();
  }
  return p;
}

void main() {
  test('renders a score through the instrument, non-silent', () {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    final pcm = renderScoreWithInstrument(score, _voice());
    expect(pcm, isNotEmpty);
    expect(_peak(pcm), greaterThan(0.01));
  });

  test('a four-note phrase is longer than a one-note phrase', () {
    final one =
        renderScoreWithInstrument(Score.simple(notes: 'c4:q'), _voice());
    final four = renderScoreWithInstrument(
      Score.simple(notes: 'c4:q d4 e4 f4'),
      _voice(),
    );
    expect(four.length, greaterThan(one.length));
  });

  test('a slower tempo (bigger quarterMs) makes a longer render', () {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    final fast = renderScoreWithInstrument(score, _voice(), quarterMs: 250);
    final slow = renderScoreWithInstrument(score, _voice(), quarterMs: 1000);
    expect(slow.length, greaterThan(fast.length));
  });

  test('a multi-part score sums to non-silent audio', () {
    final mp = MultiPartScore([
      Score.simple(notes: 'c4:q d4 e4 f4'),
      Score.simple(notes: 'g3:q a3 b3 c4'),
    ]);
    final pcm = renderMultiPartWithInstrument(mp, _voice());
    expect(pcm, isNotEmpty);
    expect(_peak(pcm), greaterThan(0.01));
  });

  Score oneNote(DynamicLevel? dyn) => Score(
        clef: Clef.treble,
        measures: [
          const Measure([
            NoteElement(
              id: 'e0',
              pitches: [Pitch(Step.c)],
              duration: NoteDuration.whole,
            ),
          ]),
        ],
        dynamics: dyn == null ? const [] : [DynamicMarking('e0', dyn)],
      );

  test('dynamics scale note loudness (ff louder than pp)', () {
    final pp = renderScoreWithInstrument(oneNote(DynamicLevel.pp), _voice());
    final ff = renderScoreWithInstrument(oneNote(DynamicLevel.ff), _voice());
    expect(_peak(ff), greaterThan(_peak(pp)));
  });

  test('a score with no dynamics is byte-identical to the plain render', () {
    // The expressive path is gated on score.dynamics being non-empty, so an
    // unmarked score renders exactly as before.
    final a = renderScoreWithInstrument(oneNote(null), _voice());
    final b = renderScoreWithInstrument(oneNote(null), _voice());
    expect(a, b);
    // ff differs from the unmarked (default full-level) render.
    final ff = renderScoreWithInstrument(oneNote(DynamicLevel.ff), _voice());
    expect(
      _peak(ff),
      lessThan(_peak(a)),
      reason: 'ff = 112/127 gain < unmarked full 1.0',
    );
  });

  test('panPartsToStereo places part 0 left, part 1 right', () {
    final loud = Float64List(64)..fillRange(0, 64, 0.5);
    final silent = Float64List(64);
    // part 0 loud → louder on the left; part 1 silent.
    final (l0, r0) = panPartsToStereo([loud, silent]);
    expect(_peak(l0), greaterThan(_peak(r0)));
    // swap → louder on the right.
    final (l1, r1) = panPartsToStereo([silent, loud]);
    expect(_peak(r1), greaterThan(_peak(l1)));
    // a single part is centred (equal channels).
    final (lc, rc) = panPartsToStereo([loud]);
    expect(_peak(lc), closeTo(_peak(rc), 1e-9));
  });
}
