// lib/core/audio/transcription/separated_stem.dart
//
// One stereo stem out of a source separator — what the practice-stems player
// listens to. Pure Dart (web-safe): the CrispASR FFI that produces it lives in
// crispasr_ffi_separate_io.dart.

import 'dart:typed_data';

/// A named stereo stem at [sampleRate].
class SeparatedStem {
  const SeparatedStem(this.name, this.left, this.right, this.sampleRate);

  /// Split CrispASR's interleaved `L,R,L,R,…` buffer into two channels.
  factory SeparatedStem.fromInterleaved(
    String name,
    Float32List interleaved,
    int sampleRate,
  ) {
    final n = interleaved.length ~/ 2;
    final l = Float32List(n);
    final r = Float32List(n);
    for (var i = 0; i < n; i++) {
      l[i] = interleaved[2 * i];
      r[i] = interleaved[2 * i + 1];
    }
    return SeparatedStem(name, l, r, sampleRate);
  }

  /// CrispASR's stem name: `vocals`, `drums`, `bass`, `other`, `instrumental`.
  final String name;
  final Float32List left;
  final Float32List right;
  final int sampleRate;

  int get frames => left.length < right.length ? left.length : right.length;

  /// The two channels averaged — what the transcribers and pitch trackers take.
  Float64List mono() {
    final m = Float64List(frames);
    for (var i = 0; i < m.length; i++) {
      m[i] = (left[i] + right[i]) / 2;
    }
    return m;
  }
}
