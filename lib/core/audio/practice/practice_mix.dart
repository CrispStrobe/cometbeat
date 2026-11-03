// lib/core/audio/practice/practice_mix.dart
//
// The pure logic behind "practise with your own song": per-stem mute / solo /
// level, the windows the stem player streams, and the sing-along chart built
// from the vocal stem. No Flutter, no FFI — unit-tested in
// test/practice_mix_test.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/audio/practice/practice_split.dart'
    show mixtureConsistentInPlace;
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
  final out = [
    for (final s in stems)
      SeparatedStem(
        s.name,
        Float32List.fromList(Float32List.sublistView(s.left, 0, n)),
        Float32List.fromList(Float32List.sublistView(s.right, 0, n)),
        s.sampleRate,
      ),
  ];
  mixtureConsistentInPlace(out, left, right);
  return out;
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

/// What the stem player streams: [count] stereo stems, [frames] long, read a
/// window at a time — so a loop, or a slowed song, need never exist whole.
abstract interface class StemSource {
  int get count;
  int get frames;
  int get sampleRate;

  /// [frames] frames of stem [stem] from [start], interleaved `L,R,…`. Past
  /// the end it is shorter (possibly empty), never padded.
  Float32List window(int stem, int start, int frames);
}

/// Stems as they are.
class StemListSource implements StemSource {
  StemListSource(this.stems) : assert(stems.isNotEmpty);

  final List<SeparatedStem> stems;

  @override
  int get count => stems.length;
  @override
  int get frames => stems.map((s) => s.frames).reduce(math.min);
  @override
  int get sampleRate => stems.first.sampleRate;
  @override
  Float32List window(int stem, int start, int frames) {
    final int n = math.min(frames, this.frames - start);
    return interleavedWindow(stems[stem], start, n);
  }
}

/// Frames [start, end) of [stems], faded in and out over [fadeFrames] exactly
/// like [loopRegion], and — with a [plan] from [stretchGuide] + [planStretch] —
/// slowed exactly like [slowStems]. Rendered window by window from views of
/// the stems: nothing song-sized is copied.
class StemRegion implements StemSource {
  StemRegion(
    List<SeparatedStem> stems, {
    int start = 0,
    int? end,
    int fadeFrames = 0,
    this.plan,
  }) : assert(stems.isNotEmpty) {
    final int all = stems.map((s) => s.frames).reduce(math.min);
    _a = math.min(math.max(start, 0), all);
    final b = math.min(math.max(end ?? all, _a), all);
    _n = b - _a;
    _fade = math.min(fadeFrames, _n ~/ 2);
    _left = [for (final s in stems) Float32List.sublistView(s.left, _a, b)];
    _right = [for (final s in stems) Float32List.sublistView(s.right, _a, b)];
    _rate = stems.first.sampleRate;
  }

  /// The stretch, or null to play at speed.
  final StretchPlan? plan;
  late final int _a, _n, _fade, _rate;
  late final List<Float32List> _left, _right;

  /// Region frames before any stretch.
  int get regionFrames => _n;

  @override
  int get count => _left.length;
  @override
  int get frames => plan?.targetLen ?? _n;
  @override
  int get sampleRate => _rate;

  /// The [loopRegion] fade at region frame [i].
  double gain(int i) {
    if (i < _fade) return i / _fade;
    if (i >= _n - _fade) return (_n - 1 - i) / _fade;
    return 1;
  }

  @override
  Float32List window(int stem, int start, int frames) {
    final int from = math.min(math.max(start, 0), this.frames);
    final int to = math.min(this.frames, from + math.max(0, frames));
    final out = Float32List((to - from) * 2);
    final l = _left[stem], r = _right[stem];
    final p = plan;
    if (p == null) {
      for (var t = from, o = 0; t < to; t++, o += 2) {
        final g = gain(t);
        out[o] = l[t] * g;
        out[o + 1] = r[t] * g;
      }
      return out;
    }
    final fade = _fade == 0 ? null : gain;
    renderStretchSpan(p, l, from, to, out, stride: 2, gain: fade);
    renderStretchSpan(p, r, from, to, out, outStart: 1, stride: 2, gain: fade);
    return out;
  }

  /// The guide [timeStretchLinked] picks its splices on — the sum of every
  /// faded channel — in float32, built in slices so the UI isolate never
  /// stalls on a whole song. Feed it (as float64) to [planStretch].
  Future<Float32List> stretchGuide() async {
    final g = Float32List(_n);
    const slice = 1 << 16;
    for (var a = 0; a < _n; a += slice) {
      final b = math.min(_n, a + slice);
      for (var t = a; t < b; t++) {
        var sum = 0.0;
        for (var k = 0; k < _left.length; k++) {
          sum += _left[k][t] + _right[k][t];
        }
        g[t] = sum * gain(t);
      }
      await Future<void>.delayed(Duration.zero);
    }
    return g;
  }
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

/// The stems cut to `[startFrame, endFrame)` for a practice loop, with short
/// fades at both ends ([fadeFrames], ~5 ms at 44.1 kHz) so the seam where the
/// loop jumps back does not click.
List<SeparatedStem> loopRegion(
  List<SeparatedStem> stems,
  int startFrame,
  int endFrame, {
  int fadeFrames = 220,
}) {
  return [
    for (final s in stems)
      () {
        final a = math.min(math.max(startFrame, 0), s.frames);
        final b = math.min(math.max(endFrame, a), s.frames);
        final n = b - a;
        final l = Float32List.fromList(Float32List.sublistView(s.left, a, b));
        final r = Float32List.fromList(Float32List.sublistView(s.right, a, b));
        final f = math.min(fadeFrames, n ~/ 2);
        for (var i = 0; i < f; i++) {
          final g = i / f;
          l[i] *= g;
          r[i] *= g;
          l[n - 1 - i] *= g;
          r[n - 1 - i] *= g;
        }
        return SeparatedStem(s.name, l, r, s.sampleRate);
      }(),
  ];
}

/// [ms] moved to the nearest beat of [grid] (unchanged without one) — so a
/// practice loop starts and ends on the beat, not a few ms off it.
double snapToBeat(double ms, BeatGrid? grid) {
  final beats = grid?.beatMs;
  if (beats == null || beats.isEmpty) return ms;
  var best = beats.first;
  for (final b in beats) {
    if ((b - ms).abs() < (best - ms).abs()) best = b;
  }
  return best;
}

/// Slows the stems to [speed] (0.5 = half speed) without changing pitch, with
/// ONE shared WSOLA plan for every channel of every stem
/// ([timeStretchLinked]), so the parts stay locked together and the stereo
/// image holds. `deep` quality: the bass stem goes below what the default
/// frame can hold in tune. Heavy (~10 s of CPU per 30 s of 4 stereo stems) —
/// run it off the UI isolate.
List<SeparatedStem> slowStems(List<SeparatedStem> stems, double speed) {
  if (stems.isEmpty || speed >= 0.999) return stems;
  final channels = <Float64List>[
    for (final s in stems) ...[
      Float64List.fromList(s.left),
      Float64List.fromList(s.right),
    ],
  ];
  final out = timeStretchLinked(
    channels,
    1 / speed,
    quality: StretchQuality.deep,
  );
  return [
    for (var i = 0; i < stems.length; i++)
      SeparatedStem(
        stems[i].name,
        Float32List.fromList(out[2 * i]),
        Float32List.fromList(out[2 * i + 1]),
        stems[i].sampleRate,
      ),
  ];
}
