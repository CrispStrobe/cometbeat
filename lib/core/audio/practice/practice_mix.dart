// lib/core/audio/practice/practice_mix.dart
//
// The pure logic behind "practise with your own song": per-stem mute / solo /
// level, the windows the stem player streams, and the sing-along chart built
// from the vocal stem. No Flutter, no FFI — unit-tested in
// test/practice_mix_test.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/audio/transcription/beat_grid.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart'
    show NoteEvent;
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';

/// One stem's mixer strip.
class StemControl {
  const StemControl({
    required this.name,
    this.volume = 1,
    this.muted = false,
    this.solo = false,
  });

  final String name;
  final double volume;
  final bool muted;
  final bool solo;

  StemControl copyWith({double? volume, bool? muted, bool? solo}) =>
      StemControl(
        name: name,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        solo: solo ?? this.solo,
      );
}

/// What each strip actually plays at. Solo wins: while any strip is soloed,
/// only soloed strips sound (muted or not — solo is the louder intent, as on a
/// mixing desk); otherwise every unmuted strip sounds at its volume.
List<double> effectiveVolumes(List<StemControl> strips) {
  final anySolo = strips.any((s) => s.solo);
  return [
    for (final s in strips)
      (anySolo ? s.solo : !s.muted) ? s.volume.clamp(0.0, 1.0).toDouble() : 0.0,
  ];
}

/// Mixture consistency: share what the separator left out — `mix − Σ stems` —
/// equally among the stems, so that playing every stem gives back the original
/// song exactly. That is the least-squares projection of the estimates onto
/// "stems that sum to the mix" (Wisdom et al., 2019), so it is the smallest
/// change that achieves it.
///
/// Why it is needed: a masking separator estimates each stem independently and
/// nothing forces them to add up. htdemucs's stems reconstruct a test mix to
/// only ~15 dB (Mini-BS-RoFormer's to ~40 dB on the CPU) — so with every stem
/// on, the learner would hear a duller song than the one they loaded.
///
/// [left]/[right] are the mix at the stems' rate; lengths may differ by a few
/// frames, and only the common span is touched.
List<SeparatedStem> mixtureConsistent(
  List<SeparatedStem> stems,
  Float32List left,
  Float32List right,
) {
  if (stems.isEmpty) return stems;
  final n = stems.map((s) => s.frames).fold(
        math.min(left.length, right.length),
        math.min,
      );
  final share = 1 / stems.length;
  final rl = Float32List(n), rr = Float32List(n);
  for (var i = 0; i < n; i++) {
    var sl = 0.0, sr = 0.0;
    for (final s in stems) {
      sl += s.left[i];
      sr += s.right[i];
    }
    rl[i] = (left[i] - sl) * share;
    rr[i] = (right[i] - sr) * share;
  }
  return [
    for (final s in stems)
      SeparatedStem(
        s.name,
        Float32List.fromList([
          for (var i = 0; i < n; i++) s.left[i] + rl[i],
        ]),
        Float32List.fromList([
          for (var i = 0; i < n; i++) s.right[i] + rr[i],
        ]),
        s.sampleRate,
      ),
  ];
}

/// The strips for "minus one": every stem on except [without].
List<StemControl> minusOne(List<StemControl> strips, String without) => [
      for (final s in strips) s.copyWith(muted: s.name == without, solo: false),
    ];

/// [frames] frames of [stem] from [start], interleaved `L,R,…` for the stream
/// player. Past the end it is shorter (possibly empty), never padded.
Float32List interleavedWindow(SeparatedStem stem, int start, int frames) {
  final int from = math.min(math.max(start, 0), stem.frames);
  final int to = math.min(stem.frames, from + math.max(0, frames));
  final out = Float32List((to - from) * 2);
  for (var i = from, o = 0; i < to; i++, o += 2) {
    out[o] = stem.left[i];
    out[o + 1] = stem.right[i];
  }
  return out;
}

/// Shortest note kept in a sing-along chart: anything briefer is a pitch
/// tracker's flicker (a consonant, a slide), not a note anyone could sing to.
const double kMinSingNoteMs = 90;

/// A sing-along chart of the vocal [notes], in absolute song time: beat 0 is
/// the first sample of the audio, so a backing that starts on beat 0 stays in
/// step with every note. The tempo comes from [grid] when there is one (the
/// chart's beat lines then fall on the song's beats); otherwise 100 BPM, which
/// changes only where the beat lines are drawn — the notes keep their times,
/// because a note's beat and the chart's beat length use the same tempo.
PlayAlongChart melodyChart(
  List<NoteEvent> notes, {
  BeatGrid? grid,
  String name = 'song',
}) {
  final raw = grid?.bpm ?? 0;
  final bpm = raw.isFinite && raw >= 30 && raw <= 300 ? raw.round() : 100;
  final beatMs = 60000.0 / bpm;
  final kept = [
    for (final n in notes)
      if (n.offMs - n.onMs >= kMinSingNoteMs) n,
  ]..sort((a, b) => a.onMs.compareTo(b.onMs));
  return PlayAlongChart(
    name: name,
    bpm: bpm,
    octaveAgnostic: true, // a voice sings in its own octave
    notes: [
      for (final n in kept)
        TargetNote(
          midi: n.midi,
          startBeat: n.onMs / beatMs,
          beats: (n.offMs - n.onMs) / beatMs,
        ),
    ],
  );
}
