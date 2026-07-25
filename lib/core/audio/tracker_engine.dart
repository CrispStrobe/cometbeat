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
import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/karplus.dart';
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
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
    this.nativeNote,
    this.nativeEffect = -1,
    this.nativeEffectParam = 0,
    this.nativeVolpan = -1,
    this.nativeFormat,
    this.volume,
    this.effect = TrackerEffect.none,
    this.fxCmd = 0,
    this.fxParam = 0,
    this.instrument = 0,
    this.keyOff = false,
  });

  TrackerCell copyWith({
    int? midi,
    bool clearMidi = false,
    int? nativeNote,
    bool clearNativeNote = false,
    int? nativeEffect,
    int? nativeEffectParam,
    bool clearNativeEffect = false,
    int? nativeVolpan,
    bool clearNativeVolpan = false,
    String? nativeFormat,
    double? volume,
    bool clearVolume = false,
    TrackerEffect? effect,
    int? fxCmd,
    int? fxParam,
    int? instrument,
    bool? keyOff,
  }) {
    return TrackerCell(
      midi: clearMidi ? null : (midi ?? this.midi),
      nativeNote: clearNativeNote || midi != null
          ? nativeNote
          : (nativeNote ?? this.nativeNote),
      nativeEffect: clearNativeEffect || fxCmd != null || fxParam != null
          ? -1
          : (nativeEffect ?? this.nativeEffect),
      nativeEffectParam: nativeEffectParam ?? this.nativeEffectParam,
      nativeVolpan: clearNativeVolpan || volume != null || clearVolume
          ? -1
          : (nativeVolpan ?? this.nativeVolpan),
      nativeFormat: nativeFormat ?? this.nativeFormat,
      volume: clearVolume ? null : (volume ?? this.volume),
      effect: effect ?? this.effect,
      fxCmd: fxCmd ?? this.fxCmd,
      fxParam: fxParam ?? this.fxParam,
      instrument: instrument ?? this.instrument,
      keyOff: keyOff ?? this.keyOff,
    );
  }

  final int? midi;

  /// Original module key used for native XM/IT keymap lookup. It is kept
  /// separate from [midi], which may already include an IT note-map transpose.
  /// Editing the MIDI note clears this provenance through [copyWith].
  final int? nativeNote;

  /// Original format command/volume-column provenance. It is used only when
  /// exporting back to the same format; editing the generic effect or volume
  /// fields clears it through [copyWith].
  final int nativeEffect;
  final int nativeEffectParam;
  final int nativeVolpan;
  final String? nativeFormat;
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

  /// Explicit command to trigger the release phase of the sounding instrument.
  final bool keyOff;

  /// Whether the cell is completely empty (no note, no volume, no effects).
  bool get isEmpty =>
      midi == null &&
      volume == null &&
      effect == TrackerEffect.none &&
      !hasCommand &&
      instrument == 0 &&
      !keyOff &&
      nativeEffect < 0 &&
      nativeVolpan < 0;

  /// Whether an effect-column command is present (any non-zero cmd/param).
  bool get hasCommand => fxCmd != 0 || fxParam != 0;

  static const empty = TrackerCell();

  /// A Note Cut command that instructs the instrument to enter its release phase.
  static const noteCut = TrackerCell(keyOff: true);
  bool get isNoteCut => keyOff;

  @override
  bool operator ==(Object other) =>
      other is TrackerCell &&
      other.midi == midi &&
      other.nativeNote == nativeNote &&
      other.nativeEffect == nativeEffect &&
      other.nativeEffectParam == nativeEffectParam &&
      other.nativeVolpan == nativeVolpan &&
      other.nativeFormat == nativeFormat &&
      other.volume == volume &&
      other.effect == effect &&
      other.fxCmd == fxCmd &&
      other.fxParam == fxParam &&
      other.instrument == instrument &&
      other.keyOff == keyOff;

  @override
  int get hashCode => Object.hash(
        midi,
        nativeNote,
        nativeEffect,
        nativeEffectParam,
        nativeVolpan,
        nativeFormat,
        volume,
        effect,
        fxCmd,
        fxParam,
        instrument,
        keyOff,
      );
}

