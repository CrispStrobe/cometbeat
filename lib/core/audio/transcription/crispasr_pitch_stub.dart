// Web / no-dart:io fallback: no CLI, so no CrispASR CREPE F0.
// Signatures must match crispasr_pitch_io.dart so the conditional export in
// crispasr_pitch.dart presents one API on both platforms.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

F0Estimator? crispasrCliCrepeF0({
  String? binary,
  String? model,
  String? workDir,
}) =>
    null;

bool crispasrCrepeAvailable() => false;

/// Pure parser — no dart:io needed, so it works on web too (mirrors the IO
/// impl). Reads `--pitch` text: "time_ms\tf0_hz\tvoiced_prob" per line.
PitchTrack parsePitchFrames(String stdout) {
  final track = <PitchFrame>[];
  for (final line in stdout.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final t = double.tryParse(parts[0]);
    final f = double.tryParse(parts[1]);
    final v = double.tryParse(parts[2]);
    if (t == null || f == null || v == null) continue;
    track.add((timeMs: t, f0Hz: f, voicedProb: v));
  }
  return track;
}
