// lib/core/harmony/band_playback.dart
//
// The band, assembled: style + form + generators → one WAV.
//
// This is where BB-A2..A6 stop being separate libraries and become a sound.
// Everything above it is pure data; everything below it is the synth we already
// ship. Nothing here decides anything musical — the style says what plays, the
// realiser says where, the generators say which notes, and this file only
// places them on a timeline and mixes.
//
// It renders the WHOLE mix itself rather than going through
// `AudioService.playMixedTimedChords`, for one reason: that path renders every
// stem with the melodic voice, and the kit is not melodic. Building the mix
// here keeps `AudioService` untouched and hands it a finished WAV, which
// `playWavBytes` already accepts.
//
// ⚠️ `chart_playback.dart` is NOT replaced. It stays the simple, dependable
// path (one chord per bar, no style, no kit) and the screen can still use it —
// a band that fails to assemble must degrade to something that plays, not to
// silence.
library;

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/harmony/bass_generator.dart';
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_playback.dart' show barBeats;
import 'package:comet_beat/core/harmony/comp_arranger.dart';
import 'package:comet_beat/core/harmony/drum_generator.dart';
import 'package:comet_beat/core/harmony/form_realizer.dart';
import 'package:comet_beat/core/harmony/humanize.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';

/// Where a realised bar sits in time, so the screen can follow the playhead.
class BandBarSpan {
  const BandBarSpan({
    required this.startMs,
    required this.durationMs,
    required this.bar,
  });

  final int startMs;
  final int durationMs;
  final RealizedBar bar;

  int get endMs => startMs + durationMs;
}

/// A rendered band performance.
class BandPerformance {
  const BandPerformance({
    required this.wav,
    required this.bars,
    required this.totalMs,
    required this.beatMs,
  });

  /// PCM16 WAV, ready for `AudioService.playWavBytes`.
  final Uint8List wav;

  final List<BandBarSpan> bars;
  final int totalMs;
  final int beatMs;

  /// The bar sounding at [ms], or null past the end.
  BandBarSpan? barAt(int ms) {
    for (final span in bars) {
      if (ms >= span.startMs && ms < span.endMs) return span;
    }
    return null;
  }
}

/// How loud each role sits. Authored gains, not per-combination normalisation:
/// `mixStemsFloat` is unit-peak per stem × gain, so these ARE the balance.
class BandMix {
  const BandMix({
    this.comp = 0.55,
    this.bass = 0.75,
    this.drums = 0.7,
  });

  final double comp;
  final double bass;
  final double drums;
}

