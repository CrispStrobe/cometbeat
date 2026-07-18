// lib/core/audio/tracker_engine.dart
//
// Pure-Dart pattern-sequencer engine behind the Tracker (a touch-first take on
// ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker). A tracker is
// the Loop Mixer with an EDITABLE grid: each channel is a column of cells
// (one per row/step); rendering sums the channels through the same
// offline-mix-then-loop path the Loop Mixer uses (mixStems -> one seamless WAV,
// one player, sample-accurate sync). Flutter-free, like synth.dart /
// loop_engine.dart — unit-tested without a device.
//
// Slice 0 ships ADDITIVE instruments only (the built-in synth timbres). The
// [TrackerInstrument] abstraction is the seam where sfxr-generated and
// recorded/effected sample instruments plug in later (see
// docs/TRACKER_HANDOVER.md) without changing the engine.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/crisp_dsp/karplus.dart';
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_effects.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart';

export 'package:comet_beat/core/audio/tracker_effects.dart' show TrackerEffect;

/// The musical clock a pattern renders against. [rows] steps at [stepsPerBeat]
/// steps per beat, [tempoBpm] BPM. Pick values whose step length is an integral
/// number of ms (and of samples at 44.1 kHz) so every channel sums to exactly
/// the same sample count and the loop seam stays click-free — e.g. 120 BPM with
/// 4 steps/beat gives a 125 ms step. (Non-integral choices still play; they just
/// lean on mixStems' shorter-stem padding.)
class TrackerTiming {
  const TrackerTiming({
    this.tempoBpm = 120,
    this.rows = 16,
    this.stepsPerBeat = 4,
    this.swing = 0.0,
  })  : assert(tempoBpm > 0),
        assert(rows > 0),
        assert(stepsPerBeat > 0),
        assert(swing >= 0 && swing < 1);

  final int tempoBpm;
  final int rows;
  final int stepsPerBeat;

  /// Swing: 0 = straight. Delays each off-beat (odd) step's onset by
  /// `swing * stepMs` (≈0.66 = a triplet shuffle) — the even step rings longer,
  /// the odd one shorter. The loop's total length is unchanged.
  final double swing;

  int get beatMs => 60000 ~/ tempoBpm;
  int get stepMs => beatMs ~/ stepsPerBeat;
  int get totalMs => stepMs * rows;
  int get totalSamples => (totalMs * kSampleRate) ~/ 1000;
  Duration get loopLength => Duration(milliseconds: totalMs);

  /// The onset time (ms) of [step], swing-aware (off-beats delayed).
  double stepOnsetMs(int step) =>
      step * stepMs + (step.isOdd ? swing * stepMs : 0.0);

  /// The onset sample of [step], swing-aware.
  int stepStartSample(int step) =>
      (stepOnsetMs(step) * kSampleRate / 1000).round();

  TrackerTiming copyWith({
    int? tempoBpm,
    int? rows,
    int? stepsPerBeat,
    double? swing,
  }) =>
      TrackerTiming(
        tempoBpm: tempoBpm ?? this.tempoBpm,
        rows: rows ?? this.rows,
        stepsPerBeat: stepsPerBeat ?? this.stepsPerBeat,
        swing: swing ?? this.swing,
      );
}

/// One step in a channel column. An empty cell means "no trigger here" — it
/// either extends the previous note (let it ring) or is a rest if nothing is
/// sounding. [volume] (0..1) is reserved for the Studio skin; Slice 0 ignores it
/// and uses the channel gain.
class TrackerCell {
  const TrackerCell({
    this.midi,
    this.volume,
    this.effect = TrackerEffect.none,
    this.fxCmd = 0,
    this.fxParam = 0,
    this.instrument = 0,
  });

  final int? midi;
  final double? volume;

  /// The per-cell INSTRUMENT number (the classic tracker sample/instrument
  /// column): 0 = none (the note keeps the channel's current instrument), else a
  /// 1-based index into [TrackerSong.instruments]. Honoured by the replayer's
  /// additive voices (a note can switch timbre); a reference to a non-additive
  /// pool instrument is ignored for now (documented follow-up). Added additively
  /// — 0 everywhere leaves every existing render unchanged.
  final int instrument;

  /// A per-note effect command (arp/vibrato/slide). Honoured by additive voices
  /// (see [AdditiveInstrument]); other instruments ignore it. This is the simple
  /// legacy effect used by the Beginner grid.
  final TrackerEffect effect;

  /// The classic MOD-style effect COLUMN: a command nibble [fxCmd] (0x0–0xF) and
  /// an 8-bit parameter [fxParam] (0x00–0xFF), e.g. C20 = command 0xC param 0x20.
  /// `0/0` = no command. Applied by the tracker replayer (tracker_replay.dart);
  /// the Advanced tracker authors these. Kept alongside [effect] so nothing in
  /// the Beginner path changes.
  final int fxCmd;
  final int fxParam;

  bool get isEmpty => midi == null;

  /// Whether an effect-column command is present (any non-zero cmd/param).
  bool get hasCommand => fxCmd != 0 || fxParam != 0;

