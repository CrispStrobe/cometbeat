// Beat and downbeat tracking with CrispASR's beat-this (MIT code + weights; no
// madmom DBN, which is non-commercial). Runs off the calling isolate. dart:io
// only; null when the lib or the model is not available.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/practice/practice_split.dart'
    show resampleLinear32;
import 'package:comet_beat/core/audio/transcription/beat_grid.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:crispasr/crispasr.dart' show CrispasrSession;

export 'package:comet_beat/core/audio/transcription/beat_grid.dart';

const _backend = 'beat-this';

/// Whether beat tracking can run now (lib + cached model, or [download]).
Future<bool> crispasrBeatsAvailable({bool download = false}) async =>
    crispasrModelPath(_backend, download: download) != null;

/// The beat grid of [mono] at [sampleRate], or null.
Future<BeatGrid?> crispasrBeatGrid(
  Float64List mono,
  int sampleRate, {
  bool download = false,
}) async {
  final modelPath = crispasrModelPath(_backend, download: download);
  if (modelPath == null || mono.isEmpty) return null;
  final libPath = crispasrLibPath();
  return Isolate.run(() {
    CrispasrSession? session;
    try {
      session =
          CrispasrSession.open(modelPath, libPath: libPath, backend: _backend);
      final sr = session.beatsSampleRate;
      if (sr <= 0) return null;
      // The native side rejects a rate mismatch rather than resample, because
      // resampling silently would move every beat — so convert here.
      final at =
          sr == sampleRate ? mono : resampleLinear(mono, sampleRate / sr);
      final pcm = Float32List(at.length);
      for (var i = 0; i < at.length; i++) {
        pcm[i] = at[i];
      }
      final beats = session.beats(pcm);
      return BeatGrid(
        beatMs: [for (final b in beats) b.timeS * 1000],
        downbeatMs: [
          for (final b in beats)
            if (b.isDownbeat) b.timeS * 1000,
        ],
        bpm: session.beatsTempoBpm,
      );
    } catch (_) {
      return null;
    } finally {
      session?.close();
    }
  });
}

/// [crispasrBeatGrid] for a float32 [mono] — what the practice player has.
/// Resampled in float32, so a song-length float64 copy is never made.
Future<BeatGrid?> crispasrBeatGrid32(
  Float32List mono,
  int sampleRate, {
  bool download = false,
}) async {
  final modelPath = crispasrModelPath(_backend, download: download);
  if (modelPath == null || mono.isEmpty) return null;
  final libPath = crispasrLibPath();
  return Isolate.run(() {
    CrispasrSession? session;
    try {
      session =
          CrispasrSession.open(modelPath, libPath: libPath, backend: _backend);
      final sr = session.beatsSampleRate;
      if (sr <= 0) return null;
      final beats = session.beats(resampleLinear32(mono, sampleRate, sr));
      return BeatGrid(
        beatMs: [for (final b in beats) b.timeS * 1000],
        downbeatMs: [
          for (final b in beats)
            if (b.isDownbeat) b.timeS * 1000,
        ],
        bpm: session.beatsTempoBpm,
      );
    } catch (_) {
      return null;
    } finally {
      session?.close();
    }
  });
}