/// Collapses a channel's cells into runs using the classic tracker rule: a
/// non-empty cell triggers a note that rings across itself and every
/// immediately-following empty cell (until the next trigger); leading empties
/// are a rest. Each run is `(midi?, steps)` — `midi == null` is a rest. Runs sum
/// to exactly [TrackerTiming.rows] steps.
/// Like [cellRuns], but separates the run into a sustain phase (up to a Note Cut
/// or New Note) and a release phase (from Note Cut to the New Note).
/// Returns `(midi, sustainSteps, releaseSteps)`.
List<(int?, int, int)> noteRuns(List<TrackerCell> cells) {
  final runs = <(int?, int, int)>[];
  int? currentMidi;
  int sustain = 0;
  int release = 0;
  bool inRelease = false;

  void push() {
    if (sustain > 0 || release > 0) {
      runs.add((currentMidi, sustain, release));
    }
  }

  for (final cell in cells) {
    if (cell.midi != null) {
      push();
      currentMidi = cell.midi;
      if (cell.keyOff) {
        sustain = 0;
        release = 1;
        inRelease = true;
      } else {
        sustain = 1;
        release = 0;
        inRelease = false;
      }
    } else if (cell.keyOff) {
      if (!inRelease) inRelease = true;
      release++;
    } else {
      if (inRelease) {
        release++;
      } else {
        sustain++;
      }
    }
  }
  push();
  return runs;
}

List<(int?, int)> cellRuns(List<TrackerCell> cells) {
  return noteRuns(cells).map((r) => (r.$1, r.$2 + r.$3)).toList();
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

/// A two-operator FM instrument (electric piano / bell / tine / FM bass) — a
/// [FmPreset] synthesized fresh at each note's frequency. Struck-and-mellowing
/// timbres the additive/sfxr voices can't make, with no sample assets. Pure/
/// deterministic → stable stem cache.
class FmInstrument implements TrackerInstrument {
  const FmInstrument(this.id, this.preset);

  /// Builds from a named [kFmPresets] entry.
  factory FmInstrument.preset(String id, FmPreset preset) =>
      FmInstrument(id, preset);

  @override
  final String id;
  final FmPreset preset;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) =>
      _renderPerNote(
        cells,
        timing,
        (freq, samples) => fmVoice(
          freq: freq,
          samples: samples,
          ratio: preset.ratio,
          index: preset.index,
          indexDecay: preset.indexDecay,
          ampDecay: preset.ampDecay,
        ),
      );
}

/// A subtractive instrument (pad / lead / synth bass) — a saw/square oscillator
/// through an envelope-swept lowpass, synthesized per note from a [SubPreset].
/// The sustained/analog side of the melodic palette. Pure → stable stem cache.
class SubtractiveInstrument implements TrackerInstrument {
  const SubtractiveInstrument(this.id, this.preset);

  /// Builds from a named [kSubPresets] entry.
  factory SubtractiveInstrument.preset(String id, SubPreset preset) =>
      SubtractiveInstrument(id, preset);

  @override
  final String id;
  final SubPreset preset;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) =>
      _renderPerNote(
        cells,
        timing,
        (freq, samples) => subtractiveVoice(
          freq: freq,
          samples: samples,
          wave: preset.wave,
          cutoffStart: preset.cutoffStart,
          cutoffEnd: preset.cutoffEnd,
          cutoffDecay: preset.cutoffDecay,
          ampDecay: preset.ampDecay,
        ),
      );
}

/// Shared per-note render for the procedural voices ([FmInstrument],
/// [SubtractiveInstrument]): each note run is synthesized by [voice] at its
/// frequency over its exact sample span and placed on the timeline.
Float64List _renderPerNote(
  List<TrackerCell> cells,
  TrackerTiming timing,
  Float64List Function(double freq, int samples) voice,
) {
  final out = Float64List(timing.totalSamples);
  var startStep = 0;
  for (final (midi, steps) in cellRuns(cells)) {
    if (midi != null) {
      final start = timing.stepStartSample(startStep);
      final end = timing.stepStartSample(startStep + steps);
      final buf = voice(midiToFrequency(midi), end - start);
      final n = min(buf.length, out.length - start);
      for (var i = 0; i < n; i++) {
        out[start + i] = buf[i];
      }
    }
    startStep += steps;
  }
  return out;
}

/// A sampled instrument: a recorded (optionally voice-effected) buffer played at
/// each note's pitch by classic tracker resampling — `ratio = noteFreq /
/// baseFreq`, so a higher note plays the sample faster (higher, shorter). The
/// note is capped at its run length (a one-shot note-off). [baseMidi] is the
/// pitch the recorded sample represents (default C4). This is the payload behind
/// "record your voice → play a tune with it".
/// Fold a monotonically-increasing read position [pos] into the actual (still
/// fractional, for interpolation) sample position for a loop
/// `[loopStart, loopStart+loopLen)`. Before the loop end it is [pos] unchanged
/// (the one-shot lead-in + first pass). After it, a FORWARD loop wraps
/// (`% loopLen`); a [pingPong] loop bounces — a triangle over period `2·loopLen`
/// (forward loopStart→loopEnd, then backward loopEnd→loopStart, repeat). The
/// returned position is a real point in sample space, so linear interpolation
/// between its floor/ceil neighbours is correct in either direction.
double foldLoopPosition(
  double pos,
  int loopStart,
  int loopLen, {
  required bool pingPong,
}) {
  final loopEnd = loopStart + loopLen;
  if (pos < loopEnd || loopLen <= 0) return pos;
  if (!pingPong) return loopStart + ((pos - loopStart) % loopLen);
  final period = 2 * loopLen;
  final q = (pos - loopStart) % period;
  return q < loopLen ? loopStart + q : loopStart + (period - q);
}