  static const empty = TrackerCell();

  @override
  bool operator ==(Object other) =>
      other is TrackerCell &&
      other.midi == midi &&
      other.volume == volume &&
      other.effect == effect &&
      other.fxCmd == fxCmd &&
      other.fxParam == fxParam &&
      other.instrument == instrument;

  @override
  int get hashCode =>
      Object.hash(midi, volume, effect, fxCmd, fxParam, instrument);
}

/// Collapses a channel's cells into runs using the classic tracker rule: a
/// non-empty cell triggers a note that rings across itself and every
/// immediately-following empty cell (until the next trigger); leading empties
/// are a rest. Each run is `(midi?, steps)` — `midi == null` is a rest. Runs sum
/// to exactly [TrackerTiming.rows] steps.
List<(int?, int)> cellRuns(List<TrackerCell> cells) {
  final runs = <(int?, int)>[];
  for (final cell in cells) {
    if (cell.isEmpty) {
      if (runs.isEmpty) {
        runs.add((null, 1)); // leading rest
      } else {
        final (m, s) = runs.last;
        runs[runs.length - 1] = (m, s + 1); // extend previous note or rest
      }
    } else {
      runs.add((cell.midi, 1));
    }
  }
  return runs;
}

/// The runs of [cells] as back-to-back [Segment]s (for the additive voices).
/// Segment durations follow the swing grid, so the concatenation swings.
List<Segment> cellsToSegments(List<TrackerCell> cells, TrackerTiming timing) {
  final segs = <Segment>[];
  var step = 0;
  for (final (midi, steps) in cellRuns(cells)) {
    final ms = timing.stepOnsetMs(step + steps) - timing.stepOnsetMs(step);
    segs.add(
      (
        freqs: midi == null ? const <double>[] : [midiToFrequency(midi)],
        ms: ms.round(),
      ),
    );
    step += steps;
  }
  return segs;
}

/// How a channel's cells become an un-normalized sample buffer. The seam for
/// non-additive instruments (sfxr, recorded samples) added in later slices.
abstract class TrackerInstrument {
  String get id;

  /// Render [cells] onto a buffer sized ~[TrackerTiming.totalSamples] (mixStems
  /// tolerates a shorter stem and pads it). Must not normalize — mixStems sets
  /// levels.
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing);
}

/// The Slice 0 instrument: one of the built-in additive [Instrument] voices.
class AdditiveInstrument implements TrackerInstrument {
  const AdditiveInstrument(this.id, this.instrument);

