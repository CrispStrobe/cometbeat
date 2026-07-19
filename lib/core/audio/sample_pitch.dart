// Auto base-pitch detection for a recorded/loaded sample — so a recording plays
// a tune IN TUNE instead of being assumed to be middle C. Reuses the app's MPM
// pitch detector (pitch_analysis.dart) over several windows of the sustained
// region and takes the median, which is robust to a stray attack/vibrato frame.
// Pure Dart, non-destructive.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_finder.dart'
    show crossfadeLoop, findLoopPoints;
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// Detect the fundamental pitch of [pcm] (mono, ±1) as the nearest MIDI note —
/// the value to use as [SampleInstrument.baseMidi] so the sample plays in tune.
/// Returns null when no confident pitch is found (percussive/noisy/silent).
///
/// Samples MPM windows across the sustained middle of the sample (skipping the
/// attack) and returns the MEDIAN nearest-note, so one off frame can't skew it.
int? detectSampleBaseMidi(Float64List pcm, {int sampleRate = kSampleRate}) {
  if (pcm.isEmpty) return null;
  final det = PitchDetector(sampleRate: sampleRate);
  final w = det.windowSize;

  // Too short for a full window → one pass over the whole buffer.
  if (pcm.length <= w) {
    final r = det.analyze(pcm);
    return r.hasPitch ? r.nearestMidi : null;
  }

  final first = (pcm.length * 0.15).floor(); // skip the attack
  final last = pcm.length - w;
  const steps = 8;
  final midis = <int>[];
  for (var s = 0; s < steps; s++) {
    var pos = first + ((last - first) * s) ~/ (steps - 1);
    if (pos < 0) pos = 0;
    if (pos > last) pos = last;
    final r = det.analyze(Float64List.sublistView(pcm, pos, pos + w));
    if (r.hasPitch) midis.add(r.nearestMidi);
  }
  if (midis.isEmpty) return null;
  midis.sort();
  return midis[midis.length ~/ 2]; // median
}

/// Build a ready-to-play [SampleInstrument] from a raw recording: auto-detect
/// its base pitch (so it plays IN TUNE) and, when [autoLoop] is set, a seamless
/// sustain loop (so a held note rings). Falls back to `baseMidi` 60 / a one-shot
/// when detection finds nothing. [pingPong] makes any detected loop
/// bidirectional; [crossfade] smooths a forward loop's seam (recommended for
/// real recordings, skipped for ping-pong).
SampleInstrument tunedRecordedSample(
  String id,
  Float64List pcm, {
  int sampleRate = kSampleRate,
  bool autoLoop = true,
  bool pingPong = false,
  bool crossfade = false,
}) {
  final base = detectSampleBaseMidi(pcm, sampleRate: sampleRate) ?? 60;
  final lp = autoLoop ? findLoopPoints(pcm) : null;
  var sample = pcm;
  if (lp != null && crossfade && !pingPong) {
    sample = crossfadeLoop(
      pcm,
      loopStart: lp.loopStart,
      loopLength: lp.loopLength,
    );
  }
  return SampleInstrument(
    id,
    sample,
    baseMidi: base,
    loopStart: lp?.loopStart ?? 0,
    loopLength: lp?.loopLength ?? 0,
    pingPong: lp != null && pingPong,
  );
}