class SampleInstrument implements TrackerInstrument {
  const SampleInstrument(
    this.id,
    this.sample, {
    this.baseMidi = 60,
    this.envelope = Envelope.declick,
    this.loopStart = 0,
    this.loopLength = 0,
    this.sustainLoopStart = 0,
    this.sustainLoopLength = 0,
    this.sustainPingPong = false,
    this.offsetScale = 1.0,
    this.pingPong = false,
    this.volume = 1.0,
    this.normalize = true,
    this.sampleRight,
    this.nativeVolumeEnvelope,
    this.nativePanEnvelope,
    this.nativeNna = 0,
    this.nativeDct = 0,
    this.nativeDca = 0,
    this.nativeFadeout = 0,
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

  /// Optional right channel for native stereo module samples.
  final Float64List? sampleRight;

  /// Tracker-native instrument envelope, expressed in milliseconds. It is
  /// evaluated per note so a per-cell sample switch also switches envelopes.
  final VolumeEnvelope? nativeVolumeEnvelope;

  /// Tracker-native pan envelope, evaluated from each note onset.
  final PanEnvelope? nativePanEnvelope;

  /// IT/XM old-note action metadata. NNA values follow IT: 0=cut,
  /// 1=continue, 2=note-off, 3=fade.
  final int nativeNna;
  final int nativeDct;
  final int nativeDca;
  final int nativeFadeout;
  final int baseMidi;

  /// A per-note volume envelope (default a gentle declick attack/release).
  final Envelope envelope;

  /// Loop points (in samples of [sample], at the engine rate). [loopLength] `0`
  /// = no loop (a one-shot note, the default — byte-identical to before). When
  /// set, a note rings by repeating `[loopStart, loopStart+loopLength)` after the
  /// one-shot lead-in, so a sustained note doesn't cut off at the sample's end.
  final int loopStart;
  final int loopLength;

  /// IT sustain loop, used while a note is held. After an explicit key-off the
  /// ordinary playback loop is used, matching IT's two-loop model.
  final int sustainLoopStart;
  final int sustainLoopLength;
  final bool sustainPingPong;

  /// A bidirectional ("ping-pong") loop bounces forward → backward → forward
  /// through `[loopStart, loopStart+loopLength)` instead of wrapping (the IT/XM
  /// bidi-loop flag). Default false = the plain forward loop (byte-identical).
  final bool pingPong;

  /// Converts a `9xx` sample-offset param (in ORIGINAL module-sample units) to
  /// this buffer's units. When the module PCM was resampled to the engine rate
  /// (ratio = c5speed/engineRate), the same offset lands `engineRate/c5speed`×
  /// deeper — the bridge sets this to that factor. `1.0` (default) for a sample
  /// already at the engine rate (byte-identical to before).
  final double offsetScale;

  /// Native module/sample volume, normalized from the format's 0..64 field.
  final double volume;

  /// Imported module samples retain their native amplitude instead of being
  /// peak-normalized as user-recorded samples are.
  final bool normalize;

  SampleInstrument copyWith({
    String? id,
    Float64List? sample,
    int? baseMidi,
    Envelope? envelope,
    int? loopStart,
    int? loopLength,
    int? sustainLoopStart,
    int? sustainLoopLength,
    bool? sustainPingPong,
    double? offsetScale,
    bool? pingPong,
    double? volume,
    bool? normalize,
    Float64List? sampleRight,
    VolumeEnvelope? nativeVolumeEnvelope,
    PanEnvelope? nativePanEnvelope,
    int? nativeNna,
    int? nativeDct,
    int? nativeDca,
    int? nativeFadeout,
  }) =>
      SampleInstrument(
        id ?? this.id,
        sample ?? this.sample,
        baseMidi: baseMidi ?? this.baseMidi,
        envelope: envelope ?? this.envelope,
        loopStart: loopStart ?? this.loopStart,
        loopLength: loopLength ?? this.loopLength,
        sustainLoopStart: sustainLoopStart ?? this.sustainLoopStart,
        sustainLoopLength: sustainLoopLength ?? this.sustainLoopLength,
        sustainPingPong: sustainPingPong ?? this.sustainPingPong,
        offsetScale: offsetScale ?? this.offsetScale,
        pingPong: pingPong ?? this.pingPong,
        volume: volume ?? this.volume,
        normalize: normalize ?? this.normalize,
        sampleRight: sampleRight ?? this.sampleRight,
        nativeVolumeEnvelope: nativeVolumeEnvelope ?? this.nativeVolumeEnvelope,
        nativePanEnvelope: nativePanEnvelope ?? this.nativePanEnvelope,
        nativeNna: nativeNna ?? this.nativeNna,
        nativeDct: nativeDct ?? this.nativeDct,
        nativeDca: nativeDca ?? this.nativeDca,
        nativeFadeout: nativeFadeout ?? this.nativeFadeout,
      );

  bool get loops =>
      loopLength > 0 &&
      loopStart >= 0 &&
      loopStart + loopLength <= sample.length;

  bool get sustainLoops =>
      sustainLoopLength > 0 &&
      sustainLoopStart >= 0 &&
      sustainLoopStart + sustainLoopLength <= sample.length;

  /// Renders a native stereo sample without flattening its right channel.
  ({Float64List left, Float64List right}) renderChannelStereo(
    List<TrackerCell> cells,
    TrackerTiming timing,
  ) =>
      (
        left: _renderChannelFrom(sample, cells, timing),
        right: _renderChannelFrom(sampleRight ?? sample, cells, timing),
      );

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) =>
      _renderChannelFrom(sample, cells, timing);

  Float64List _renderChannelFrom(
      Float64List source, List<TrackerCell> cells, TrackerTiming timing,
      {bool applyNativeAction = true}) {
    if (applyNativeAction &&
        (nativeNna != 0 || nativeDct != 0) &&
        (identical(source, sample) || identical(source, sampleRight))) {
      return _renderWithNativeNoteAction(source, cells, timing);
    }
    final out = Float64List(timing.totalSamples);
    if (source.isEmpty) return out;
    final baseFreq = midiToFrequency(baseMidi);
    var startStep = 0;
    for (final run in noteRuns(cells)) {
      final midi = run.$1;
      final sustainSteps = run.$2;
      final releaseSteps = run.$3;
      final steps = sustainSteps + releaseSteps;

      // 9xx sample offset (classic MOD): start the sample at param×256. Read from
      // the triggering cell's effect column; the cells already carry it here.
      final trigger = cells[startStep];
      final offset = trigger.fxCmd == 0x9
          ? (trigger.fxParam * 256 * offsetScale).round()
          : 0;
      if (midi != null && offset < source.length) {
        final src =
            offset > 0 ? Float64List.sublistView(source, offset) : source;
        final startSample = timing.stepStartSample(startStep);
        final runSamples =
            timing.stepStartSample(startStep + steps) - startSample;
        final sustainSamples =
            timing.stepStartSample(startStep + sustainSteps) - startSample;
        final baseRatio = midiToFrequency(midi) / baseFreq;
        final maxOut = min(runSamples, out.length - startSample);
        // Looping sample → a wrapping read-pointer fills the whole run (so a
        // sustained note doesn't cut off). Else the existing one-shot resample
        // (byte-identical): a pitch-envelope glide, or a fixed-ratio cubic.
        final useSustainLoop = sustainLoops && releaseSteps == 0;
        final playbackLoop = useSustainLoop || loops;
        final playbackLoopStart = useSustainLoop ? sustainLoopStart : loopStart;
        final playbackLoopLength =
            useSustainLoop ? sustainLoopLength : loopLength;
        final playbackPingPong = useSustainLoop ? sustainPingPong : pingPong;
        final buf = playbackLoop && maxOut > 0
            ? _resampleLooping(
                source,
                baseRatio,
                maxOut,
                offset,
                loopStart: playbackLoopStart,
                loopLength: playbackLoopLength,
                pingPong: playbackPingPong,
              )
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
          // - explicit key-off: use sustainSamples (enter ADSR release)
          // - normal retrigger: use n (sustain until boundary, then hard choke)
          // - natural pattern end / sample end: fit release at end (declick)
          final rSamples = (envelope.release * kSampleRate).round();
          final isPatternEnd = (startSample + runSamples) > out.length;
          final naturallyEnds = !loops && buf.length <= runSamples;

          int? effectiveSustain;
          if (releaseSteps > 0) {
            effectiveSustain = sustainSamples;
          } else if (isPatternEnd || naturallyEnds) {
            effectiveSustain = max(0, n - rSamples);
          } else {
            effectiveSustain = n;
          }

          final voiced = applyEnvelope(
            Float64List.sublistView(buf, 0, n),
            envelope,
            sustainSamples: effectiveSustain,
          );
          // A per-cell volume column scales the note (null = full, unchanged).
          final vol = trigger.volume ?? 1.0;
          final nativeVol = nativeVolumeEnvelope;
          for (var i = 0; i < n; i++) {
            final env = nativeVol?.levelAt(
                  i / kSampleRate * 1000,
                  released: i >= effectiveSustain,
                ) ??
                1.0;
            out[startSample + i] = voiced[i] * vol * volume * env;
          }
        }
      }
      startStep += steps;
    }
    return out;
  }

