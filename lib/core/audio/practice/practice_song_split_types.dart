// Types shared by the native and web halves of practice_song_split.dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separated_stem.dart';

/// Where `splitSongForPractice` is; reported as each step starts.
enum PracticeSplitPhase { decoding, separating, finishing }

/// A separated song, ready to play: [stems] add back up to the song exactly
/// (mixture-consistent). [beatMono] is the song's mono mix at [beatRate] —
/// all the beat tracker needs, so the decoded song itself is not kept.
///
/// The stems may be memory-mapped from disk: call [release] once nothing
/// reads them any more (the player stopped, the screen gone) — after it their
/// samples must not be touched. A no-op for stems held in memory.
typedef PracticeSongSplit = ({
  List<SeparatedStem> stems,
  double seconds,
  Float32List beatMono,
  int beatRate,
  void Function() release,
});