/// Renders [chart] as a band.
///
/// Returns null when there is nothing to play, rather than an empty WAV — a
/// caller must be able to tell "silence" from "no performance".
///
/// [extraStems] are mixed alongside the band — a melody over the top, say.
/// `mixStemsFloat` unit-peaks each stem independently before applying its gain,
/// so an extra stem CANNOT change the band's own contribution; that is what
/// makes "mute the melody, the band is untouched" true by construction rather
/// than by luck.
BandPerformance? renderBand(
  Chart chart, {
  required StyleSpec style,
  FormOptions form = const FormOptions(),
  BandMix mix = const BandMix(),
  bool humanize = true,
  int seed = 0,
  int sampleRate = kSampleRate,
  List<MixStem> extraStems = const [],
}) {
  final bars = realizeForm(chart, options: form);
  if (bars.isEmpty) return null;

  final bpm = chart.tempoBpm < 1 ? 1 : chart.tempoBpm;
  final beatMs = 60000 / bpm;

  // Pass 1 — place every bar on the clock.
  final spans = <BandBarSpan>[];
  var cursor = 0.0;
  for (final bar in bars) {
    final ms = barBeats(bar.meter) * beatMs;
    spans.add(
      BandBarSpan(
        startMs: cursor.round(),
        durationMs: ms.round(),
        bar: bar,
      ),
    );
    cursor += ms;
  }
  final totalMs = cursor.round();
  if (totalMs <= 0) return null;

  // Pass 2 — the comp is voiced across the WHOLE piece at once, so voice
  // leading is chosen over the form rather than bar by bar. Feeding
  // `arrangeComp` one bar at a time throws that away entirely.
  final compChords = [
    for (final bar in bars)
      if (bar.chords.isNotEmpty) bar.chords.first.chord,
  ];
  final voicings =
      compChords.isEmpty ? const <Voicing>[] : arrangeComp(compChords);
  var voicingCursor = 0;

  // Pass 3 — generate each role, bar by bar, onto absolute-time event lists.
  final compEvents = <Segment>[];
  final bassEvents = <Segment>[];
  final drumHits = <(int, Drum)>[];
  final drumGains = <double>[];

  var compClock = 0.0; // ms already covered by comp segments
  var bassClock = 0.0;
  int? previousBassMidi;
  var eventIndex = 0;

  for (var i = 0; i < bars.length; i++) {
    final bar = bars[i];
    final span = spans[i];
    final beats = barBeats(bar.meter);
    final level = style.levelAt(bar.intensity);

    // ---- drums -----------------------------------------------------------
    final drumPattern = level[StyleRole.drums];
    final kit = bar.role == BarRole.countIn
        ? countInBar(beats)
        : generateDrumBar(
            pattern: drumPattern,
            context: DrumContext(
              barIndex: i,
              beats: beats,
              isPhraseEnd: bar.isPhraseEnd,
              isSectionEnd: bar.isSectionEnd,
              isLastBar: bar.isLastBar,
              intensity: bar.intensity,
            ),
            seed: seed,
          );
    for (final hit in kit) {
      final placed = _place(
        hit.beat,
        hit.velocity,
        beats,
        humanize ? RoleFeel.drums : 0,
        style,
        humanize,
        seed,
        eventIndex++,
      );
      drumHits.add(
        (
          span.startMs + (placed.beat * beatMs).round(),
          _drumFor(hit.voice),
        ),
      );
      drumGains.add(placed.velocity);
    }

    // The count-in is kit only: playing the harmony over it would defeat it.
    if (bar.role == BarRole.countIn) {
      compEvents.add((freqs: const <double>[], ms: span.durationMs));
      bassEvents.add((freqs: const <double>[], ms: span.durationMs));
      compClock += span.durationMs;
      bassClock += span.durationMs;
      continue;
    }

    final voicing = bar.chords.isEmpty || voicingCursor >= voicings.length
        ? null
        : voicings[voicingCursor++];

    // ---- comp ------------------------------------------------------------
    final compPattern = level[StyleRole.comp] ?? level[StyleRole.pad];
    if (voicing != null && compPattern != null && compPattern.hits.isNotEmpty) {
      for (final hit in compPattern.hits) {
        if (hit.beat >= beats) continue; // truncated to this meter
        final placed = _place(
          hit.beat,
          hit.velocity,
          beats,
          humanize ? RoleFeel.comp : 0,
          style,
          humanize,
          seed,
          eventIndex++,
        );
        final atMs = span.startMs + placed.beat * beatMs;
        final lenMs =
            (hit.duration * beatMs).clamp(1.0, span.endMs - atMs).toDouble();
        compClock = _appendSegment(
          compEvents,
          compClock,
          atMs,
          lenMs,
          voicing.midis,
          placed.velocity,
        );
      }
    }

    // ---- bass ------------------------------------------------------------
    final bassPattern = level[StyleRole.bass];
    final chord =
        bar.chords.isEmpty ? chordAt(bars, i) : bar.chords.first.chord;
    if (bassPattern?.bassMode != null && chord != null) {
      final line = generateBassBar(
        chord: chord,
        next: nextChordAfter(bars, i),
        beats: beats,
        mode: bassPattern!.bassMode!,
        previousMidi: previousBassMidi,
        seed: seed,
        barIndex: i,
      );
      for (final note in line) {
        final placed = _place(
          note.beat,
          note.velocity,
          beats,
          humanize ? RoleFeel.bass : 0,
          style,
          humanize,
          seed,
          eventIndex++,
        );
        final atMs = span.startMs + placed.beat * beatMs;
        final lenMs =
            (note.duration * beatMs).clamp(1.0, span.endMs - atMs).toDouble();
        bassClock = _appendSegment(
          bassEvents,
          bassClock,
          atMs,
          lenMs,
          [note.midi],
          placed.velocity,
        );
      }
      if (line.isNotEmpty) previousBassMidi = line.last.midi;
    }
  }

  // Pass 4 — render and mix.
  final totalSamples = (totalMs * sampleRate) ~/ 1000;
  if (totalSamples <= 0) return null;

  final stems = <MixStem>[
    if (compEvents.isNotEmpty)
      (
        samples: renderSegmentsRaw(compEvents, sampleRate: sampleRate),
        gain: mix.comp
      ),
    if (bassEvents.isNotEmpty)
      (
        samples: renderSegmentsRaw(bassEvents, sampleRate: sampleRate),
        gain: mix.bass
      ),
    if (drumHits.isNotEmpty)
      (
        samples: renderDrumPattern(
          drumHits,
          totalMs: totalMs,
          sampleRate: sampleRate,
          gains: drumGains,
        ),
        gain: mix.drums
      ),
    ...extraStems,
  ];
  if (stems.isEmpty) return null;

  final mixed = mixStemsFloat(stems, totalSamples: totalSamples);
  final pcm = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    pcm[i] = (mixed[i].clamp(-1.0, 1.0) * 32767).round();
  }

  return BandPerformance(
    wav: wavBytes(pcm, sampleRate: sampleRate),
    bars: spans,
    totalMs: totalMs,
    beatMs: beatMs.round(),
  );
}

