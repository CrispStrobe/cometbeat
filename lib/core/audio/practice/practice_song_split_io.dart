// Native: decode a picked song and split it into practice stems in ONE worker
// isolate, so the whole-song PCM never sits on the UI isolate and nothing
// song-sized is copied between isolates.
//
// The worker separates in windows on the model's own chunk grid
// (practice_split.dart), makes each finished block mixture-consistent, and —
// where the platform allows — writes it straight to disk (stem_files_io.dart).
// The UI isolate then MAPS the stem files read-only: the stems of a whole song
// cost the process no anonymous memory at all. Elsewhere the stems stay in
// memory and come back through Isolate.exit (handed over, not copied).
//
// Peak memory, a 6:14 stereo MP3 (test/practice/real_song_probe_test.dart,
// docs/HISTORY.md "practice-stems memory"): see there for before/after.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';
import 'package:comet_beat/core/audio/practice/practice_split.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/practice/song_audio_file.dart';
import 'package:comet_beat/core/audio/practice/stem_files_io.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate_io.dart'
    show crispasrSeparatorGrid, openCrispasrSeparator;
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:crispasr/crispasr.dart' show CrispasrSession;

export 'package:comet_beat/core/audio/practice/practice_song_split_types.dart';

/// The beat tracker's rate (Beat This!: 22050 Hz). The beat mix is made at
/// this rate so it is small; crispasrBeatGrid32 still resamples if a model
/// ever wants another.
const int kPracticeBeatRate = 22050;

/// Decode [bytes] (the file at [path]), separate it with [model] and make the
/// stems mixture-consistent, off the calling isolate. [onPhase] reports each
/// step as it starts (with the song's length once decoded). [inMemory] keeps
/// the stems in memory even where they could be mapped from disk. Throws
/// [StateError] `undecodable` or `separation` when a step fails.
Future<PracticeSongSplit> splitSongForPractice(
  String path,
  Uint8List bytes, {
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
  bool download = false,
  bool inMemory = false,
  void Function(PracticeSplitPhase phase, double? seconds)? onPhase,
}) async {
  final backend = model.registryBackend;
  final modelPath = crispasrModelPath(backend, download: download);
  if (modelPath == null) throw StateError('separation');
  final folder = !inMemory && stemFilesSupported ? newStemFolder().path : null;
  final port = ReceivePort();
  var done = false;
  final sub = port.listen((m) {
    if (done || onPhase == null || m is! List) return;
    onPhase(PracticeSplitPhase.values[m[0] as int], m[1] as double?);
  });
  final _Result r;
  try {
    r = await _spawn(
      path,
      bytes,
      modelPath,
      crispasrLibPath(),
      backend,
      model.cpuOnly,
      folder,
      port.sendPort,
    );
  } finally {
    done = true;
    await sub.cancel();
    port.close();
  }
  final files = r.files;
  if (files == null) {
    return (
      stems: r.stems!,
      seconds: r.seconds,
      beatMono: r.beatMono,
      beatRate: kPracticeBeatRate,
      release: () {},
    );
  }
  try {
    final mapped = mapStemFiles(files, r.frames, r.sampleRate);
    return (
      stems: mapped.stems,
      seconds: r.seconds,
      beatMono: r.beatMono,
      beatRate: kPracticeBeatRate,
      release: mapped.release,
    );
  } on FileSystemException {
    // Unmappable after all: read them in.
    return (
      stems: [
        for (final f in files)
          _readStem(f.name, f.path, r.frames, r.sampleRate),
      ],
      seconds: r.seconds,
      beatMono: r.beatMono,
      beatRate: kPracticeBeatRate,
      release: () {},
    );
  }
}

SeparatedStem _readStem(String name, String path, int frames, int rate) {
  final file = File(path);
  final all = file.readAsBytesSync().buffer.asFloat32List(0, frames * 2);
  try {
    file.deleteSync();
  } on FileSystemException {
    // gone already
  }
  return SeparatedStem(
    name,
    Float32List.sublistView(all, 0, frames),
    Float32List.sublistView(all, frames),
    rate,
  );
}

/// What the worker hands back: [files] on disk (with [frames] and
/// [sampleRate]), or the [stems] themselves.
typedef _Result = ({
  List<({String name, String path})>? files,
  List<SeparatedStem>? stems,
  int frames,
  int sampleRate,
  double seconds,
  Float32List beatMono,
});

// Its own function ON PURPOSE: the closure handed to Isolate.run must capture
// only sendable values, and a closure shares its context with every other
// closure of the same function (the listener above holds [onPhase]).
Future<_Result> _spawn(
  String path,
  Uint8List bytes,
  String modelPath,
  String libPath,
  String backend,
  bool cpuOnly,
  String? folder,
  SendPort phases,
) =>
    Isolate.run(
      () => _work(
        path,
        bytes,
        modelPath,
        libPath,
        backend,
        cpuOnly,
        folder,
        phases,
      ),
    );

Future<_Result> _work(
  String path,
  Uint8List bytes,
  String modelPath,
  String libPath,
  String backend,
  bool cpuOnly,
  String? folder,
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
    final n = math.min(left.length, right.length);
    final writer = folder == null ? null : StemFileWriter(Directory(folder), n);
    final memL = <Float32List>[], memR = <Float32List>[];
    // Each finished block: mixture-consistent (all stems on = the song), then
    // to disk or into the in-memory stems.
    void sink(
      int start,
      List<String> names,
      List<Float32List> l,
      List<Float32List> r,
    ) {
      final len = l.first.length;
      mixtureConsistentInPlace(
        [
          for (var k = 0; k < names.length; k++)
            SeparatedStem(names[k], l[k], r[k], sr),
        ],
        Float32List.sublistView(left, start, start + len),
        Float32List.sublistView(right, start, start + len),
      );
      for (var k = 0; k < names.length; k++) {
        if (writer != null) {
          writer.write(names[k], start, l[k], r[k]);
        } else {
          if (memL.length <= k) {
            memL.add(Float32List(n));
            memR.add(Float32List(n));
          }
          memL[k].setAll(start, l[k]);
          memR[k].setAll(start, r[k]);
        }
      }
    }

    final names = separateInWindowsTo(
      left,
      right,
      sr,
      session.separate,
      sink,
      grid: crispasrSeparatorGrid(backend, sr),
    );
    final files = writer?.close();
    if (names.isEmpty) throw StateError('separation');
    session.close();
    session = null;
    phases.send([PracticeSplitPhase.finishing.index, seconds]);
    return (
      files: files,
      stems: writer != null
          ? null
          : [
              for (var k = 0; k < names.length; k++)
                SeparatedStem(names[k], memL[k], memR[k], sr),
            ],
      frames: n,
      sampleRate: sr,
      seconds: seconds,
      beatMono: monoAtRate(left, right, sr, kPracticeBeatRate),
    );
  } finally {
    session?.close();
  }
}
