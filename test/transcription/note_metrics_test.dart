// Locks the shared note-metric harness (mir_eval-style) that gates every
// transcription slice.
import 'package:flutter_test/flutter_test.dart';

import 'note_metrics.dart';

void main() {
  test('identical transcriptions score F = 1', () {
    final gt = notes([(60, 0, 400), (62, 400, 800), (64, 800, 1200)]);
    expect(notePrf(gt, gt).f, 1.0);
    expect(onsetPrf(gt, gt).f, 1.0);
  });

  test('a wrong pitch fails note F but passes onset F', () {
    final gt = notes([(60, 0, 400), (62, 400, 800)]);
    final det = notes([(60, 10, 400), (99, 410, 800)]); // 2nd pitch wrong
    expect(onsetPrf(gt, det).f, 1.0); // both onsets line up
    // 1 of 2 pitches correct → P = R = 0.5 → F = 0.5.
    expect(notePrf(gt, det).f, 0.5);
  });

  test('onset tolerance and a spurious extra note', () {
    final gt = notes([(60, 0, 400)]);
    final late = notes([(60, 40, 400)]); // within 50ms
    expect(notePrf(gt, late).f, 1.0);
    final tooLate = notes([(60, 200, 400)]); // outside tol
    expect(notePrf(gt, tooLate).f, 0.0);
    // A spurious extra detection lowers precision.
    final withExtra = notes([(60, 5, 400), (72, 100, 400)]);
    final prf = notePrf(gt, withExtra);
    expect(prf.recall, 1.0);
    expect(prf.precision, 0.5);
  });

  test('pitchTol accepts near/octave matches', () {
    final gt = notes([(60, 0, 400)]);
    final oct = notes([(72, 0, 400)]); // an octave up
    expect(notePrf(gt, oct).f, 0.0);
    expect(notePrf(gt, oct, pitchTol: 12).f, 1.0);
  });
}
