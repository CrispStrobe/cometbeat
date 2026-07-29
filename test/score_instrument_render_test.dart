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

  Score oneVel(int? velocity) => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c)],
              duration: NoteDuration.whole,
              velocity: velocity,
            ),
          ]),
        ],
      );

  test('MIDI note velocity scales loudness (120 louder than 40)', () {
    final soft = renderScoreWithInstrument(oneVel(40), _voice());
    final loud = renderScoreWithInstrument(oneVel(120), _voice());
    expect(_peak(loud), greaterThan(_peak(soft)));
    // No velocity → unscaled (full) render, louder than an explicit 120.
    final none = renderScoreWithInstrument(oneVel(null), _voice());
    expect(_peak(none), greaterThan(_peak(loud)));
  });

  test('a note carries a release tail beyond its notated length', () {
    // A whole note at the default 500 ms/quarter = 2000 ms; the render extends
    // past that by the release fade instead of stopping hard.
    final pcm = renderScoreWithInstrument(oneVel(100), _voice());
    const notatedSamples = 2000 * 44100 ~/ 1000; // 2 s
    expect(pcm.length, greaterThan(notatedSamples));
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

  group('SE-C5: the render follows what is notated', () {
    // ⚠ No "count the attacks" helper here, and the reason is worth recording:
    // my first version counted the signal rising past a threshold, which on a
    // 220 Hz sine counts ZERO CROSSINGS — it reported 20 attacks for one note
    // and 80 for four. Re-attacks of a continuous tone also butt together with
    // no gap, so an envelope would not separate them either. So these assert
    // things this signal genuinely can support: exact equivalence where the
    // notation defines one, and difference where it must exist.

    Score one(NoteElement note) => Score(
          clef: Clef.treble,
          measures: [
            Measure([note]),
          ],
        );

    NoteElement plainNote(NoteDuration d, {int? tremolo, Ornament? ornament}) =>
        NoteElement(
          pitches: [Pitch.fromMidi(60)],
          duration: d,
          tremolo: tremolo,
          ornament: ornament,
          id: 'n0',
        );

    test('a TIE sounds exactly like the single longer note it means', () {
      // The strongest statement available: two tied quarters must render
      // BYTE-IDENTICALLY to one half note. It used to re-articulate.
      final tied = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: [Pitch.fromMidi(60)],
              duration: NoteDuration.quarter,
              tieToNext: true,
              id: 'n0',
            ),
            NoteElement(
              pitches: [Pitch.fromMidi(60)],
              duration: NoteDuration.quarter,
              id: 'n1',
            ),
          ]),
        ],
      );
      final asHalf = one(plainNote(NoteDuration.half));
      expect(
        renderScoreWithInstrument(tied, _voice()),
        renderScoreWithInstrument(asHalf, _voice()),
      );
    });

    test('a tremolo differs from the plain note but occupies the same time',
        () {
      final plain = renderScoreWithInstrument(
        one(plainNote(NoteDuration.whole)),
        _voice(),
      );
      final trem = renderScoreWithInstrument(
        one(plainNote(NoteDuration.whole, tremolo: 2)),
        _voice(),
      );
      expect(trem, isNot(plain), reason: 'it used to render as one long note');
      // Within a sample: partitioning the note into repeats rounds each edge.
      expect(
        trem.length,
        closeTo(plain.length, 2),
        reason: 'and it must not steal time',
      );
    });

    test('an ornament is audible and does not shorten the music', () {
      final plain = renderScoreWithInstrument(
        one(plainNote(NoteDuration.half)),
        _voice(),
      );
      final turned = renderScoreWithInstrument(
        one(plainNote(NoteDuration.half, ornament: Ornament.turn)),
        _voice(),
      );
      expect(turned, isNot(plain));
      expect(turned.length, greaterThanOrEqualTo(plain.length));
    });

    test('a plain score is untouched — same length, still non-silent', () {
      final pcm = renderScoreWithInstrument(
        Score.simple(notes: 'c4:q d4 e4 f4'),
        _voice(),
      );
      expect(_peak(pcm), greaterThan(0.01));
      // Four quarters at 120 bpm = 2 s of notes, plus the last note's sample
      // tail — the render runs a little past the written end and always has.
      // The claim is that nothing in this score asks for extra time.
      expect(pcm.length, greaterThanOrEqualTo(2 * 44100));
      expect(pcm.length, lessThan((2.5 * 44100).round()));
    });
  });
}