  @override
  final String id;
  final Instrument instrument;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final timbre = timbreFor(instrument);
    // Fast path: no per-note effects → the plain whole-channel additive render.
    final hasEffect =
        cells.any((c) => !c.isEmpty && c.effect != TrackerEffect.none);
    if (!hasEffect) {
      return renderSegmentsRaw(cellsToSegments(cells, timing), timbre: timbre);
    }
    // Effect path: render each note's run on its own so its effect can modulate
    // the frequency during synthesis, then place it on the timeline.
    final out = Float64List(timing.totalSamples);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final start = timing.stepStartSample(startStep);
        final ms = (timing.stepOnsetMs(startStep + steps) -
                timing.stepOnsetMs(startStep))
            .round();
        final effect = cells[startStep].effect;
        final buf = effect == TrackerEffect.none
            ? renderSegmentsRaw(
                [
                  (freqs: [midiToFrequency(midi)], ms: ms),
                ],
                timbre: timbre,
              )
            : renderNoteWithEffect(midi, ms, effect, timbre: timbre);
        final n = min(buf.length, out.length - start);
        for (var i = 0; i < n; i++) {
          out[start + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// A chiptune instrument: an sfxr preset (a frozen [SfxrParams]) synthesized at
/// each note's pitch (sfxr's `baseFreq` is set to the note frequency ÷ 440).
/// Every note is a one-shot that decays within its run — the classic tracker
/// sampled-voice feel. Deterministic via [seed] so the stem cache is stable.
class SfxrInstrument implements TrackerInstrument {
  const SfxrInstrument(this.id, this.params, {this.seed = 0});

  /// Builds an instrument from a named [SfxrPreset], freezing it with [seed].
  factory SfxrInstrument.preset(String id, SfxrPreset preset, {int seed = 0}) =>
      SfxrInstrument(id, preset(Random(seed)), seed: seed);

  @override
  final String id;
  final SfxrParams params;
  final int seed;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    final rng = Random(seed);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final startSample = timing.stepStartSample(startStep);
        final ms = timing.stepOnsetMs(startStep + steps) -
            timing.stepOnsetMs(startStep);
        final buf = sfxrGenerate(
          params.copyWith(baseFreq: midiToFrequency(midi) / 440),
          durationSec: ms / 1000,
          rng: rng,
        );
        final n = min(buf.length, out.length - startSample);
        for (var i = 0; i < n; i++) {
          out[startSample + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// A Karplus-Strong plucked-string instrument (guitar / harp / koto / plucked
/// bass) — a physical-model timbre that complements the additive voices without
/// any sample assets. Each note run is a fresh pluck at the note frequency,
/// decaying within its run like a real string; [damping] sets the sustain/decay
/// and [blend] the string↔percussive character. Deterministic via [seed] (stable
/// stem cache), so it plugs into the same offline-mix path as the other voices.
class KarplusInstrument implements TrackerInstrument {
  const KarplusInstrument(
    this.id, {
    this.damping = 0.996,
    this.blend = 1.0,
    this.seed = 0,
  });

  @override
  final String id;
  final double damping;
  final double blend;
  final int seed;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final startSample = timing.stepStartSample(startStep);
        final endSample = timing.stepStartSample(startStep + steps);
        final buf = karplusPluck(
          freq: midiToFrequency(midi),
          samples: endSample - startSample,
          damping: damping,
          blend: blend,
          // Per-note seed keeps the render deterministic yet varies the burst.
          seed: seed + startStep,
        );
        final n = min(buf.length, out.length - startSample);
        for (var i = 0; i < n; i++) {
          out[startSample + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// A sampled instrument: a recorded (optionally voice-effected) buffer played at
/// each note's pitch by classic tracker resampling — `ratio = noteFreq /
/// baseFreq`, so a higher note plays the sample faster (higher, shorter). The
/// note is capped at its run length (a one-shot note-off). [baseMidi] is the
/// pitch the recorded sample represents (default C4). This is the payload behind
/// "record your voice → play a tune with it".
class SampleInstrument implements TrackerInstrument {
  const SampleInstrument(
    this.id,
    this.sample, {
    this.baseMidi = 60,
    this.envelope = Envelope.declick,
    this.loopStart = 0,
    this.loopLength = 0,
  });

  /// Records-once: applies [fx] to [raw] and keeps the result as the sample.
  factory SampleInstrument.recorded(
    String id,
    Float64List raw,
    VoiceEffect fx, {
    int baseMidi = 60,
    int sampleRate = kSampleRate,
    Envelope envelope = Envelope.declick,
  }) =>
      SampleInstrument(
        id,
        applyVoiceEffect(raw, fx, sampleRate: sampleRate),
        baseMidi: baseMidi,
        envelope: envelope,
      );

  @override
  final String id;
  final Float64List sample;
  final int baseMidi;

  /// A per-note volume envelope (default a gentle declick attack/release).
  final Envelope envelope;

  /// Loop points (in samples of [sample], at the engine rate). [loopLength] `0`
  /// = no loop (a one-shot note, the default — byte-identical to before). When
  /// set, a note rings by repeating `[loopStart, loopStart+loopLength)` after the
  /// one-shot lead-in, so a sustained note doesn't cut off at the sample's end.
  final int loopStart;
  final int loopLength;

  bool get loops =>
      loopLength > 0 &&
      loopStart >= 0 &&
      loopStart + loopLength <= sample.length;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    if (sample.isEmpty) return out;
    final baseFreq = midiToFrequency(baseMidi);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      // 9xx sample offset (classic MOD): start the sample at param×256. Read from
      // the triggering cell's effect column; the cells already carry it here.
      final trigger = cells[startStep];
      final offset = trigger.fxCmd == 0x9 ? trigger.fxParam * 256 : 0;
      if (midi != null && offset < sample.length) {
        final src =
            offset > 0 ? Float64List.sublistView(sample, offset) : sample;
        final startSample = timing.stepStartSample(startStep);
        final runSamples =
            timing.stepStartSample(startStep + steps) - startSample;
        final baseRatio = midiToFrequency(midi) / baseFreq;
        final maxOut = min(runSamples, out.length - startSample);
        // Looping sample → a wrapping read-pointer fills the whole run (so a
        // sustained note doesn't cut off). Else the existing one-shot resample
        // (byte-identical): a pitch-envelope glide, or a fixed-ratio cubic.
        final buf = loops && maxOut > 0
            ? _resampleLooping(baseRatio, maxOut, offset)
            : envelope.pitchStart != 0 && maxOut > 0
                ? resampleGlide(
                    src,
                    ratioStart: baseRatio * pow(2, envelope.pitchStart / 12),
                    ratioEnd: baseRatio,
                    glideSamples: (envelope.pitchTime * kSampleRate).round(),
                    outLen: maxOut,
                  )
                : resampleCubic(src, baseRatio);
        final n = min(min(buf.length, runSamples), out.length - startSample);
        if (n > 0) {
          // Envelope only the played portion, so the release fades at the note's
          // end (not the end of the resampled sample).
          final voiced = applyEnvelope(
            Float64List.sublistView(buf, 0, n),
            envelope,
          );
          for (var i = 0; i < n; i++) {
            out[startSample + i] = voiced[i];
          }
        }
      }
      startStep += steps;
    }
    return out;
  }

  /// A [outLen]-sample render of a LOOPING sample at [ratio] (linear interp),
  /// starting at sample [startPos]. The lead-in `[0, loopStart+loopLength)` plays
  /// once, then `[loopStart, loopStart+loopLength)` repeats — so a note longer
  /// than the sample sustains instead of falling silent.
  Float64List _resampleLooping(double ratio, int outLen, int startPos) {
    final out = Float64List(outLen);
    final loopEnd = loopStart + loopLength;
    var pos = startPos.toDouble();
    for (var i = 0; i < outLen; i++) {
      var p = pos;
      if (p >= loopEnd) p = loopStart + ((p - loopStart) % loopLength);
      final idx = p.floor();
      if (idx >= sample.length - 1) {
        out[i] = idx < sample.length ? sample[idx] : 0.0;
      } else {
        final frac = p - idx;
        out[i] = sample[idx] * (1 - frac) + sample[idx + 1] * frac;
      }
      pos += ratio;
    }
    return out;
  }
}

/// A drum instrument: each non-empty cell is a one-shot hit (not held), the
/// cell's [TrackerCell.midi] encoding the [Drum] index (0 kick, 1 snare, 2 hat).
/// Renders via the Loop Mixer's noise percussion. Its rows are drums, not
/// pitches — the screen renders it with a drum row model.
class PercussionInstrument implements TrackerInstrument {
  const PercussionInstrument(this.id);

  @override
  final String id;

  /// The drums, ordered top row → bottom row on the grid.
  static const rows = [Drum.hat, Drum.snare, Drum.kick];

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final hits = <(int, Drum)>[];
    for (var step = 0; step < cells.length; step++) {
      final midi = cells[step].midi;
      if (midi != null) {
        final idx = midi.clamp(0, Drum.values.length - 1);
        hits.add((timing.stepOnsetMs(step).round(), Drum.values[idx]));
      }
    }
    return renderDrumPattern(hits, totalMs: timing.totalMs);
  }
}

/// An optional insert effect applied to a channel's stem (before mixStems).
enum TrackerChannelEffect {
  none,
  delay,
  chorus,
  flanger,
  reverb,
  ringMod,
  crunch,
}

/// Applies [fx] to a channel [stem] with kid-friendly default params, returning a
/// SAME-LENGTH buffer (so stems still line up for mixStems). [TrackerChannelEffect.none]
/// returns the stem unchanged.
Float64List applyChannelEffect(
  Float64List stem,
  TrackerChannelEffect fx, {
  int sampleRate = kSampleRate,
}) =>
    // The DSP functions' own defaults are the tuned kid-friendly params; only the
    // few overrides that differ from those defaults are passed here.
    switch (fx) {
      TrackerChannelEffect.none => stem,
      TrackerChannelEffect.delay => delayFx(
          stem,
          delayMs: 200,
          feedback: 0.3,
          mix: 0.3,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.chorus => chorusFx(
          stem,
          rateHz: 1.2,
          mix: 0.4,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.flanger => flangerFx(
          stem,
          mix: 0.4,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.reverb => reverbFx(stem, sampleRate: sampleRate),
      TrackerChannelEffect.ringMod => ringModFx(
          stem,
          carrierHz: 110,
          mix: 0.6,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.crunch => distortionFx(stem, drive: 3, mix: 0.7),
    };

/// Applies a CHAIN of insert effects to a [stem] in order (each same-length), for
/// the per-channel effect list. An empty chain returns the stem unchanged.
Float64List applyChannelEffects(
  Float64List stem,
  List<TrackerChannelEffect> effects, {
  int sampleRate = kSampleRate,
}) {
  var out = stem;
  for (final fx in effects) {
    out = applyChannelEffect(out, fx, sampleRate: sampleRate);
  }
  return out;
}

/// One editable column: an [instrument], an authored mix [gain], and [rows]
/// cells. Levels are combo-independent (each channel carries its gain into
/// mixStems' unit-peak-per-stem + soft-limiter mixdown), so editing one channel
/// never changes how loud the others are.
/// A per-channel VOLUME envelope: a level (0..1) shape over time (ms) applied on
/// top of a note's synthesized amplitude, so a note can fade in, swell, or fade
/// out independently of the instrument's own attack/decay. [points] are ascending
/// in ms with level 0..1; the level linearly interpolates between them, holds the
/// FIRST level before the first point and the LAST level after the last. Applied
/// by the replayer's additive voice only (see [levelAt]); null/empty = no change.
class VolumeEnvelope {
  const VolumeEnvelope(this.points);

  /// `(ms, level 0..1)` breakpoints, ascending in ms.
  final List<({int ms, double level})> points;

  bool get isEmpty => points.isEmpty;

  /// The envelope level at [ms] — linear interpolation between breakpoints,
  /// clamped/held at the ends.
  double levelAt(double ms) {
    if (points.isEmpty) return 1.0;
    if (ms <= points.first.ms) return points.first.level;
    for (var i = 1; i < points.length; i++) {
      final b = points[i];
      if (ms <= b.ms) {
        final a = points[i - 1];
        final span = b.ms - a.ms;
        if (span <= 0) return b.level;
        return a.level + (b.level - a.level) * ((ms - a.ms) / span);
      }
    }
    return points.last.level;
  }
}

/// A per-channel PAN envelope: pan (−1 left … +1 right) over a note's lifetime
/// (ms), added to the channel's base pan and clamped. Same breakpoint shape as
/// [VolumeEnvelope] (linear interp, holds the ends). Honoured by the replayer's
/// stereo render (uniform-timing path); null/empty = no auto-pan.
class PanEnvelope {
  const PanEnvelope(this.points);

  /// `(ms, pan −1..1)` breakpoints, ascending in ms.
  final List<({int ms, double pan})> points;

  bool get isEmpty => points.isEmpty;

  /// The pan offset at [ms] — linear interpolation, held at the ends.
  double panAt(double ms) {
    if (points.isEmpty) return 0.0;
    if (ms <= points.first.ms) return points.first.pan;
    for (var i = 1; i < points.length; i++) {
      final b = points[i];
      if (ms <= b.ms) {
        final a = points[i - 1];
        final span = b.ms - a.ms;
        if (span <= 0) return b.pan;
        return a.pan + (b.pan - a.pan) * ((ms - a.ms) / span);
      }
    }
    return points.last.pan;
  }
}

class TrackerChannel {
  TrackerChannel({
    required this.id,
    required this.instrument,
    required int rows,
    this.gain = 0.6,
    this.pan = 0.0,
    this.volumeEnvelope,
    this.panEnvelope,
    List<TrackerChannelEffect>? effects,
    List<TrackerCell>? cells,
  })  : effects = effects != null
            ? List<TrackerChannelEffect>.of(effects)
            : <TrackerChannelEffect>[],
        cells = cells != null
            ? List<TrackerCell>.of(cells)
            : List<TrackerCell>.filled(
                rows,
                TrackerCell.empty,
                growable: true,
              ) {
    assert(this.cells.length == rows, 'cells must be exactly $rows long');
  }

  final String id;

  /// Mutable so a channel can be re-voiced at runtime (e.g. assigning a freshly
  /// recorded [SampleInstrument] to the voice channel). Go through
  /// [TrackerEngine.setChannelInstrument] so caches are invalidated.
  TrackerInstrument instrument;

  /// The channel's mix level. Mutable — go through [TrackerEngine.setChannelGain]
  /// so the mixed WAV invalidates. (It scales the stem at mixdown, not the stem
  /// itself, so the per-channel stem cache is untouched.)
  double gain;

  /// The channel's stereo pan (−1 = hard left … 0 = centre … +1 = hard right).
  /// Mutable — go through [TrackerEngine.setChannelPan] so the mixed WAV
  /// invalidates. Like gain, it applies at the stereo mixdown, not to the stem,
  /// so the per-channel stem cache is untouched. Default 0 (centre) keeps every
  /// existing (mono) render unchanged.
  double pan;

  /// An optional per-channel [VolumeEnvelope] shaping each note's amplitude over
  /// time. Null = none (unchanged render). Honoured by the replayer's additive
  /// voice; set via [TrackerEngine.setChannelVolumeEnvelope] so the WAV
  /// invalidates. A song with any envelope routes through the replayer.
  VolumeEnvelope? volumeEnvelope;

  /// An optional per-channel [PanEnvelope] auto-panning each note over time
  /// (added to [pan], clamped). Null = none. Honoured by the replayer's stereo
  /// render; set via [TrackerEngine.setChannelPanEnvelope]. A song with any pan
  /// envelope [usesPan] → renders in stereo.
  PanEnvelope? panEnvelope;

  /// The channel's insert-effect CHAIN, applied to its stem in order (before
  /// mixStems). Empty = dry. Mutate via [TrackerEngine.setChannelEffects] so
  /// caches are invalidated.
  final List<TrackerChannelEffect> effects;
  final List<TrackerCell> cells;

  /// Muted channels are excluded from the mixdown (their stem is not summed).
  /// Mutate via [TrackerEngine.setChannelMuted] so the mixed WAV invalidates.
  bool muted = false;

  bool get hasAnyNote => cells.any((c) => !c.isEmpty);
}

/// Default Sandbox band: melodic additive voices plus one sfxr chiptune lead
/// (all pentatonic-friendly so the scale-locked kid grid always grooves). Drums
/// arrive with the percussion instrument in a later slice.
List<TrackerChannel> defaultTrackerChannels({int rows = 16}) => [
      TrackerChannel(
        id: 'melody',
        instrument: const AdditiveInstrument('piano', Instrument.piano),
        gain: 0.55,
        rows: rows,
      ),
      TrackerChannel(
        id: 'sparkle',
        instrument: const AdditiveInstrument('musicBox', Instrument.musicBox),
        gain: 0.40,
        rows: rows,
      ),
      TrackerChannel(
        id: 'zap',
        instrument: SfxrInstrument.preset('zap', sfxrZap, seed: 7),
        gain: 0.45,
        rows: rows,
      ),
      TrackerChannel(
        id: 'bass',
        instrument: const AdditiveInstrument('cello', Instrument.cello),
        gain: 0.55,
        rows: rows,
      ),
      TrackerChannel(
        id: 'drums',
        instrument: const PercussionInstrument('drums'),
        gain: 0.50,
        rows: rows,
      ),
      // Empty until the child records into it (renders silence meanwhile).
      TrackerChannel(
        id: 'voice',
        instrument: SampleInstrument('voice', Float64List(0)),
        rows: rows,
      ),
    ];

/// The family a sound belongs to, so a picker / sound-library browser can group
/// entries (like the Song Book groups songs). Derived from the instrument type
/// by [soundCategoryOf].
enum SoundCategory { tonal, plucked, chiptune, drum, recorded }

/// Classify a built [instrument] into a [SoundCategory] for the library browser.
SoundCategory soundCategoryOf(TrackerInstrument instrument) {
  if (instrument is KarplusInstrument) return SoundCategory.plucked;
  if (instrument is SfxrInstrument) return SoundCategory.chiptune;
  if (instrument is PercussionInstrument) return SoundCategory.drum;
  if (instrument is SampleInstrument) return SoundCategory.recorded;
  return SoundCategory.tonal; // additive + anything new/tonal
}

/// A selectable voice for the instrument picker / sound-library browser: a
/// stable [id] (matches the built instrument's `id`, for highlighting the
/// current choice + tests) and a factory. Additive timbres + a curated sfxr
/// palette + Karplus-Strong strings; the recorded `voice` instrument stays off
/// the palette (it's set by recording). [category] groups it in the browser
/// (derived from the built instrument's type).
class InstrumentOption {
  const InstrumentOption(this.id, this.build);

  final String id;
  final TrackerInstrument Function() build;

  /// The sound family this option belongs to (built once to classify).
  SoundCategory get category => soundCategoryOf(build());
}

/// The built-in sound library grouped by [SoundCategory] — the seam a Song
/// Book-style sound browser enumerates (tonal / plucked / chiptune first, drum /
/// recorded when present). Preserves [kTrackerInstruments] order within a group.
Map<SoundCategory, List<InstrumentOption>> soundLibraryByCategory() {
  final out = <SoundCategory, List<InstrumentOption>>{};
  for (final o in kTrackerInstruments) {
    (out[o.category] ??= []).add(o);
  }
  return out;
}

/// The picker palette / built-in sound library: four additive voices, seven
/// chiptune (sfxr) presets, and three Karplus-Strong plucked strings.
final List<InstrumentOption> kTrackerInstruments = [
  InstrumentOption(
    'piano',
    () => const AdditiveInstrument('piano', Instrument.piano),
  ),
  InstrumentOption(
    'cello',
    () => const AdditiveInstrument('cello', Instrument.cello),
  ),
  InstrumentOption(
    'flute',
    () => const AdditiveInstrument('flute', Instrument.flute),
  ),
  InstrumentOption(
    'musicBox',
    () => const AdditiveInstrument('musicBox', Instrument.musicBox),
  ),
  InstrumentOption('zap', () => SfxrInstrument.preset('zap', sfxrZap, seed: 7)),
  InstrumentOption(
    'blip',
    () => SfxrInstrument.preset('blip', sfxrBlip, seed: 3),
  ),
  InstrumentOption(
    'laser',
    () => SfxrInstrument.preset('laser', sfxrLaser, seed: 5),
  ),
  InstrumentOption(
    'coin',
    () => SfxrInstrument.preset('coin', sfxrCoin, seed: 11),
  ),
  InstrumentOption(
    'explosion',
    () => SfxrInstrument.preset('explosion', sfxrExplosion, seed: 13),
  ),
  InstrumentOption(
    'bell',
    () => SfxrInstrument.preset('bell', sfxrBell, seed: 17),
  ),
  // Karplus-Strong plucked strings — melodic, sample-free physical models.
  InstrumentOption('pluck', () => const KarplusInstrument('pluck')),
  InstrumentOption(
    'harp',
    () => const KarplusInstrument('harp', damping: 0.9985),
  ),
  InstrumentOption(
    'pluckBass',
    () => const KarplusInstrument('pluckBass', damping: 0.992),
  ),
];

/// Holds the pattern (channels × rows) + timing, edits cells, and renders the
/// current pattern to a loop-ready WAV. Caches per-channel stems and the mixed
/// WAV so an edit only re-synthesizes the channel that changed.
class TrackerEngine {
  TrackerEngine({List<TrackerChannel>? channels, TrackerTiming? timing})
      : _timing = timing ?? const TrackerTiming(),
        channels = channels ??
            defaultTrackerChannels(
              rows: (timing ?? const TrackerTiming()).rows,
            ) {
    for (final c in this.channels) {
      assert(
        c.cells.length == _timing.rows,
        'channel "${c.id}" has ${c.cells.length} cells, expected '
        '${_timing.rows}',
      );
    }
  }

  final List<TrackerChannel> channels;

  TrackerTiming _timing;
  TrackerTiming get timing => _timing;
  set timing(TrackerTiming value) {
    _timing = value;
    _stemCache.clear();
    _wav = null;
  }

  // Rendered stem per channel index (at the current timing) and the mixed WAV.
  final Map<int, Float64List> _stemCache = {};
  Uint8List? _wav;

  int get rows => _timing.rows;

  TrackerCell cellAt(int channel, int row) => channels[channel].cells[row];

  /// Re-voices [channel] (e.g. assigning a freshly recorded [SampleInstrument])
  /// and invalidates that channel's cached stem + the mixed WAV.
  void setChannelInstrument(int channel, TrackerInstrument instrument) {
    channels[channel].instrument = instrument;
    _stemCache.remove(channel);
    _wav = null;
  }

  /// Mutes/unmutes [channel] (excludes it from the mix) and invalidates the
  /// mixed WAV. The channel's stem cache is untouched — muting only changes
  /// which stems are summed, not the stems themselves.
  void setChannelMuted(int channel, bool muted) {
    if (channels[channel].muted == muted) return;
    channels[channel].muted = muted;
    _wav = null;
  }

  /// Sets a channel's mix [gain] (0..~1.2) and invalidates the mixed WAV. Like
  /// muting, gain scales at mixdown, so the per-channel stem cache is untouched.
  void setChannelGain(int channel, double gain) {
    if (channels[channel].gain == gain) return;
    channels[channel].gain = gain;
    _wav = null;
  }

  /// Sets a channel's stereo [pan] (−1..1) and invalidates the mixed WAV. Like
  /// gain, pan is applied at the stereo mixdown, so the per-channel stem cache is
  /// untouched.
  void setChannelPan(int channel, double pan) {
    if (channels[channel].pan == pan) return;
    channels[channel].pan = pan;
    _wav = null;
  }

  /// Sets a channel's [VolumeEnvelope] (null = none) and invalidates the mixed
  /// WAV. The envelope is honoured by the replayer's additive voice.
  void setChannelVolumeEnvelope(int channel, VolumeEnvelope? envelope) {
    channels[channel].volumeEnvelope = envelope;
    _wav = null;
  }

  /// Sets a channel's [PanEnvelope] (null = none) and invalidates the mixed WAV.
  void setChannelPanEnvelope(int channel, PanEnvelope? envelope) {
    channels[channel].panEnvelope = envelope;
    _wav = null;
  }

  /// Sets a channel's insert-effect CHAIN (applied to its stem in order before
  /// mixStems; `none` entries are dropped) and invalidates that channel's cached
  /// stem + the mixed WAV.
  void setChannelEffects(int channel, List<TrackerChannelEffect> effects) {
    final list = channels[channel].effects
      ..clear()
      ..addAll(effects);
    // Drop `none` — an empty chain is dry.
    list.removeWhere((e) => e == TrackerChannelEffect.none);
    _stemCache.remove(channel);
    _wav = null;
  }

  /// Replaces every cell of [channel] with [cells] (same length as the row
  /// count) — used to import a whole pattern (e.g. a Score). Invalidates caches.
  void setChannelCells(int channel, List<TrackerCell> cells) {
    final target = channels[channel].cells;
    assert(cells.length == target.length, 'cells length must match rows');
    for (var i = 0; i < target.length; i++) {
      target[i] = cells[i];
    }
    _stemCache.remove(channel);
    _wav = null;
  }

  /// Sets [row] of [channel] to [cell] and invalidates the affected caches.
  void setCell(int channel, int row, TrackerCell cell) {
    final cells = channels[channel].cells;
    if (cells[row] == cell) return;
    cells[row] = cell;
    _stemCache.remove(channel);
    _wav = null;
  }

  void clearCell(int channel, int row) =>
      setCell(channel, row, TrackerCell.empty);

  /// Sets the [volume] (a soft/ghost note, 0..1; null = normal) of the note at
  /// [row]. No-op on an empty cell — only notes carry dynamics.
  void setCellVolume(int channel, int row, double? volume) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      TrackerCell(
        midi: cur.midi,
        volume: volume,
        effect: cur.effect,
        fxCmd: cur.fxCmd,
        fxParam: cur.fxParam,
        instrument: cur.instrument,
      ),
    );
  }

  /// Sets the per-note [effect] of the note at [row]. No-op on an empty cell.
  void setCellEffect(int channel, int row, TrackerEffect effect) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      TrackerCell(
        midi: cur.midi,
        volume: cur.volume,
        effect: effect,
        fxCmd: cur.fxCmd,
        fxParam: cur.fxParam,
        instrument: cur.instrument,
      ),
    );
  }

  /// Tap-to-place/remove for the grid: placing [midi] where the same note
  /// already sits clears it; otherwise sets it. Returns the note now at the cell
  /// (null if cleared).
  int? toggleNote(int channel, int row, int midi) {
    final current = channels[channel].cells[row];
    if (current.midi == midi) {
      clearCell(channel, row);
      return null;
    }
    setCell(channel, row, TrackerCell(midi: midi));
    return midi;
  }

  /// Clears every cell in every channel.
  void clearAll() {
    for (final c in channels) {
      for (var i = 0; i < c.cells.length; i++) {
        c.cells[i] = TrackerCell.empty;
      }
    }
    _stemCache.clear();
    _wav = null;
  }

  bool get isEmpty => channels.every((c) => !c.hasAnyNote);

  /// The RMS level of [channel]'s stem over [windowSamples] starting at
  /// [startSample] — for a VU meter. 0 for a muted/silent channel. Uses the
  /// cached stem (already rendered during playback), so it's cheap per frame.
  double channelRms(int channel, int startSample, int windowSamples) {
    final ch = channels[channel];
    if (ch.muted || !ch.hasAnyNote) return 0;
    final s = _stem(channel);
    if (s.isEmpty) return 0;
    var sum = 0.0;
    var n = 0;
    for (var i = startSample;
        i < startSample + windowSamples && i < s.length;
        i++) {
      if (i < 0) continue;
      sum += s[i] * s[i];
      n++;
    }
    return n == 0 ? 0 : sqrt(sum / n) * ch.gain;
  }

  Float64List _stem(int channel) =>
      _stemCache[channel] ??= _renderWithDynamics(channel);

  /// Renders a channel, then scales each note's sample range by that note's
  /// [TrackerCell.volume] (a soft/ghost note) — a renderer-agnostic volume
  /// column: additive, sfxr, sampled and percussion voices all honour it.
  Float64List _renderWithDynamics(int channel) {
    final ch = channels[channel];
    final buf = ch.instrument.renderChannel(ch.cells, _timing);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(ch.cells)) {
      final vol = midi != null ? ch.cells[startStep].volume : null;
      if (vol != null && vol != 1.0) {
        final start = _timing.stepStartSample(startStep);
        final end = _timing.stepStartSample(startStep + steps);
        for (var i = start; i < end && i < buf.length; i++) {
          buf[i] *= vol;
        }
      }
      startStep += steps;
    }
    // Effect-column volume commands (Cxx/Axy) — a no-op when the channel has
    // none, so patterns without an effect column are untouched.
    final withVol = applyVolumeColumn(buf, ch.cells, _timing);
    return applyChannelEffects(withVol, ch.effects);
  }

  /// The current pattern mixed to PCM16 (one loop's worth). Used by [renderLoop]
  /// and by [renderSong] (which concatenates one per order-list entry).
  Int16List renderLoopPcm() => mixStems(
        [
          for (var i = 0; i < channels.length; i++)
            if (channels[i].hasAnyNote && !channels[i].muted)
              (samples: _stem(i), gain: channels[i].gain),
        ],
        totalSamples: _timing.totalSamples,
      );

  /// The current pattern mixed to INTERLEAVED stereo PCM16, honouring each
  /// channel's [TrackerChannel.pan] (constant-power). Used when the song
  /// [TrackerSong.usesPan]; centre-panned channels split equally, so a song with
  /// every pan at 0 spreads the mono mix evenly across both sides.
  Int16List renderLoopPcmStereo() => mixStemsStereo(
        [
          for (var i = 0; i < channels.length; i++)
            if (channels[i].hasAnyNote && !channels[i].muted)
              (
                samples: _stem(i),
                gain: channels[i].gain,
                pan: channels[i].pan,
              ),
        ],
        totalSamples: _timing.totalSamples,
      );

  /// The current pattern as one loop-ready WAV. An empty pattern renders silence
  /// of the full loop length.
  Uint8List renderLoop() => _wav ??= wavBytes(renderLoopPcm());

  /// A deep copy of every channel's cells — a pattern snapshot for arrangement.
  List<List<TrackerCell>> exportCells() =>
      [for (final c in channels) List<TrackerCell>.of(c.cells)];

  /// Loads a snapshot from [exportCells] back into the channels.
  void importCells(List<List<TrackerCell>> data) {
    for (var i = 0; i < channels.length && i < data.length; i++) {
      setChannelCells(i, data[i]);
    }
  }
}

/// Renders a song: the [patterns] (each a snapshot from [TrackerEngine.
/// exportCells]) played back-to-back into one long loop-ready WAV — the
/// arrangement / order-list. Uses [engine]'s band + timing; the engine's live
/// pattern is saved and restored, so this is side-effect-free to the caller.
Uint8List renderSong(
  TrackerEngine engine,
  List<List<List<TrackerCell>>> patterns,
) {
  if (patterns.isEmpty) return wavBytes(Int16List(0));
  final saved = engine.exportCells();
  final chunks = <Int16List>[];
  for (final pattern in patterns) {
    engine.importCells(pattern);
    chunks.add(engine.renderLoopPcm());
  }
  engine.importCells(saved);

  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Int16List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return wavBytes(out);
}

/// The stereo sibling of [renderSong]: concatenates each pattern's
/// [TrackerEngine.renderLoopPcmStereo] (interleaved L,R) into one 2-channel WAV,
/// honouring per-channel pan. Used by the song render when a pan is in play but
/// no effect commands are (the offline mix path). Side-effect-free.
Uint8List renderSongStereo(
  TrackerEngine engine,
  List<List<List<TrackerCell>>> patterns,
) {
  if (patterns.isEmpty) return wavBytesStereo(Int16List(0));
  final saved = engine.exportCells();
  final chunks = <Int16List>[];
  for (final pattern in patterns) {
    engine.importCells(pattern);
    chunks.add(engine.renderLoopPcmStereo());
  }
  engine.importCells(saved);

  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Int16List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return wavBytesStereo(out);
}