  Float64List _renderWithNativeNoteAction(
    Float64List source,
    List<TrackerCell> cells,
    TrackerTiming timing,
  ) {
    final out = Float64List(timing.totalSamples);
    final starts = <int>[];
    for (var row = 0; row < cells.length; row++) {
      final cell = cells[row];
      if (cell.midi != null && cell.fxCmd != 0x3 && cell.fxCmd != 0x5) {
        starts.add(row);
      }
    }
    for (var n = 0; n < starts.length; n++) {
      final row = starts[n];
      final startSample = timing.stepStartSample(row);
      var duplicate = -1;
      for (var candidate = n + 1; candidate < starts.length; candidate++) {
        final sameNote = cells[starts[candidate]].midi == cells[row].midi;
        final matches =
            nativeDct == 0 || nativeDct >= 2 || (nativeDct == 1 && sameNote);
        if (matches) {
          duplicate = candidate;
          break;
        }
      }
      final nextSample = duplicate >= 0
          ? timing.stepStartSample(starts[duplicate])
          : timing.totalSamples;
      final one = List<TrackerCell>.filled(cells.length, TrackerCell.empty)
        ..[row] = cells[row];
      final voice = _renderChannelFrom(
        source,
        one,
        timing,
        applyNativeAction: false,
      );
      // Continue keeps the old voice. Note-off/cut ends it at the next trigger.
      // Fade keeps it and applies the IT fade curve after the next trigger.
      final action = duplicate >= 0 && nativeDct != 0 ? nativeDca : nativeNna;
      final keep = action == 1 || action == 3;
      final end = keep ? timing.totalSamples : nextSample;
      for (var i = startSample; i < end && i < out.length; i++) {
        var gain = 1.0;
        if (action == 3 && i >= nextSample) {
          final seconds = (i - nextSample) / kSampleRate;
          final rate = nativeFadeout / 1024.0;
          gain = exp(-rate * seconds * 8.0);
        }
        out[i] += voice[i] * gain;
      }
    }
    return out;
  }

