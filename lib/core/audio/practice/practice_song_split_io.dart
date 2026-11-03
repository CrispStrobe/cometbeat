// Native: decode a picked song and split it into practice stems in ONE worker
// isolate, so the whole-song PCM never sits on the UI isolate and nothing
// song-sized is copied between isolates. The worker receives the file's bytes,
// and returns the stems through Isolate.exit (handed over, not copied).
//
// Peak memory, a 6:14 stereo MP3 (test/practice/real_song_probe_test.dart):
// was 2.4 GB with whole-song separation and float64/boxed copies; now the
// song at the model's rate + the four stems + one window's buffers. See
// docs/HISTORY.md "practice-stems memory".

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';
import 'package:comet_beat/core/audio/practice/practice_split.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/practice/song_audio_file.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate_io.dart'
    show openCrispasrSeparator;
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:crispasr/crispasr.dart' show CrispasrSession;

export 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';

/// The beat tracker's rate (Beat This!: 22050 Hz). The beat mix is made at
/// this rate so it is small; crispasrBeatGrid still resamples if a model
/// ever wants another.
const int kPracticeBeatRate = 22050;

/// Decode [bytes] (the file at [path]), separate it with [model] and make the
/// stems mixture-consistent, off the calling isolate. [onPhase] reports each
/// step as it starts (with the song's length once decoded). Throws
/// [StateError] `undecodable` or `separation` when a step fails.
Future<PracticeSongSplit> splitSongForPractice(
  String path,
  Uint8List bytes, {
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
  bool download = false,
  void Function(PracticeSplitPhase phase, double? seconds)? onPhase,
}) async {
  final backend = model.registryBackend;
  final modelPath = crispasrModelPath(backend, download: download);
  if (modelPath == null) throw StateError('separation');
  final port = ReceivePort();
  var done = false;
  final sub = port.listen((m) {
    if (done || onPhase == null || m is! List) return;
    onPhase(PracticeSplitPhase.values[m[0] as int], m[1] as double?);
  });
  try {
    return await _spawn(
      path,
      bytes,
      modelPath,
      crispasrLibPath(),
      backend,
      model.cpuOnly,
      port.sendPort,
    );
  } finally {
    done = true;
    await sub.cancel();
    port.close();
  }
}

// Its own function ON PURPOSE: the closure handed to Isolate.run must capture
// only sendable values, and a closure shares its context with every other
// closure of the same function (the listener above holds [onPhase]).
Future<PracticeSongSplit> _spawn(
  String path,
  Uint8List bytes,
  String modelPath,
  String libPath,
  String backend,
  bool cpuOnly,
  SendPort phases,
) =>
    Isolate.run(
      () => _work(path, bytes, modelPath, libPath, backend, cpuOnly, phases),
    );

Future<PracticeSongSplit> _work(
  String path,
  Uint8List bytes,
  String modelPath,
  String libPath,
  String backend,
  bool cpuOnly,
  SendPort phases,
) async {
  phases.send([PracticeSplitPhase.decoding.index, null]);
  SongAudio? song = await decodeSongFile(path, bytes);
  if (song == null || song.frames == 0) throw StateError('undecodable');
  final seconds = song.seconds;
  phases.send([PracticeSplitPhase.separating.index, seconds]);
  CrispasrSession? session;
  try {
    session =
        openCrispasrSeparator(modelPath, libPath, backend, cpuOnly: cpuOnly);
    final sr = session.separateSampleRate;
    if (sr <= 0) throw StateError('separation');
    // At the model's rate in float32 — the decoded song is dropped here, so
    // a 48 kHz file does not stay alive beside its 44.1 kHz copy.
    final left = resampleLinear32(song.left, song.sampleRate, sr);
    final right = resampleLinear32(song.right, song.sampleRate, sr);
    song = null;
    final stems = separateInWindows(left, right, sr, session.separate);
    if (stems.isEmpty) throw StateError('separation');
    session.close();
    session = null;
    phases.send([PracticeSplitPhase.finishing.index, seconds]);
    // All stems on must sound like the song that was loaded.
    mixtureConsistentInPlace(stems, left, right);
    return (
      stems: stems,
      seconds: seconds,
      beatMono: monoAtRate(left, right, sr, kPracticeBeatRate),
      beatRate: kPracticeBeatRate,
    );
  } finally {
    session?.close();
  }
}
