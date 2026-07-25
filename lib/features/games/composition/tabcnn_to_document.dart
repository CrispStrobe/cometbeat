// Turns the audio→tab emitter's per-frame frettings into an editable
// [TabDocument] — a recording opens as tab in the Tab Editor / saves to the Song
// Book. The shared core a GUI "open recording as tab" button and a CLI
// `--out file.gp` both build on.
//
// Kept OUT of tabcnn_emitter.dart on purpose: this imports `tab_document.dart`,
// which pulls the Flutter-tainted crisp_notation umbrella, so it must NOT sit on
// the Flutter-free CLI path (bin/transcribe.dart imports only tabcnn_emitter).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show Backend;
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show Fretting;
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart'
    show collapseTabFrames;
import 'package:comet_beat/features/games/composition/tabcnn_emitter.dart'
    show TabCnnModelStore, audioToTab;
import 'package:crisp_notation/crisp_notation.dart' show NoteDuration, Tuning;
import 'package:flutter/foundation.dart' show compute;

/// TabCNN's per-frame hop in seconds (512 samples ÷ 22.05 kHz).
const double kTabCnnHopSeconds = 512 / 22050;

/// The [kTabDurations] note value whose length in 32nd-note steps is nearest
/// [steps]. NB: [kTabDurations] is measured on a **32nd-note** grid (a whole
/// note is 32 steps, a quarter is 8) — it used to be an eighth-note grid, and
/// callers that still hand over eighth-steps land four times too short.
NoteDuration _nearestTabDuration(int steps) {
  var best = kTabDurations.last.$1;
  var bestDiff = 1 << 30;
  for (final (nd, s) in kTabDurations) {
    final d = (s - steps).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = nd;
    }
  }
  return best;
}

/// Quantises [perFrame] frettings into a [TabDocument] on [tuning] at
/// [tempoBpm]. Consecutive identical frames collapse to one column whose length
/// (frames × [hopSeconds]) rounds to the nearest tab note value; silent runs
/// become rest columns, preserving timing. Runs shorter than [minFrames]
/// (≈ sub-46 ms flicker) are dropped, which drifts the grid slightly — good
/// enough for a first pass the user then edits. Pure + testable (no model).
TabDocument tabFramesToDocument(
  List<Fretting> perFrame, {
  required Tuning tuning,
  int tempoBpm = 120,
  double hopSeconds = kTabCnnHopSeconds,
  int minFrames = 2,
}) {
  final columns = <TabColumn>[];
  for (final (frets, frames) in collapseTabFrames(perFrame)) {
    if (frames < minFrames) continue; // drop flicker (minor grid drift)
    final beats = frames * hopSeconds * tempoBpm / 60;
    // One beat is a quarter = 8 thirty-second steps; a whole note = 32.
    final steps = (beats * 8).round().clamp(1, 32);
    columns.add(
      TabColumn(
        frets: frets.isEmpty ? const {} : Map<int, int>.of(frets),
        duration: _nearestTabDuration(steps),
      ),
    );
  }
  if (columns.isEmpty) columns.add(const TabColumn());
  return TabDocument(tuning: tuning, columns: columns);
}

/// End-to-end: a recording → an editable [TabDocument] (TabCNN emitter → decoder
/// → quantise). Null when the model is unavailable (offline / web). The caller
/// hands the result to the Tab Editor or saves it to the Song Book.
Future<TabDocument?> audioToTabDocument(
  Float64List mono,
  int sampleRate, {
  required Tuning tuning,
  int tempoBpm = 120,
  TabCnnModelStore? store,
  Backend prefer = Backend.auto,
}) async {
  // The model download + onnx inference is the heavy part (~1 s); run it off the
  // caller's isolate so the UI stays responsive. Only the frettings
  // (List<Map>) cross the boundary — small + sendable. A custom [store] can't be
  // sent, so those calls (tests) stay inline. The pure quantise runs here.
  final frames = store != null
      ? await audioToTab(mono, sampleRate, store: store, prefer: prefer)
      // Pass the enum as an index — a plain int is unconditionally sendable
      // across the isolate boundary.
      : await compute(_emitTabInIsolate, (mono, sampleRate, prefer.index));
  if (frames == null) return null;
  return tabFramesToDocument(frames, tuning: tuning, tempoBpm: tempoBpm);
}

/// Isolate entry: run the audio→frettings emit (model load + inference) in a
/// background isolate. Top-level so `compute` can spawn it.
Future<List<Fretting>?> _emitTabInIsolate((Float64List, int, int) m) =>
    audioToTab(m.$1, m.$2, prefer: Backend.values[m.$3]);