/// Applies the style's swing and the role's feel to one event.
Humanized _place(
  double beat,
  double velocity,
  double barBeatCount,
  double roleOffset,
  StyleSpec style,
  bool humanize,
  int seed,
  int index,
) =>
    humanizeEvent(
      beat: beat,
      velocity: velocity,
      barBeats: barBeatCount,
      spec: humanize
          ? HumanizeSpec(
              swing: style.swing,
              roleOffset: roleOffset,
              timingJitter: 0.008,
              velocityJitter: 0.06,
            )
          // Swing is NOT humanisation — it is the style. With humanising off
          // the feel goes, the swing stays, or turning off "humanise" would
          // silently straighten a swing chart.
          : HumanizeSpec(swing: style.swing),
      seed: seed,
      index: index,
    );

/// Appends silence up to [atMs] and then the note, returning the new clock.
///
/// `renderSegmentsRaw` lays segments end to end, so a part is built as
/// alternating rests and notes rather than as absolute times. Overlaps are
/// impossible in that model: a note that would start before the clock is
/// simply placed at the clock, which is what a monophonic part does anyway.
///
/// ⚠️ [velocity] is accepted and NOT used, and that is a real limitation rather
/// than an oversight: `Segment` is `(freqs, ms)` with no level field, so a
/// melodic part's dynamics come only from its stem gain. Per-note dynamics
/// would need a change to `Segment` in the shared `synth.dart`, which is not
/// this card's business. The KIT does get per-hit dynamics, because
/// `renderDrumPattern` takes a gains list.
double _appendSegment(
  List<Segment> into,
  double clock,
  double atMs,
  double lenMs,
  List<int> midis,
  // ignore: avoid_unused_constructor_parameters
  double velocity,
) {
  final gap = atMs - clock;
  var cursor = clock;
  if (gap > 0.5) {
    into.add((freqs: const <double>[], ms: gap.round()));
    cursor += gap.round();
  }
  final ms = lenMs.round().clamp(1, 1 << 20);
  into.add(
    (
      freqs: [
        for (final m in midis) midiToFrequency(m),
      ],
      ms: ms,
    ),
  );
  return cursor + ms;
}

/// Maps a style's voice ordinal onto the order-locked `Drum` palette.
///
/// Out-of-range falls back to the kick rather than throwing: a style is data,
/// and bad data must not crash the band.
Drum _drumFor(int voice) =>
    voice >= 0 && voice < Drum.values.length ? Drum.values[voice] : Drum.kick;
