// Types shared by the native and web halves of practice_song_split.dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separated_stem.dart';

/// The song is longer than this device splits ([maxSeconds]): thrown by
/// `splitSongForPractice` after decoding, before the model is loaded.
class PracticeSongTooLong implements Exception {
  const PracticeSongTooLong(this.seconds, this.maxSeconds);

  final double seconds;
  final int maxSeconds;

  @override
  String toString() => 'PracticeSongTooLong($seconds s > $maxSeconds s)';
}

/// The longest song split on a phone or tablet. Memory no longer grows with
/// the stems (they are mapped from disk), but decoding still holds the whole
/// song several times over (glint: ~90 MB per minute at its peak) and the
/// separator holds it once more — so an hour-long recording would still be
/// killed. Desktop has no limit.
const int kPracticeMaxSecondsMobile = 10 * 60;

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
