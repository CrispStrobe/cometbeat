// lib/core/harmony/song_with_band.dart
//
// BB-X8 — a rhythm section under any piece in the library.
//
// This is the bridge that turns library items into play-alongs: a notated score
// that carries chord symbols already has everything a band needs, so the band
// can play underneath while the melody plays, or while the student plays it
// themselves.
//
// 🔴 THE HARD PART IS ALIGNMENT, AND IT IS NOT OBVIOUS. The band's timeline is
// the REALISED form — count-in, tune, ending — while the melody is just the
// tune. Starting both at sample 0 puts the melody on top of the count-in and
// leaves it a bar early for the whole piece. So the melody is offset to the
// first TUNE bar of the realised timeline, and the offset is asserted at the
// sample level rather than trusted.
//
// The band is rendered by `renderBand` exactly as it is without a melody; the
// melody arrives as an extra stem. `mixStemsFloat` unit-peaks each stem before
// its gain, so adding or muting the melody cannot change what the band
// contributes — the acceptance criterion is true by construction.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/harmony/band_playback.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_score_bridge.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// A library piece playing with a band under it.
class SongWithBand {
  const SongWithBand({
    required this.performance,
    required this.chart,
    required this.melodyStartMs,
    required this.melodyNoteCount,
    this.losses = const [],
  });

  /// The mixed render, whose `bars` timeline drives any highlight.
  final BandPerformance performance;

  /// The chart the band played from — derived, so a caller can show it.
  final Chart chart;

  /// Where the melody begins in the mix. Non-zero whenever the form has a
  /// count-in, which is the whole alignment problem.
  final int melodyStartMs;

  final int melodyNoteCount;

  /// Anything the chord derivation could not carry.
  final List<BridgeLoss> losses;
}

/// Renders [score] with a band underneath.
///
/// Returns null when the score carries no chord symbols — there is nothing to
/// derive a band from, and a silent band would look like a bug rather than a
/// missing input.
SongWithBand? renderSongWithBand(
  Score score, {
  StyleSpec? style,
  FormOptions form = const FormOptions(),
  BandMix mix = const BandMix(),
  double melodyGain = 0.9,
  bool includeMelody = true,
  int? tempoBpm,
  bool humanize = true,
  int seed = 0,
  int sampleRate = kSampleRate,
}) {
  if (score.chordSymbols.isEmpty) return null;

  final derived = chartFromScore(score);
  var chart = derived.value;
  if (tempoBpm != null && tempoBpm > 0) {
    chart = _withTempo(chart, tempoBpm);
  }
  if (chart.isEmpty) return null;

  // The band first, and WITHOUT the melody, so its timeline is known before
  // anything is placed against it.
  final probe = renderBand(
    chart,
    style: style ?? styleFor(chart.styleId),
    form: form,
    mix: mix,
    humanize: humanize,
    seed: seed,
    sampleRate: sampleRate,
  );
  if (probe == null) return null;

  // ⚠️ The melody starts at the first TUNE bar, not at zero. With a count-in
  // those differ by a whole bar, and starting at zero would play the melody
  // over the count-in and a bar early for the entire piece.
  final firstTune = probe.bars.firstWhere(
    (b) => b.bar.role == BarRole.tune,
    orElse: () => probe.bars.first,
  );
  final melodyStartMs = firstTune.startMs;

  final beatMs = 60000 / (chart.tempoBpm < 1 ? 1 : chart.tempoBpm);
  final melody = _melodySegments(score, beatMs, melodyStartMs);

  final stems = <MixStem>[
    if (includeMelody && melody.notes > 0)
      (
        samples: renderSegmentsRaw(melody.segments, sampleRate: sampleRate),
        gain: melodyGain,
      ),
  ];

  final performance = renderBand(
    chart,
    style: style ?? styleFor(chart.styleId),
    form: form,
    mix: mix,
    humanize: humanize,
    seed: seed,
    sampleRate: sampleRate,
    extraStems: stems,
  );
  if (performance == null) return null;

  return SongWithBand(
    performance: performance,
    chart: chart,
    melodyStartMs: melodyStartMs,
    melodyNoteCount: melody.notes,
    losses: derived.losses,
  );
}

/// The score's notes as a segment list, preceded by [offsetMs] of silence.
///
/// `renderSegmentsRaw` lays segments end to end, so the offset IS a leading
/// rest — which is exactly how the melody is aligned to the band.
({List<Segment> segments, int notes}) _melodySegments(
  Score score,
  double beatMs,
  int offsetMs,
) {
  final segments = <Segment>[];
  if (offsetMs > 0) segments.add((freqs: const <double>[], ms: offsetMs));

  var notes = 0;
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      final beats = element is NoteElement
          ? element.duration.toFraction().toDouble() * 4
          : element is RestElement
              ? element.duration.toFraction().toDouble() * 4
              : 0.0;
      if (beats <= 0) continue;
      final ms = math.max(1, (beats * beatMs).round());

      if (element is NoteElement) {
        notes++;
        segments.add(
          (
            freqs: [
              for (final pitch in element.pitches)
                midiToFrequency(pitch.midiNumber),
            ],
            ms: ms,
          ),
        );
      } else {
        segments.add((freqs: const <double>[], ms: ms));
      }
    }
  }
  return (segments: segments, notes: notes);
}

Chart _withTempo(Chart chart, int bpm) => Chart(
      title: chart.title,
      composer: chart.composer,
      keyFifths: chart.keyFifths,
      minor: chart.minor,
      meter: chart.meter,
      tempoBpm: bpm,
      styleId: chart.styleId,
      sections: chart.sections,
      pickupBeats: chart.pickupBeats,
      extra: chart.extra,
    );

/// The band's own render, with no melody at all.
///
/// Exists so a caller — and a test — can show that muting the melody leaves the
/// band exactly as it was, rather than asserting it by listening.
Uint8List? bandOnly(
  Score score, {
  StyleSpec? style,
  FormOptions form = const FormOptions(),
  BandMix mix = const BandMix(),
  int? tempoBpm,
  bool humanize = true,
  int seed = 0,
  int sampleRate = kSampleRate,
}) =>
    renderSongWithBand(
      score,
      style: style,
      form: form,
      mix: mix,
      includeMelody: false,
      tempoBpm: tempoBpm,
      humanize: humanize,
      seed: seed,
      sampleRate: sampleRate,
    )?.performance.wav;
