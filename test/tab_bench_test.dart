// Benchmark for the Tab Workshop's document work — OPT-IN, not part of the gate.
//
// Written BEFORE optimising anything, because "it feels laggy" is not a
// measurement and neither is a plausible-looking hot loop. Everything the screen
// does per frame or per edit funnels through `TabDocument.toScore` (the derived
// score the notation view, the exports and playback all read), so that is what
// this times, at sizes a real piece reaches.
//
//   TAB_BENCH=1 flutter test test/tab_bench_test.dart
//
// ⚠️ Opt-in (the pattern `tracker_effect_reference_sweep_test.dart` uses) for two
// reasons: a wall-clock number on shared CI hardware is noise, and a benchmark
// that fails the build teaches people to ignore it. It prints; it never asserts
// a duration.
//
// ⚠️ And it is a TEST rather than a `tool/` script because `tab_document.dart`
// imports the Flutter-facing `crisp_notation`, so `dart run` cannot compile it
// (the FFI transformer crashes on the app's native bindings). Worth knowing
// before writing the next headless tool against the tab model.

import 'dart:io';

import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A document of [columns] columns with something on most of them — a plausible
/// piece rather than a pathological one: chords, techniques, ties and a few
/// bar-level marks, which is what a real arrangement carries.
TabDocument _doc(int columns) {
  final doc = TabDocument(tuning: Tuning.standardGuitar);
  for (var col = 0; col < columns; col++) {
    // A three-note chord every fourth column, single notes elsewhere.
    if (col % 4 == 0) {
      doc
        ..setFret(col, 5, 3 + col % 5)
        ..setFret(col, 4, 2 + col % 4)
        ..setFret(col, 3, col % 3);
    } else {
      doc.setFret(col, 5 - col % 6, col % 12);
    }
    if (col % 8 == 3) doc.toggleTechnique(col, TabTechnique.hammer);
    if (col % 16 == 7) doc.setTie(col, true);
    doc.setDuration(
      col,
      col.isEven ? NoteDuration.eighth : NoteDuration.quarter,
    );
  }
  return doc;
}

/// Median wall-clock milliseconds of [runs] calls to [body], after a warm-up.
///
/// Median, not mean: a single GC pause during a run would dominate a mean and
/// make a real improvement invisible.
double _median(int runs, void Function() body) {
  // ⚠️ Three warm-ups was not enough: the first measured sample of the arranger
  // came out 2× the rest, which made a real change unmeasurable and briefly made
  // a hoist look like a regression. The JIT needs to see the inner loops go
  // fully hot before anything is timed.
  for (var i = 0; i < 20; i++) {
    body();
  }
  final samples = <double>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  test(
    'arrangeTab, by note count',
    () {
      // The import/open cost: `fromScore` runs this once per voice, so it is what
      // "opening a big tab" waits on.
      stdout.writeln('notes   arrangeTab');
      for (final size in const [32, 128, 512]) {
        // DENSE chords on purpose: the Viterbi inner loop is
        // `candidates × candidates`, and a one- or two-note column produces so few
        // candidates that it never exercises the case that costs anything. Four
        // notes is a real guitar chord and generates real candidate fan-out.
        final pitches = [
          for (var i = 0; i < size; i++)
            <int>[
              40 + i % 12,
              47 + i % 9,
              52 + i % 7,
              57 + i % 5,
            ],
        ];
        final ms = _median(
          25,
          () => arrangeTab(pitches, Tuning.standardGuitar),
        );
        stdout.writeln(
          '${size.toString().padRight(7)} ${ms.toStringAsFixed(2).padLeft(7)}ms',
        );
      }
    },
    skip: Platform.environment['TAB_BENCH'] == null ? 'set TAB_BENCH=1' : null,
  );

  test(
    'toScore, by document size',
    () {
      stdout.writeln('columns   toScore   notes   per-note');
      for (final size in const [32, 128, 512]) {
        final doc = _doc(size);
        final score = doc.toScore();
        final notes = score.measures.fold<int>(
          0,
          (sum, measure) => sum + measure.elements.length,
        );
        final ms = _median(20, doc.toScore);
        final per = notes == 0 ? 0.0 : ms * 1000 / notes;
        stdout.writeln(
          '${size.toString().padRight(9)} '
          '${ms.toStringAsFixed(2).padLeft(7)}ms '
          '${notes.toString().padLeft(6)} '
          '${per.toStringAsFixed(1).padLeft(8)}\u00b5s',
        );
      }
    },
    skip: Platform.environment['TAB_BENCH'] == null ? 'set TAB_BENCH=1' : null,
  );
}
