// LoopReferenceScheduler — the AEC reference-alignment core (Loop Mixer jam
// grading §B, slice B1). Pure model tests against tiny synthetic loops: seam
// wrap, cursor arithmetic, phase-preserving swap-at-seam, and bar mapping. No
// audio hardware.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_reference.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PCM16 byte buffer from mono sample values (little-endian).
Uint8List pcm(List<int> samples) =>
    Int16List.fromList(samples).buffer.asUint8List();

/// The mono sample values in a PCM16 byte window.
List<int> samplesOf(Uint8List bytes) => Int16List.sublistView(bytes).toList();

void main() {
  test('nextWindow walks the loop and wraps the seam seamlessly', () {
    final s = LoopReferenceScheduler(pcm([10, 20, 30, 40]));
    expect(s.lengthSamples, 4);

    // A window longer than the loop repeats it end-to-end with no gap.
    expect(samplesOf(s.nextWindow(6)), [10, 20, 30, 40, 10, 20]);
    expect(s.cursorSample, 2);

    // The next window continues from the cursor, wrapping again.
    expect(samplesOf(s.nextWindow(4)), [30, 40, 10, 20]);
    expect(s.cursorSample, 2);
  });

  test('pulling exactly one loop returns the whole loop and resets the cursor',
      () {
    final s = LoopReferenceScheduler(pcm([1, 2, 3, 4]));
    expect(samplesOf(s.nextWindow(4)), [1, 2, 3, 4]);
    expect(s.cursorSample, 0);
  });

  test('a swap is adopted only at the seam (phase preserved to the downbeat)',
      () {
    final s = LoopReferenceScheduler(pcm([1, 2, 3, 4]));
    s.swap(pcm([5, 6, 7, 8]));
    expect(s.hasPendingSwap, isTrue);

    // Mid-loop: still the old loop, swap still pending.
    expect(samplesOf(s.nextWindow(2)), [1, 2]);
    expect(s.hasPendingSwap, isTrue);

    // Crossing the seam adopts the new loop exactly on the downbeat: the tail
    // of the old loop, then the head of the new one.
    expect(samplesOf(s.nextWindow(4)), [3, 4, 5, 6]);
    expect(s.hasPendingSwap, isFalse);
    expect(s.cursorSample, 2);

    // From here on it's the new loop.
    expect(samplesOf(s.nextWindow(4)), [7, 8, 5, 6]);
  });

  test('the latest swap before the seam wins', () {
    final s = LoopReferenceScheduler(pcm([1, 2]));
    s.swap(pcm([3, 3]));
    s.swap(pcm([4, 4])); // supersedes
    expect(samplesOf(s.nextWindow(4)), [1, 2, 4, 4]);
  });

  test('a different-length swap re-grids from its own downbeat', () {
    final s = LoopReferenceScheduler(pcm([1, 2, 3, 4]));
    s.swap(pcm([9, 8])); // shorter loop (e.g. a tempo change)

    // Consume the old loop; the seam adopts the 2-sample loop.
    expect(samplesOf(s.nextWindow(4)), [1, 2, 3, 4]);
    expect(s.lengthSamples, 2);
    expect(samplesOf(s.nextWindow(3)), [9, 8, 9]);
    expect(s.cursorSample, 1);
  });

  test('barAt maps the cursor to a bar via samplesPerBar', () {
    final s = LoopReferenceScheduler(pcm(List<int>.filled(8, 0)));
    s.nextWindow(3); // cursor → 3
    expect(s.barAt(2), 1); // 3 ~/ 2
    s.nextWindow(2); // cursor → 5
    expect(s.barAt(2), 2);
    expect(s.barAt(0), 0); // guard: no divide-by-zero
  });
}