  /// A [outLen]-sample render of a LOOPING sample at [ratio] (linear interp),
  /// starting at sample [startPos]. The lead-in `[0, loopStart+loopLength)` plays
  /// once, then `[loopStart, loopStart+loopLength)` repeats — so a note longer
  /// than the sample sustains instead of falling silent.
  Float64List _resampleLooping(
    Float64List source,
    double ratio,
    int outLen,
    int startPos, {
    int? loopStart,
    int? loopLength,
    bool? pingPong,
  }) {
    final activeLoopStart = loopStart ?? this.loopStart;
    final activeLoopLength = loopLength ?? this.loopLength;
    final activePingPong = pingPong ?? this.pingPong;
    final out = Float64List(outLen);
    var pos = startPos.toDouble();
    for (var i = 0; i < outLen; i++) {
      final p = foldLoopPosition(
        pos,
        activeLoopStart,
        activeLoopLength,
        pingPong: activePingPong,
      );
      final idx = p.floor();
      if (idx >= source.length - 1) {
        out[i] = idx < source.length ? source[idx] : 0.0;
      } else {
        final frac = p - idx;
        out[i] = source[idx] * (1 - frac) + source[idx + 1] * frac;
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

/// An instrument composed of multiple sub-instruments mapped across the keyboard.
/// Essential for drum kits (where each key triggers a distinct sample) or realistic
class MultiSampleInstrument implements TrackerInstrument {
  const MultiSampleInstrument(
    this.id,
    this.zones, {
    this.polyphonic = false,
    this.nativeVoiceSemantics = false,
  });

  MultiSampleInstrument copyWith({
    String? id,
    Map<int, TrackerInstrument>? zones,
    bool? polyphonic,
    bool? nativeVoiceSemantics,
  }) =>
      MultiSampleInstrument(
        id ?? this.id,
        zones ?? this.zones,
        polyphonic: polyphonic ?? this.polyphonic,
        nativeVoiceSemantics: nativeVoiceSemantics ?? this.nativeVoiceSemantics,
      );

  @override
  final String id;

  /// If true, notes are not choked by subsequent notes on the channel (drum kit mode).
  final bool polyphonic;

  /// Whether this zone map came from a format with IT-style NNA/DCT/DCA
  /// instrument semantics. XM's multi-sample instruments are polyphonic but
  /// do not have these old-voice actions, so this must be explicit rather than
  /// inferred from [polyphonic].
  final bool nativeVoiceSemantics;

  /// Maps a base MIDI note to the [TrackerInstrument] representing that zone.
  final Map<int, TrackerInstrument> zones;

  TrackerInstrument? _closestZone(int midi) {
    if (zones.isEmpty) return null;
    if (zones.containsKey(midi)) return zones[midi]!;

    int bestDist = 9999;
    TrackerInstrument? best;
    for (final key in zones.keys) {
      final dist = (key - midi).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = zones[key];
      }
    }
    return best;
  }

  /// Resolves the native note-to-zone mapping for renderer/editor bridges.
  /// Exact-key matches win; otherwise the nearest mapped key is used, matching
  /// the tracker import behavior for sparse XM/IT keymaps.
  TrackerInstrument? zoneForNote(int midi) => _closestZone(midi);

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    if (nativeVoiceSemantics) {
      return _renderNativeVoices(cells, timing).left;
    }
    final out = Float64List(timing.totalSamples);
    if (zones.isEmpty) return out;

    var startStep = 0;
    for (final run in noteRuns(cells)) {
      final midi = run.$1;
      final sustainSteps = run.$2;
      final releaseSteps = run.$3;
      final totalSteps = sustainSteps + releaseSteps;

      if (midi != null) {
        final zone = _closestZone(cells[startStep].nativeNote ?? midi);
        if (zone != null) {
          // Isolate this note run so the sub-instrument accurately envelopes it
          final dummyCells =
              List.generate(timing.rows, (i) => const TrackerCell());
          dummyCells[startStep] = cells[startStep];

          if (!polyphonic) {
            if (startStep + sustainSteps < timing.rows) {
              // Properly trigger the release phase in the sub-instrument.
              dummyCells[startStep + sustainSteps] = TrackerCell.noteCut;
            }
          }

          final zoneStem = zone.renderChannel(dummyCells, timing);

          final startSample = timing.stepStartSample(startStep);
          final maxSample = polyphonic
              ? out.length
              : min(timing.stepStartSample(startStep + totalSteps), out.length);

          for (var i = startSample; i < maxSample; i++) {
            if (polyphonic) {
              out[i] += zoneStem[i];
            } else {
              out[i] = zoneStem[i];
            }
          }
        }
      }
      startStep += totalSteps;
    }
    return out;
  }

  /// Stereo counterpart used by native XM/IT zone imports. A zone that owns a
  /// right-channel sample keeps that image; procedural/mono zones are copied
  /// to both outputs and are panned by the caller.
  ({Float64List left, Float64List right}) renderChannelStereo(
    List<TrackerCell> cells,
    TrackerTiming timing,
  ) {
    if (nativeVoiceSemantics) return _renderNativeVoices(cells, timing);
    final left = Float64List(timing.totalSamples);
    final right = Float64List(timing.totalSamples);
    if (zones.isEmpty) return (left: left, right: right);

    var startStep = 0;
    for (final run in noteRuns(cells)) {
      final midi = run.$1;
      final sustainSteps = run.$2;
      final releaseSteps = run.$3;
      final totalSteps = sustainSteps + releaseSteps;
      if (midi != null) {
        final zone = _closestZone(cells[startStep].nativeNote ?? midi);
        if (zone != null) {
          final dummyCells =
              List<TrackerCell>.filled(timing.rows, TrackerCell.empty);
          dummyCells[startStep] = cells[startStep];
          if (!polyphonic && startStep + sustainSteps < timing.rows) {
            dummyCells[startStep + sustainSteps] = releaseSteps > 0
                ? TrackerCell.noteCut
                : TrackerCell(midi: midi);
          }
          final zoneStereo = zone is SampleInstrument
              ? zone.renderChannelStereo(dummyCells, timing)
              : null;
          final zoneLeft =
              zoneStereo?.left ?? zone.renderChannel(dummyCells, timing);
          final zoneRight = zoneStereo?.right;
          final startSample = timing.stepStartSample(startStep);
          final maxSample = polyphonic
              ? left.length
              : min(
                  timing.stepStartSample(startStep + totalSteps), left.length);
          for (var i = startSample; i < maxSample; i++) {
            if (polyphonic) {
              left[i] += zoneLeft[i];
              right[i] += zoneRight?[i] ?? zoneLeft[i];
            } else {
              left[i] = zoneLeft[i];
              right[i] = zoneRight?[i] ?? zoneLeft[i];
            }
          }
        }
      }
      startStep += totalSteps;
    }
    return (left: left, right: right);
  }

  ({Float64List left, Float64List right}) _renderNativeVoices(
    List<TrackerCell> cells,
    TrackerTiming timing,
  ) {
    final left = Float64List(timing.totalSamples);
    final right = Float64List(timing.totalSamples);
    final voices = <_NativeZoneVoice>[];
    var startStep = 0;

    for (final run in noteRuns(cells)) {
      final midi = run.$1;
      final sustainSteps = run.$2;
      final releaseSteps = run.$3;
      final totalSteps = sustainSteps + releaseSteps;
      if (midi != null) {
        final zone = _closestZone(cells[startStep].nativeNote ?? midi);
        if (zone != null) {
          final trigger = cells[startStep];
          final voiceCells = _nativeVoiceCells(
            cells.length,
            startStep,
            trigger,
            releaseSteps > 0 ? startStep + sustainSteps : null,
          );
          final rendered = zone is SampleInstrument
              ? zone.renderChannelStereo(voiceCells, timing)
              : (() {
                  final mono = zone.renderChannel(voiceCells, timing);
                  return (left: mono, right: Float64List.fromList(mono));
                })();
          final voice = _NativeZoneVoice(
            midi: midi,
            zone: zone,
            startSample: timing.stepStartSample(startStep),
            left: rendered.left,
            right: rendered.right,
          );
          final newStart = voice.startSample;
          for (final old in voices) {
            if (old.endSample <= newStart) continue;
            final duplicate = _isDuplicate(old, voice, nativeDctOf(zone));
            final action =
                duplicate ? nativeDcaOf(zone) : nativeNnaOf(old.zone);
            switch (action) {
              case 0:
                old.endSample = newStart;
              case 1:
                old.releaseAt = newStart;
                if (old.releaseLeft == null) {
                  final released = _renderNativeRelease(
                    old.zone,
                    cells.length,
                    old.startStep,
                    old.trigger,
                    startStep,
                    timing,
                  );
                  old.releaseLeft = released.left;
                  old.releaseRight = released.right;
                }
              case 2:
                old.fadeAt = newStart;
            }
          }
          voice.startStep = startStep;
          voice.trigger = trigger;
          voices.add(voice);
        }
      }
      startStep += totalSteps;
    }

    for (final voice in voices) {
      final end = voice.endSample.clamp(voice.startSample, timing.totalSamples);
      final fadeRate = nativeFadeoutOf(voice.zone) / 1024.0;
      for (var i = voice.startSample; i < end; i++) {
        final released = voice.releaseAt != null && i >= voice.releaseAt!;
        final sourceLeft = released ? voice.releaseLeft : voice.left;
        final sourceRight = released ? voice.releaseRight : voice.right;
        if (sourceLeft == null || i >= sourceLeft.length) continue;
        var gain = 1.0;
        if (voice.fadeAt != null && i >= voice.fadeAt!) {
          gain = exp(-fadeRate * (i - voice.fadeAt!) / kSampleRate * 8.0);
        }
        left[i] += sourceLeft[i] * gain;
        right[i] += (sourceRight != null && i < sourceRight.length
                ? sourceRight[i]
                : sourceLeft[i]) *
            gain;
      }
    }
    return (left: left, right: right);
  }

  ({Float64List left, Float64List right}) _renderNativeRelease(
    TrackerInstrument zone,
    int rows,
    int startStep,
    TrackerCell trigger,
    int releaseStep,
    TrackerTiming timing,
  ) {
    final cells = _nativeVoiceCells(
      rows,
      startStep,
      trigger,
      releaseStep,
    );
    if (zone is SampleInstrument) {
      return zone.renderChannelStereo(cells, timing);
    }
    final mono = zone.renderChannel(cells, timing);
    return (left: mono, right: Float64List.fromList(mono));
  }
}

class _NativeZoneVoice {
  _NativeZoneVoice({
    required this.midi,
    required this.zone,
    required this.startSample,
    required this.left,
    required this.right,
  });

  final int midi;
  final TrackerInstrument zone;
  final int startSample;
  final Float64List left;
  final Float64List right;
  late int startStep;
  late TrackerCell trigger;
  int endSample = 1 << 60;
  int? releaseAt;
  int? fadeAt;
  Float64List? releaseLeft;
  Float64List? releaseRight;
}

List<TrackerCell> _nativeVoiceCells(
  int rows,
  int startStep,
  TrackerCell trigger,
  int? releaseStep,
) {
  final cells = List<TrackerCell>.filled(rows, TrackerCell.empty);
  cells[startStep] = trigger;
  if (releaseStep != null && releaseStep >= 0 && releaseStep < rows) {
    cells[releaseStep] = TrackerCell.noteCut;
  }
  return cells;
}

int nativeNnaOf(TrackerInstrument zone) =>
    zone is SampleInstrument ? zone.nativeNna.clamp(0, 3).toInt() : 0;

int nativeDctOf(TrackerInstrument zone) =>
    zone is SampleInstrument ? zone.nativeDct.clamp(0, 3).toInt() : 0;

int nativeDcaOf(TrackerInstrument zone) =>
    zone is SampleInstrument ? zone.nativeDca.clamp(0, 2).toInt() : 0;

int nativeFadeoutOf(TrackerInstrument zone) =>
    zone is SampleInstrument ? zone.nativeFadeout.clamp(0, 65535).toInt() : 0;

bool _isDuplicate(
  _NativeZoneVoice old,
  _NativeZoneVoice next,
  int dct,
) {
  switch (dct) {
    case 1:
      return old.midi == next.midi;
    case 2:
      return old.zone.id == next.zone.id;
    case 3:
      return true;
    default:
      return false;
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
  const VolumeEnvelope(
    this.points, {
    this.sustain,
    this.loopStart,
    this.loopEnd,
  });

  /// `(ms, level 0..1)` breakpoints, ascending in ms.
  final List<({int ms, double level})> points;
  final int? sustain;
  final int? loopStart;
  final int? loopEnd;

  bool get isEmpty => points.isEmpty;

  /// The envelope level at [ms] — linear interpolation between breakpoints,
  /// clamped/held at the ends.
  double levelAt(double ms, {bool released = false}) {
    if (points.isEmpty) return 1.0;
    ms = _envelopeTime(
      ms,
      released: released,
      sustain: sustain,
      loopStart: loopStart,
      loopEnd: loopEnd,
      pointMs: [for (final p in points) p.ms],
    );
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
  const PanEnvelope(
    this.points, {
    this.sustain,
    this.loopStart,
    this.loopEnd,
  });

  /// `(ms, pan −1..1)` breakpoints, ascending in ms.
  final List<({int ms, double pan})> points;
  final int? sustain;
  final int? loopStart;
  final int? loopEnd;

  bool get isEmpty => points.isEmpty;

  /// The pan offset at [ms] — linear interpolation, held at the ends.
  double panAt(double ms, {bool released = false}) {
    if (points.isEmpty) return 0.0;
    ms = _envelopeTime(
      ms,
      released: released,
      sustain: sustain,
      loopStart: loopStart,
      loopEnd: loopEnd,
      pointMs: [for (final p in points) p.ms],
    );
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

double _envelopeTime(
  double ms, {
  required bool released,
  required int? sustain,
  required int? loopStart,
  required int? loopEnd,
  required List<int> pointMs,
}) {
  if (pointMs.isEmpty) return ms;
  final sustainIndex = sustain;
  if (!released &&
      sustainIndex != null &&
      sustainIndex >= 0 &&
      sustainIndex < pointMs.length) {
    ms = min(ms, pointMs[sustainIndex].toDouble());
  }
  final loopStartIndex = loopStart;
  final loopEndIndex = loopEnd;
  if (loopStartIndex != null &&
      loopEndIndex != null &&
      loopStartIndex >= 0 &&
      loopEndIndex > loopStartIndex &&
      loopEndIndex < pointMs.length) {
    final start = pointMs[loopStartIndex].toDouble();
    final end = pointMs[loopEndIndex].toDouble();
    final length = end - start;
    if (length > 0 && ms >= end) {
      ms = start + ((ms - start) % length);
    }
  }
  return ms;
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
/// chiptune (sfxr) presets, three Karplus-Strong plucked strings, three 2-op FM
/// voices, and three subtractive voices — all sample-free / zero-license.
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
  // Two-op FM — electric piano, bell, FM bass (struck-and-mellowing).
  for (final e in kFmPresets.entries)
    InstrumentOption(e.key, () => FmInstrument.preset(e.key, e.value)),
  // Subtractive — pad, lead, synth bass (the sustained analog side).
  for (final e in kSubPresets.entries)
    InstrumentOption(e.key, () => SubtractiveInstrument.preset(e.key, e.value)),
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
      cur.copyWith(volume: volume, clearVolume: volume == null),
    );
  }

  /// Sets the per-note [effect] of the note at [row]. No-op on an empty cell.
  void setCellEffect(int channel, int row, TrackerEffect effect) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      cur.copyWith(effect: effect),
    );
  }

  /// Sets the per-cell [instrument] column (0 = the channel default, else a
  /// 1-based index into the song's instrument pool) of the note at [row]. No-op
  /// on an empty cell — the instrument column rides on a note.
  void setCellInstrument(int channel, int row, int instrument) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      cur.copyWith(instrument: instrument),
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

  /// The raw PCM waveform of a channel for visualization (oscilloscopes).
  Float64List getStem(int channel) => _stem(channel);

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

  /// The current pattern mixed to a raw Float64List buffer, used for baking the Tracker
  /// into a LoopTrack stem without clipping or applying 16-bit PCM quantization.
  Float64List renderLoopFloat() => mixStemsFloat(
        [
          for (var i = 0; i < channels.length; i++)
            if (channels[i].hasAnyNote && !channels[i].muted)
              (samples: _stem(i), gain: channels[i].gain),
        ],
        totalSamples: _timing.totalSamples,
      );

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
