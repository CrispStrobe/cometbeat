// lib/core/audio/tracker_replayer.dart
//
// The tick-based Tracker REPLAYER — the audio engine for the classic MOD
// effect-column PITCH commands (phase 2). Where the offline renderer
// (tracker_engine.dart) renders each note in isolation as a segment, the
// replayer walks order → pattern → row → TICK holding per-channel pitch / volume
// / LFO state across ticks, so effects that need cross-tick continuity —
// portamento, vibrato, tremolo, arpeggio — become possible. It synthesizes each
// additive channel with a PHASE-ACCUMULATING oscillator (`phase += 2π·f/sr` per
// sample, exactly like [renderNoteWithEffect]) so a time-varying frequency stays
// phase-continuous.
//
// Commands implemented here (additive voices):
//   0xy arpeggio · 1xx porta up · 2xx porta down · 3xx tone porta ·
//   4xy vibrato · 5xy tone-porta+vol-slide · 6xy vibrato+vol-slide ·
//   7xy tremolo · Axy volume slide (per-tick) · Cxx set volume.
//
// FLOW commands (phase 3) that change the ORDER/timeline are resolved at render
// time by [walkFlow], which expands order→pattern→row under the flow rules into
// the flat sequence of rows actually played, then renders that flattened song
// through the same per-channel path (so pitch commands AND non-additive voices
// keep working). Implemented: Bxx position jump · Dxx pattern break (with the
// classic decimal row param). The row-timing map maps each flat row back to its
// (orderIndex, patternIndex, row) so the playhead can follow the non-linear
// sequence. Implemented too: Exy extended — E1x/E2x fine porta, E3x glissando
// control, E4x/E7x vibrato/tremolo waveform (sine/saw/square), E5x set-finetune,
// E9x retrigger, EAx/EBx fine volume, ECx note cut, EDx note delay (per-tick, in
// ReplayVoice) + E6x pattern loop and EEx pattern delay (row-level flow, in
// walkFlow), plus Rxy retrigger+volslide (kFxRetrigVolSlide) and Txy tremor
// (kFxTremor). Fxx SET-SPEED (param <0x20 →
// ticks/row) AND SET-TEMPO (param ≥0x20 → BPM): [walkFlow] annotates every played
// row with the speed/tempo IN EFFECT for that row. A song with a single (or no)
// value renders UNIFORMLY (the top-of-module value, [songInitialSpeed]/
// [songInitialTempo]/[effectiveTiming]) — byte-identical to before. A MID-SONG
// change ([songUsesVariableTiming]) routes through [_replayVariable]: each row's
// duration follows its own tempo (laid back-to-back at accumulated sample
// offsets), so a tempo drop lengthens the song and songTotalMs/resolveTimingMap
// track the summed per-row durations.
//
// PER-CELL INSTRUMENT ([TrackerCell.instrument], 1-based into
// [TrackerSong.instruments]): a note can switch a channel's timbre, persisting
// per channel — so one channel can play piano then flute. Honoured on ADDITIVE
// channels (the tick oscillator re-reads the pool timbre) AND on SAMPLE channels
// (the tick voice swaps `cur` to the pool's SampleInstrument — see
// [_renderSampleChannelInto]). A per-cell reference to a non-additive pool
// instrument that is neither additive nor sample keeps the channel's own voice.
//
// 9xx sample-offset works on SAMPLE voices — the sample tick voice starts the
// read pointer at param×256 (and [SampleInstrument.renderChannel] does the same
// on the effect-free fallback path). MID-SONG speed/tempo CHANGES are handled by
// the variable render (see the Fxx note above). So an imported module's per-tick
// pitch/volume effects (porta/vibrato/tremolo/Cxx/Axy/arp/extended) now actually
// SOUND on its SAMPLED channels, not just additive ones.
//
// Mixing (see Trap A in docs/TRACKER_REPLAYER_HANDOVER.md): the replayer sums
// voices at a FIXED-normalized amplitude (each additive voice divided by its
// timbre's harmonic-sum, so peak ≤ 1) × the channel gain, then a tanh soft-knee —
// it does NOT unit-peak each stem per render. That is the whole point: a Cxx or a
// tremolo changes the summed amplitude audibly, instead of being normalized away.
// This is a deliberate divergence from the offline `mixStems` path, gated to the
// replayer (only songs that `usesCommands`). Non-additive channels (sfxr / sample
// / percussion) fall back to the offline whole-channel render, unit-peaked × gain
// like `mixStems`, so they still sound (their per-note effects are ignored for
// now — documented limitation).
//
// The state machine is exposed pure (no audio) via [traceChannel] for trajectory
// tests — see test/tracker_replayer_test.dart.
//
// Flutter-free → unit-tested without a device.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kFxVolumeSlide, kFxSetVolume, kDefaultTicksPerRow;
import 'package:comet_beat/core/audio/tracker_song.dart';

// --- Command nibbles ---------------------------------------------------------

const int kFxArpeggio = 0x0; // 0xy (only when the param is non-zero)
const int kFxPortaUp = 0x1; // 1xx
const int kFxPortaDown = 0x2; // 2xx
const int kFxTonePorta = 0x3; // 3xx
const int kFxVibrato = 0x4; // 4xy
const int kFxTonePortaVolSlide = 0x5; // 5xy = 3xx (memory) + Axy
const int kFxVibratoVolSlide = 0x6; // 6xy = 4xy (continue) + Axy
const int kFxTremolo = 0x7; // 7xy
const int kFxSetPan =
    0x8; // 8xx — set channel pan: 0x00 left … 0x80 centre … 0xFF right
const int kFxSampleOffset =
    0x9; // 9xx — start a sample at xx×256 (sample voices)
const int kFxPositionJump = 0xB; // Bxx — continue at order xx, row 0
const int kFxPatternBreak = 0xD; // Dxx — next order entry, row = decimal(xx)
const int kFxSetSpeed = 0xF; // Fxx — <0x20 set speed (ticks/row); ≥0x20 tempo
const int kFxExtended =
    0xE; // Exy — sub-command in the high nibble of the param

// Exy sub-commands (the high nibble of the param; the low nibble is the value).
const int kExFinePortaUp = 0x1; // E1x — bump pitch up x fine units, once
const int kExFinePortaDown = 0x2; // E2x — bump pitch down x, once
const int kExPatternLoop = 0x6; // E60 set loop start · E6x loop back x times
const int kExRetrigger = 0x9; // E9x — retrigger the note every x ticks
const int kExFineVolUp = 0xA; // EAx — raise volume by x, once
const int kExFineVolDown = 0xB; // EBx — lower volume by x, once
const int kExNoteCut = 0xC; // ECx — cut the note (volume 0) at tick x
const int kExNoteDelay = 0xD; // EDx — delay the note trigger until tick x
const int kExGlissando =
    0x3; // E3x — 1: tone-porta snaps output to whole semitones · 0: off
const int kExVibratoWaveform = 0x4; // E4x — 0 sine · 1 saw(ramp) · 2 square
const int kExSetFinetune =
    0x5; // E5x — nudge the note's tune; 8 = centre, <8 flat, >8 sharp
const int kExTremoloWaveform = 0x7; // E7x — 0 sine · 1 saw(ramp) · 2 square
const int kExPatternDelay =
    0xE; // EEx — repeat the current row x extra times (row-level, in walkFlow)

/// Rxy — retrigger the note every y ticks, applying volume change code x on each
/// retrigger (the XM table). Not a 0x0–0xF nibble, so it never collides with the
/// classic MOD commands; importers can map XM effect 0x1B onto it.
const int kFxRetrigVolSlide = 0x1B;

/// Gxx — set GLOBAL volume (0x00–0x40), scaling the whole mix. XM effect 'G'
/// (0x10). A post-mix scalar, not a per-voice command; persists across rows.
const int kFxSetGlobalVolume = 0x10;

/// Hxy — GLOBAL volume slide: x raises, y lowers the global volume by that much
/// per tick (classic volume-slide semantics). XM effect 'H' (0x11).
const int kFxGlobalVolSlide = 0x11;

/// Pxy — PAN slide (XM effect 'P', 0x19): high nibble x slides the pan RIGHT, low
/// nibble y slides it LEFT, per tick. Modelled at ROW granularity in
/// [_panRegions] (like [kFxTempoSlide]): each row carrying Pxy steps the pan by
/// `(x−y) × (speed) / 128`, clamped to −1..1. Stereo-only.
const int kFxPanSlide = 0x19;

/// Txy — TEMPO slide (S3M/IT effect 'T'): high nibble 1 slides the tempo (BPM)
/// UP by the low nibble, else DOWN. Modelled at ROW granularity in [walkFlow] —
/// each row carrying Txx steps the tempo by `amount × (speed−1)` (the per-tick
/// slide summed over the row's non-first ticks), so it rides the existing
/// per-row-tempo variable-timing render. Clamped to a valid BPM (32–255).
const int kFxTempoSlide = 0x1F;

/// Txy — tremor: pulse the note ON for x ticks then OFF for y, repeating. XM
/// effect T and S3M/IT effect I map here.
const int kFxTremor = 0x1D;

/// Yxy — panbrello: a stereo pan LFO (IT/S3M).
const int kFxPanbrello = 0x1E;
const double kPanbrelloDepthPerUnit = 1 / 15;

/// Zxx — set the resonant low-pass FILTER (IT effect 'Z'): `Z00..Z7F` set the
/// cutoff (the param IS the 0..127 cutoff), `Z80..ZFF` set the resonance (param
/// `& 0x7F`). Decoded per-voice in [ReplayVoice.armRow]; applied by the sample
/// tick voices via a stateful [Biquad] low-pass. Carried across streaming chunks
/// with the rest of the voice state.
const int kFxSetFilter = 0x1C;

// --- IT resonant low-pass filter mapping (OpenMPT/IT formula) -----------------
//
// Cutoff (0..127) → corner frequency (Hz):
//   fc = 110 · 2^(0.25 + cutoff/24)
// This is OpenMPT's `CutOffToFrequency` with the neutral filter modifier (256,
// i.e. no filter-envelope/cutoff-swing offset): `computedCutoff = cutoff·512`
// and `fc = 110·2^(0.25 + computedCutoff/(24·512))`. Clamped to [120 Hz,
// Nyquist]. cutoff 127 ≈ 5.1 kHz (near-open); low cutoffs get dark, as IT is.
//
// Resonance (0..127) → biquad Q:
//   Q = 0.70710678 · 10^(1.2 · resonance/127)
// resonance 0 → Butterworth Q≈0.707 (no resonant peak); 127 → Q≈11.2 (≈+24 dB
// peak). This drives the RBJ low-pass [Biquad] resonance directly.
double itFilterCutoffHz(int cutoff, {double sampleRate = kSampleRate + 0.0}) {
  final c = cutoff.clamp(0, 127).toDouble();
  final fc = 110.0 * pow(2.0, 0.25 + c / 24.0);
  final nyquist = sampleRate / 2.0;
  return fc.clamp(120.0, nyquist - 1.0);
}

double itFilterResonanceQ(int resonance) {
  final r = resonance.clamp(0, 127).toDouble();
  return 0.70710678 * pow(10.0, 1.2 * r / 127.0);
}

// --- Filter-envelope cutoff modulation (OpenMPT/IT) ---------------------------
//
// When an IT instrument's third envelope is a FILTER envelope, its 0..64 value
// modulates the cutoff. Following OpenMPT's `CutOffToFrequency(cutoff,
// flt_modifier)`: the envelope value `v` (0..64) becomes the filter modifier
// `flt = v·4` (0..256), and
//   computedCutoff = clamp(cutoff · (flt + 256), 0, 127·512)
//   fc = 110 · 2^(0.25 + computedCutoff/(24·512))
// v = 64 → flt = 256 → computedCutoff = cutoff·512 → the NEUTRAL cutoff (matches
// [itFilterCutoffHz] with no envelope). Lower values darken (v = 0 → cutoff·256,
// i.e. ~one octave down). This lets a rising envelope open the filter over the
// note and a falling envelope close it. [fltModifier] is 0..256.
double itFilterCutoffHzMod(
  int cutoff,
  int fltModifier, {
  double sampleRate = kSampleRate + 0.0,
}) {
  final c = cutoff.clamp(0, 127);
  final m = fltModifier.clamp(0, 256);
  final computed = (c * (m + 256)).clamp(0, 127 * 512).toDouble();
  final fc = 110.0 * pow(2.0, 0.25 + computed / (24.0 * 512.0));
  final nyquist = sampleRate / 2.0;
  return fc.clamp(120.0, nyquist - 1.0);
}

// --- Tuning constants (MUSICAL APPROXIMATIONS, not period-accurate MOD) -------
//
// Real MOD effects operate on Amiga period units; we model pitch in fractional
// semitones, so these map a command's param to a per-tick semitone/volume delta.
// Chosen for a pleasant musical feel; documented so the trajectory tests pin
// them.

/// Semitones per porta param-unit, per tick (1xx/2xx/3xx). 16 units ≈ 1 st/tick.
const double kPortaSemitonesPerUnit = 1 / 16;

/// Vibrato depth: semitones per depth-unit (y). 8 ⇒ ±1 semitone.
const double kVibratoDepthSemitonesPerUnit = 1 / 8;

/// Vibrato phase advance (radians) per speed-unit (x), per tick. A full cycle
/// takes 32/x ticks.
const double kVibratoRadPerSpeedUnit = 2 * pi / 32;

/// Tremolo depth: volume units (0..64) per depth-unit (y).
const double kTremoloDepthPerUnit = 1.0;

/// Tremolo phase advance (radians) per speed-unit (x), per tick.
const double kTremoloRadPerSpeedUnit = 2 * pi / 32;

/// The full channel volume (classic tracker 0..64).
const int kMaxVolume = 64;

// --- Row-timing map ----------------------------------------------------------

/// One entry of the replayer's timing map: the wall-clock onset of a played row,
/// with the order/pattern/row it corresponds to. Under flow commands (phase 3)
/// the cadence and order become non-uniform; the Advanced screen's playhead reads
/// this instead of assuming fixed pattern lengths.
class RowTiming {
  const RowTiming(this.startMs, this.orderIndex, this.patternIndex, this.row);

  final int startMs;
  final int orderIndex;
  final int patternIndex;
  final int row;

  @override
  String toString() =>
      'RowTiming($startMs ms, order $orderIndex, pat $patternIndex, row $row)';
}

/// The result of a replay: the mixed PCM16 and the row-timing map.
class ReplayResult {
  const ReplayResult(this.pcm, this.timing);

  final Int16List pcm;
  final List<RowTiming> timing;
}

// --- The per-channel voice state machine -------------------------------------

/// Mutable per-channel replay state, advanced tick by tick. Public fields are the
/// trajectory the tests assert against.
/// The tracker LFO shape for vibrato/tremolo, in [-1, 1], selected by E4x/E7x:
/// 0 = sine, 1 = ramp-down (sawtooth), 2 = square. Anything else (incl. the
/// classic "random", 3) falls back to sine so the pure trajectory stays
/// deterministic for tests.
double trackerLfo(int waveform, double phase) {
  switch (waveform & 3) {
    case 1: // ramp down: +1 at the start of a cycle, sloping to −1
      final t = ((phase / (2 * pi)) % 1.0 + 1.0) % 1.0;
      return 1.0 - 2.0 * t;
    case 2: // square
      return sin(phase) >= 0 ? 1.0 : -1.0;
    default: // 0 sine (and 3 random ≈ sine, kept deterministic)
      return sin(phase);
  }
}

/// The Rxy (retrigger + volslide) volume change for code [x], applied to volume
/// [v] on each retrigger — the classic XM table (0/8 = no change; 1–5 subtract
/// 1/2/4/8/16; 6/7 = ×⅔/×½; 9–D add 1/2/4/8/16; E/F = ×1½/×2).
int retrigVolume(int v, int x) {
  final n = switch (x) {
    1 => v - 1,
    2 => v - 2,
    3 => v - 4,
    4 => v - 8,
    5 => v - 16,
    6 => v * 2 ~/ 3,
    7 => v ~/ 2,
    9 => v + 1,
    0xA => v + 2,
    0xB => v + 4,
    0xC => v + 8,
    0xD => v + 16,
    0xE => v * 3 ~/ 2,
    0xF => v * 2,
    _ => v, // 0 and 8: no change
  };
  return n.clamp(0, kMaxVolume);
}

class ReplayVoice {
  /// Current base pitch as a FRACTIONAL MIDI note (porta/tone-porta move this).
  double pitch = 0;

  /// Tone-porta (3xx/5xy) target pitch — the row's note.
  double targetPitch = 0;

  /// Channel volume, 0..64 (persists across rows).
  int volume = kMaxVolume;

  /// The soft/ghost-note multiplier (TrackerCell.volume, 0..1) of the CURRENT
  /// note — applied on top of [volume] in synthesis.
  double noteVolume = 1.0;

  /// Whether a note has ever been triggered (so 3xx with no prior note starts).
  bool active = false;

  /// A key-off ended the sustain portion of the current sampled note. Additive
  /// voices retain their existing hard-stop behavior; sampled tick renderers
  /// use this state to enter the native release envelope and ordinary loop.
  bool released = false;
  bool _releasedThisRow = false;

  // Effect memory: a 0 param reuses the last non-zero param for that command.
  int _memPortaUp = 0;
  int _memPortaDown = 0;
  int _memTonePorta = 0;
  int _memVibSpeed = 0;
  int _memVibDepth = 0;
  int _memTremSpeed = 0;
  int _memTremDepth = 0;
  int _memVolSlide = 0;
  int _memRetrig = 0; // Rxy param (x = vol code, y = tick interval)
  int _memTremor = 0; // Txy param (x = on ticks, y = off ticks)
  int _memPanbrelloSpeed = 0;
  int _memPanbrelloDepth = 0;

  // LFO waveform select (E4x/E7x) + glissando control (E3x) — persist across
  // rows like a real tracker's per-channel control state.
  int _vibWave = 0;
  int _tremWave = 0;
  bool _glissando = false;

  // LFO phases (radians), reset on a new note.
  double _vibPhase = 0;
  double _tremPhase = 0;
  double _panbrelloPhase = 0;

  // --- IT resonant low-pass filter (initial cutoff/resonance + Zxx) ----------
  // Current filter parameters: cutoff 0..127 (127 = fully open), resonance
  // 0..127. Defaults (open, no resonance) leave the voice UNFILTERED — the
  // biquad is never built and [filterOut] returns the sample untouched, so a
  // no-filter voice is bit-for-bit identical to a filterless render.
  int filterCutoff = 127;
  int filterResonance = 0;
  bool _filterSetThisRow = false; // a Zxx set the filter on the current row
  Biquad? _lpf; // mono / left channel
  Biquad? _lpfR; // right channel of a stereo sample
  int _lpfCutoff = -1;
  int _lpfRes = -1;

  // IT filter-cutoff ENVELOPE (the instrument's third envelope when its
  // env-filter flag is set). When present it modulates the cutoff over the note
  // via [itFilterCutoffHzMod]; [filterCutoff] is the base it modulates from
  // (127 = fully open when the instrument set no initial cutoff). A voice with
  // no filter envelope leaves [_filterEnv] null → the biquad path is byte-for-
  // byte the initial-cutoff-only behaviour.
  FilterEnvelope? _filterEnv;
  bool _hasFilterEnv = false;
  int _filterEnvMod = 256; // 0..256; 256 = neutral (base cutoff)
  int _lpfEnvMod = -1; // last modifier the biquad was tuned for

  bool get _filterActive =>
      filterCutoff < 127 || filterResonance > 0 || _hasFilterEnv;

  // --- Anti-click ramps (MultiPLAY-style) ------------------------------------
  // Two per-voice smoothers that kill the two classic tracker clicks. They live
  // ON the voice, so the row-chunk streamer carries them across chunk boundaries
  // like every other voice cursor (read pointer, biquad, envelope phase).
  //
  //  • NOTE-ON SOFT-START: a freshly (re)triggered voice ramps its first
  //    [softStartSamples] OUTPUT samples 0→1 linearly, so a note that starts
  //    mid-waveform fades in instead of stepping from silence to a non-zero
  //    sample. Mirrors MultiPLAY `SOFT_START_SAMPLES 10`
  //    (../MultiPLAY/src/sample_builtintype.h:402). Only armed on a REAL trigger
  //    (see [armSoftStart]) — never on a tone-porta tie / volume-column change.
  //
  //  • HARD-CUT RESIDUE TAIL: an instant note cut (ECx) drops the sample voice's
  //    output to 0 in one step — a click. Instead, on a cut we decay the LAST
  //    emitted value (plus its slope) by [residueFade] each subsequent sample —
  //    a tiny smoothing tail, not an audible note. Mirrors MultiPLAY
  //    `residue`/`RESIDUE_FADE 0.93` (../MultiPLAY/src/channel.cc:180-186,600-620).
  static const int softStartSamples = 10; // MultiPLAY SOFT_START_SAMPLES
  static const double residueFade = 0.93; // MultiPLAY RESIDUE_FADE
  int _softStart = 0; // OUTPUT samples still remaining in the 0→1 ramp
  double _resL = 0.0; // residue tail state (mono / left)
  double _resR = 0.0; // residue tail state (right)
  double _resSlopeL = 0.0; // last per-sample delta (mono / left)
  double _resSlopeR = 0.0; // last per-sample delta (right)

  /// ECx note-cut is silencing the voice on the CURRENT tick (set by [tick]).
  bool noteCut = false;

  /// Arm the note-on soft-start on a REAL (re)trigger. Clears any residue tail
  /// (a new note supersedes the old one's decay). Called from the sample tick
  /// renderers everywhere they (re)seed the read pointer.
  void armSoftStart() {
    _softStart = softStartSamples;
    _resL = 0;
    _resR = 0;
    _resSlopeL = 0;
    _resSlopeR = 0;
  }

  /// The soft-start gain for the CURRENT output sample, advancing the ramp by
  /// one sample. Returns 1.0 once the ramp is done (the common case). Rises
  /// 0 → 1 over [softStartSamples] samples (first sample exactly 0.0).
  double softStartGain() {
    if (_softStart <= 0) return 1.0;
    final g = (softStartSamples - _softStart) / softStartSamples;
    _softStart--;
    return g;
  }

  /// Feed one finished MONO/left output value [v] to the residue tracker (so a
  /// later hard cut can decay from it) and return it unchanged.
  double keepResidue(double v) {
    _resSlopeL = v - _resL;
    _resL = v;
    return v;
  }

  /// Feed one finished STEREO output pair to the residue tracker. The inputs are
  /// the finished per-channel output (the caller uses them directly), so this is
  /// void — returning a record here would heap-allocate per sample in the hot
  /// streaming loop.
  void keepResidueStereo(double l, double r) {
    _resSlopeL = l - _resL;
    _resSlopeR = r - _resR;
    _resL = l;
    _resR = r;
  }

  /// One MONO/left residue-tail sample for a hard cut: the last kept value,
  /// then decayed (value + slope) by [residueFade]. Emits a short smoothing
  /// tail instead of an instant discontinuity.
  double residueStep() {
    final out = _resL;
    _resL = (_resL + _resSlopeL) * residueFade;
    _resSlopeL *= residueFade;
    return out;
  }

  /// The most recent [residueStepStereo] outputs (avoids a per-sample record
  /// allocation in the hot loop — read after the call).
  double resOutL = 0.0;
  double resOutR = 0.0;

  /// STEREO residue-tail step for a hard cut (both channels decayed together).
  /// Writes the tail sample into [resOutL]/[resOutR] rather than returning a
  /// record, so the streaming stereo loop stays allocation-free.
  void residueStepStereo() {
    resOutL = _resL;
    resOutR = _resR;
    _resL = (_resL + _resSlopeL) * residueFade;
    _resR = (_resR + _resSlopeR) * residueFade;
    _resSlopeL *= residueFade;
    _resSlopeR *= residueFade;
  }

  // The command armed for the current row.
  int _cmd = 0;
  int _param = 0;
  bool _retriggered =
      false; // did the current row (re)trigger a note at tick 0?

  // EDx note delay: a note that triggers partway through the row.
  int? _pendingDelayTick;
  double _pendingNote = 0;
  double _pendingNoteVolume = 1.0;

  int get _exSub =>
      (_param >> 4) & 0xF; // Exy sub-command (valid when cmd == E)
  int get _exVal => _param & 0xF; // Exy value

  /// Whether a delayed note (EDx) is still waiting to trigger this row.
  bool get hasPendingNote => _pendingDelayTick != null;

  /// Whether this row starts a note (immediate trigger OR a pending delayed one)
  /// — the audio renderer computes the envelope run-length when true.
  bool get startsNoteThisRow => _retriggered || _pendingDelayTick != null;

  // Audio-only envelope bookkeeping (ignored by [traceChannel]).
  int noteStartSample = 0;
  double noteSeconds = 1.0;
  double oscPhase = 0;

  bool get _isTonePorta => _cmd == kFxTonePorta || _cmd == kFxTonePortaVolSlide;
  bool get _isVibrato => _cmd == kFxVibrato || _cmd == kFxVibratoVolSlide;
  bool get _isVolSlide =>
      _cmd == kFxVolumeSlide ||
      _cmd == kFxTonePortaVolSlide ||
      _cmd == kFxVibratoVolSlide;
  bool get _isArpeggio => _cmd == kFxArpeggio && _param != 0;

  /// Whether [cell] would (re)trigger the note — a pitched cell that is NOT a
  /// tone-porta continuation.
  static bool triggers(TrackerCell cell) =>
      cell.midi != null &&
      cell.fxCmd != kFxTonePorta &&
      cell.fxCmd != kFxTonePortaVolSlide;

  /// Arm the voice's filter from an instrument's INITIAL cutoff/resonance at a
  /// note (re)trigger. A Zxx on the same row wins ([_filterSetThisRow]); otherwise
  /// the instrument default replaces the current filter. The biquad memory is
  /// always cleared — a new note starts the filter fresh (like a fresh sample
  /// read-pointer). [instCutoff] < 0 means the instrument has no filter → open.
  void armFilterOnTrigger(
    int instCutoff,
    int instResonance, [
    FilterEnvelope? filterEnv,
  ]) {
    if (!_filterSetThisRow) {
      filterCutoff = (instCutoff < 0 || instCutoff > 127) ? 127 : instCutoff;
      filterResonance = instResonance.clamp(0, 127);
    }
    // The filter envelope re-arms fresh at each note trigger (evaluated from the
    // note onset like the volume/pitch envelopes). A Zxx cutoff set on the row
    // still wins for the BASE cutoff; the envelope modulates around it.
    _filterEnv = filterEnv;
    _hasFilterEnv = filterEnv != null;
    _filterEnvMod = 256;
    _lpfEnvMod = -1;
    _lpf?.reset();
    _lpfR?.reset();
    _lpfCutoff = -1;
    _lpfRes = -1;
  }

  /// Evaluate the filter-cutoff envelope at [ms] since the note onset and update
  /// the current modifier. No-op (and byte-identical) when the voice has no
  /// filter envelope. Call once per sample, before [filterOut].
  void updateFilterEnv(double ms) {
    final env = _filterEnv;
    if (env == null) return;
    final v = env.valueAt(ms, released: released); // 0..64
    _filterEnvMod = (v * 4.0).round().clamp(0, 256);
  }

  /// Runs one sample through the voice's (mono/left) resonant low-pass. A no-op
  /// pass-through (returns [x] unchanged, no biquad allocated) when the voice is
  /// unfiltered — the guarantee that a filterless voice is bit-identical.
  double filterOut(double x) => _filter(x, false);

  /// The right-channel counterpart for a stereo sample (its own biquad state).
  double filterOutRight(double x) => _filter(x, true);

  double _filter(double x, bool right) {
    if (!_filterActive) return x;
    // A filter ENVELOPE modulates the corner frequency per sample; retune on any
    // change of the (quantised 0..256) modifier as well as cutoff/resonance. The
    // no-envelope path is left byte-for-byte unchanged (same [itFilterCutoffHz]).
    if (_hasFilterEnv) {
      if (_lpf == null || _lpfRes != filterResonance) {
        final f = itFilterCutoffHzMod(filterCutoff, _filterEnvMod);
        final q = itFilterResonanceQ(filterResonance);
        _lpf = Biquad(
          BiquadKind.lowpass,
          freq: f,
          sampleRate: kSampleRate.toDouble(),
          q: q,
        );
        _lpfR = Biquad(
          BiquadKind.lowpass,
          freq: f,
          sampleRate: kSampleRate.toDouble(),
          q: q,
        );
        _lpfCutoff = filterCutoff;
        _lpfRes = filterResonance;
        _lpfEnvMod = _filterEnvMod;
      } else if (_lpfCutoff != filterCutoff || _lpfEnvMod != _filterEnvMod) {
        final f = itFilterCutoffHzMod(filterCutoff, _filterEnvMod);
        _lpf!.setFreq(f);
        _lpfR!.setFreq(f);
        _lpfCutoff = filterCutoff;
        _lpfEnvMod = _filterEnvMod;
      }
      return right ? _lpfR!.process(x) : _lpf!.process(x);
    }
    // (Re)build on a resonance change (Q is fixed at construction); retune in
    // place on a cutoff change (preserves memory → click-free sweeps).
    if (_lpfRes != filterResonance) {
      final f = itFilterCutoffHz(filterCutoff);
      final q = itFilterResonanceQ(filterResonance);
      _lpf = Biquad(
        BiquadKind.lowpass,
        freq: f,
        sampleRate: kSampleRate.toDouble(),
        q: q,
      );
      _lpfR = Biquad(
        BiquadKind.lowpass,
        freq: f,
        sampleRate: kSampleRate.toDouble(),
        q: q,
      );
      _lpfCutoff = filterCutoff;
      _lpfRes = filterResonance;
    } else if (_lpfCutoff != filterCutoff) {
      final f = itFilterCutoffHz(filterCutoff);
      _lpf!.setFreq(f);
      _lpfR!.setFreq(f);
      _lpfCutoff = filterCutoff;
    }
    return right ? _lpfR!.process(x) : _lpf!.process(x);
  }

  /// Arm the row: parse the cell, (re)trigger the note if pitched, set the target
  /// for tone-porta, load the volume for Cxx, and fill effect memory. Call once
  /// at tick 0.
  void armRow(TrackerCell cell) {
    _cmd = cell.fxCmd;
    _param = cell.fxParam;
    _retriggered = false;
    _releasedThisRow = false;
    _pendingDelayTick = null;
    _filterSetThisRow = false;

    // Zxx (kFxSetFilter): Z00..Z7F set the cutoff, Z80..ZFF set the resonance.
    // A "set", applied immediately (no per-tick slide) and carried on the voice.
    if (_cmd == kFxSetFilter) {
      if (_param < 0x80) {
        filterCutoff = _param;
      } else {
        filterResonance = _param & 0x7F;
      }
      _filterSetThisRow = true;
    }

    // EDx note delay: defer the trigger to tick x instead of triggering now.
    final noteDelay =
        _cmd == kFxExtended && _exSub == kExNoteDelay && cell.midi != null;

    if (noteDelay) {
      _pendingNote = cell.midi!.toDouble();
      _pendingNoteVolume = cell.volume ?? 1.0;
      _pendingDelayTick = _exVal;
    } else if (cell.keyOff) {
      if (active) {
        released = true;
        _releasedThisRow = true;
      }
      active = false;
    } else if (cell.midi != null) {
      final m = cell.midi!.toDouble();
      if (_isTonePorta) {
        targetPitch = m;
        if (!active) {
          pitch = m;
          active = true;
          released = false;
          _retriggered = true;
          noteVolume = cell.volume ?? 1.0;
          _vibPhase = 0;
          _tremPhase = 0;
          _panbrelloPhase = 0;
        }
      } else {
        pitch = m;
        targetPitch = m;
        active = true;
        released = false;
        _retriggered = true;
        noteVolume = cell.volume ?? 1.0;
        _vibPhase = 0;
        _tremPhase = 0;
        _panbrelloPhase = 0;
      }
    } else if (cell.volume != null) {
      // A volume-column-only cell (no note) sets the RINGING note's volume — a
      // mid-note change, like a set-volume, without re-triggering.
      noteVolume = cell.volume!;
    }

    // Arm the note-on soft-start on a REAL (re)trigger only — a tone-porta tie
    // or a volume-column change leaves [_retriggered] false, so no fade-in.
    if (_retriggered) armSoftStart();

    // Effect memory + immediate (tick-0) commands.
    switch (_cmd) {
      case kFxPortaUp:
        if (_param != 0) _memPortaUp = _param;
      case kFxPortaDown:
        if (_param != 0) _memPortaDown = _param;
      case kFxTonePorta:
        if (_param != 0) _memTonePorta = _param;
      case kFxVibrato:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memVibSpeed = x;
        if (y != 0) _memVibDepth = y;
      case kFxVibratoVolSlide:
        // 6xy = CONTINUE the vibrato (reuse the existing speed/depth memory) +
        // volume slide xy. The param is the SLIDE amount, not vib speed/depth —
        // do NOT touch the vibrato memory (would corrupt/invent vibrato).
        if (_param != 0) _memVolSlide = _param;
      case kFxTremolo:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memTremSpeed = x;
        if (y != 0) _memTremDepth = y;
      case kFxTonePortaVolSlide:
        if (_param != 0) _memVolSlide = _param;
      case kFxVolumeSlide:
        if (_param != 0) _memVolSlide = _param;
      case kFxSetVolume:
        volume = _param.clamp(0, kMaxVolume);
      case kFxRetrigVolSlide:
        if (_param != 0) _memRetrig = _param;
      case kFxTremor:
        if (_param != 0) _memTremor = _param;
      case kFxPanbrello:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memPanbrelloSpeed = x;
        if (y != 0) _memPanbrelloDepth = y;
      case kFxExtended:
        // One-time (tick-0) extended commands: fine porta and fine volume.
        switch (_exSub) {
          case kExFinePortaUp:
            pitch += _exVal * kPortaSemitonesPerUnit;
          case kExFinePortaDown:
            pitch -= _exVal * kPortaSemitonesPerUnit;
          case kExFineVolUp:
            volume = (volume + _exVal).clamp(0, kMaxVolume);
          case kExFineVolDown:
            volume = (volume - _exVal).clamp(0, kMaxVolume);
          // Persistent control state (takes effect on later vibrato/tremolo/
          // tone-porta rows):
          case kExGlissando:
            _glissando = _exVal != 0;
          case kExVibratoWaveform:
            _vibWave = _exVal;
          case kExTremoloWaveform:
            _tremWave = _exVal;
          case kExSetFinetune:
            // Nudge this note's tune: 8 = centre, each step ±1/16 semitone.
            pitch += (_exVal - 8) * kPortaSemitonesPerUnit;
        }
    }
  }

  /// True on any row that (re)triggered a note (so the audio renderer can reset
  /// the envelope). Valid after [armRow].
  bool get retriggeredThisRow => _retriggered;

  bool get releasedThisRow => _releasedThisRow;

  /// Advance one tick [k] (0-based within the row) and return the effective
  /// (pitch, volume0to64) to synthesize this tick. [ticksPerRow] is the row's
  /// speed. Slide-type effects act on ticks 1.. (tick 0 holds), matching classic
  /// tracker behaviour; arpeggio and the LFOs act on every tick.
  ({double pitch, double volume, double pan, bool retrigger}) tick(
    int k,
    int ticksPerRow,
  ) {
    var retrigger = false;
    noteCut = false;

    // EDx note delay: the deferred note triggers at its tick.
    if (_pendingDelayTick != null && k == _pendingDelayTick) {
      pitch = _pendingNote;
      targetPitch = _pendingNote;
      noteVolume = _pendingNoteVolume;
      active = true;
      released = false;
      retrigger = true;
      _vibPhase = 0;
      _tremPhase = 0;
      _panbrelloPhase = 0;
      _pendingDelayTick = null;
    }

    var effPitch = pitch;
    var effVol = volume.toDouble();
    var effPan = 0.0;

    // Arpeggio: cycle base / base+x / base+y each tick (does not move `pitch`).
    if (_isArpeggio) {
      final x = (_param >> 4) & 0xF, y = _param & 0xF;
      final steps = [0, x, y];
      effPitch = pitch + steps[k % 3].toDouble();
    }

    // Porta up / down: move `pitch` on ticks > 0.
    if (_cmd == kFxPortaUp && k > 0) {
      pitch += _memPortaUp * kPortaSemitonesPerUnit;
      effPitch = pitch;
    } else if (_cmd == kFxPortaDown && k > 0) {
      pitch -= _memPortaDown * kPortaSemitonesPerUnit;
      effPitch = pitch;
    }

    // Tone porta: slide toward the target, never overshoot. With glissando
    // (E3x) on, the OUTPUT snaps to whole semitones while the slide continues.
    if (_isTonePorta && k > 0) {
      final step = _memTonePorta * kPortaSemitonesPerUnit;
      if (pitch < targetPitch) {
        pitch = min(targetPitch, pitch + step);
      } else if (pitch > targetPitch) {
        pitch = max(targetPitch, pitch - step);
      }
      effPitch = pitch;
    }
    if (_isTonePorta && _glissando) effPitch = effPitch.roundToDouble();

    // Vibrato: zero-mean LFO (E4x waveform) on pitch; phase advances each tick.
    if (_isVibrato) {
      final depth = _memVibDepth * kVibratoDepthSemitonesPerUnit;
      effPitch = pitch + depth * trackerLfo(_vibWave, _vibPhase);
      _vibPhase += _memVibSpeed * kVibratoRadPerSpeedUnit;
    }

    // Tremolo: zero-mean LFO (E7x waveform) on volume; phase advances each tick.
    if (_cmd == kFxTremolo) {
      final depth = _memTremDepth * kTremoloDepthPerUnit;
      effVol = (volume + depth * trackerLfo(_tremWave, _tremPhase))
          .clamp(0.0, kMaxVolume + 0.0);
      _tremPhase += _memTremSpeed * kTremoloRadPerSpeedUnit;
    }

    if (_cmd == kFxPanbrello) {
      effPan = _memPanbrelloDepth *
          kPanbrelloDepthPerUnit *
          trackerLfo(0, _panbrelloPhase);
      _panbrelloPhase += _memPanbrelloSpeed * kVibratoRadPerSpeedUnit;
    }

    // Volume slide (A / 5 / 6): move `volume` on ticks > 0.
    if (_isVolSlide && k > 0) {
      final x = (_memVolSlide >> 4) & 0xF, y = _memVolSlide & 0xF;
      volume = (volume + x - y).clamp(0, kMaxVolume);
      if (_cmd != kFxTremolo) effVol = volume.toDouble();
    }

    // Extended per-tick commands: E9x retrigger, ECx note cut.
    if (_cmd == kFxExtended) {
      if (_exSub == kExRetrigger && _exVal > 0 && k > 0 && k % _exVal == 0) {
        retrigger = true;
        _vibPhase = 0;
        _tremPhase = 0;
        _panbrelloPhase = 0;
      } else if (_exSub == kExNoteCut && k >= _exVal) {
        effVol = 0;
        noteCut = true; // hard cut → emit a residue tail, not an instant zero
      }
    }

    // Rxy: retrigger every y ticks, changing volume by code x each time.
    if (_cmd == kFxRetrigVolSlide) {
      final y = _memRetrig & 0xF;
      if (y > 0 && k > 0 && k % y == 0) {
        retrigger = true;
        _vibPhase = 0;
        _tremPhase = 0;
        _panbrelloPhase = 0;
        volume = retrigVolume(volume, (_memRetrig >> 4) & 0xF);
        effVol = volume.toDouble();
      }
    }

    // Txy tremor: the note pulses ON for x ticks then OFF for y, repeating.
    if (_cmd == kFxTremor) {
      final x = (_memTremor >> 4) & 0xF, y = _memTremor & 0xF;
      final cycle = x + y;
      if (cycle > 0 && k % cycle >= x) effVol = 0; // in the OFF phase
    }

    // A per-tick retrigger (EDx delayed note, E9x / Rxy) is a real trigger too —
    // fade it in with the soft-start ramp, like a fresh note.
    if (retrigger) armSoftStart();

    return (
      pitch: effPitch,
      volume: effVol,
      pan: effPan,
      retrigger: retrigger,
    );
  }
}

// --- Trajectory trace (pure, for tests) --------------------------------------

/// The per-tick effective (pitch, volume) trajectory of one channel — the pure
/// state-machine output with no audio, for trajectory tests. `pitch[r][k]` is the
/// fractional-MIDI pitch synthesized at row r, tick k; `volume[r][k]` is 0..64.
class ChannelTrace {
  ChannelTrace(this.pitch, this.volume, this.retrigger);

  final List<List<double>> pitch;
  final List<List<double>> volume;

  /// Whether the note (re)triggered at row [r], tick [k] — for EDx note delay
  /// and E9x retrigger, which don't otherwise change pitch/volume.
  final List<List<bool>> retrigger;

  /// The effective pitch at row [r], tick [k].
  double pitchAt(int r, int k) => pitch[r][k];

  /// The effective volume (0..64) at row [r], tick [k].
  double volumeAt(int r, int k) => volume[r][k];

  /// Whether row [r], tick [k] (re)triggered the note.
  bool retriggerAt(int r, int k) => retrigger[r][k];
}

/// Runs the voice state machine over [cells] and returns the per-tick
/// (pitch, volume) trajectory — no audio. The correctness anchor for phase 2.
ChannelTrace traceChannel(
  List<TrackerCell> cells, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final voice = ReplayVoice();
  final pitch = <List<double>>[];
  final volume = <List<double>>[];
  final retrigger = <List<bool>>[];
  for (final cell in cells) {
    voice.armRow(cell);
    final rowPitch = <double>[];
    final rowVol = <double>[];
    final rowRetrig = <bool>[];
    for (var k = 0; k < ticksPerRow; k++) {
      final s = voice.tick(k, ticksPerRow);
      rowPitch.add(s.pitch);
      rowVol.add(s.volume);
      rowRetrig.add(s.retrigger);
    }
    pitch.add(rowPitch);
    volume.add(rowVol);
    retrigger.add(rowRetrig);
  }
  return ChannelTrace(pitch, volume, retrigger);
}

// --- Audio rendering ---------------------------------------------------------

double _freqOfMidi(double midi) => 440.0 * pow(2.0, (midi - 69.0) / 12.0);

double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

/// The row after [from] (exclusive) in [cells] that (re)triggers a note, or
/// `cells.length` if none — the end of the current note's run (for the envelope).
int _nextTriggerRow(List<TrackerCell> cells, int from) {
  for (var r = from + 1; r < cells.length; r++) {
    if (ReplayVoice.triggers(cells[r])) return r;
  }
  return cells.length;
}

/// The run length in SECONDS of the note (re)triggered at row [from] — from its
/// row start to the next trigger (or the pattern end) — the envelope's timebase.
double _runSeconds(
  List<TrackerCell> cells,
  int from,
  int rows,
  TrackerTiming timing,
) {
  final runEnd = _nextTriggerRow(cells, from);
  final endSample =
      runEnd < rows ? timing.stepStartSample(runEnd) : timing.totalSamples;
  final runSamples = endSample - timing.stepStartSample(from);
  return runSamples > 0 ? runSamples / kSampleRate : 0.001;
}

/// Whether [instrument] is an additive voice the replayer synthesizes tick-wise.
Instrument? _additiveOf(TrackerInstrument instrument) =>
    instrument is AdditiveInstrument ? instrument.instrument : null;

/// Renders a NON-additive channel note by note, so each note is played by its
/// EFFECTIVE instrument — the channel's [channelInstrument] by default, swapped
/// to `pool[cell.instrument-1]` when a cell names a per-cell instrument (any
/// type; persists per channel, tracker-style). This is what lets a sample
/// channel pick a different sample per note (module fidelity + the per-note
/// enabler for 9xx / mid-song timing).
///
/// Each note is rendered over its EXACT run: the trigger cell plus a dummy
/// cap-trigger at the run's end (so the instrument's run-length-dependent
/// envelope fades exactly where the whole-channel render would), then only the
/// run's samples are copied in. Consequence: with no instrument change this is
/// BYTE-IDENTICAL to `channelInstrument.renderChannel(cells, timing)` — the
/// regression guard the tests pin. Cost is one `renderChannel` per note (each
/// only synthesizes its single note), fine for offline render.
Float64List renderChannelPerNote(
  TrackerInstrument channelInstrument,
  List<TrackerCell> cells,
  TrackerTiming timing,
  List<TrackerInstrument> pool, {
  VolumeEnvelope? envelope,
}) {
  final stem = Float64List(timing.totalSamples);
  // One reusable whole-song scratch buffer for every note render on this
  // channel — instead of a fresh Float64List(totalSamples) per note-run inside
  // each renderChannel. Cuts allocation from O(notes × song) to O(song) per
  // channel. Each note clears only its own run window before rendering, so the
  // reuse is byte-identical to the fresh-buffer path (see the fillRange below).
  final scratch = Float64List(timing.totalSamples);
  final rows = cells.length;
  var curInst = channelInstrument;
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final releaseSteps = run.$3;
    final steps = sustainSteps + releaseSteps;

    final trigger = cells[startStep];
    if (trigger.instrument > 0 && trigger.instrument - 1 < pool.length) {
      curInst = pool[trigger.instrument - 1];
    }
    if (midi != null) {
      final capRow = startStep + sustainSteps;
      final one = List<TrackerCell>.filled(rows, TrackerCell.empty)
        ..[startStep] = trigger;
      if (capRow < rows) {
        // An isolated run needs the same boundary semantics as the source
        // channel. A following note is a tracker choke, not a key-off: use a
        // dummy retrigger so SampleInstrument keeps full sustain through the
        // boundary. Only an explicit release run should enter ADSR release.
        one[capRow] =
            releaseSteps > 0 ? TrackerCell.noteCut : TrackerCell(midi: midi);
      }
      final s = timing.stepStartSample(startStep);
      final endRow = startStep + steps;
      final e =
          endRow < rows ? timing.stepStartSample(endRow) : timing.totalSamples;
      // Clear ONLY this note's run window before rendering it. Required for
      // correctness: a previous note's NNA / release tail may have written past
      // its own window into this one. We only ever read [s, lim) (lim <= e), and
      // each later note clears its own window, so tails past e are never read.
      scratch.fillRange(s, min(e, scratch.length), 0.0);
      final buf = curInst.renderChannel(one, timing, into: scratch);
      final lim = min(e, min(buf.length, stem.length));
      final instrumentEnvelope =
          curInst is SampleInstrument ? curInst.nativeVolumeEnvelope : null;
      if (envelope == null || instrumentEnvelope != null) {
        for (var i = s; i < lim; i++) {
          stem[i] += buf[i];
        }
      } else {
        // Shape each note by the volume envelope (time from the note's onset).
        for (var i = s; i < lim; i++) {
          stem[i] += buf[i] * envelope.levelAt((i - s) / kSampleRate * 1000);
        }
      }
    }
    startStep += steps;
  }
  return stem;
}

/// Whether [cells] carry any PER-TICK pitch/volume effect (porta/tone-porta/
/// vibrato/tremolo/vol-slide/set-volume/arpeggio/extended) — the ones that need
/// the tick voice to sound. Flow (Bxx/Dxx/E6x) and 9xx are handled elsewhere and
/// don't count here.
bool _hasPerTickEffect(List<TrackerCell> cells) {
  for (final c in cells) {
    final cmd = c.fxCmd;
    if (cmd == kFxPortaUp ||
        cmd == kFxPortaDown ||
        cmd == kFxTonePorta ||
        cmd == kFxVibrato ||
        cmd == kFxTonePortaVolSlide ||
        cmd == kFxVibratoVolSlide ||
        cmd == kFxTremolo ||
        cmd == kFxVolumeSlide ||
        cmd == kFxSetVolume ||
        cmd == kFxRetrigVolSlide ||
        cmd == kFxTremor ||
        cmd == kFxPanbrello ||
        cmd == kFxSetFilter ||
        cmd == kFxExtended) {
      return true;
    }
    if (cmd == kFxArpeggio && c.fxParam != 0) return true;
  }
  return false;
}

/// Maps a neighbour-tap integer position [j] to a valid sample index for the
/// 4-point cubic read, resolving it CONSISTENTLY with the main read position:
///  • a forward loop wraps a tap past the loop end back to the loop start, and
///    clamps a tap that runs off the front of the sample (idx-1 < 0) to 0;
///  • a ping-pong loop folds the tap through [foldLoopPosition] (the same fold
///    the read pointer follows), so a tap on the reflected side reads the
///    reflected sample;
///  • a non-looping sample clamps taps to the sample bounds (like [resampleCubic]
///    endpoint handling) — the very start of a sample repeats sample[0].
int _wrapSampleIndex(
  int j,
  int len,
  bool loops,
  bool pingPong,
  int loopStart,
  int loopLen,
) {
  if (loops && loopLen > 0) {
    if (pingPong) {
      final folded =
          foldLoopPosition(j.toDouble(), loopStart, loopLen, pingPong: true)
              .floor();
      return folded < 0 ? 0 : (folded >= len ? len - 1 : folded);
    }
    final loopEnd = loopStart + loopLen;
    if (j >= loopEnd) {
      final w = loopStart + ((j - loopStart) % loopLen);
      return w < 0 ? 0 : (w >= len ? len - 1 : w);
    }
  }
  return j < 0 ? 0 : (j >= len ? len - 1 : j);
}

/// Reads [sample] at the fractional position [readPos] using **4-point cubic
/// (Catmull-Rom) interpolation** — the tick-voice analogue of the offline
/// [resampleCubic] pitcher, so command songs get the same smoother resampling as
/// the simple-song path instead of 2-point linear. Fetches the four neighbours
/// `s[idx-1..idx+2]`, each mapped through [_wrapSampleIndex] so loop / ping-pong
/// wrap is respected per tap (MultiPLAY's looped-neighbour handling,
/// ../MultiPLAY/src/sample_builtintype.h:288-305), and blends by the fractional
/// part. Allocation-free (top-level helper calls, no closures) for the hot
/// streaming loop. Returns null when a one-shot (non-looping) sample is
/// exhausted, so callers can stop the note — same signalling as before.
double? _readLoopedSample(
  Float64List sample,
  double readPos,
  bool loops,
  bool pingPong,
  int loopStart,
  int loopLen,
) {
  if (sample.isEmpty) return null;
  var src = readPos;
  if (loops && loopLen > 0) {
    if (pingPong) {
      src = foldLoopPosition(readPos, loopStart, loopLen, pingPong: true);
    } else {
      final loopEnd = loopStart + loopLen;
      if (src >= loopEnd || src < loopStart) {
        src = loopStart + ((src - loopStart) % loopLen);
      }
    }
  }

  var idx = src.floor();
  if (!loops) {
    if (idx >= sample.length - 1) return null;
  } else {
    if (idx < 0 || idx >= sample.length) {
      final span = loopLen > 0 ? loopLen : sample.length;
      final start = loopLen > 0 ? loopStart : 0;
      idx = start + ((idx - start) % span);
    }
    idx = idx.clamp(0, sample.length - 1).toInt();
  }

  final frac = src - src.floor();
  final len = sample.length;
  final p0 = sample[
      _wrapSampleIndex(idx - 1, len, loops, pingPong, loopStart, loopLen)];
  final p1 =
      sample[_wrapSampleIndex(idx, len, loops, pingPong, loopStart, loopLen)];
  final p2 = sample[
      _wrapSampleIndex(idx + 1, len, loops, pingPong, loopStart, loopLen)];
  final p3 = sample[
      _wrapSampleIndex(idx + 2, len, loops, pingPong, loopStart, loopLen)];
  final t2 = frac * frac;
  final t3 = t2 * frac;
  return 0.5 *
      (2 * p1 +
          (-p0 + p2) * frac +
          (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
          (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
}

/// Test-only handle on the private tick-voice cubic reader [_readLoopedSample],
/// so interpolation-quality tests can exercise the exact production read. Not
/// used by production code (see test/interpolation_quality_test.dart).
double? readLoopedSampleForTest(
  Float64List sample,
  double readPos, {
  bool loops = false,
  bool pingPong = false,
  int loopStart = 0,
  int loopLen = 0,
}) =>
    _readLoopedSample(sample, readPos, loops, pingPong, loopStart, loopLen);

/// Stereo counterpart of the per-tick sample voice. It keeps the native right
/// waveform while applying the same pitch/volume/effect state as the mono tick
/// path. [rowStart] is absolute within the returned buffer, so this also serves
/// variable-tempo flow renders.
({Float64List left, Float64List right}) _renderSampleChannelStereoTicks(
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  List<TrackerInstrument>? pool, {
  (Float64List, Float64List)? into,
}) {
  final total = rowStart.last;
  // Optional caller-provided scratch (whole-song export): zero-fill and reuse
  // instead of allocating a fresh per-run buffer. Peak/scale run over [0,total)
  // exactly as before, so the result is byte-identical.
  final left =
      into != null ? (into.$1..fillRange(0, total, 0.0)) : Float64List(total);
  final right =
      into != null ? (into.$2..fillRange(0, total, 0.0)) : Float64List(total);
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final rows = cells.length;
  var cur = channel.instrument is SampleInstrument ? channel.instrument : null;
  final voice = ReplayVoice();
  var readPos = 0.0;
  var noteStartSample = 0;
  var releaseStartSample = 0;
  var rowPan = channel.pan.clamp(-1.0, 1.0);

  for (var r = 0; r < rows; r++) {
    final cell = cells[r];
    final cellInst = cell.instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      cur = pool[cellInst - 1];
    }
    if (cell.fxCmd == kFxSetPan) {
      rowPan = _panFromParam(cell.fxParam);
    } else if (cell.fxCmd == kFxPanSlide) {
      final rightAmount = (cell.fxParam >> 4) & 0xF;
      final leftAmount = cell.fxParam & 0xF;
      rowPan = (rowPan + (rightAmount - leftAmount) * ticksPerRow[r] / 128.0)
          .clamp(-1.0, 1.0);
    }
    voice.armRow(cell);
    if (voice.releasedThisRow) releaseStartSample = rowStart[r];
    if (voice.retriggeredThisRow) {
      final os = cur is SampleInstrument ? cur.offsetScale : 1.0;
      if (cur is SampleInstrument) {
        voice.armFilterOnTrigger(
          cur.filterCutoff,
          cur.filterResonance,
          cur.nativeFilterEnvelope,
        );
      }
      readPos = cell.fxCmd == kFxSampleOffset
          ? (cell.fxParam * 256 * os).toDouble()
          : 0.0;
      noteStartSample = rowStart[r];
    }
    if ((!voice.active && !voice.released && !voice.hasPendingNote) ||
        cur is! SampleInstrument ||
        cur.sample.isEmpty) {
      continue;
    }

    final baseMidi = cur.baseMidi;
    final sample = cur.sample;
    final sampleRight = cur.sampleRight;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    // A held note uses the IT sustain loop until a key-off. The tick voice is
    // only entered for effect-bearing rows, so it must make the same choice as
    // SampleInstrument.renderChannel instead of silently falling through to
    // the ordinary playback loop.
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticksPerRow[r] < 1 ? 1 : ticksPerRow[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        readPos = 0.0;
        noteStartSample = ts;
      }
      if (!voice.active && !voice.released) continue;
      final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
      for (var i = ts; i < te && i < total; i++) {
        final activeLoopStart = voice.released ? loopStart : playbackLoopStart;
        final activeLoopLength = voice.released ? loopLen : playbackLoopLength;
        final activePingPong = voice.released ? pingPong : playbackPingPong;
        final activeLoops = voice.released ? loops : playbackLoops;
        final activeLoopEnd = activeLoopStart + activeLoopLength;
        if (activeLoops &&
            !activePingPong &&
            activeLoopLength > 0 &&
            readPos >= activeLoopEnd) {
          readPos = activeLoopStart +
              ((readPos - activeLoopStart) % activeLoopLength);
        }
        final value = _readLoopedSample(
          sample,
          readPos,
          activeLoops,
          activePingPong,
          activeLoopStart,
          activeLoopLength,
        );
        if (value == null) break;
        final rightValue = sampleRight == null
            ? value
            : _readLoopedSample(
                  sampleRight,
                  readPos,
                  activeLoops,
                  activePingPong,
                  activeLoopStart,
                  activeLoopLength,
                ) ??
                0.0;
        // Per-voice resonant low-pass (IT initial cutoff/resonance + Zxx + the
        // filter-cutoff envelope). A no-op pass-through when the voice is
        // unfiltered; updateFilterEnv is a no-op without a filter envelope.
        voice.updateFilterEnv((i - noteStartSample) / kSampleRate * 1000);
        final fValue = voice.filterOut(value);
        final fRight =
            sampleRight == null ? fValue : voice.filterOutRight(rightValue);
        final t = (i - noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final nativeEnv = cur.nativeVolumeEnvelope;
        final level = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
            (hasEnv ? env.levelAt(t * 1000) : 1.0);
        final pan = (rowPan +
                state.pan +
                (channel.panEnvelope?.panAt(t * 1000) ?? 0.0) +
                (cur.nativePanEnvelope?.panAt(t * 1000) ?? 0.0))
            .clamp(-1.0, 1.0);
        final fadeRate = cur.nativeFadeout / 1024.0;
        final relSamples = max(0, i - releaseStartSample);
        final release = voice.released
            ? (fadeRate > 0
                ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                : exp(-relSamples / (0.03 * kSampleRate)))
            : 1.0;
        final amount = vol * attack * level * release;
        // Anti-click: hard-cut residue tail (panned as the note was) vs. a
        // soft-start fade-in applied equally to both channels of one output
        // sample. Mirror this block byte-for-byte in the streaming stereo path.
        final double outL, outR;
        if (voice.noteCut) {
          voice.residueStepStereo();
          outL = voice.resOutL;
          outR = voice.resOutR;
        } else {
          final sg = voice.softStartGain();
          final double cl, cr;
          if (sampleRight != null) {
            final leftGain = pan > 0 ? 1.0 - pan : 1.0;
            final rightGain = pan < 0 ? 1.0 + pan : 1.0;
            cl = fValue * amount * leftGain * sg;
            cr = fRight * amount * rightGain * sg;
          } else {
            final theta = (pan + 1) / 2 * (pi / 2);
            cl = fValue * amount * cos(theta) * sg;
            cr = fValue * amount * sin(theta) * sg;
          }
          voice.keepResidueStereo(cl, cr);
          outL = cl;
          outR = cr;
        }
        left[i] += outL;
        right[i] += outR;
        final pitch = cur.nativePitchEnvelope?.semitonesAt(
              t * 1000,
              released: voice.released,
            ) ??
            0.0;
        readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
      }
    }
  }

  final nativeSample = channel.instrument is SampleInstrument &&
      !(channel.instrument as SampleInstrument).normalize;
  var peak = 0.0;
  if (!nativeSample) {
    for (var i = 0; i < total; i++) {
      peak = max(peak, max(left[i].abs(), right[i].abs()));
    }
    if (peak == 0) return (left: left, right: right);
  }
  final scale = nativeSample ? channel.gain : channel.gain / peak;
  for (var i = 0; i < total; i++) {
    left[i] *= scale;
    right[i] *= scale;
  }
  return (left: left, right: right);
}

/// Renders a SAMPLE channel through a per-tick voice: a fractional resampling
/// read-pointer whose advance follows the tick voice's instantaneous PITCH
/// (porta/vibrato/arpeggio) and whose amplitude follows its VOLUME (tremolo/Cxx/
/// Axy) — the sample-instrument analogue of the additive tick voice. So an
/// imported module's pitch/volume effects actually sound on its sampled channels.
/// Per-cell instrument switches the sample; 9xx sets the start offset; a note is
/// one-shot (no loop, matching [SampleInstrument.renderChannel]); a short attack
/// declick + the channel [VolumeEnvelope] shape it. Unit-peak × gain like the
/// other non-additive paths.
void _renderSampleChannelInto(
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset, {
  List<TrackerInstrument>? pool,
}) {
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final stem = Float64List(timing.totalSamples);
  final rows = cells.length;
  var cur = channel.instrument is SampleInstrument ? channel.instrument : null;
  final voice = ReplayVoice();
  var readPos = 0.0; // fractional index into the current sample
  var noteStartSample = 0;
  var releaseStartSample = 0;

  for (var r = 0; r < rows; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      cur = pool[cellInst - 1];
    }
    voice.armRow(cells[r]);
    if (voice.releasedThisRow) releaseStartSample = timing.stepStartSample(r);
    if (voice.retriggeredThisRow) {
      final c = cells[r];
      final os = cur is SampleInstrument ? cur.offsetScale : 1.0;
      if (cur is SampleInstrument) {
        voice.armFilterOnTrigger(
          cur.filterCutoff,
          cur.filterResonance,
          cur.nativeFilterEnvelope,
        );
      }
      readPos =
          c.fxCmd == kFxSampleOffset ? (c.fxParam * 256 * os).toDouble() : 0.0;
      noteStartSample = timing.stepStartSample(r);
    }
    if ((!voice.active && !voice.released && !voice.hasPendingNote) ||
        cur is! SampleInstrument ||
        cur.sample.isEmpty) {
      continue;
    }

    final baseMidi = cur.baseMidi;
    final s = cur.sample;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final rowStart = timing.stepStartSample(r);
    final rowEnd =
        r + 1 < rows ? timing.stepStartSample(r + 1) : timing.totalSamples;
    for (var k = 0; k < ticksPerRow; k++) {
      final ts = rowStart + ((rowEnd - rowStart) * k) ~/ ticksPerRow;
      final te = rowStart + ((rowEnd - rowStart) * (k + 1)) ~/ ticksPerRow;
      final state = voice.tick(k, ticksPerRow);
      if (state.retrigger) {
        readPos = 0.0;
        noteStartSample = ts;
      }
      if (!voice.active && !voice.released) continue;
      final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
      for (var i = ts; i < te && i < stem.length; i++) {
        final activeLoopStart = voice.released ? loopStart : playbackLoopStart;
        final activeLoopLength = voice.released ? loopLen : playbackLoopLength;
        final activePingPong = voice.released ? pingPong : playbackPingPong;
        final activeLoops = voice.released ? loops : playbackLoops;
        final activeLoopEnd = activeLoopStart + activeLoopLength;
        if (activeLoops &&
            !activePingPong &&
            activeLoopLength > 0 &&
            readPos >= activeLoopEnd) {
          readPos = activeLoopStart +
              ((readPos - activeLoopStart) % activeLoopLength);
        }
        final sampleVal = _readLoopedSample(
          s,
          readPos,
          activeLoops,
          activePingPong,
          activeLoopStart,
          activeLoopLength,
        );
        if (sampleVal == null) break; // one-shot: sample exhausted
        final t = (i - noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final nativeEnv = cur.nativeVolumeEnvelope;
        final el = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
            (hasEnv ? env.levelAt(t * 1000) : 1.0);
        final fadeRate = cur.nativeFadeout / 1024.0;
        final relSamples = max(0, i - releaseStartSample);
        final release = voice.released
            ? (fadeRate > 0
                ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                : exp(-relSamples / (0.03 * kSampleRate)))
            : 1.0;
        // Anti-click: a hard cut (ECx) emits a decaying residue tail instead of
        // an instant zero; a real trigger fades in over the soft-start ramp.
        voice.updateFilterEnv(t * 1000);
        if (voice.noteCut) {
          stem[i] += voice.residueStep();
        } else {
          final sg = voice.softStartGain();
          final out =
              voice.filterOut(sampleVal) * vol * attack * el * release * sg;
          stem[i] += voice.keepResidue(out);
        }
        final pitch = cur.nativePitchEnvelope?.semitonesAt(
              t * 1000,
              released: voice.released,
            ) ??
            0.0;
        readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
      }
    }
  }

  final nativeSample = channel.instrument is SampleInstrument &&
      !(channel.instrument as SampleInstrument).normalize;
  var peak = 0.0;
  if (!nativeSample) {
    for (final v in stem) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) return;
  }
  final scale = nativeSample ? channel.gain : channel.gain / peak;
  final n = min(stem.length, mix.length - sampleOffset);
  for (var i = 0; i < n; i++) {
    mix[sampleOffset + i] += stem[i] * scale;
  }
}

/// The variable-timing sibling of [_renderSampleChannelInto]: the same per-tick
/// resampling read-pointer (pitch/volume effects + sample loop), but over
/// VARIABLE row spans — row `r` runs from absolute sample `rowStart[r]` to
/// `rowStart[r+1]`, subdivided into `ticksPerRow[r]` ticks. So a SAMPLE channel
/// that carries per-tick effects (porta/vibrato/tremolo/Cxx/Axy) AND a mid-song
/// tempo/speed change (or a per-pattern length change) plays those effects
/// instead of falling back to one-shot-per-note. Mixes into the absolute-offset
/// `mix` (rowStart is already absolute), unit-peak × gain like the other
/// non-additive paths.
void _renderSampleChannelIntoVariable(
  List<double> mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  List<TrackerInstrument>? pool, {
  void Function(int i, double v)? nativeSink,
}) {
  // Bounded-memory direct path: when a NATIVE (normalize==false) run is rendered
  // for the stereo export, [nativeSink] receives each produced sample already
  // scaled by the channel gain (== the `mix[i] += stem[i] * gain` the buffered
  // path would emit) so no whole-run `stem`/output buffer is allocated at all.
  // The caller must only pass a sink when scale == channel.gain (native sample).
  final useSink = nativeSink != null;
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final rows = cells.length;
  final stemLen = rowStart[rows];
  final stem = useSink ? Float64List(0) : Float64List(stemLen);
  var cur = channel.instrument is SampleInstrument ? channel.instrument : null;
  final voice = ReplayVoice();
  var readPos = 0.0;
  var noteStartSample = 0;
  var releaseStartSample = 0;

  for (var r = 0; r < rows; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      cur = pool[cellInst - 1];
    }
    voice.armRow(cells[r]);
    if (voice.releasedThisRow) releaseStartSample = rowStart[r];
    if (voice.retriggeredThisRow) {
      final c = cells[r];
      final os = cur is SampleInstrument ? cur.offsetScale : 1.0;
      if (cur is SampleInstrument) {
        voice.armFilterOnTrigger(
          cur.filterCutoff,
          cur.filterResonance,
          cur.nativeFilterEnvelope,
        );
      }
      readPos =
          c.fxCmd == kFxSampleOffset ? (c.fxParam * 256 * os).toDouble() : 0.0;
      noteStartSample = rowStart[r];
    }
    if ((!voice.active && !voice.released && !voice.hasPendingNote) ||
        cur is! SampleInstrument ||
        cur.sample.isEmpty) {
      continue;
    }

    final baseMidi = cur.baseMidi;
    final s = cur.sample;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticksPerRow[r] < 1 ? 1 : ticksPerRow[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        readPos = 0.0;
        noteStartSample = ts;
      }
      if (!voice.active && !voice.released) continue;
      final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
      for (var i = ts; i < te && i < stemLen; i++) {
        final activeLoopStart = voice.released ? loopStart : playbackLoopStart;
        final activeLoopLength = voice.released ? loopLen : playbackLoopLength;
        final activePingPong = voice.released ? pingPong : playbackPingPong;
        final activeLoops = voice.released ? loops : playbackLoops;
        final activeLoopEnd = activeLoopStart + activeLoopLength;
        if (activeLoops &&
            !activePingPong &&
            activeLoopLength > 0 &&
            readPos >= activeLoopEnd) {
          readPos = activeLoopStart +
              ((readPos - activeLoopStart) % activeLoopLength);
        }
        final sampleVal = _readLoopedSample(
          s,
          readPos,
          activeLoops,
          activePingPong,
          activeLoopStart,
          activeLoopLength,
        );
        if (sampleVal == null) break; // one-shot: sample exhausted
        final t = (i - noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final nativeEnv = cur.nativeVolumeEnvelope;
        final el = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
            (hasEnv ? env.levelAt(t * 1000) : 1.0);
        final fadeRate = cur.nativeFadeout / 1024.0;
        final relSamples = max(0, i - releaseStartSample);
        final release = voice.released
            ? (fadeRate > 0
                ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                : exp(-relSamples / (0.03 * kSampleRate)))
            : 1.0;
        // Anti-click: hard-cut residue tail vs. soft-start fade-in (see the
        // buffered [_renderSampleChannelInto] emit). [sv] is the finished value
        // BEFORE channel gain, so the residue tracks the pre-gain scalar.
        voice.updateFilterEnv(t * 1000);
        final double sv;
        if (voice.noteCut) {
          sv = voice.residueStep();
        } else {
          final sg = voice.softStartGain();
          final out =
              voice.filterOut(sampleVal) * vol * attack * el * release * sg;
          sv = voice.keepResidue(out);
        }
        if (useSink) {
          // Native (scale == channel.gain): emit the finished PCM sample value
          // directly — identical to the buffered `mix[i] += stem[i] * gain`.
          nativeSink(i, sv * channel.gain);
        } else {
          stem[i] += sv;
        }
        final pitch = cur.nativePitchEnvelope?.semitonesAt(
              t * 1000,
              released: voice.released,
            ) ??
            0.0;
        readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
      }
    }
  }

  // samples were streamed to the sink; no stem to mix down.
  if (useSink) {
    return;
  }

  final nativeSample = channel.instrument is SampleInstrument &&
      !(channel.instrument as SampleInstrument).normalize;
  var peak = 0.0;
  if (!nativeSample) {
    for (final v in stem) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) return;
  }
  final scale = nativeSample ? channel.gain : channel.gain / peak;
  final n = min(stem.length, mix.length);
  for (var i = 0; i < n; i++) {
    mix[i] += stem[i] * scale;
  }
}

/// The synthesis parameters of an additive [inst] (harmonics + envelope + the
/// L1 harmonic norm used to keep the voice's peak ≤ 1). Recomputed whenever a
/// per-cell instrument switches the additive timbre.
({List<double> harmonics, double attackSec, double decay, double harmNorm})
    _timbreParamsOf(Instrument inst) {
  final t = timbreFor(inst);
  var norm = 0.0;
  for (final h in t.harmonics) {
    norm += h.abs();
  }
  return (
    harmonics: t.harmonics,
    attackSec: t.attackMs / 1000,
    decay: t.decay,
    harmNorm: norm == 0 ? 1 : norm,
  );
}

/// Renders one channel's [cells] into [mix] starting at [sampleOffset]. Additive
/// voices synthesize per tick (honouring commands); other instruments fall back
/// to the offline whole-channel render (unit-peak × gain), so they still sound.
void _renderChannelInto(
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset, {
  List<TrackerInstrument>? pool,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;

  if (channel.instrument is MultiSampleInstrument && _hasPerTickEffect(cells)) {
    _renderMultiSampleChannelInto(
      mix,
      channel,
      cells,
      timing,
      ticksPerRow,
      sampleOffset,
    );
    return;
  }

  final inst = _additiveOf(channel.instrument);
  if (inst == null) {
    // A SAMPLE channel that carries per-tick pitch/volume effects (porta/
    // vibrato/tremolo/Cxx/Axy/arp/extended) renders through the sample TICK
    // voice so those effects actually SOUND (the whole-channel render can't do
    // per-tick modulation). Effect-free sample channels — and sfxr/percussion —
    // keep the unchanged non-additive render below (byte-identical).
    if (channel.instrument is SampleInstrument &&
        (_hasPerTickEffect(cells) ||
            (channel.instrument as SampleInstrument).hasFilter)) {
      _renderSampleChannelInto(
        mix,
        channel,
        cells,
        timing,
        ticksPerRow,
        sampleOffset,
        pool: pool,
      );
      return;
    }
    // Non-additive: build the channel stem, unit-peak × gain, sum at true
    // amplitude. With no per-cell instrument this is the unchanged whole-channel
    // render; with per-cell instruments it's a per-note render (each note played
    // by its pool instrument) that is BYTE-IDENTICAL to the whole render when the
    // instrument doesn't change (see renderChannelPerNote).
    final hasPerCell = pool != null && cells.any((c) => c.instrument != 0);
    final env = channel.volumeEnvelope;
    final hasEnv = env != null && !env.isEmpty;
    final stem = (hasPerCell || hasEnv)
        ? renderChannelPerNote(
            channel.instrument,
            cells,
            timing,
            pool ?? const <TrackerInstrument>[],
            envelope: hasEnv ? env : null,
          )
        : channel.instrument.renderChannel(cells, timing);
    var peak = 0.0;
    for (final v in stem) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) return;
    final scale = channel.instrument is SampleInstrument &&
            !(channel.instrument as SampleInstrument).normalize
        ? channel.gain
        : channel.gain / peak;
    final n = min(stem.length, mix.length - sampleOffset);
    for (var i = 0; i < n; i++) {
      mix[sampleOffset + i] += stem[i] * scale;
    }
    return;
  }

  // The current additive timbre — the channel's by default, swapped when a cell
  // names an additive pool instrument (persists per channel, tracker-style).
  var tp = _timbreParamsOf(inst);
  final gain = channel.gain;

  final voice = ReplayVoice();
  final rows = cells.length;
  for (var r = 0; r < rows; r++) {
    // Per-cell instrument: switch the additive timbre if the cell names an
    // additive pool instrument (a non-additive reference is ignored here).
    final cellInst = cells[r].instrument;
    if (cellInst > 0 && pool != null && cellInst - 1 < pool.length) {
      final pi = _additiveOf(pool[cellInst - 1]);
      if (pi != null) tp = _timbreParamsOf(pi);
    }
    voice.armRow(cells[r]);
    // Only a note that ACTUALLY triggers at tick 0 resets the envelope state
    // now. A pending EDx delay must NOT touch it here — a prior note may still be
    // ringing through ticks 0..x-1, and moving its start would re-attack it. The
    // delayed note sets its own start/run when it fires in the tick loop below.
    if (voice.retriggeredThisRow) {
      voice.oscPhase = 0;
      voice.noteStartSample = sampleOffset + timing.stepStartSample(r);
      voice.noteSeconds = _runSeconds(cells, r, rows, timing);
    }
    // A silent row: no live note and nothing pending to trigger this row.
    if (!voice.active && !voice.hasPendingNote) continue;

    final rowStart = sampleOffset + timing.stepStartSample(r);
    final rowEnd = sampleOffset +
        (r + 1 < rows ? timing.stepStartSample(r + 1) : timing.totalSamples);
    for (var k = 0; k < ticksPerRow; k++) {
      final ts = rowStart + ((rowEnd - rowStart) * k) ~/ ticksPerRow;
      final te = rowStart + ((rowEnd - rowStart) * (k + 1)) ~/ ticksPerRow;
      final state = voice.tick(k, ticksPerRow);
      // A retrigger (E9x) or a delayed note (EDx) restarts the envelope here —
      // at the actual fire tick, so a delayed note's start/run are set only when
      // it sounds (never disturbing a prior ringing note earlier in the row).
      if (state.retrigger) {
        voice.oscPhase = 0;
        voice.noteStartSample = ts;
        voice.noteSeconds = _runSeconds(cells, r, rows, timing);
      }
      if (!voice.active) continue; // pre-delay silence / never triggered
      final freq = _freqOfMidi(state.pitch);
      final volScale = (state.volume / kMaxVolume) * voice.noteVolume * gain;
      final phaseInc = 2 * pi * freq / kSampleRate;
      for (var i = ts; i < te && i < mix.length; i++) {
        final t = (i - voice.noteStartSample) / kSampleRate;
        if (t < 0) continue;
        final attack = t < tp.attackSec ? t / tp.attackSec : 1.0;
        final env = attack * exp(-tp.decay * t / voice.noteSeconds);
        var sample = 0.0;
        for (var h = 0; h < tp.harmonics.length; h++) {
          sample += tp.harmonics[h] * sin(voice.oscPhase * (h + 1));
        }
        final el = channel.volumeEnvelope?.levelAt(t * 1000) ?? 1.0;
        mix[i] += (sample / tp.harmNorm) * env * volScale * el;
        voice.oscPhase += phaseInc;
      }
    }
  }
}

// --- Opt-in deterministic TPDF dither (float→Int16 quantisation) -------------
//
// The final quantisation `round(tanh(mix)·0.95·32767)` truncates the float mix
// to signed 16-bit. Plain rounding makes the quantisation error a DETERMINISTIC
// function of the signal, so on quiet, slowly-varying material it shows up as
// harmonic distortion correlated with the signal. Adding a small triangular-PDF
// (TPDF) dither before rounding DECORRELATES that error — the quantisation noise
// becomes white and signal-independent (the standard dither result), at the cost
// of a slightly raised (but flat) noise floor. This is a real quality OPTION;
// it is OFF by default so the default render is byte-identical + reproducible.
//
// TPDF = the sum of two independent uniform values in [-0.5, +0.5] LSB, giving a
// triangular distribution over [-1, +1] LSB — exactly one quantisation step of
// support, the classic choice for 16-bit dither. We deliberately do NOT add
// noise-shaping / error-feedback: keeping the dither a pure per-sample function
// of the PRNG (no cross-sample state, channels independent) is what lets the
// STREAMING conversion produce byte-identical output to the whole-render one —
// both advance the same seeded PRNG over the same L,R,L,R sample order.
//
// The PRNG is a tiny deterministic xorshift32 (NOT `Math.random`, which is
// banned + non-reproducible): seeded from a fixed constant (or a caller-supplied
// seed), so the same input renders to the same dithered bytes every run.

/// The default dither PRNG seed — a fixed constant, so a dithered render with no
/// explicit seed is still reproducible run-to-run.
const int kDefaultDitherSeed = 0x9E3779B9;

/// A deterministic TPDF ditherer for the final float→Int16 quantisation. Holds a
/// seeded xorshift32 PRNG advanced once per emitted uniform (two per sample).
/// Passing `null` anywhere a `PcmDither?` is accepted means NO dither → the exact
/// original `round(...)` behaviour (bit-identical). Construct ONE per render and
/// thread it through every conversion so the whole sequence is deterministic.
class PcmDither {
  PcmDither({int seed = kDefaultDitherSeed})
      : _state =
            (seed & 0xFFFFFFFF) == 0 ? kDefaultDitherSeed : seed & 0xFFFFFFFF;

  // xorshift32 state, kept in the low 32 bits and never zero.
  int _state;

  /// One xorshift32 step → a uniform double in [-0.5, +0.5).
  double _nextUniform() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state / 4294967296.0 - 0.5;
  }

  /// The next TPDF sample (sum of two independent uniforms) in [-1, +1] LSB.
  double nextTriangular() => _nextUniform() + _nextUniform();

  /// Quantise a value [scaled] ALREADY in the int16 domain (i.e.
  /// `tanh(mix)·0.95·32767`) by adding TPDF dither, then rounding.
  int quantizeScaled(double scaled) => (scaled + nextTriangular()).round();
}

/// Converts a Float64 mix to PCM16 with the same tanh soft-knee as [mixStems].
/// With a non-null [dither] each sample is TPDF-dithered before rounding;
/// null leaves it bit-identical to plain rounding.
Int16List _mixToPcm(Float64List mix, [PcmDither? dither]) {
  final out = Int16List(mix.length);
  for (var i = 0; i < mix.length; i++) {
    final s = _tanh(mix[i]) * 0.95 * 32767;
    out[i] = dither == null ? s.round() : dither.quantizeScaled(s);
  }
  return out;
}

/// Whether any cell in [rows] (row-major `rows[r][channel]`) carries a global-
/// volume command (Gxx set or Hxy slide) — the gate that decides whether a
/// render pays for the [globalVolumeEnvelope] pass.
bool _hasGlobalVolume(List<List<TrackerCell>> rows) {
  for (final row in rows) {
    for (final c in row) {
      if (c.fxCmd == kFxSetGlobalVolume || c.fxCmd == kFxGlobalVolSlide) {
        return true;
      }
    }
  }
  return false;
}

/// The per-sample GLOBAL-volume scale (0..1) over a played row sequence, driven
/// by Gxx (set, 0x00–0x40) and Hxy (slide: x up / y down per tick). Global
/// volume persists across rows, starting at full (0x40). [rows] is row-major
/// (`rows[r][channel]`); [rowStart] gives each row's start sample (length ==
/// rows.length) and [totalSamples] bounds the last row. Returns null when no
/// Gxx/Hxy appears, so the caller skips the multiply and the common render stays
/// byte-identical. First Gxx/Hxy on a row wins (scanned across channels).
Float64List? globalVolumeEnvelope(
  List<List<TrackerCell>> rows,
  List<int> rowStart,
  int totalSamples,
  int ticksPerRow, {
  int startVolume = 64,
}) {
  if (!_hasGlobalVolume(rows)) return null;
  final env = Float64List(totalSamples);
  final tpr = ticksPerRow < 1 ? 1 : ticksPerRow;
  var gv = startVolume.clamp(0, 64);
  for (var r = 0; r < rows.length; r++) {
    int? setTo;
    int? slide;
    for (final c in rows[r]) {
      if (c.fxCmd == kFxSetGlobalVolume) {
        setTo ??= c.fxParam;
      } else if (c.fxCmd == kFxGlobalVolSlide) {
        slide ??= c.fxParam;
      }
    }
    if (setTo != null) gv = setTo.clamp(0, 64);
    final rowS = rowStart[r];
    final rowE = r + 1 < rows.length ? rowStart[r + 1] : totalSamples;
    if (slide == null) {
      final s = gv / 64.0;
      for (var i = rowS; i < rowE && i < totalSamples; i++) {
        env[i] = s;
      }
    } else {
      final up = (slide >> 4) & 0xF;
      final down = slide & 0xF;
      for (var k = 0; k < tpr; k++) {
        if (k > 0) gv = (gv + up - down).clamp(0, 64); // slide on ticks >= 1
        final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
        final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
        final s = gv / 64.0;
        for (var i = ts; i < te && i < totalSamples; i++) {
          env[i] = s;
        }
      }
    }
  }
  return env;
}

// --- Stereo panning (Feature C) ----------------------------------------------
//
// Pan is a purely SPATIAL, post-mix operation: it never changes a voice's mono
// waveform, so the stereo path renders each channel to its own mono buffer with
// the existing [_renderChannelInto] (all pitch/volume commands intact), then
// distributes that buffer across L/R with a constant-power law. A channel's pan
// starts at [TrackerChannel.pan] and is overridden by 8xx cells (persisting per
// channel, like volume) — [_panRegions] walks the cells into contiguous
// (start,end,pan) spans so an 8xx mid-pattern re-pans from that row onward.

/// Maps an 8xx param (0x00 left … 0x80 centre … 0xFF right) to a pan of −1..1.
double _panFromParam(int param) => ((param - 0x80) / 0x80).clamp(-1.0, 1.0);

/// Interleaves separate [left]/[right] Float64 mixes into stereo PCM16 with the
/// same tanh soft-knee as [_mixToPcm].
Int16List _interleaveToPcm(
  List<double> left,
  List<double> right, [
  PcmDither? dither,
]) {
  final out = Int16List(left.length * 2);
  for (var i = 0; i < left.length; i++) {
    final l = _tanh(left[i]) * 0.95 * 32767;
    final r = _tanh(right[i]) * 0.95 * 32767;
    // Advance the PRNG in L,R,L,R order so the streaming stereo converter
    // (same order) is byte-identical.
    out[i * 2] = dither == null ? l.round() : dither.quantizeScaled(l);
    out[i * 2 + 1] = dither == null ? r.round() : dither.quantizeScaled(r);
  }
  return out;
}

/// The pan spans of [cells]: contiguous `(start,end,pan)` sample ranges covering
/// `[0,totalSamples)`, starting at [basePan] and switching wherever an 8xx cell
/// sets a new pan (from that row's sample onward, persisting like volume).
List<({int start, int end, double pan})> _panRegions(
  double basePan,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int totalSamples, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final regions = <({int start, int end, double pan})>[];
  var pan = basePan;
  var regionStart = 0;
  for (var r = 0; r < cells.length; r++) {
    final c = cells[r];
    // 8xx sets the pan outright; Pxy slides it (row-granular step, like Txx).
    double? newPan;
    if (c.fxCmd == kFxSetPan) {
      newPan = _panFromParam(c.fxParam);
    } else if (c.fxCmd == kFxPanSlide) {
      final rightAmt = (c.fxParam >> 4) & 0xF;
      final leftAmt = c.fxParam & 0xF;
      final ticks = ticksPerRow > 1 ? ticksPerRow : 1;
      newPan = (pan + (rightAmt - leftAmt) * ticks / 128.0).clamp(-1.0, 1.0);
    }
    if (newPan != null && newPan != pan) {
      final s = timing.stepStartSample(r);
      if (s > regionStart) {
        regions.add((start: regionStart, end: s, pan: pan));
      }
      regionStart = s;
      pan = newPan;
    }
  }
  regions.add((start: regionStart, end: totalSamples, pan: pan));
  return regions;
}

({Float64List left, Float64List right})? _renderSampleNotesStereo(
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  List<TrackerInstrument>? pool,
) {
  if (channel.instrument is! SampleInstrument) return null;
  final base = channel.instrument as SampleInstrument;
  if (!cells.any((c) => c.instrument != 0) &&
      (base.nativeNna != 0 || base.nativeDct != 0)) {
    final rendered = base.renderChannelStereo(cells, timing);
    final left = Float64List.fromList(rendered.left);
    final right = Float64List.fromList(rendered.right);
    final pan = channel.pan.clamp(-1.0, 1.0);
    final leftGain = pan > 0 ? 1.0 - pan : 1.0;
    final rightGain = pan < 0 ? 1.0 + pan : 1.0;
    final stereo = base.sampleRight != null;
    final theta = (pan + 1) / 2 * (pi / 2);
    for (var i = 0; i < left.length; i++) {
      if (stereo) {
        left[i] *= leftGain;
        right[i] *= rightGain;
      } else {
        right[i] = left[i] * sin(theta);
        left[i] *= cos(theta);
      }
      left[i] *= channel.gain;
      right[i] *= channel.gain;
    }
    return (left: left, right: right);
  }
  final left = Float64List(timing.totalSamples);
  final right = Float64List(timing.totalSamples);
  var cur = base;
  var startStep = 0;
  var allNative = true;

  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final releaseSteps = run.$3;
    final totalSteps = sustainSteps + releaseSteps;
    final trigger = cells[startStep];
    if (trigger.instrument > 0 &&
        pool != null &&
        trigger.instrument - 1 < pool.length) {
      final selected = pool[trigger.instrument - 1];
      if (selected is! SampleInstrument) return null;
      cur = selected;
    }
    if (midi != null) {
      final one = List<TrackerCell>.filled(cells.length, TrackerCell.empty)
        ..[startStep] = trigger;
      final capRow = startStep + sustainSteps;
      if (capRow < cells.length) {
        one[capRow] =
            releaseSteps > 0 ? TrackerCell.noteCut : TrackerCell(midi: midi);
      }
      final rendered = cur.renderChannelStereo(one, timing);
      final s = timing.stepStartSample(startStep);
      final e = min(
        startStep + totalSteps < cells.length
            ? timing.stepStartSample(startStep + totalSteps)
            : timing.totalSamples,
        timing.totalSamples,
      );
      final nativePan = cur.nativePanEnvelope;
      final hasRight = cur.sampleRight != null;
      allNative = allNative && !cur.normalize;
      final channelEnv = channel.volumeEnvelope;
      for (var i = s; i < e; i++) {
        final noteMs = (i - s) / kSampleRate * 1000;
        final vol = cur.nativeVolumeEnvelope == null
            ? channelEnv?.levelAt(noteMs) ?? 1.0
            : 1.0;
        final released = releaseSteps > 0 &&
            i - s >=
                timing.stepStartSample(sustainSteps) -
                    timing.stepStartSample(0);
        final pan = (channel.pan +
                (nativePan?.panAt(noteMs, released: released) ?? 0.0))
            .clamp(-1.0, 1.0);
        if (hasRight) {
          final leftGain = pan > 0 ? 1.0 - pan : 1.0;
          final rightGain = pan < 0 ? 1.0 + pan : 1.0;
          left[i] += rendered.left[i] * vol * leftGain;
          right[i] += rendered.right[i] * vol * rightGain;
        } else {
          final theta = (pan + 1) / 2 * (pi / 2);
          left[i] += rendered.left[i] * vol * cos(theta);
          right[i] += rendered.left[i] * vol * sin(theta);
        }
      }
    }
    startStep += totalSteps;
  }

  var peak = 0.0;
  for (final v in left) {
    if (v.abs() > peak) peak = v.abs();
  }
  for (final v in right) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) return (left: left, right: right);
  final scale = allNative ? channel.gain : channel.gain / peak;
  for (var i = 0; i < left.length; i++) {
    left[i] *= scale;
    right[i] *= scale;
  }
  return (left: left, right: right);
}

/// Renders sampled XM/IT zones through the tick voice. The ordinary
/// MultiSampleInstrument path already resolves zones for effect-free notes,
/// but its generic fallback cannot apply per-tick tracker commands. Each note
/// run is isolated so the selected zone, envelope, loop, and key-off state are
/// all evaluated from that run's native instrument.
class _NativeTickZoneVoice {
  _NativeTickZoneVoice({
    required this.midi,
    required this.zone,
    required this.startStep,
    required this.runSteps,
    required this.cells,
  });

  final int midi;
  final TrackerInstrument zone;
  final int startStep;
  final int runSteps;
  final List<TrackerCell> cells;
  int endSample = 1 << 60;
  int? releaseAt;
  int? fadeAt;
  // Step at which a release (NNA action 1) was first triggered on this voice.
  // The audio for the release variant is rendered lazily in pass 2, so we only
  // record the metadata here.
  int? releaseStep;
}

typedef _NativeTickZoneRenderer = ({Float64List left, Float64List? right})
    Function(
  TrackerInstrument zone,
  List<TrackerCell> cells,
);

List<TrackerCell> _isolatedTickZoneCells(
  List<TrackerCell> cells,
  int startStep,
  int runSteps,
) {
  final isolated = List<TrackerCell>.filled(cells.length, TrackerCell.empty);
  final end = min(startStep + runSteps, cells.length);
  isolated.setRange(startStep, end, cells, startStep);
  if (end < isolated.length) isolated[end] = TrackerCell.noteCut;
  return isolated;
}

({Float64List left, Float64List? right}) _renderNativeTickZoneVoices(
  MultiSampleInstrument multi,
  List<TrackerCell> cells,
  List<int> rowStart,
  _NativeTickZoneRenderer render,
) {
  final total = rowStart.last;
  final left = Float64List(total);
  final voices = <_NativeTickZoneVoice>[];
  var startStep = 0;

  // Pass 1: build voice metadata and resolve NNA/DCT actions WITHOUT rendering
  // any audio. Each note run walks the same as before; the only difference is
  // that no whole-song buffers are allocated here.
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final runSteps = run.$2 + run.$3;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone != null) {
        final voiceCells = _isolatedTickZoneCells(cells, startStep, runSteps);
        final voice = _NativeTickZoneVoice(
          midi: midi,
          zone: zone,
          startStep: startStep,
          runSteps: runSteps,
          cells: voiceCells,
        );
        final newStart = rowStart[startStep];
        for (final old in voices) {
          if (old.endSample <= newStart) continue;
          final duplicate = _isNativeTickDuplicate(
            old,
            voice,
            nativeDctOf(zone),
          );
          final action = duplicate ? nativeDcaOf(zone) : nativeNnaOf(old.zone);
          switch (action) {
            case 0:
              old.endSample = newStart;
            case 1:
              old.releaseAt = newStart;
              // Record the release trigger step once (matches the original
              // guard that only rendered the release variant the first time).
              old.releaseStep ??= startStep;
            case 2:
              old.fadeAt = newStart;
          }
        }
        voices.add(voice);
      }
    }
    startStep += runSteps;
  }

  // Pass 2: render and mix one voice at a time so voice buffers are never
  // co-resident. At most ~2 whole-song buffers (the note and its release
  // variant) are alive at once instead of one per overlapping voice.
  Float64List? rightStem;
  for (final voice in voices) {
    final rendered = render(voice.zone, voice.cells);
    // All voices in a single call share the same renderer, so its right-channel
    // presence is uniform; allocating the stem on first sight is equivalent to
    // the previous `voices.any((v) => v.right != null)` decision.
    if (rendered.right != null && rightStem == null) {
      rightStem = Float64List(total);
    }
    Float64List? releaseLeft;
    Float64List? releaseRight;
    if (voice.releaseAt != null) {
      final releasedCells = List<TrackerCell>.from(voice.cells);
      final rs = voice.releaseStep!;
      if (rs < releasedCells.length) {
        releasedCells[rs] = TrackerCell.noteCut;
      }
      final releasedRendered = render(voice.zone, releasedCells);
      releaseLeft = releasedRendered.left;
      releaseRight = releasedRendered.right;
    }
    final start = rowStart[voice.startStep];
    final end = voice.endSample.clamp(start, total);
    final fadeRate = nativeFadeoutOf(voice.zone) / 1024.0;
    if (rightStem != null) {
      for (var i = start; i < end; i++) {
        final released = voice.releaseAt != null && i >= voice.releaseAt!;
        final selected = released
            ? (releaseRight ?? releaseLeft)
            : (rendered.right ?? rendered.left);
        if (selected == null || i >= selected.length) continue;
        var gain = 1.0;
        if (voice.fadeAt != null && i >= voice.fadeAt!) {
          gain = exp(-fadeRate * (i - voice.fadeAt!) / kSampleRate * 8.0);
        }
        rightStem[i] += selected[i] * gain;
      }
    }
    for (var i = start; i < end; i++) {
      final released = voice.releaseAt != null && i >= voice.releaseAt!;
      final selected = released ? releaseLeft : rendered.left;
      if (selected == null || i >= selected.length) continue;
      var gain = 1.0;
      if (voice.fadeAt != null && i >= voice.fadeAt!) {
        gain = exp(-fadeRate * (i - voice.fadeAt!) / kSampleRate * 8.0);
      }
      left[i] += selected[i] * gain;
    }
  }
  return (left: left, right: rightStem);
}

bool _isNativeTickDuplicate(
  _NativeTickZoneVoice old,
  _NativeTickZoneVoice next,
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

void _renderMultiSampleChannelInto(
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset,
) {
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument) return;
  if (multi.nativeVoiceSemantics &&
      multi.zones.values.every((zone) => zone is SampleInstrument)) {
    final rowStart = [
      for (var row = 0; row < cells.length; row++) timing.stepStartSample(row),
      timing.totalSamples,
    ];
    final rendered = _renderNativeTickZoneVoices(
      multi,
      cells,
      rowStart,
      (zone, isolated) {
        final out = Float64List(timing.totalSamples);
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        _renderSampleChannelInto(
          out,
          zoneChannel,
          isolated,
          timing,
          ticksPerRow,
          0,
        );
        return (left: out, right: null);
      },
    );
    final n = min(rendered.left.length, mix.length - sampleOffset);
    for (var i = 0; i < n; i++) {
      mix[sampleOffset + i] += rendered.left[i];
    }
    return;
  }
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final steps = run.$2 + run.$3;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone == null) {
        startStep += steps;
        continue;
      }
      if (zone is SampleInstrument || _additiveOf(zone) != null) {
        final isolated =
            List<TrackerCell>.filled(cells.length, TrackerCell.empty)
              ..setRange(
                startStep,
                min(startStep + steps, cells.length),
                cells,
                startStep,
              );
        final boundary = startStep + steps;
        if (boundary < isolated.length && isolated[boundary].isEmpty) {
          isolated[boundary] = TrackerCell.noteCut;
        }
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        if (zone is SampleInstrument) {
          _renderSampleChannelInto(
            mix,
            zoneChannel,
            isolated,
            timing,
            ticksPerRow,
            sampleOffset,
          );
        } else if (_additiveOf(zone) != null) {
          _renderChannelInto(
            mix,
            zoneChannel,
            isolated,
            timing,
            ticksPerRow,
            sampleOffset,
          );
        }
      }
    }
    startStep += steps;
  }
}

({Float64List left, Float64List right}) _renderMultiSampleChannelStereoTicks(
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow, [
  _StereoScratch? scratch,
]) {
  final total = timing.totalSamples;
  // Reuse the channel accumulator across orders/channels when a scratch set is
  // supplied (uniform whole-song export); zero-fill first so the sum is exact.
  final left = scratch != null
      ? (scratch.chL..fillRange(0, total, 0.0))
      : Float64List(total);
  final right = scratch != null
      ? (scratch.chR..fillRange(0, total, 0.0))
      : Float64List(total);
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument) return (left: left, right: right);
  final rowStart = [
    for (var row = 0; row < cells.length; row++) timing.stepStartSample(row),
    timing.totalSamples,
  ];
  if (multi.nativeVoiceSemantics &&
      multi.zones.values.every((zone) => zone is SampleInstrument)) {
    final rendered = _renderNativeTickZoneVoices(
      multi,
      cells,
      rowStart,
      (zone, isolated) {
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        final stereo = _renderSampleChannelStereoTicks(
          zoneChannel,
          isolated,
          rowStart,
          List<int>.filled(cells.length, ticksPerRow),
          null,
        );
        return (left: stereo.left, right: stereo.right);
      },
    );
    return (
      left: rendered.left,
      right: rendered.right ?? Float64List.fromList(rendered.left),
    );
  }
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final steps = run.$2 + run.$3;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone == null) {
        startStep += steps;
        continue;
      }
      if (zone is SampleInstrument || _additiveOf(zone) != null) {
        final isolated =
            List<TrackerCell>.filled(cells.length, TrackerCell.empty)
              ..setRange(
                startStep,
                min(startStep + steps, cells.length),
                cells,
                startStep,
              );
        final boundary = startStep + steps;
        if (boundary < isolated.length && isolated[boundary].isEmpty) {
          isolated[boundary] = TrackerCell.noteCut;
        }
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        late final ({Float64List left, Float64List right}) rendered;
        if (_additiveOf(zone) != null) {
          final zoneLeft = Float64List(timing.totalSamples);
          final zoneRight = Float64List(timing.totalSamples);
          _renderChannelIntoStereo(
            zoneLeft,
            zoneRight,
            zoneChannel,
            isolated,
            timing,
            ticksPerRow,
            0,
          );
          rendered = (left: zoneLeft, right: zoneRight);
        } else {
          rendered = _renderSampleChannelStereoTicks(
            zoneChannel,
            isolated,
            rowStart,
            List<int>.filled(cells.length, ticksPerRow),
            null,
            into: scratch != null ? (scratch.runL, scratch.runR) : null,
          );
        }
        for (var i = 0; i < left.length; i++) {
          left[i] += rendered.left[i];
          right[i] += rendered.right[i];
        }
      }
    }
    startStep += steps;
  }
  return (left: left, right: right);
}

void _renderMultiSampleChannelIntoVariable(
  List<double> mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
) {
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument) return;
  if (multi.nativeVoiceSemantics &&
      multi.zones.values.every((zone) => zone is SampleInstrument)) {
    final rendered = _renderNativeTickZoneVoices(
      multi,
      cells,
      rowStart,
      (zone, isolated) {
        final out = Float64List(rowStart.last);
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        _renderSampleChannelIntoVariable(
          out,
          zoneChannel,
          isolated,
          rowStart,
          ticksPerRow,
          null,
        );
        return (left: out, right: null);
      },
    );
    for (var i = 0; i < rendered.left.length && i < mix.length; i++) {
      mix[i] += rendered.left[i];
    }
    return;
  }
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final steps = run.$2 + run.$3;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone == null) {
        startStep += steps;
        continue;
      }
      if (zone is SampleInstrument || _additiveOf(zone) != null) {
        final isolated =
            List<TrackerCell>.filled(cells.length, TrackerCell.empty)
              ..setRange(
                startStep,
                min(startStep + steps, cells.length),
                cells,
                startStep,
              );
        final boundary = startStep + steps;
        if (boundary < isolated.length && isolated[boundary].isEmpty) {
          isolated[boundary] = TrackerCell.noteCut;
        }
        final zoneChannel = TrackerChannel(
          id: '${channel.id}:zone',
          instrument: zone,
          rows: cells.length,
          gain: channel.gain,
          pan: channel.pan,
          volumeEnvelope: channel.volumeEnvelope,
          panEnvelope: channel.panEnvelope,
        );
        if (zone is SampleInstrument) {
          _renderSampleChannelIntoVariable(
            mix,
            zoneChannel,
            isolated,
            rowStart,
            ticksPerRow,
            null,
          );
        } else if (_additiveOf(zone) != null) {
          _renderChannelIntoVariable(
            mix,
            zoneChannel,
            isolated,
            rowStart,
            ticksPerRow,
            ticksPerRow.first,
          );
        }
      }
    }
    startStep += steps;
  }
}

/// Renders one channel's [cells] mono (via [_renderChannelInto]) then pans it
/// into the [left]/[right] stereo mixes at [sampleOffset], honouring the
/// channel's base pan and any 8xx pan changes ([_panRegions]).
/// Reusable per-pattern scratch buffers for the uniform whole-song stereo render
/// ([_replaySongStereoFloat] main branch). Every per-order channel render uses
/// buffers of the SAME `timing.totalSamples`, so one set is cleared and reused
/// for every channel/order instead of freshly allocating (and orphaning to the
/// GC) a whole-pattern Float64List per channel and per note run — the churn that
/// dominated the whole-file export peak. Reuse changes no arithmetic (buffers are
/// zero-filled before use), so the render stays byte-identical.
class _StereoScratch {
  _StereoScratch(this.len)
      : chL = Float64List(len),
        chR = Float64List(len),
        runL = Float64List(len),
        runR = Float64List(len),
        mono = Float64List(len);
  final int len;
  final Float64List chL; // channel-level accumulator (multi-sample tick render)
  final Float64List chR;
  final Float64List runL; // per-note-run sample render
  final Float64List runR;
  final Float64List mono; // mono pan path
}

void _renderChannelIntoStereo(
  Float64List left,
  Float64List right,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset, {
  List<TrackerInstrument>? pool,
  _StereoScratch? scratch,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;

  if (channel.instrument is MultiSampleInstrument && _hasPerTickEffect(cells)) {
    final rendered = _renderMultiSampleChannelStereoTicks(
      channel,
      cells,
      timing,
      ticksPerRow,
      scratch,
    );
    final n = min(timing.totalSamples, left.length - sampleOffset);
    for (var i = 0; i < n; i++) {
      left[sampleOffset + i] += rendered.left[i];
      right[sampleOffset + i] += rendered.right[i];
    }
    return;
  }

  if (channel.instrument is SampleInstrument && _hasPerTickEffect(cells)) {
    final rowStart = [
      for (var row = 0; row < cells.length; row++) timing.stepStartSample(row),
      timing.totalSamples,
    ];
    final rendered = _renderSampleChannelStereoTicks(
      channel,
      cells,
      rowStart,
      List<int>.filled(cells.length, ticksPerRow),
      pool,
    );
    final n = min(timing.totalSamples, left.length - sampleOffset);
    for (var i = 0; i < n; i++) {
      left[sampleOffset + i] += rendered.left[i];
      right[sampleOffset + i] += rendered.right[i];
    }
    return;
  }

  if (!_hasPerTickEffect(cells)) {
    final rendered = channel.instrument is SampleInstrument
        ? _renderSampleNotesStereo(channel, cells, timing, pool)
        : channel.instrument is MultiSampleInstrument
            ? _renderMultiSampleNotesStereo(channel, cells, timing, scratch)
            : null;
    if (rendered != null) {
      final n = min(timing.totalSamples, left.length - sampleOffset);
      for (var i = 0; i < n; i++) {
        left[sampleOffset + i] += rendered.left[i];
        right[sampleOffset + i] += rendered.right[i];
      }
      return;
    }
    // A non-sample pool instrument requires the existing mixed mono path.
  }

  final total = timing.totalSamples;
  final mono = scratch != null
      ? (scratch.mono..fillRange(0, total, 0.0))
      : Float64List(total);
  _renderChannelInto(mono, channel, cells, timing, ticksPerRow, 0, pool: pool);

  // A pan ENVELOPE auto-pans each note over time (base pan + the envelope offset,
  // clamped) — a per-note, per-sample sweep. It takes precedence over 8xx (which
  // it would otherwise fight); 8xx-only channels use the region path below.
  final penv = channel.panEnvelope;
  if (penv != null && !penv.isEmpty) {
    final rows = cells.length;
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final s = timing.stepStartSample(startStep);
        final e = startStep + steps < rows
            ? timing.stepStartSample(startStep + steps)
            : total;
        final end = min(e, total);
        for (var i = s; i < end; i++) {
          final o = sampleOffset + i;
          if (o >= left.length) break;
          final pan = (channel.pan + penv.panAt((i - s) / kSampleRate * 1000))
              .clamp(-1.0, 1.0);
          final theta = (pan + 1) / 2 * (pi / 2);
          left[o] += mono[i] * cos(theta);
          right[o] += mono[i] * sin(theta);
        }
      }
      startStep += steps;
    }
    return;
  }

  for (final reg in _panRegions(
    channel.pan,
    cells,
    timing,
    total,
    ticksPerRow: ticksPerRow,
  )) {
    final theta = (reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2);
    final lGain = cos(theta);
    final rGain = sin(theta);
    final end = min(reg.end, total);
    for (var i = reg.start; i < end; i++) {
      final o = sampleOffset + i;
      if (o >= left.length) break;
      left[o] += mono[i] * lGain;
      right[o] += mono[i] * rGain;
    }
  }
}

({Float64List left, Float64List right}) _renderMultiSampleNotesStereo(
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing, [
  _StereoScratch? scratch,
]) {
  final instrument = channel.instrument as MultiSampleInstrument;
  // Reuse the per-channel accumulator (chL/chR) and the per-run zone-render
  // scratch (runL/runR) when a scratch set is supplied (whole-song export), so
  // the note-run render allocates no whole-song transients. Byte-identical.
  final raw = instrument.renderChannelStereo(
    cells,
    timing,
    into: scratch != null ? (scratch.chL, scratch.chR) : null,
    runInto: scratch != null ? (scratch.runL, scratch.runR) : null,
  );
  // raw.left / raw.right are owned by this render (fresh, or the reused scratch
  // pair) and never aliased to each other, so pan/gain in place instead of
  // copying — two whole-song transients per channel eliminated.
  final left = raw.left;
  final right = raw.right;
  final pan = channel.pan.clamp(-1.0, 1.0);
  final hasNativeStereo = instrument.zones.values.any(
    (zone) => zone is SampleInstrument && zone.sampleRight != null,
  );
  final theta = (pan + 1) / 2 * (pi / 2);
  final leftGain = pan > 0 ? 1.0 - pan : 1.0;
  final rightGain = pan < 0 ? 1.0 + pan : 1.0;
  for (var i = 0; i < left.length; i++) {
    if (hasNativeStereo) {
      left[i] *= leftGain;
      right[i] *= rightGain;
    } else {
      right[i] = left[i] * sin(theta);
      left[i] *= cos(theta);
    }
    left[i] *= channel.gain;
    right[i] *= channel.gain;
  }
  return (left: left, right: right);
}

/// Replays a single pattern ([cells] per channel of [channels]) at [timing],
/// returning the mixed PCM16. Used for the current-pattern preview.
ReplayResult replayPattern(
  List<TrackerChannel> channels,
  List<List<TrackerCell>> cells,
  TrackerTiming timing, {
  int ticksPerRow = kDefaultTicksPerRow,
  List<TrackerInstrument>? pool,
}) {
  final speed = _firstFxx(cells, timing.rows, wantTempo: false);
  final ticks = speed > 0 ? speed : ticksPerRow;
  final mix = Float64List(timing.totalSamples);
  for (var c = 0; c < channels.length && c < cells.length; c++) {
    _renderChannelInto(
      mix,
      channels[c],
      cells[c],
      timing,
      ticks,
      0,
      pool: pool,
    );
  }
  final (rows, starts) = _rowScan(cells, timing, 0);
  _applyGlobalVolumeMix(mix, rows, starts, ticks);
  return ReplayResult(_mixToPcm(mix), const [RowTiming(0, 0, 0, 0)]);
}

/// Row-major channel cells + each row's start sample for one pattern at
/// [sampleOffset] — the shape [globalVolumeEnvelope] consumes.
(List<List<TrackerCell>>, List<int>) _rowScan(
  List<List<TrackerCell>> cells,
  TrackerTiming timing,
  int sampleOffset,
) {
  final rows = <List<TrackerCell>>[];
  final starts = <int>[];
  for (var r = 0; r < timing.rows; r++) {
    rows.add([
      for (final col in cells)
        if (r < col.length) col[r] else TrackerCell.empty,
    ]);
    starts.add(sampleOffset + timing.stepStartSample(r));
  }
  return (rows, starts);
}

/// Multiplies the Gxx/Hxy global-volume envelope of [rows] into [mix] in place.
/// A no-op (and no allocation beyond the scan) when there is no global-volume
/// command, so the common render stays byte-identical.
void _applyGlobalVolumeMix(
  Float64List mix,
  List<List<TrackerCell>> rows,
  List<int> starts,
  int ticks,
) {
  final env = globalVolumeEnvelope(rows, starts, mix.length, ticks);
  if (env == null) return;
  for (var i = 0; i < mix.length; i++) {
    mix[i] *= env[i];
  }
}

/// The stereo sibling of [_applyGlobalVolumeMix]: the same global-volume envelope
/// multiplies into both [left] and [right] (global volume is spatially neutral).
void _applyGlobalVolumeStereo(
  List<double> left,
  List<double> right,
  List<List<TrackerCell>> rows,
  List<int> starts,
  int ticks,
) {
  final env = globalVolumeEnvelope(rows, starts, left.length, ticks);
  if (env == null) return;
  for (var i = 0; i < left.length; i++) {
    left[i] *= env[i];
    right[i] *= env[i];
  }
}

void _applySongGlobalVolume(List<double> mix, double gain) {
  if (gain >= 1.0) return;
  for (var i = 0; i < mix.length; i++) {
    mix[i] *= gain;
  }
}

/// Row-major channel cells + each played row's start sample for a flattened
/// (walkFlow) sequence — the [globalVolumeEnvelope] shape for the flow/variable
/// render paths. [rowStartOf] maps a played-row index to its start sample.
(List<List<TrackerCell>>, List<int>) _flatRowScan(
  List<PlayedRow> played,
  TrackerSong song,
  int channelCount,
  int Function(int i) rowStartOf,
) {
  final rows = <List<TrackerCell>>[];
  final starts = <int>[];
  for (var i = 0; i < played.length; i++) {
    final pr = played[i];
    rows.add([
      for (var c = 0; c < channelCount; c++)
        song.patterns[pr.patternIndex].cells[c][pr.row],
    ]);
    starts.add(rowStartOf(i));
  }
  return (rows, starts);
}

/// The stereo sibling of [replayPattern]: renders each channel mono then pans it
/// (per-channel [TrackerChannel.pan] + 8xx) into an INTERLEAVED stereo PCM16.
/// [ReplayResult.pcm] is interleaved L,R — wrap it with [wavBytesStereo].
ReplayResult replayPatternStereo(
  List<TrackerChannel> channels,
  List<List<TrackerCell>> cells,
  TrackerTiming timing, {
  int ticksPerRow = kDefaultTicksPerRow,
  List<TrackerInstrument>? pool,
}) {
  final speed = _firstFxx(cells, timing.rows, wantTempo: false);
  final ticks = speed > 0 ? speed : ticksPerRow;
  final total = timing.totalSamples;
  final left = Float64List(total);
  final right = Float64List(total);
  for (var c = 0; c < channels.length && c < cells.length; c++) {
    _renderChannelIntoStereo(
      left,
      right,
      channels[c],
      cells[c],
      timing,
      ticks,
      0,
      pool: pool,
    );
  }
  final (gvRows, gvStarts) = _rowScan(cells, timing, 0);
  _applyGlobalVolumeStereo(left, right, gvRows, gvStarts, ticks);
  return ReplayResult(
    _interleaveToPcm(left, right),
    const [RowTiming(0, 0, 0, 0)],
  );
}

// --- Flow (phase 3): Bxx position jump + Dxx pattern break -------------------

/// One row actually played, in playback order — the output of [walkFlow].
/// [ticksPerRow] (speed) and [tempoBpm] carry the Fxx state IN EFFECT for this
/// row, so a mid-song tempo/speed change gives each row its own duration and
/// effect granularity. Added as positional-optional with defaults so existing
/// callers/tests stay source-compatible; `tempoBpm == 0` means "song default".
class PlayedRow {
  const PlayedRow(
    this.orderIndex,
    this.patternIndex,
    this.row, [
    this.ticksPerRow = kDefaultTicksPerRow,
    this.tempoBpm = 0,
  ]);

  final int orderIndex;
  final int patternIndex;
  final int row;

  /// The speed (ticks/row) in effect for THIS row (Fxx `param < 0x20`).
  final int ticksPerRow;

  /// The tempo (BPM) in effect for THIS row (Fxx `param >= 0x20`); 0 = the
  /// song's own [TrackerTiming.tempoBpm].
  final int tempoBpm;

  @override
  String toString() => 'PlayedRow(order $orderIndex, pat $patternIndex, '
      'row $row)';
}

/// Whether any cell in [song] carries a flow command (Bxx/Dxx) — the gate that
/// routes [replaySong] through the [walkFlow] path.
bool songUsesFlow(TrackerSong song) => song.patterns.any(
      (p) => p.cells.any(
        (col) => col.any(
          (c) =>
              c.fxCmd == kFxPositionJump ||
              c.fxCmd == kFxPatternBreak ||
              (c.fxCmd == kFxExtended &&
                  (((c.fxParam >> 4) & 0xF) == kExPatternLoop ||
                      ((c.fxParam >> 4) & 0xF) == kExPatternDelay)),
        ),
      ),
    );

/// Whether every pattern referenced by [song.order] has exactly
/// [song.timing.rows] rows — the classic uniform-length assumption. When false,
/// patterns vary in length (Feature B), so the render must route through the
/// walk/flatten path ([_replayFlow]) instead of the fixed-size concatenation,
/// exactly like a flow song. A uniform-length song stays on the fast path and
/// renders bit-for-bit as before.
bool songHasUniformPatternLengths(TrackerSong song) {
  final r = song.timing.rows;
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    if (song.patterns[oi].rows != r) return false;
  }
  return true;
}

/// Whether [song] must render through the walk/flatten path — because it carries
/// flow commands OR its patterns vary in length. The uniform, flow-free song
/// keeps the fast fixed-size render.
bool songNeedsWalkRender(TrackerSong song) =>
    songUsesFlow(song) || !songHasUniformPatternLengths(song);

/// Whether any cell in [song] carries an `Fxx` speed/tempo OR a `Txx` tempo-slide
/// command at all — a cheap pre-filter so the common command-free/single-tempo
/// song never pays for the [walkFlow] scan in [songUsesVariableTiming]. Both
/// change the per-row tempo, so both must arm the variable-timing render.
bool _songHasFxx(TrackerSong song) => song.patterns.any(
      (p) => p.cells.any(
        (col) => col.any(
          (c) => c.fxCmd == kFxSetSpeed || c.fxCmd == kFxTempoSlide,
        ),
      ),
    );

/// Whether [song] has a MID-SONG tempo/speed change — i.e. its played rows do
/// NOT all share one tempo AND one speed (more than one distinct `Fxx` value in
/// play order, OR a value that first takes effect after play-position 0, e.g. a
/// later order entry changing tempo while the first plays at the song default).
/// When true, [replaySong] routes through the per-row-duration variable render;
/// a song with a single (or no) value returns false → the uniform/flow path is
/// used unchanged (byte-identical). The caller is expected to have synced the
/// live pattern (like [songUsesFlow]).
bool songUsesVariableTiming(TrackerSong song) {
  final initialSpeed =
      song.initialSpeed > 0 ? song.initialSpeed : kDefaultTicksPerRow;
  if (!_songHasFxx(song) && initialSpeed == kDefaultTicksPerRow) return false;
  final played = walkFlow(song);
  if (played.length < 2) return false;
  for (final p in played) {
    if (p.ticksPerRow != kDefaultTicksPerRow) return true;
  }
  final tempo0 = played.first.tempoBpm;
  for (final p in played) {
    if (p.tempoBpm != tempo0) return true;
  }
  return false;
}

/// The wall-clock duration (ms) of a played row, honouring BOTH its tempo and
/// its SPEED (ticks/row). Classic tracker tick duration is `2500 / BPM` ms, so
/// a row is `speed * 2500 / BPM`. At speed 6 this matches the app's default
/// 4-steps-per-beat grid: `6 * 2500 / BPM == 60000 / BPM / 4`.
int _rowMsFor(int tempoBpm, int ticks) =>
    ((ticks <= 0 ? kDefaultTicksPerRow : ticks) * 2500 / tempoBpm).round();

/// The accumulated onset (ms) of each played row, honouring per-row tempo. Entry
/// `i` is the ms offset where played row `i` begins; the sum of all step
/// durations is the song length ([variableSongTotalMs]).
List<int> _variableRowStartMs(TrackerSong song, List<PlayedRow> played) {
  final def = song.timing.tempoBpm;
  final starts = List<int>.filled(played.length, 0);
  var acc = 0;
  for (var i = 0; i < played.length; i++) {
    starts[i] = acc;
    acc += _rowMsFor(
      played[i].tempoBpm > 0 ? played[i].tempoBpm : def,
      played[i].ticksPerRow,
    );
  }
  return starts;
}

/// The total song length (ms) as the SUM of per-row durations under a mid-song
/// tempo change — used by [TrackerSong.songTotalMs] when [songUsesVariableTiming].
int variableSongTotalMs(TrackerSong song) {
  final played = walkFlow(song);
  final def = song.timing.tempoBpm;
  var ms = 0;
  for (final p in played) {
    ms += _rowMsFor(
      p.tempoBpm > 0 ? p.tempoBpm : def,
      p.ticksPerRow,
    );
  }
  return ms;
}

/// Expands [song]'s order/pattern/row walk under the flow rules (Bxx jump, Dxx
/// break, E6x pattern loop) into the flat sequence of rows actually played. Bxx
/// wins the order, Dxx sets the landing row; both on one row ⇒ jump order + break
/// row. E60 marks a loop start, E6x (x>0) repeats the marked span x extra times.
/// Guarded by [maxRows] as a last resort. A Bxx/Dxx landing on an order-row that
/// already played is treated as the module's intentional song loop and stops the
/// offline render instead of unrolling to the cap.
List<PlayedRow> walkFlow(TrackerSong song, {int maxRows = 65536}) {
  final order = song.order;
  final played = <PlayedRow>[];
  final visitedOrderRows = <(int, int)>{};
  var oi = 0;
  var row = 0;
  var loopStartRow = 0; // E6x pattern-loop start (defaults to row 0)
  var loopCount = 0; // remaining E6x repeats
  // Fxx state carried across rows: speed (ticks/row) + tempo (BPM). A value takes
  // effect ON its own row and persists until the next Fxx of that kind.
  var curSpeed = song.initialSpeed;
  var curTempo = song.timing.tempoBpm;
  while (oi >= 0 && oi < order.length && played.length < maxRows) {
    final patternIndex = order[oi];
    final cells = song.patterns[patternIndex].cells;
    // Per-pattern length: each entry uses ITS OWN row count (Feature B). A jump/
    // break landing row is clamped to the TARGET pattern's length here.
    final rows = song.patterns[patternIndex].rows;
    if (row < 0) {
      row = 0;
    } else if (row >= rows) {
      row = rows - 1;
    }
    visitedOrderRows.add((oi, row));

    // Apply any Fxx (set-speed/tempo) or Txx (tempo SLIDE) on this row BEFORE
    // recording it (effect is on its own row): Fxx param < 0x20 → speed (min 1),
    // >= 0x20 → tempo (BPM) (Feature A); Txx steps the tempo by amount×(speed−1),
    // row-granular. First Txx across channels wins.
    var slidThisRow = false;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxSetSpeed) {
        if (c.fxParam >= 0x20) {
          curTempo = c.fxParam;
        } else if (c.fxParam > 0) {
          curSpeed = c.fxParam; // already >= 1
        }
      } else if (c.fxCmd == kFxTempoSlide && !slidThisRow) {
        slidThisRow = true;
        final up = ((c.fxParam >> 4) & 0xF) == 1;
        final amount = c.fxParam & 0xF;
        final ticks = curSpeed > 1 ? curSpeed - 1 : 1;
        curTempo = (curTempo + (up ? amount : -amount) * ticks).clamp(32, 255);
      }
    }
    played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));

    // EEx pattern delay: repeat THIS row x additional times (x+1 total) before
    // advancing. The extra copies re-run the row (additive voices re-trigger on
    // each), lengthening it consistently across walk → timing → render. First
    // EEx on the row wins; delay of 0 is a no-op.
    int? patternDelay;
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternDelay) {
        patternDelay ??= c.fxParam & 0xF;
      }
    }
    if (patternDelay != null && patternDelay > 0) {
      for (var i = 0; i < patternDelay && played.length < maxRows; i++) {
        played.add(PlayedRow(oi, patternIndex, row, curSpeed, curTempo));
      }
    }

    // Scan the row across channels for flow commands (first of each wins).
    int? jumpToOrder;
    int? breakToRow;
    int? loopValue; // E6x low nibble (0 = set the loop start)
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxPositionJump) {
        jumpToOrder ??= c.fxParam;
      } else if (c.fxCmd == kFxPatternBreak) {
        // Decimal row param; clamped to the TARGET pattern's length at landing.
        breakToRow ??= (c.fxParam >> 4) * 10 + (c.fxParam & 0xF);
      } else if (c.fxCmd == kFxExtended &&
          ((c.fxParam >> 4) & 0xF) == kExPatternLoop) {
        loopValue ??= c.fxParam & 0xF;
      }
    }

    void advance() {
      row += 1;
      if (row >= rows) {
        oi += 1;
        row = 0;
      }
    }

    bool wouldReplayOrderRow(int targetOrder, int targetRow) {
      if (targetOrder < 0 || targetOrder >= order.length) return false;
      final targetPattern = order[targetOrder];
      if (targetPattern < 0 || targetPattern >= song.patterns.length) {
        return false;
      }
      final targetRows = song.patterns[targetPattern].rows;
      final clampedRow = targetRow.clamp(0, targetRows - 1);
      return visitedOrderRows.contains((targetOrder, clampedRow));
    }

    if (jumpToOrder != null) {
      final targetRow = breakToRow ?? 0;
      if (wouldReplayOrderRow(jumpToOrder, targetRow)) break;
      oi = jumpToOrder;
      row = targetRow;
    } else if (breakToRow != null) {
      if (wouldReplayOrderRow(oi + 1, breakToRow)) break;
      oi += 1;
      row = breakToRow;
    } else if (loopValue == 0) {
      loopStartRow = row; // E60 marks the loop start, then plays on
      advance();
    } else if (loopValue != null && loopValue > 0) {
      if (loopCount == 0) {
        loopCount = loopValue; // arm the loop
        row = loopStartRow;
      } else {
        loopCount -= 1;
        if (loopCount > 0) {
          row = loopStartRow;
        } else {
          advance(); // loop finished
        }
      }
    } else {
      advance();
    }
  }
  return played;
}

/// The first `Fxx` value in [columns] (scanned row-major) of the requested kind:
/// [wantTempo] false → a SET-SPEED (`0 < param < 0x20`, ticks/row); [wantTempo]
/// true → a SET-TEMPO (param ≥ 0x20, BPM). Returns -1 if none of that kind.
int _firstFxx(
  List<List<TrackerCell>> columns,
  int rows, {
  required bool wantTempo,
}) {
  for (var r = 0; r < rows; r++) {
    for (final col in columns) {
      if (r < col.length) {
        final c = col[r];
        if (c.fxCmd == kFxSetSpeed) {
          final isTempo = c.fxParam >= 0x20;
          if (wantTempo && isTempo) return c.fxParam;
          if (!wantTempo && c.fxParam > 0 && !isTempo) return c.fxParam;
        }
      }
    }
  }
  return -1;
}

/// The speed ([TrackerTiming]-independent ticks/row) a song should replay at: the
/// first `Fxx` set-speed command in play order, else [fallback]. Applied by
/// [replaySong] so an imported/authored module's authored speed sets the effect
/// granularity. Tracker rows last `speed * 2500 / bpm` ms, so imported module
/// speed affects both duration and per-tick effect cadence.
int songInitialSpeed(TrackerSong song, {int fallback = kDefaultTicksPerRow}) {
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    final s =
        _firstFxx(song.patterns[oi].cells, song.timing.rows, wantTempo: false);
    if (s > 0) return s;
  }
  return fallback;
}

/// The tempo (BPM) a song should replay at: the first `Fxx` set-tempo command
/// (param ≥ 0x20) in play order, else `null` (use the song's own tempo). This is
/// applied uniformly to the whole render (like the initial tempo a module sets at
/// the top) — mid-song tempo CHANGES need the per-row-duration rework and are a
/// follow-up. Because it's uniform, [TrackerSong.songTotalMs] applies the same
/// value so the render length stays consistent.
int? songInitialTempo(TrackerSong song) {
  for (final oi in song.order) {
    if (oi < 0 || oi >= song.patterns.length) continue;
    final t =
        _firstFxx(song.patterns[oi].cells, song.timing.rows, wantTempo: true);
    if (t > 0) return t.clamp(32, 255);
  }
  return null;
}

/// [song.timing] with the initial `Fxx` set-tempo applied (if any) — the tempo
/// the render and [TrackerSong.songTotalMs] both use.
TrackerTiming effectiveTiming(TrackerSong song) {
  final t = songInitialTempo(song);
  return t != null ? song.timing.copyWith(tempoBpm: t) : song.timing;
}

/// The row-timing map WITHOUT rendering any audio — the same
/// `(startMs, orderIndex, patternIndex, row)` sequence [replaySong] emits, built
/// cheaply from [walkFlow] (flow songs) or the uniform order walk. This is what
/// the Advanced playhead consumes: resolve it once when playback starts, then use
/// [rowIndexAtMs] per frame to map elapsed ms → the currently-playing row, so the
/// highlight follows Bxx/Dxx/E6x jumps instead of assuming fixed pattern lengths.
List<RowTiming> resolveTimingMap(TrackerSong song) {
  song.syncCurrent();
  // Mid-song tempo change: non-uniform per-row onsets (match [_replayVariable]).
  if (songUsesVariableTiming(song)) {
    final played = walkFlow(song);
    final starts = _variableRowStartMs(song, played);
    return [
      for (var i = 0; i < played.length; i++)
        RowTiming(
          starts[i],
          played[i].orderIndex,
          played[i].patternIndex,
          played[i].row,
        ),
    ];
  }
  final timing = effectiveTiming(song); // match the render's Fxx set-tempo
  // Flow OR variable-length patterns both resolve via the flattened walk.
  if (songNeedsWalkRender(song)) {
    final played = walkFlow(song);
    final flatTiming =
        timing.copyWith(rows: played.isEmpty ? 1 : played.length);
    return [
      for (var i = 0; i < played.length; i++)
        RowTiming(
          flatTiming.stepOnsetMs(i).round(),
          played[i].orderIndex,
          played[i].patternIndex,
          played[i].row,
        ),
    ];
  }
  final map = <RowTiming>[];
  for (var o = 0; o < song.order.length; o++) {
    final baseMs = timing.totalMs * o;
    for (var r = 0; r < timing.rows; r++) {
      map.add(
        RowTiming(baseMs + timing.stepOnsetMs(r).round(), o, song.order[o], r),
      );
    }
  }
  return map;
}

/// The index into [map] of the row playing at song-time [ms] — the last entry
/// whose `startMs <= ms` (binary search; [map] is ascending in startMs). Returns
/// -1 for an empty map, 0 for a time before the first row. Feed it
/// `elapsedMs % songTotalMs` for a looping transport.
int rowIndexAtMs(List<RowTiming> map, int ms) {
  if (map.isEmpty) return -1;
  var lo = 0;
  var hi = map.length - 1;
  var ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (map[mid].startMs <= ms) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// Replays the whole [song] (its order list) into one mixed PCM16 + a row-timing
/// map. Command-free / flow-free songs render one [TrackerTiming.totalMs] per
/// order entry (uniform); when the song [songUsesFlow] the order is expanded by
/// [walkFlow] into the exact played sequence and rendered as one flattened
/// pattern. [resolveTimingMap] gives the same map without the audio. The Fxx
/// set-speed value is applied to the render but not to row durations (speed is
/// timing-neutral in our model). Side-effect-free.
ReplayResult replaySong(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
  PcmDither? dither,
}) {
  song.syncCurrent();
  // A MID-SONG tempo/speed change needs per-row durations — render that first
  // (it also expands flow via [walkFlow], so it subsumes flow+variable songs).
  if (songUsesVariableTiming(song)) {
    return _replayVariable(song, dither: dither);
  }
  // An Fxx set-speed command overrides the default ticks/row (effect
  // granularity); timing-safe (speed subdivides the row, not its duration).
  final initialTicks = song.initialSpeed > 0 ? song.initialSpeed : ticksPerRow;
  final ticks = songInitialSpeed(song, fallback: initialTicks);
  // Flow OR variable-length patterns both flatten the played sequence.
  if (songNeedsWalkRender(song)) {
    return _replayFlow(song, ticks, dither: dither);
  }

  // An Fxx set-tempo command sets the (uniform) render tempo.
  final timing = effectiveTiming(song);
  final channels = song.channels;
  final order = song.order;
  final patternSamples = timing.totalSamples;
  final mix = Float64List(patternSamples * order.length);
  final timingMap = <RowTiming>[];

  for (var o = 0; o < order.length; o++) {
    final patternIndex = order[o];
    final cells = song.patterns[patternIndex].cells;
    final sampleOffset = patternSamples * o;
    final baseMs = timing.totalMs * o;
    for (var r = 0; r < timing.rows; r++) {
      timingMap.add(
        RowTiming(baseMs + timing.stepOnsetMs(r).round(), o, patternIndex, r),
      );
    }
    for (var c = 0; c < channels.length && c < cells.length; c++) {
      _renderChannelInto(
        mix,
        channels[c],
        cells[c],
        timing,
        ticks,
        sampleOffset,
        pool: song.instruments,
      );
    }
  }
  // Global volume (Gxx/Hxy) persists across the whole song, so build one
  // envelope over every order entry's rows rather than per-pattern.
  final gvRows = <List<TrackerCell>>[];
  final gvStarts = <int>[];
  for (var o = 0; o < order.length; o++) {
    final (rr, ss) =
        _rowScan(song.patterns[order[o]].cells, timing, patternSamples * o);
    gvRows.addAll(rr);
    gvStarts.addAll(ss);
  }
  _applyGlobalVolumeMix(mix, gvRows, gvStarts, ticks);
  _applySongGlobalVolume(mix, song.globalVolume);
  return ReplayResult(_mixToPcm(mix, dither), timingMap);
}

/// The stereo sibling of [replaySong]: same order walk / flow expansion, but each
/// channel is panned (per-channel [TrackerChannel.pan] + 8xx) into an INTERLEAVED
/// stereo mix. [ReplayResult.pcm] is interleaved L,R — wrap with [wavBytesStereo].
ReplayResult replaySongStereo(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
  PcmDither? dither,
}) {
  final f = _replaySongStereoFloat(song, ticksPerRow: ticksPerRow);
  return ReplayResult(_interleaveToPcm(f.left, f.right, dither), f.timingMap);
}

/// The raw float stereo mixes of [replaySongStereo] (same routing / arithmetic),
/// BEFORE PCM16 quantisation. The bounded CLI export uses this to convert +
/// stream the whole-song render to disk block-by-block, so the whole-song int16
/// PCM and WAV copy are never held alongside the float accumulator.
({List<double> left, List<double> right, List<RowTiming> timingMap})
    songStereoFloat(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
}) =>
        _replaySongStereoFloat(song, ticksPerRow: ticksPerRow);

/// Quantises one float mix sample to signed PCM16 with the SAME tanh soft-knee
/// as [_interleaveToPcm] / [_mixToPcm], so a streamed conversion is byte-for-byte
/// identical to the in-memory render.
int pcm16Sample(double x, [PcmDither? dither]) {
  final s = _tanh(x) * 0.95 * 32767;
  return dither == null ? s.round() : dither.quantizeScaled(s);
}

/// The float L/R core of [replaySongStereo] — same routing / arithmetic, but it
/// returns the raw stereo float mixes (not yet quantised to PCM16). The bounded
/// CLI export streams these to disk block-by-block ([streamSongStereoWav]) so
/// the whole-song int16 + WAV copy are never held alongside the float
/// accumulator; the in-memory [replaySongStereo] wraps it with [_interleaveToPcm]
/// unchanged.
({List<double> left, List<double> right, List<RowTiming> timingMap})
    _replaySongStereoFloat(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  song.syncCurrent();
  final initialTicks = song.initialSpeed > 0 ? song.initialSpeed : ticksPerRow;
  final ticks = songInitialSpeed(song, fallback: initialTicks);
  // Mirror the mono replaySong routing: mid-song tempo/speed → the per-row
  // stereo render; flow OR variable-length → the flattened stereo render.
  if (songUsesVariableTiming(song)) return _replayVariableStereoFloat(song);
  if (songNeedsWalkRender(song)) return _replayFlowStereoFloat(song, ticks);

  final timing = effectiveTiming(song);
  final channels = song.channels;
  final order = song.order;
  final patternSamples = timing.totalSamples;
  final left = Float64List(patternSamples * order.length);
  final right = Float64List(patternSamples * order.length);
  final timingMap = <RowTiming>[];
  // One reusable per-pattern scratch set for the whole render — every per-order
  // channel render is the same `patternSamples` length, so the transient
  // per-channel / per-run buffers are recycled instead of churned through the GC.
  final scratch = _StereoScratch(patternSamples);

  for (var o = 0; o < order.length; o++) {
    final patternIndex = order[o];
    final cells = song.patterns[patternIndex].cells;
    final sampleOffset = patternSamples * o;
    final baseMs = timing.totalMs * o;
    for (var r = 0; r < timing.rows; r++) {
      timingMap.add(
        RowTiming(baseMs + timing.stepOnsetMs(r).round(), o, patternIndex, r),
      );
    }
    for (var c = 0; c < channels.length && c < cells.length; c++) {
      _renderChannelIntoStereo(
        left,
        right,
        channels[c],
        cells[c],
        timing,
        ticks,
        sampleOffset,
        pool: song.instruments,
        scratch: scratch,
      );
    }
  }
  final gvRows = <List<TrackerCell>>[];
  final gvStarts = <int>[];
  for (var o = 0; o < order.length; o++) {
    final (rr, ss) =
        _rowScan(song.patterns[order[o]].cells, timing, patternSamples * o);
    gvRows.addAll(rr);
    gvStarts.addAll(ss);
  }
  _applyGlobalVolumeStereo(left, right, gvRows, gvStarts, ticks);
  _applySongGlobalVolume(left, song.globalVolume);
  _applySongGlobalVolume(right, song.globalVolume);
  return (left: left, right: right, timingMap: timingMap);
}

/// The flow render: expand the order via [walkFlow], flatten the played rows into
/// one long column per channel, and render that flattened song. Voice state
/// (porta/vibrato/oscillator phase) stays continuous across the flat rows, and
/// non-additive voices trigger at their flattened positions, so both stay
/// aligned with the reordered timeline.
ReplayResult _replayFlow(
  TrackerSong song,
  int ticksPerRow, {
  PcmDither? dither,
}) {
  final played = walkFlow(song);
  final channels = song.channels;
  final base = effectiveTiming(song); // Fxx set-tempo (uniform)
  final flatRows = played.isEmpty ? 1 : played.length;
  final flatTiming = base.copyWith(rows: flatRows);
  final mix = Float64List(flatTiming.totalSamples);

  for (var c = 0; c < channels.length; c++) {
    final flatCells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    _renderChannelInto(
      mix,
      channels[c],
      flatCells,
      flatTiming,
      ticksPerRow,
      0,
      pool: song.instruments,
    );
  }

  final (gvRows, gvStarts) = _flatRowScan(
    played,
    song,
    channels.length,
    flatTiming.stepStartSample,
  );
  _applyGlobalVolumeMix(mix, gvRows, gvStarts, ticksPerRow);
  _applySongGlobalVolume(mix, song.globalVolume);

  final timingMap = [
    for (var i = 0; i < played.length; i++)
      RowTiming(
        flatTiming.stepOnsetMs(i).round(),
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return ReplayResult(_mixToPcm(mix, dither), timingMap);
}

/// The stereo sibling of [_replayFlow]: flatten the played rows then pan each
/// channel (per-channel [TrackerChannel.pan] + 8xx) into an interleaved mix.
({List<double> left, List<double> right, List<RowTiming> timingMap})
    _replayFlowStereoFloat(TrackerSong song, int ticksPerRow) {
  final played = walkFlow(song);
  final channels = song.channels;
  final base = effectiveTiming(song);
  final flatRows = played.isEmpty ? 1 : played.length;
  final flatTiming = base.copyWith(rows: flatRows);
  final left = Float64List(flatTiming.totalSamples);
  final right = Float64List(flatTiming.totalSamples);
  for (var c = 0; c < channels.length; c++) {
    final flatCells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    _renderChannelIntoStereo(
      left,
      right,
      channels[c],
      flatCells,
      flatTiming,
      ticksPerRow,
      0,
      pool: song.instruments,
    );
  }
  final (gvRows, gvStarts) = _flatRowScan(
    played,
    song,
    channels.length,
    flatTiming.stepStartSample,
  );
  _applyGlobalVolumeStereo(left, right, gvRows, gvStarts, ticksPerRow);
  _applySongGlobalVolume(left, song.globalVolume);
  _applySongGlobalVolume(right, song.globalVolume);
  final timingMap = [
    for (var i = 0; i < played.length; i++)
      RowTiming(
        flatTiming.stepOnsetMs(i).round(),
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return (left: left, right: right, timingMap: timingMap);
}

// --- Variable-timing render (mid-song tempo/speed changes) -------------------

/// The mid-song-timing render: expand the order via [walkFlow] (which annotates
/// every played row with the tempo/speed in effect), lay the rows back-to-back
/// at accumulated sample offsets whose lengths follow each row's OWN tempo, and
/// render each channel across those variable boundaries. Additive voices use each
/// row's [PlayedRow.ticksPerRow] for tick granularity; non-additive voices are
/// placed per note over their run's summed duration. The row-timing map + length
/// use the ms-summed onsets so [TrackerSong.songTotalMs] and the transport agree.
ReplayResult _replayVariable(TrackerSong song, {PcmDither? dither}) {
  final played = walkFlow(song);
  final channels = song.channels;
  final def = song.timing.tempoBpm;
  final n = played.length;

  // Per-row sample boundaries: rowStart[i]..rowStart[i+1] is played row i.
  final rowStart = List<int>.filled(n + 1, 0);
  final ticks = List<int>.filled(n, kDefaultTicksPerRow);
  var acc = 0;
  for (var i = 0; i < n; i++) {
    rowStart[i] = acc;
    ticks[i] = played[i].ticksPerRow;
    final tempo = played[i].tempoBpm > 0 ? played[i].tempoBpm : def;
    final stepMs = _rowMsFor(tempo, played[i].ticksPerRow);
    acc += (stepMs * kSampleRate / 1000).round();
  }
  rowStart[n] = acc;

  final mix = Float64List(acc);
  for (var c = 0; c < channels.length; c++) {
    final flatCells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    _renderChannelIntoVariable(
      mix,
      channels[c],
      flatCells,
      rowStart,
      ticks,
      song.timing.stepsPerBeat,
      pool: song.instruments,
    );
  }

  final (gvRows, gvStarts) =
      _flatRowScan(played, song, channels.length, (i) => rowStart[i]);
  _applyGlobalVolumeMix(mix, gvRows, gvStarts, song.initialSpeed);
  _applySongGlobalVolume(mix, song.globalVolume);

  final starts = _variableRowStartMs(song, played);
  final timingMap = [
    for (var i = 0; i < n; i++)
      RowTiming(
        starts[i],
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return ReplayResult(_mixToPcm(mix, dither), timingMap);
}

/// The run length in SECONDS of the note (re)triggered at row [from] under
/// VARIABLE per-row durations — from its row start to the next trigger (or the
/// end), read from the [rowStart] sample boundaries. The variable sibling of
/// [_runSeconds].
double _runSecondsVariable(
  List<TrackerCell> cells,
  int from,
  int rows,
  List<int> rowStart,
) {
  final runEnd = _nextTriggerRow(cells, from);
  final endSample = runEnd < rows ? rowStart[runEnd] : rowStart[rows];
  final runSamples = endSample - rowStart[from];
  return runSamples > 0 ? runSamples / kSampleRate : 0.001;
}

/// Renders one channel's flattened [cells] into [mix] across VARIABLE row
/// boundaries [rowStart] (length `cells.length + 1`), each row using its own
/// [ticksPerRow]. The variable-timing sibling of [_renderChannelInto]: additive
/// voices synthesize per tick (honouring commands + per-cell timbre); other
/// instruments fall back to a per-note render over the variable spans.
void _renderChannelIntoVariable(
  List<double> mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  int stepsPerBeat, {
  List<TrackerInstrument>? pool,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;
  final rows = cells.length;

  if (channel.instrument is MultiSampleInstrument && _hasPerTickEffect(cells)) {
    _renderMultiSampleChannelIntoVariable(
      mix,
      channel,
      cells,
      rowStart,
      ticksPerRow,
    );
    return;
  }

  final inst = _additiveOf(channel.instrument);
  if (inst == null) {
    // A sample channel with per-tick effects gets the variable-timing tick voice
    // (porta/vibrato/tremolo/Cxx/Axy over the variable spans); otherwise the
    // cheaper one-shot-per-note path (byte-identical when effect-free).
    if (channel.instrument is SampleInstrument && _hasPerTickEffect(cells)) {
      _renderSampleChannelIntoVariable(
        mix,
        channel,
        cells,
        rowStart,
        ticksPerRow,
        pool,
      );
    } else {
      _renderNonAdditiveVariable(mix, channel, cells, rowStart, pool);
    }
    return;
  }

  var tp = _timbreParamsOf(inst);
  final gain = channel.gain;
  final voice = ReplayVoice();
  for (var r = 0; r < rows; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 && pool != null && cellInst - 1 < pool.length) {
      final pi = _additiveOf(pool[cellInst - 1]);
      if (pi != null) tp = _timbreParamsOf(pi);
    }
    voice.armRow(cells[r]);
    if (voice.retriggeredThisRow) {
      voice.oscPhase = 0;
      voice.noteStartSample = rowStart[r];
      voice.noteSeconds = _runSecondsVariable(cells, r, rows, rowStart);
    }
    if (!voice.active && !voice.hasPendingNote) continue;

    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticksPerRow[r] < 1 ? 1 : ticksPerRow[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        voice.oscPhase = 0;
        voice.noteStartSample = ts;
        voice.noteSeconds = _runSecondsVariable(cells, r, rows, rowStart);
      }
      if (!voice.active) continue;
      final freq = _freqOfMidi(state.pitch);
      final volScale = (state.volume / kMaxVolume) * voice.noteVolume * gain;
      final phaseInc = 2 * pi * freq / kSampleRate;
      for (var i = ts; i < te && i < mix.length; i++) {
        final t = (i - voice.noteStartSample) / kSampleRate;
        if (t < 0) continue;
        final attack = t < tp.attackSec ? t / tp.attackSec : 1.0;
        final env = attack * exp(-tp.decay * t / voice.noteSeconds);
        var sample = 0.0;
        for (var h = 0; h < tp.harmonics.length; h++) {
          sample += tp.harmonics[h] * sin(voice.oscPhase * (h + 1));
        }
        final el = channel.volumeEnvelope?.levelAt(t * 1000) ?? 1.0;
        mix[i] += (sample / tp.harmNorm) * env * volScale * el;
        voice.oscPhase += phaseInc;
      }
    }
  }
}

/// Renders a NON-additive channel across VARIABLE row spans: each note run is
/// rendered by its effective instrument over its OWN duration (the summed span of
/// its rows), then placed at the accumulated sample offset, unit-peaked × gain
/// like the uniform non-additive path. So a sample note that triggers after a
/// tempo change still lands at the correct offset.
void _renderNonAdditiveVariable(
  List<double> mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<TrackerInstrument>? pool,
) {
  final rows = cells.length;
  final stem = Float64List(rowStart[rows]);
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  var curInst = channel.instrument;
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final releaseSteps = run.$3;
    final steps = sustainSteps + releaseSteps;

    final trigger = cells[startStep];
    if (trigger.instrument > 0 &&
        pool != null &&
        trigger.instrument - 1 < pool.length) {
      curInst = pool[trigger.instrument - 1];
    }
    if (midi != null) {
      final s = rowStart[startStep];
      final e = rowStart[startStep + steps];
      final runSamples = e - s;
      if (runSamples > 0) {
        // A one-run timing sized to this note's actual span, so the instrument
        // renders the note over exactly runSamples (± a rounding sample).
        final runMs = (runSamples * 1000 / kSampleRate).round();
        final tempo =
            (runMs <= 0 ? 240 : (60000 / runMs).round()).clamp(1, 1 << 20);
        final noteTiming =
            TrackerTiming(tempoBpm: tempo, rows: steps, stepsPerBeat: steps);

        final capRow = sustainSteps;
        final one = List<TrackerCell>.filled(steps, TrackerCell.empty)
          ..[0] = trigger;
        if (capRow < steps) one[capRow] = TrackerCell.noteCut;

        final buf = curInst.renderChannel(one, noteTiming);
        final lim = min(runSamples, min(buf.length, stem.length - s));
        for (var i = 0; i < lim; i++) {
          final el = hasEnv ? env.levelAt(i / kSampleRate * 1000) : 1.0;
          stem[s + i] += buf[i] * el;
        }
      }
    }
    startStep += steps;
  }

  var peak = 0.0;
  for (final v in stem) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) return;
  final scale = curInst is SampleInstrument && !curInst.normalize
      ? channel.gain
      : channel.gain / peak;
  final n = min(stem.length, mix.length);
  for (var i = 0; i < n; i++) {
    mix[i] += stem[i] * scale;
  }
}

/// Long-render fallback for native IT multi-sample channels. Unlike
/// [_renderNonAdditiveVariable], this writes each note run directly into the
/// destination, avoiding a second full-song Float64 stem. The exact NNA path
/// is reserved for preview-sized renders; this bounded path keeps the selected
/// native zone, timing, sample envelope, and channel gain without exhausting
/// memory on export-scale songs.
void _renderLongNativeVariable(
  List<double> mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
) {
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument) return;
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final releaseSteps = run.$3;
    final steps = sustainSteps + releaseSteps;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone is SampleInstrument) {
        final start = rowStart[startStep];
        final end = rowStart[startStep + steps];
        final runSamples = end - start;
        if (runSamples > 0) {
          final runCells = cells.sublist(startStep, startStep + steps);
          if (sustainSteps < steps) {
            runCells[sustainSteps] = TrackerCell.noteCut;
          }
          final runTicks = ticksPerRow.sublist(startStep, startStep + steps);
          final runStarts = <int>[0];
          for (var row = 0; row < steps; row++) {
            runStarts.add(rowStart[startStep + row + 1] - start);
          }
          final buf = Float64List(runSamples);
          _renderSampleChannelIntoVariable(
            buf,
            TrackerChannel(
              id: '${channel.id}:native-zone',
              instrument: zone,
              rows: steps,
              gain: channel.gain,
              volumeEnvelope: channel.volumeEnvelope,
            ),
            runCells,
            runStarts,
            runTicks,
            null,
          );
          final limit = min(runSamples, buf.length);
          for (var i = 0; i < limit && start + i < mix.length; i++) {
            mix[start + i] += buf[i];
          }
        }
      }
    }
    startStep += steps;
  }
}

/// The stereo direct-accumulate sibling of [_renderLongNativeVariable]: each note
/// run is rendered into the SAME run-length buffer, then distributed straight
/// into [left]/[right] via the per-region pan gains [regions] and the SAME
/// Float32 truncation the whole-song `mono` buffer applied ([left]/[right] are
/// Float32List). This removes the whole-song per-channel `mono` buffer (the
/// export-scale memory blow-up) while producing byte-identical PCM: every sample
/// is written by exactly one run and lands in exactly one pan region, so the
/// mono-store-then-region-multiply and this in-place multiply agree bit-for-bit.
void _renderLongNativeVariableStereo(
  Float32List left,
  Float32List right,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  List<({int start, int end, double pan})> regions,
) {
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument) return;
  // Constant-power gains per region — the SAME cos/sin(theta) the mono pan loop
  // computes, precomputed once so the run walk is a plain region lookup.
  final regGain = [
    for (final reg in regions)
      (
        start: reg.start,
        end: reg.end,
        l: cos((reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2)),
        r: sin((reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2)),
      ),
  ];
  final f32 = Float32List(1);
  final total = left.length;
  // Per-sample native sink: truncate to Float32 (matching the whole-song mono
  // store), find the pan region, and accumulate straight into L/R. [runStart] is
  // updated before each native run so `runStart + i` is the global sample index.
  var runStart = 0;
  void sink(int i, double v) {
    final g = runStart + i;
    if (g >= total) return;
    f32[0] = v;
    final m = f32[0];
    for (final rg in regGain) {
      if (g >= rg.start && g < rg.end) {
        left[g] += m * rg.l;
        right[g] += m * rg.r;
        return;
      }
    }
  }

  // Buffered fallback (reused, grown lazily) — only for normalize==true zones,
  // which need the whole-run peak before scaling. Native zones never allocate.
  Float64List? buf;
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final releaseSteps = run.$3;
    final steps = sustainSteps + releaseSteps;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone is SampleInstrument) {
        final start = rowStart[startStep];
        final end = rowStart[startStep + steps];
        final runSamples = end - start;
        if (runSamples > 0) {
          final runCells = cells.sublist(startStep, startStep + steps);
          if (sustainSteps < steps) {
            runCells[sustainSteps] = TrackerCell.noteCut;
          }
          final runTicks = ticksPerRow.sublist(startStep, startStep + steps);
          final runStarts = <int>[0];
          for (var row = 0; row < steps; row++) {
            runStarts.add(rowStart[startStep + row + 1] - start);
          }
          final zoneChannel = TrackerChannel(
            id: '${channel.id}:native-zone',
            instrument: zone,
            rows: steps,
            gain: channel.gain,
            volumeEnvelope: channel.volumeEnvelope,
          );
          if (!zone.normalize) {
            // Native run: stream each sample straight into L/R, no run buffer.
            runStart = start;
            _renderSampleChannelIntoVariable(
              const <double>[],
              zoneChannel,
              runCells,
              runStarts,
              runTicks,
              null,
              nativeSink: sink,
            );
          } else {
            var b = buf;
            if (b == null || b.length < runSamples) {
              b = Float64List(runSamples);
              buf = b;
            }
            b.fillRange(0, runSamples, 0.0);
            _renderSampleChannelIntoVariable(
              b,
              zoneChannel,
              runCells,
              runStarts,
              runTicks,
              null,
            );
            final limit = min(runSamples, b.length);
            final runEnd = min(start + limit, total);
            for (final rg in regGain) {
              final s = max(rg.start, start);
              final e = min(rg.end, runEnd);
              for (var g = s; g < e; g++) {
                f32[0] = b[g - start];
                final m = f32[0];
                left[g] += m * rg.l;
                right[g] += m * rg.r;
              }
            }
          }
        }
      }
    }
    startStep += steps;
  }
}

/// The stereo sibling of [_replayVariable]: the mid-song per-row-duration render,
/// each channel panned (base pan + 8xx) into an interleaved mix — so a PANNED
/// song with a mid-song tempo/speed change stays in sync (length matches
/// [variableSongTotalMs]). Each channel is rendered mono over the variable
/// boundaries then split L/R, exactly like [_renderChannelIntoStereo] does for
/// the uniform case.
// Full-song native IT voice rendering keeps one waveform buffer per active
// NNA voice. That is valuable for normal previews, but becomes unbounded for
// long modules. Large renders use the bounded per-note path below instead of
// retaining every full-song voice waveform.
const _nativeTickFullBufferLimit = kSampleRate * 120;

({List<double> left, List<double> right, List<RowTiming> timingMap})
    _replayVariableStereoFloat(TrackerSong song) {
  final played = walkFlow(song);
  final channels = song.channels;
  final def = song.timing.tempoBpm;
  final n = played.length;

  final rowStart = List<int>.filled(n + 1, 0);
  final ticks = List<int>.filled(n, kDefaultTicksPerRow);
  var acc = 0;
  for (var i = 0; i < n; i++) {
    rowStart[i] = acc;
    ticks[i] = played[i].ticksPerRow;
    final tempo = played[i].tempoBpm > 0 ? played[i].tempoBpm : def;
    acc +=
        (_rowMsFor(tempo, played[i].ticksPerRow) * kSampleRate / 1000).round();
  }
  rowStart[n] = acc;

  final left = Float32List(acc);
  final right = Float32List(acc);
  for (var c = 0; c < channels.length; c++) {
    final flatCells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    final multi = channels[c].instrument;
    if (acc <= _nativeTickFullBufferLimit &&
        multi is MultiSampleInstrument &&
        multi.nativeVoiceSemantics &&
        multi.zones.values.every((zone) => zone is SampleInstrument) &&
        _hasPerTickEffect(flatCells)) {
      final rendered = _renderNativeTickZoneVoices(
        multi,
        flatCells,
        rowStart,
        (zone, isolated) {
          final zoneChannel = TrackerChannel(
            id: '${channels[c].id}:zone',
            instrument: zone,
            rows: flatCells.length,
            gain: channels[c].gain,
            pan: channels[c].pan,
            volumeEnvelope: channels[c].volumeEnvelope,
            panEnvelope: channels[c].panEnvelope,
          );
          final stereo = _renderSampleChannelStereoTicks(
            zoneChannel,
            isolated,
            rowStart,
            ticks,
            null,
          );
          return (left: stereo.left, right: stereo.right);
        },
      );
      final renderedRight = rendered.right ?? rendered.left;
      for (var i = 0; i < acc; i++) {
        left[i] += rendered.left[i];
        right[i] += renderedRight[i];
      }
      continue;
    }
    if (channels[c].instrument is SampleInstrument &&
        _hasPerTickEffect(flatCells)) {
      final rendered = _renderSampleChannelStereoTicks(
        channels[c],
        flatCells,
        rowStart,
        ticks,
        song.instruments,
      );
      for (var i = 0; i < acc; i++) {
        left[i] += rendered.left[i];
        right[i] += rendered.right[i];
      }
      continue;
    }
    final penvChk = channels[c].panEnvelope;
    final noPenv = penvChk == null || penvChk.isEmpty;
    final channelActive =
        !channels[c].muted && flatCells.any((cell) => !cell.isEmpty);
    final isNativeLong = acc > _nativeTickFullBufferLimit &&
        multi is MultiSampleInstrument &&
        multi.nativeVoiceSemantics;
    // Export-scale bounded path: a mute/empty channel contributes an all-zero
    // mono (adding 0.0 leaves L/R unchanged), so skip it entirely instead of
    // allocating a whole-song mono to add nothing. Byte-identical output.
    if (!channelActive) continue;
    // DIRECT-ACCUMULATE (no whole-song per-channel mono): the bounded native
    // long path writes each note run straight into L/R with the SAME per-region
    // pan gains and the SAME Float32 truncation the mono buffer applied, so the
    // PCM is byte-identical while the ~1 buffer/channel churn is eliminated.
    // Only the non-pan-envelope case (pan is a per-sample region lookup) takes
    // this route; a pan ENVELOPE still uses the mono path below.
    if (isNativeLong && noPenv) {
      final regions = _panRegionsVariable(
        channels[c].pan,
        flatCells,
        rowStart,
        ticksPerRow: song.initialSpeed,
      );
      _renderLongNativeVariableStereo(
        left,
        right,
        channels[c],
        flatCells,
        rowStart,
        ticks,
        regions,
      );
      continue;
    }
    final mono = Float32List(acc);
    if (isNativeLong) {
      // Avoid one full-song buffer per IT NNA voice. Each note run still uses
      // the correct mapped sample zone and timing, but old-voice actions are
      // intentionally bounded for export-scale renders.
      _renderLongNativeVariable(
        mono,
        channels[c],
        flatCells,
        rowStart,
        ticks,
      );
    } else {
      _renderChannelIntoVariable(
        mono,
        channels[c],
        flatCells,
        rowStart,
        ticks,
        song.timing.stepsPerBeat,
        pool: song.instruments,
      );
    }
    final penv = channels[c].panEnvelope;
    if (penv != null && !penv.isEmpty) {
      // Per-note auto-pan over the variable spans (onset = rowStart[startStep]).
      final basePan = channels[c].pan;
      var startStep = 0;
      for (final (midi, steps) in cellRuns(flatCells)) {
        if (midi != null) {
          final s = rowStart[startStep];
          final e = min(rowStart[startStep + steps], acc);
          for (var i = s; i < e; i++) {
            final pan = (basePan + penv.panAt((i - s) / kSampleRate * 1000))
                .clamp(-1.0, 1.0);
            final theta = (pan + 1) / 2 * (pi / 2);
            left[i] += mono[i] * cos(theta);
            right[i] += mono[i] * sin(theta);
          }
        }
        startStep += steps;
      }
    } else {
      for (final reg in _panRegionsVariable(
        channels[c].pan,
        flatCells,
        rowStart,
        ticksPerRow: song.initialSpeed,
      )) {
        final theta = (reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2);
        final lGain = cos(theta);
        final rGain = sin(theta);
        final end = min(reg.end, acc);
        for (var i = reg.start; i < end; i++) {
          left[i] += mono[i] * lGain;
          right[i] += mono[i] * rGain;
        }
      }
    }
  }

  final (gvRows, gvStarts) =
      _flatRowScan(played, song, channels.length, (i) => rowStart[i]);
  _applyGlobalVolumeStereo(left, right, gvRows, gvStarts, song.initialSpeed);
  _applySongGlobalVolume(left, song.globalVolume);
  _applySongGlobalVolume(right, song.globalVolume);

  final starts = _variableRowStartMs(song, played);
  final timingMap = [
    for (var i = 0; i < n; i++)
      RowTiming(
        starts[i],
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return (left: left, right: right, timingMap: timingMap);
}

/// Variable-timing pan regions: like [_panRegions] (8xx set + Pxy slide) but the
/// row boundaries come from the per-row sample offsets [rowStart] (the flattened
/// length is `rowStart.last`). [ticksPerRow] scales the Pxy step.
List<({int start, int end, double pan})> _panRegionsVariable(
  double basePan,
  List<TrackerCell> cells,
  List<int> rowStart, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final total = rowStart.last;
  final regions = <({int start, int end, double pan})>[];
  var pan = basePan;
  var regionStart = 0;
  for (var r = 0; r < cells.length && r < rowStart.length - 1; r++) {
    final c = cells[r];
    double? newPan;
    if (c.fxCmd == kFxSetPan) {
      newPan = _panFromParam(c.fxParam);
    } else if (c.fxCmd == kFxPanSlide) {
      final rightAmt = (c.fxParam >> 4) & 0xF;
      final leftAmt = c.fxParam & 0xF;
      final t = ticksPerRow > 1 ? ticksPerRow : 1;
      newPan = (pan + (rightAmt - leftAmt) * t / 128.0).clamp(-1.0, 1.0);
    }
    if (newPan != null && newPan != pan) {
      final s = rowStart[r];
      if (s > regionStart) {
        regions.add((start: regionStart, end: s, pan: pan));
      }
      regionStart = s;
      pan = newPan;
    }
  }
  regions.add((start: regionStart, end: total, pan: pan));
  return regions;
}

// ===========================================================================
// Bounded-memory CHUNKED flow / variable render (flat RAM, carried voice state)
// ===========================================================================
//
// The whole-song flow/variable renders ([_replayFlow], [_replayVariable] and
// their stereo float siblings) allocate a WHOLE-SONG Float64/Float32 mix
// accumulator — for a long command module that is the memory floor (a 20-minute
// command song's Float64 stereo L/R is ~850 MB). The streamers below render the
// played rows in fixed-size ROW-CHUNKS, carrying each channel's persistent voice
// state ([ReplayVoice] + sample read-pointer / envelope cursors) ACROSS chunk
// boundaries, so no whole-song buffer is ever held. Each chunk is quantised to
// PCM16 and handed to [onBlock]; the concatenation is BYTE-IDENTICAL to the
// whole-song render because it is the same per-sample computation with the same
// carried state (mirroring MultiPLAY's per-frame streaming from per-voice state).
//
// SCOPE (see [songCanStreamFlowVariable]): only channels whose contribution is a
// pure sum with NO whole-channel dependency can stream byte-identically —
//   * ADDITIVE voices (peak-free: gain folded into the tick synthesis), and
//   * NATIVE ([SampleInstrument.normalize] == false) sample TICK voices, whose
//     final scale is a constant `channel.gain` (no whole-channel peak).
// A NORMALIZED sample (scale = gain / whole-song peak), an effect-free sample
// (whole-channel `renderChannel`), a multi-sample / NNA voice, or a Gxx/Hxy
// global-volume command (its level persists across chunks) all need whole-song
// information, so a song containing any of them stays on the whole-song path
// (already < 500 MB for the corpus). The stereo/mono routing mirrors
// [renderSongWav] exactly.

/// Bytes-of-audio target per streamed chunk (~1.5 s at 44.1 kHz). Rows are
/// greedily grouped until the chunk's sample span reaches this, so a chunk's
/// buffers stay O(1) in song length. Chunking is byte-neutral (row-aligned).
const int kStreamChunkFrames = 1 << 16;

/// Whether any played cell carries a Gxx (set) or Hxy (slide) GLOBAL-volume
/// command — the one cross-chunk coupling that would make a row-chunked render
/// diverge (the level persists across chunk boundaries). Scanned over the played
/// (flattened) rows so it matches the render's actual timeline.
bool _flatHasGlobalVolume(TrackerSong song, List<PlayedRow> played) {
  for (final pr in played) {
    final cols = song.patterns[pr.patternIndex].cells;
    for (var c = 0; c < cols.length; c++) {
      final cell = cols[c][pr.row];
      if (cell.fxCmd == kFxSetGlobalVolume || cell.fxCmd == kFxGlobalVolSlide) {
        return true;
      }
    }
  }
  return false;
}

/// Whether [channel] (over its flattened [cells]) can be rendered in resumable
/// row-chunks with carried voice state — see the section header. A muted or
/// silent channel is trivially safe (contributes nothing). [stereo] rejects an
/// ADDITIVE channel carrying a pan ENVELOPE (its per-note-run auto-pan is not
/// chunked); a native sample tick voice pans per sample internally, so it stays
/// safe with or without a pan envelope.
bool _channelChunkSafe(
  TrackerChannel channel,
  List<TrackerCell> cells, {
  required bool stereo,
  required bool nativeLongStereo,
  required bool nativeLongMono,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return true;
  if (channel.instrument is MultiSampleInstrument) {
    // A native multi-sample (NNA-zone) channel streams ONLY on the bounded
    // per-note-run render, gated to LONG songs whose whole-song NNA voice render
    // ([_renderNativeTickZoneVoices]) would exceed the memory budget:
    //   * STEREO via _renderLongNativeVariableStereo — a long (> 120 s)
    //     variable-timing stereo song, no pan envelope; and
    //   * MONO via _renderLongNativeVariable — a long (> 120 s) flow/variable
    //     mono song with a per-tick effect.
    // SHORT songs of either shape (and any not matching) stay on the whole-song
    // NNA render (already < the ceiling for the corpus) — byte-identical.
    if (stereo) {
      return _isNativeLongStreamChannel(
        channel,
        nativeLongStereo: nativeLongStereo,
      );
    }
    return _isNativeLongMonoStreamChannel(
      channel,
      cells,
      nativeLongMono: nativeLongMono,
    );
  }
  if (_additiveOf(channel.instrument) != null) {
    final penv = channel.panEnvelope;
    if (stereo && penv != null && !penv.isEmpty) return false;
    return true;
  }
  if (channel.instrument is SampleInstrument &&
      !(channel.instrument as SampleInstrument).normalize &&
      _hasPerTickEffect(cells)) {
    return true;
  }
  return false;
}

/// Whether [song] renders through the flow OR variable-timing path AND every
/// active channel is chunk-safe — i.e. the row-chunk streamer below produces
/// output byte-identical to the whole-song render. [stereo] selects the pan-aware
/// channel test. A Gxx/Hxy global-volume command is now carried across chunk
/// boundaries (its running level persists in a scalar, applied per-sample exactly
/// as [globalVolumeEnvelope] does), so it no longer forces the whole-song path.
bool songCanStreamFlowVariable(TrackerSong song, {required bool stereo}) {
  if (!(songNeedsWalkRender(song) || songUsesVariableTiming(song))) {
    return false;
  }
  final played = walkFlow(song);
  if (played.isEmpty) return false;
  final nativeLongStereo = _songUsesNativeLongStereo(song, played);
  final nativeLongMono = _songUsesNativeLongMono(song, played);
  final channels = song.channels;
  for (var c = 0; c < channels.length; c++) {
    final cells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    if (!_channelChunkSafe(
      channels[c],
      cells,
      stereo: stereo,
      nativeLongStereo: nativeLongStereo,
      nativeLongMono: nativeLongMono,
    )) {
      return false;
    }
  }
  return true;
}

/// Whether a native multi-sample [channel] qualifies for the bounded per-note-run
/// stereo streamer (mirroring [_renderLongNativeVariableStereo]): its instrument
/// has native voice semantics, every zone is a NATIVE (`normalize == false`)
/// sample, and it carries no pan envelope (a pan envelope routes the whole-song
/// render through the mono long path instead). [nativeLongStereo] is the
/// song-level precondition (long variable-timing stereo song).
bool _isNativeLongStreamChannel(
  TrackerChannel channel, {
  required bool nativeLongStereo,
}) {
  if (!nativeLongStereo) return false;
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument || !multi.nativeVoiceSemantics) {
    return false;
  }
  if (!multi.zones.values.every((z) => z is SampleInstrument && !z.normalize)) {
    return false;
  }
  final penv = channel.panEnvelope;
  return penv == null || penv.isEmpty;
}

/// Whether [song]'s whole-song render takes the bounded per-note-run stereo path
/// for native multi-sample channels ([_renderLongNativeVariableStereo]): a STEREO,
/// variable-timing song longer than [_nativeTickFullBufferLimit]. Below that
/// length (or in mono / flow) native multi channels use the full NNA voice render
/// ([_renderNativeTickZoneVoices]), which the row-chunk streamer does not mirror.
bool _songUsesNativeLongStereo(TrackerSong song, List<PlayedRow> played) {
  if (!(song.usesPan || song.stereoOutput)) return false;
  if (!songUsesVariableTiming(song)) return false;
  return _FlowVarLayout(song, played).totalSamples > _nativeTickFullBufferLimit;
}

/// Whether [song]'s MONO render should route native multi-sample channels through
/// the bounded per-note-run MONO stream ([_zoneRunRenderChunkMono], mirroring the
/// whole-song bounded [_renderLongNativeVariable]) instead of the whole-song NNA
/// voice render ([_renderNativeTickZoneVoices]): a MONO (unpanned) flow / variable
/// song longer than [_nativeTickFullBufferLimit] that carries a native
/// multi-sample channel. Below that length the whole-song NNA render fits the
/// budget and is kept (byte-identical); only LONG songs — whose whole-song render
/// would retain whole-song voice buffers per NNA voice — take the bounded stream.
/// The whole corpus renders STEREO, so this MONO gate never reclassifies it.
bool _songUsesNativeLongMono(TrackerSong song, List<PlayedRow> played) {
  if (song.usesPan || song.stereoOutput) return false;
  if (_FlowVarLayout(song, played).totalSamples <= _nativeTickFullBufferLimit) {
    return false;
  }
  for (final ch in song.channels) {
    final multi = ch.instrument;
    if (multi is MultiSampleInstrument &&
        multi.nativeVoiceSemantics &&
        multi.zones.values
            .every((z) => z is SampleInstrument && !z.normalize)) {
      return true;
    }
  }
  return false;
}

/// Whether a native multi-sample [channel] qualifies for the bounded per-note-run
/// MONO streamer (mirroring [_renderLongNativeVariable]): its instrument has
/// native voice semantics, every zone is a NATIVE (`normalize == false`) sample,
/// and its flattened [cells] carry a per-tick effect — the gate that routes the
/// whole-song render through the NNA voice path ([_renderNativeTickZoneVoices])
/// this bounded render replaces. [nativeLongMono] is the song-level precondition
/// (a LONG flow/variable MONO song, above the whole-song NNA memory budget).
bool _isNativeLongMonoStreamChannel(
  TrackerChannel channel,
  List<TrackerCell> cells, {
  required bool nativeLongMono,
}) {
  if (!nativeLongMono) return false;
  final multi = channel.instrument;
  if (multi is! MultiSampleInstrument || !multi.nativeVoiceSemantics) {
    return false;
  }
  if (!multi.zones.values.every((z) => z is SampleInstrument && !z.normalize)) {
    return false;
  }
  return _hasPerTickEffect(cells);
}

/// The per-row absolute sample boundaries ([rowStart], length `rows + 1`) and
/// per-row tick counts ([ticks], length `rows`) of [song]'s played sequence —
/// laid out EXACTLY as the whole-song render it mirrors: the accumulated per-row
/// durations for a variable-timing song ([_replayVariable]), else the uniform
/// flat timing for a flow / variable-length song ([_replayFlow]). [variable]
/// records which layout was used (it also selects the Float32 vs Float64 mix).
class _FlowVarLayout {
  _FlowVarLayout(TrackerSong song, this.played)
      : rowStart = List<int>.filled(played.length + 1, 0),
        ticks = List<int>.filled(played.length, kDefaultTicksPerRow),
        variable = songUsesVariableTiming(song) {
    final n = played.length;
    if (variable) {
      final def = song.timing.tempoBpm;
      var acc = 0;
      for (var i = 0; i < n; i++) {
        rowStart[i] = acc;
        ticks[i] = played[i].ticksPerRow;
        final tempo = played[i].tempoBpm > 0 ? played[i].tempoBpm : def;
        acc += (_rowMsFor(tempo, played[i].ticksPerRow) * kSampleRate / 1000)
            .round();
      }
      rowStart[n] = acc;
    } else {
      final base = effectiveTiming(song);
      final flatTiming = base.copyWith(rows: n == 0 ? 1 : n);
      final flowTicks = songInitialSpeed(
        song,
        fallback:
            song.initialSpeed > 0 ? song.initialSpeed : kDefaultTicksPerRow,
      );
      for (var i = 0; i < n; i++) {
        rowStart[i] = flatTiming.stepStartSample(i);
        ticks[i] = flowTicks;
      }
      rowStart[n] = flatTiming.totalSamples;
    }
  }

  final List<PlayedRow> played;
  final List<int> rowStart;
  final List<int> ticks;
  final bool variable;

  int get totalSamples => rowStart.isEmpty ? 0 : rowStart.last;
}

/// Persistent additive-voice state carried across chunk boundaries.
class _AddChunkState {
  final ReplayVoice voice = ReplayVoice();
  ({
    List<double> harmonics,
    double attackSec,
    double decay,
    double harmNorm
  })? tp;
}

/// Persistent sample-voice state carried across chunk boundaries (the read
/// pointer + envelope cursors that make a note ring past a chunk edge).
class _SampChunkState {
  _SampChunkState(this.cur);
  final ReplayVoice voice = ReplayVoice();
  TrackerInstrument? cur;
  double readPos = 0.0;
  int noteStartSample = 0;
  int releaseStartSample = 0;
  double rowPan = 0.0;
}

/// Renders additive rows `[rowFrom, rowTo)` into [dest] (chunk-local, base
/// absolute sample [sampleBase]) with the carried [st]. A LINE-FOR-LINE mirror
/// of the additive branch of [_renderChannelIntoVariable] (which is itself
/// byte-identical to [_renderChannelInto] under matched boundaries), restricted
/// to a row window with state carried in/out — so the concatenation matches the
/// whole-song render. [dest] may be Float32List or Float64List; the caller's
/// choice reproduces the whole-song accumulator's precision.
void _additiveRenderRows(
  List<double> dest,
  int sampleBase,
  _AddChunkState st,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticks,
  List<TrackerInstrument>? pool,
  int rowFrom,
  int rowTo,
) {
  final inst = _additiveOf(channel.instrument);
  if (inst == null) return;
  st.tp ??= _timbreParamsOf(inst);
  var tp = st.tp!;
  final gain = channel.gain;
  final voice = st.voice;
  final rows = cells.length;
  for (var r = rowFrom; r < rowTo; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 && pool != null && cellInst - 1 < pool.length) {
      final pi = _additiveOf(pool[cellInst - 1]);
      if (pi != null) tp = _timbreParamsOf(pi);
    }
    voice.armRow(cells[r]);
    if (voice.retriggeredThisRow) {
      voice.oscPhase = 0;
      voice.noteStartSample = rowStart[r];
      voice.noteSeconds = _runSecondsVariable(cells, r, rows, rowStart);
    }
    if (!voice.active && !voice.hasPendingNote) continue;

    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticks[r] < 1 ? 1 : ticks[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        voice.oscPhase = 0;
        voice.noteStartSample = ts;
        voice.noteSeconds = _runSecondsVariable(cells, r, rows, rowStart);
      }
      if (!voice.active) continue;
      final freq = _freqOfMidi(state.pitch);
      final volScale = (state.volume / kMaxVolume) * voice.noteVolume * gain;
      final phaseInc = 2 * pi * freq / kSampleRate;
      for (var i = ts; i < te; i++) {
        final t = (i - voice.noteStartSample) / kSampleRate;
        if (t < 0) continue;
        final attack = t < tp.attackSec ? t / tp.attackSec : 1.0;
        final env = attack * exp(-tp.decay * t / voice.noteSeconds);
        var sample = 0.0;
        for (var h = 0; h < tp.harmonics.length; h++) {
          sample += tp.harmonics[h] * sin(voice.oscPhase * (h + 1));
        }
        final el = channel.volumeEnvelope?.levelAt(t * 1000) ?? 1.0;
        dest[i - sampleBase] += (sample / tp.harmNorm) * env * volScale * el;
        voice.oscPhase += phaseInc;
      }
    }
  }
  st.tp = tp;
}

/// Renders native sample rows `[rowFrom, rowTo)` MONO into [dest] (chunk-local,
/// the per-channel stem — WITHOUT gain), carrying [st]. A mirror of the buffered
/// branch of [_renderSampleChannelIntoVariable] restricted to a row window. The
/// caller scales the stem by `channel.gain` once and adds it to the mix (native
/// `scale == gain`), so the arithmetic matches the whole-song `(Σ terms) * gain`
/// exactly (folding gain per-sample would not be bit-identical).
void _sampleRenderRowsMono(
  List<double> dest,
  int sampleBase,
  _SampChunkState st,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticks,
  List<TrackerInstrument>? pool,
  int rowFrom,
  int rowTo,
) {
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final voice = st.voice;
  for (var r = rowFrom; r < rowTo; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      st.cur = pool[cellInst - 1];
    }
    voice.armRow(cells[r]);
    if (voice.releasedThisRow) st.releaseStartSample = rowStart[r];
    if (voice.retriggeredThisRow) {
      final c = cells[r];
      final scur = st.cur;
      final os = scur is SampleInstrument ? scur.offsetScale : 1.0;
      if (scur is SampleInstrument) {
        voice.armFilterOnTrigger(
          scur.filterCutoff,
          scur.filterResonance,
          scur.nativeFilterEnvelope,
        );
      }
      st.readPos =
          c.fxCmd == kFxSampleOffset ? (c.fxParam * 256 * os).toDouble() : 0.0;
      st.noteStartSample = rowStart[r];
    }
    final cur = st.cur;
    if ((!voice.active && !voice.released && !voice.hasPendingNote) ||
        cur is! SampleInstrument ||
        cur.sample.isEmpty) {
      continue;
    }

    final baseMidi = cur.baseMidi;
    final s = cur.sample;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticks[r] < 1 ? 1 : ticks[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        st.readPos = 0.0;
        st.noteStartSample = ts;
      }
      if (!voice.active && !voice.released) continue;
      final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
      for (var i = ts; i < te; i++) {
        final activeLoopStart = voice.released ? loopStart : playbackLoopStart;
        final activeLoopLength = voice.released ? loopLen : playbackLoopLength;
        final activePingPong = voice.released ? pingPong : playbackPingPong;
        final activeLoops = voice.released ? loops : playbackLoops;
        final activeLoopEnd = activeLoopStart + activeLoopLength;
        if (activeLoops &&
            !activePingPong &&
            activeLoopLength > 0 &&
            st.readPos >= activeLoopEnd) {
          st.readPos = activeLoopStart +
              ((st.readPos - activeLoopStart) % activeLoopLength);
        }
        final sampleVal = _readLoopedSample(
          s,
          st.readPos,
          activeLoops,
          activePingPong,
          activeLoopStart,
          activeLoopLength,
        );
        if (sampleVal == null) break;
        final t = (i - st.noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final nativeEnv = cur.nativeVolumeEnvelope;
        final el = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
            (hasEnv ? env.levelAt(t * 1000) : 1.0);
        final fadeRate = cur.nativeFadeout / 1024.0;
        final relSamples = max(0, i - st.releaseStartSample);
        final release = voice.released
            ? (fadeRate > 0
                ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                : exp(-relSamples / (0.03 * kSampleRate)))
            : 1.0;
        // Accumulate the un-gained stem; the caller applies gain once. Anti-click
        // (mirror of the buffered [_renderSampleChannelInto]): residue tail on a
        // hard cut, soft-start fade-in on a trigger — voice state carries the
        // ramp/residue across chunk boundaries.
        voice.updateFilterEnv(t * 1000);
        if (voice.noteCut) {
          dest[i - sampleBase] += voice.residueStep();
        } else {
          final sg = voice.softStartGain();
          final out =
              voice.filterOut(sampleVal) * vol * attack * el * release * sg;
          dest[i - sampleBase] += voice.keepResidue(out);
        }
        final pitch = cur.nativePitchEnvelope?.semitonesAt(
              t * 1000,
              released: voice.released,
            ) ??
            0.0;
        st.readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
      }
    }
  }
}

/// Renders native sample rows `[rowFrom, rowTo)` STEREO into [destL]/[destR]
/// (chunk-local, the per-channel L/R stems — WITHOUT gain), carrying [st]. A
/// mirror of [_renderSampleChannelStereoTicks] restricted to a row window; the
/// caller scales the stems by `channel.gain` once and adds them to the mix
/// (native `scale == gain`), matching the whole-song per-channel-scale-then-`+=`.
void _sampleRenderRowsStereo(
  List<double> destL,
  List<double> destR,
  int sampleBase,
  _SampChunkState st,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticks,
  List<TrackerInstrument>? pool,
  int rowFrom,
  int rowTo,
) {
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final voice = st.voice;
  for (var r = rowFrom; r < rowTo; r++) {
    final cell = cells[r];
    final cellInst = cell.instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      st.cur = pool[cellInst - 1];
    }
    if (cell.fxCmd == kFxSetPan) {
      st.rowPan = _panFromParam(cell.fxParam);
    } else if (cell.fxCmd == kFxPanSlide) {
      final rightAmount = (cell.fxParam >> 4) & 0xF;
      final leftAmount = cell.fxParam & 0xF;
      st.rowPan = (st.rowPan + (rightAmount - leftAmount) * ticks[r] / 128.0)
          .clamp(-1.0, 1.0);
    }
    voice.armRow(cell);
    if (voice.releasedThisRow) st.releaseStartSample = rowStart[r];
    if (voice.retriggeredThisRow) {
      final scur = st.cur;
      final os = scur is SampleInstrument ? scur.offsetScale : 1.0;
      if (scur is SampleInstrument) {
        voice.armFilterOnTrigger(
          scur.filterCutoff,
          scur.filterResonance,
          scur.nativeFilterEnvelope,
        );
      }
      st.readPos = cell.fxCmd == kFxSampleOffset
          ? (cell.fxParam * 256 * os).toDouble()
          : 0.0;
      st.noteStartSample = rowStart[r];
    }
    final cur = st.cur;
    if ((!voice.active && !voice.released && !voice.hasPendingNote) ||
        cur is! SampleInstrument ||
        cur.sample.isEmpty) {
      continue;
    }

    final baseMidi = cur.baseMidi;
    final sample = cur.sample;
    final sampleRight = cur.sampleRight;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final tpr = ticks[r] < 1 ? 1 : ticks[r];
    for (var k = 0; k < tpr; k++) {
      final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
      final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
      final state = voice.tick(k, tpr);
      if (state.retrigger) {
        st.readPos = 0.0;
        st.noteStartSample = ts;
      }
      if (!voice.active && !voice.released) continue;
      final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
      for (var i = ts; i < te; i++) {
        final activeLoopStart = voice.released ? loopStart : playbackLoopStart;
        final activeLoopLength = voice.released ? loopLen : playbackLoopLength;
        final activePingPong = voice.released ? pingPong : playbackPingPong;
        final activeLoops = voice.released ? loops : playbackLoops;
        final activeLoopEnd = activeLoopStart + activeLoopLength;
        if (activeLoops &&
            !activePingPong &&
            activeLoopLength > 0 &&
            st.readPos >= activeLoopEnd) {
          st.readPos = activeLoopStart +
              ((st.readPos - activeLoopStart) % activeLoopLength);
        }
        final value = _readLoopedSample(
          sample,
          st.readPos,
          activeLoops,
          activePingPong,
          activeLoopStart,
          activeLoopLength,
        );
        if (value == null) break;
        final rightValue = sampleRight == null
            ? value
            : _readLoopedSample(
                  sampleRight,
                  st.readPos,
                  activeLoops,
                  activePingPong,
                  activeLoopStart,
                  activeLoopLength,
                ) ??
                0.0;
        // Per-voice resonant low-pass (carried across chunk boundaries via the
        // voice's biquad state). A no-op pass-through when unfiltered;
        // updateFilterEnv is a no-op without a filter envelope.
        voice.updateFilterEnv((i - st.noteStartSample) / kSampleRate * 1000);
        final fValue = voice.filterOut(value);
        final fRight =
            sampleRight == null ? fValue : voice.filterOutRight(rightValue);
        final t = (i - st.noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final nativeEnv = cur.nativeVolumeEnvelope;
        final level = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
            (hasEnv ? env.levelAt(t * 1000) : 1.0);
        final pan = (st.rowPan +
                state.pan +
                (channel.panEnvelope?.panAt(t * 1000) ?? 0.0) +
                (cur.nativePanEnvelope?.panAt(t * 1000) ?? 0.0))
            .clamp(-1.0, 1.0);
        final fadeRate = cur.nativeFadeout / 1024.0;
        final relSamples = max(0, i - st.releaseStartSample);
        final release = voice.released
            ? (fadeRate > 0
                ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                : exp(-relSamples / (0.03 * kSampleRate)))
            : 1.0;
        final amount = vol * attack * level * release;
        final di = i - sampleBase;
        // Anti-click — byte-for-byte mirror of the buffered
        // [_renderSampleChannelStereoTicks] emit (residue tail on a hard cut,
        // soft-start fade-in on a trigger); voice state carries across chunks.
        final double outL, outR;
        if (voice.noteCut) {
          voice.residueStepStereo();
          outL = voice.resOutL;
          outR = voice.resOutR;
        } else {
          final sg = voice.softStartGain();
          final double cl, cr;
          if (sampleRight != null) {
            final leftGain = pan > 0 ? 1.0 - pan : 1.0;
            final rightGain = pan < 0 ? 1.0 + pan : 1.0;
            cl = fValue * amount * leftGain * sg;
            cr = fRight * amount * rightGain * sg;
          } else {
            final theta = (pan + 1) / 2 * (pi / 2);
            cl = fValue * amount * cos(theta) * sg;
            cr = fValue * amount * sin(theta) * sg;
          }
          voice.keepResidueStereo(cl, cr);
          outL = cl;
          outR = cr;
        }
        destL[di] += outL;
        destR[di] += outR;
        final pitch = cur.nativePitchEnvelope?.semitonesAt(
              t * 1000,
              released: voice.released,
            ) ??
            0.0;
        st.readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
      }
    }
  }
}

/// One note run of a native multi-sample (NNA-zone) channel — a single note
/// confined to its own row span `[startStep, startStep+steps)` and hard-cut at
/// its end, exactly as [_renderLongNativeVariableStereo] renders it. The resumable
/// tick-voice state (read pointer + envelope cursors) is carried across chunk
/// boundaries so a run that straddles a chunk edge stays continuous.
class _ZoneRun {
  _ZoneRun(this.startStep, this.steps, this.sustainSteps, this.zone);
  final int startStep;
  final int steps;
  final int sustainSteps;
  final SampleInstrument zone;
  final ReplayVoice voice = ReplayVoice();
  double readPos = 0.0;
  int noteStartSample = 0;
  int releaseStartSample = 0;
}

/// A native multi-sample channel's chunk-render plan: its note runs (resolved
/// once) and the constant-power pan gains per region (precomputed once, the same
/// `cos/sin(theta)` [_renderLongNativeVariableStereo] uses).
class _ZoneChannelState {
  _ZoneChannelState(this.runs, this.regGain);
  final List<_ZoneRun> runs;
  final List<({int start, int end, double l, double r})> regGain;
}

/// One channel's chunk-render disposition, resolved once per render.
class _ChunkChannel {
  _ChunkChannel(
    this.index,
    this.channel,
    this.cells,
    this.additive,
    this.state, {
    this.zone,
  });
  final int index;
  final TrackerChannel channel;
  final List<TrackerCell> cells;
  final bool additive; // false ⇒ native sample tick voice (unless [zone] set)
  final Object state; // _AddChunkState or _SampChunkState
  // Non-null ⇒ native multi-sample (NNA-zone) channel: render via [zone].runs.
  final _ZoneChannelState? zone;
  List<({int start, int end, double pan})>? panRegions; // stereo only
}

/// Builds the per-channel chunk-render plan for [song]'s played rows, skipping
/// muted/silent channels (they contribute nothing — byte-identical to the
/// whole-song path which renders them to zero). [stereo] arms the pan regions.
List<_ChunkChannel> _planChunkChannels(
  TrackerSong song,
  _FlowVarLayout layout, {
  required bool stereo,
}) {
  final out = <_ChunkChannel>[];
  final channels = song.channels;
  for (var c = 0; c < channels.length; c++) {
    final ch = channels[c];
    final cells = [
      for (final pr in layout.played)
        song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    if (ch.muted || !cells.any((x) => !x.isEmpty)) continue;
    // Native multi-sample (NNA-zone) channel — bounded per-note-run path
    // (mirrors _renderLongNativeVariableStereo for STEREO / _renderLongNative-
    // Variable for MONO). Gated by _isNativeLongStreamChannel (stereo) /
    // _isNativeLongMonoStreamChannel (mono) in songCanStreamFlowVariable, so it
    // reaches here only for a LONG song of the matching shape. [regGain] is the
    // per-region constant-power pan gain used by the STEREO render; the MONO
    // render ([_zoneRunRenderChunkMono]) ignores it.
    if (ch.instrument is MultiSampleInstrument) {
      final runs = _planZoneRuns(ch, cells);
      final regions = _panRegionsVariable(
        ch.pan,
        cells,
        layout.rowStart,
        ticksPerRow: song.initialSpeed,
      );
      final regGain = [
        for (final reg in regions)
          (
            start: reg.start,
            end: reg.end,
            l: cos((reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2)),
            r: sin((reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2)),
          ),
      ];
      final zoneCc = _ChunkChannel(
        c,
        ch,
        cells,
        false,
        _SampChunkState(ch.instrument),
        zone: _ZoneChannelState(runs, regGain),
      );
      out.add(zoneCc);
      continue;
    }
    final additive = _additiveOf(ch.instrument) != null;
    final state = additive ? _AddChunkState() : _SampChunkState(ch.instrument);
    // A native sample tick voice pans per sample from `rowPan`, which the
    // whole-song _renderSampleChannelStereoTicks seeds with the channel's base
    // pan (8xx/Pxy then slide it). The mono path never reads rowPan, so seeding
    // it unconditionally is harmless there and correct for stereo.
    if (state is _SampChunkState) state.rowPan = ch.pan.clamp(-1.0, 1.0);
    final cc = _ChunkChannel(c, ch, cells, additive, state);
    if (stereo && additive) {
      cc.panRegions = layout.variable
          ? _panRegionsVariable(
              ch.pan,
              cells,
              layout.rowStart,
              ticksPerRow: song.initialSpeed,
            )
          : _panRegions(
              ch.pan,
              cells,
              effectiveTiming(song).copyWith(rows: layout.played.length),
              layout.totalSamples,
              ticksPerRow:
                  layout.ticks.isEmpty ? kDefaultTicksPerRow : layout.ticks[0],
            );
    }
    out.add(cc);
  }
  return out;
}

/// Resolves a native multi-sample channel's note runs ONCE (metadata only,
/// O(notes)) — the same `noteRuns` walk + `zoneForNote` mapping
/// [_renderLongNativeVariableStereo] performs, minus any audio. Runs whose note
/// maps to no zone (or a non-sample zone) contribute nothing and are dropped, as
/// in the whole-song render.
List<_ZoneRun> _planZoneRuns(TrackerChannel channel, List<TrackerCell> cells) {
  final multi = channel.instrument as MultiSampleInstrument;
  final runs = <_ZoneRun>[];
  var startStep = 0;
  for (final run in noteRuns(cells)) {
    final midi = run.$1;
    final sustainSteps = run.$2;
    final steps = run.$2 + run.$3;
    if (midi != null) {
      final zone = multi.zoneForNote(cells[startStep].nativeNote ?? midi);
      if (zone is SampleInstrument) {
        runs.add(_ZoneRun(startStep, steps, sustainSteps, zone));
      }
    }
    startStep += steps;
  }
  return runs;
}

/// Renders a native multi-sample channel's note runs for rows `[rowFrom, rowTo)`
/// into the chunk-local stereo mix (base absolute sample [sampleBase]), carrying
/// each run's resumable tick-voice state ([_ZoneRun.readPos] / envelope cursors)
/// across chunk boundaries. A row-windowed, per-run mirror of
/// [_renderLongNativeVariableStereo]'s NATIVE sink path: each run is confined to
/// its own `[startStep, startStep+steps)` span (hard-cut at its end), the note is
/// released by a note-cut injected at `sustainSteps`, each sample is truncated to
/// Float32 (× channel gain) and distributed straight into L/R by the precomputed
/// pan region — identical arithmetic in GLOBAL coordinates (every term is a sample
/// difference or a global-index write, so the run-local original agrees bit-wise).
void _zoneRunRenderChunkStereo(
  List<double> mixL,
  List<double> mixR,
  int sampleBase,
  _ZoneChannelState zc,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticks,
  int rowFrom,
  int rowTo,
) {
  final gain = channel.gain;
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final f32 = Float32List(1);
  final regGain = zc.regGain;
  for (final run in zc.runs) {
    final runEndRow = run.startStep + run.steps;
    final r0 = max(run.startStep, rowFrom);
    final r1 = min(runEndRow, rowTo);
    if (r0 >= r1) continue;
    final runEndSample = rowStart[runEndRow];
    final cur = run.zone;
    if (cur.sample.isEmpty) continue;
    final voice = run.voice;
    final baseMidi = cur.baseMidi;
    final s = cur.sample;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final cutRow =
        run.sustainSteps < run.steps ? run.startStep + run.sustainSteps : -1;
    for (var r = r0; r < r1; r++) {
      final cell = r == cutRow ? TrackerCell.noteCut : cells[r];
      voice.armRow(cell);
      if (voice.releasedThisRow) run.releaseStartSample = rowStart[r];
      if (voice.retriggeredThisRow) {
        final os = cur.offsetScale;
        run.readPos = cell.fxCmd == kFxSampleOffset
            ? (cell.fxParam * 256 * os).toDouble()
            : 0.0;
        run.noteStartSample = rowStart[r];
      }
      if (!voice.active && !voice.released && !voice.hasPendingNote) continue;
      final rowS = rowStart[r];
      final rowE = rowStart[r + 1];
      final tpr = ticks[r] < 1 ? 1 : ticks[r];
      for (var k = 0; k < tpr; k++) {
        final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
        final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
        final state = voice.tick(k, tpr);
        if (state.retrigger) {
          run.readPos = 0.0;
          run.noteStartSample = ts;
        }
        if (!voice.active && !voice.released) continue;
        final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
        for (var i = ts; i < te && i < runEndSample; i++) {
          final activeLoopStart =
              voice.released ? loopStart : playbackLoopStart;
          final activeLoopLength =
              voice.released ? loopLen : playbackLoopLength;
          final activePingPong = voice.released ? pingPong : playbackPingPong;
          final activeLoops = voice.released ? loops : playbackLoops;
          final activeLoopEnd = activeLoopStart + activeLoopLength;
          if (activeLoops &&
              !activePingPong &&
              activeLoopLength > 0 &&
              run.readPos >= activeLoopEnd) {
            run.readPos = activeLoopStart +
                ((run.readPos - activeLoopStart) % activeLoopLength);
          }
          final sampleVal = _readLoopedSample(
            s,
            run.readPos,
            activeLoops,
            activePingPong,
            activeLoopStart,
            activeLoopLength,
          );
          if (sampleVal == null) break;
          final t = (i - run.noteStartSample) / kSampleRate;
          final attack = t < declickSec ? t / declickSec : 1.0;
          final nativeEnv = cur.nativeVolumeEnvelope;
          final el = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
              (hasEnv ? env.levelAt(t * 1000) : 1.0);
          final fadeRate = cur.nativeFadeout / 1024.0;
          final relSamples = max(0, i - run.releaseStartSample);
          final release = voice.released
              ? (fadeRate > 0
                  ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                  : exp(-relSamples / (0.03 * kSampleRate)))
              : 1.0;
          // Anti-click — mirror of the buffered [_renderSampleChannelIntoVariable]
          // native-sink emit that [_renderLongNativeVariableStereo] drives: a
          // hard-cut residue tail vs. a soft-start fade-in, on the pre-gain
          // scalar. (This path is unfiltered, matching that sink's no-op filter.)
          final double sv;
          if (voice.noteCut) {
            sv = voice.residueStep();
          } else {
            final sg = voice.softStartGain();
            sv =
                voice.keepResidue(sampleVal * vol * attack * el * release * sg);
          }
          // Native sink: truncate to Float32 (× gain), then distribute into L/R
          // via the pan region covering this global sample index.
          f32[0] = sv * gain;
          final m = f32[0];
          for (final rg in regGain) {
            if (i >= rg.start && i < rg.end) {
              final j = i - sampleBase;
              mixL[j] += m * rg.l;
              mixR[j] += m * rg.r;
              break;
            }
          }
          final pitch = cur.nativePitchEnvelope?.semitonesAt(
                t * 1000,
                released: voice.released,
              ) ??
              0.0;
          run.readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
        }
      }
    }
  }
}

/// The MONO sibling of [_zoneRunRenderChunkStereo]: renders a native
/// multi-sample channel's note runs for rows `[rowFrom, rowTo)` into the
/// chunk-local MONO mix (base absolute sample [sampleBase]), carrying each run's
/// resumable tick-voice state ([_ZoneRun.readPos] / envelope / filter cursors)
/// across chunk boundaries. Each run is confined to its own
/// `[startStep, startStep+steps)` span (hard-cut at its end), released by a
/// note-cut injected at `sustainSteps`, and its finished PRE-gain scalar is
/// scaled by `channel.gain` and summed into the mix — byte-identical to the
/// whole-song bounded per-note-run render [_renderLongNativeVariable] (which
/// renders each run into a run buffer via [_renderSampleChannelIntoVariable] then
/// adds `buf[i] == sv * gain`). The arithmetic is invariant to the run-local vs
/// GLOBAL sample origin (every term is a sample difference or a global-index
/// write), so this row-windowed global-coordinate render agrees bit-for-bit.
void _zoneRunRenderChunkMono(
  List<double> mix,
  int sampleBase,
  _ZoneChannelState zc,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticks,
  int rowFrom,
  int rowTo,
) {
  final gain = channel.gain;
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  for (final run in zc.runs) {
    final runEndRow = run.startStep + run.steps;
    final r0 = max(run.startStep, rowFrom);
    final r1 = min(runEndRow, rowTo);
    if (r0 >= r1) continue;
    final runEndSample = rowStart[runEndRow];
    final cur = run.zone;
    if (cur.sample.isEmpty) continue;
    final voice = run.voice;
    final baseMidi = cur.baseMidi;
    final s = cur.sample;
    final loops = cur.loops;
    final pingPong = cur.pingPong;
    final loopStart = cur.loopStart;
    final loopLen = cur.loopLength;
    final useSustainLoop = cur.sustainLoops;
    final playbackLoopStart = useSustainLoop ? cur.sustainLoopStart : loopStart;
    final playbackLoopLength = useSustainLoop ? cur.sustainLoopLength : loopLen;
    final playbackPingPong = useSustainLoop ? cur.sustainPingPong : pingPong;
    final playbackLoops = useSustainLoop || loops;
    final cutRow =
        run.sustainSteps < run.steps ? run.startStep + run.sustainSteps : -1;
    for (var r = r0; r < r1; r++) {
      final cell = r == cutRow ? TrackerCell.noteCut : cells[r];
      voice.armRow(cell);
      if (voice.releasedThisRow) run.releaseStartSample = rowStart[r];
      if (voice.retriggeredThisRow) {
        final os = cur.offsetScale;
        run.readPos = cell.fxCmd == kFxSampleOffset
            ? (cell.fxParam * 256 * os).toDouble()
            : 0.0;
        run.noteStartSample = rowStart[r];
      }
      if (!voice.active && !voice.released && !voice.hasPendingNote) continue;
      final rowS = rowStart[r];
      final rowE = rowStart[r + 1];
      final tpr = ticks[r] < 1 ? 1 : ticks[r];
      for (var k = 0; k < tpr; k++) {
        final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
        final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
        final state = voice.tick(k, tpr);
        if (state.retrigger) {
          run.readPos = 0.0;
          run.noteStartSample = ts;
        }
        if (!voice.active && !voice.released) continue;
        final vol = (state.volume / kMaxVolume) * voice.noteVolume * cur.volume;
        for (var i = ts; i < te && i < runEndSample; i++) {
          final activeLoopStart =
              voice.released ? loopStart : playbackLoopStart;
          final activeLoopLength =
              voice.released ? loopLen : playbackLoopLength;
          final activePingPong = voice.released ? pingPong : playbackPingPong;
          final activeLoops = voice.released ? loops : playbackLoops;
          final activeLoopEnd = activeLoopStart + activeLoopLength;
          if (activeLoops &&
              !activePingPong &&
              activeLoopLength > 0 &&
              run.readPos >= activeLoopEnd) {
            run.readPos = activeLoopStart +
                ((run.readPos - activeLoopStart) % activeLoopLength);
          }
          final sampleVal = _readLoopedSample(
            s,
            run.readPos,
            activeLoops,
            activePingPong,
            activeLoopStart,
            activeLoopLength,
          );
          if (sampleVal == null) break;
          final t = (i - run.noteStartSample) / kSampleRate;
          final attack = t < declickSec ? t / declickSec : 1.0;
          final nativeEnv = cur.nativeVolumeEnvelope;
          final el = nativeEnv?.levelAt(t * 1000, released: voice.released) ??
              (hasEnv ? env.levelAt(t * 1000) : 1.0);
          final fadeRate = cur.nativeFadeout / 1024.0;
          final relSamples = max(0, i - run.releaseStartSample);
          final release = voice.released
              ? (fadeRate > 0
                  ? exp(-fadeRate * relSamples / kSampleRate * 8.0)
                  : exp(-relSamples / (0.03 * kSampleRate)))
              : 1.0;
          // Anti-click — mirror of the buffered [_renderSampleChannelIntoVariable]
          // emit that [_renderLongNativeVariable] drives: a hard-cut residue tail
          // vs. a soft-start fade-in, on the pre-gain filtered scalar. (filterOut
          // is a pass-through when the zone is unfiltered.)
          voice.updateFilterEnv(t * 1000);
          final double sv;
          if (voice.noteCut) {
            sv = voice.residueStep();
          } else {
            final sg = voice.softStartGain();
            final out =
                voice.filterOut(sampleVal) * vol * attack * el * release * sg;
            sv = voice.keepResidue(out);
          }
          mix[i - sampleBase] += sv * gain;
          final pitch = cur.nativePitchEnvelope?.semitonesAt(
                t * 1000,
                released: voice.released,
              ) ??
              0.0;
          run.readPos += pow(2.0, (state.pitch - baseMidi + pitch) / 12.0);
        }
      }
    }
  }
}

/// Greedily groups played rows into chunks whose sample span reaches
/// [kStreamChunkFrames], invoking [render] with each `[rowFrom, rowTo)` window
/// and its absolute sample bounds. Row-aligned, so a chunk boundary never splits
/// a tick — the concatenation is exactly the whole-song timeline.
void _forEachRowChunk(
  _FlowVarLayout layout,
  void Function(int rowFrom, int rowTo, int sampleFrom, int sampleTo) render,
) {
  final n = layout.played.length;
  var rowFrom = 0;
  while (rowFrom < n) {
    final base = layout.rowStart[rowFrom];
    var rowTo = rowFrom + 1;
    while (rowTo < n && layout.rowStart[rowTo] - base < kStreamChunkFrames) {
      rowTo++;
    }
    render(rowFrom, rowTo, base, layout.rowStart[rowTo]);
    rowFrom = rowTo;
  }
}

/// The running GLOBAL-volume level (0..64) carried across chunk boundaries — the
/// one scalar of state that couples a Gxx/Hxy render, mirroring the way
/// [globalVolumeEnvelope] threads `gv` across rows for the whole-song render.
class _GvChunkState {
  _GvChunkState(this.gv);
  int gv;
}

/// The first Gxx (set) / Hxy (slide) param on each played row (scanned across all
/// channels in channel order, first wins — the exact shape [globalVolumeEnvelope]
/// consumes). Precomputed ONCE per render (O(rows·channels), bounded), so the
/// per-chunk fill only walks a row window.
List<({int? setTo, int? slide})> _flatGvPerRow(
  TrackerSong song,
  List<PlayedRow> played,
) {
  final chCount = song.channels.length;
  final out = <({int? setTo, int? slide})>[];
  for (final pr in played) {
    final cols = song.patterns[pr.patternIndex].cells;
    int? setTo;
    int? slide;
    for (var c = 0; c < chCount; c++) {
      final cell = cols[c][pr.row];
      if (cell.fxCmd == kFxSetGlobalVolume) {
        setTo ??= cell.fxParam;
      } else if (cell.fxCmd == kFxGlobalVolSlide) {
        slide ??= cell.fxParam;
      }
    }
    out.add((setTo: setTo, slide: slide));
  }
  return out;
}

/// Fills the chunk-local global-volume scale [env] (`env[i-sampleBase]`) for rows
/// `[rowFrom, rowTo)`, advancing the running level [st] across the window — a
/// row-windowed, resumable mirror of [globalVolumeEnvelope] with the same per-tick
/// slide subdivision (a single [ticks] scalar, exactly as the whole-song render
/// uses `song.initialSpeed` / the flow speed). Byte-identical because the level is
/// threaded across chunk boundaries and boundaries are row-aligned.
void _fillGvChunk(
  Float64List env,
  int sampleBase,
  _GvChunkState st,
  List<({int? setTo, int? slide})> gv,
  List<int> rowStart,
  int rowFrom,
  int rowTo,
  int ticks,
  int totalSamples,
) {
  final tpr = ticks < 1 ? 1 : ticks;
  for (var r = rowFrom; r < rowTo; r++) {
    final row = gv[r];
    if (row.setTo != null) st.gv = row.setTo!.clamp(0, 64);
    final rowS = rowStart[r];
    final rowE = rowStart[r + 1];
    final slide = row.slide;
    if (slide == null) {
      final s = st.gv / 64.0;
      for (var i = rowS; i < rowE && i < totalSamples; i++) {
        env[i - sampleBase] = s;
      }
    } else {
      final up = (slide >> 4) & 0xF;
      final down = slide & 0xF;
      for (var k = 0; k < tpr; k++) {
        if (k > 0) st.gv = (st.gv + up - down).clamp(0, 64);
        final ts = rowS + ((rowE - rowS) * k) ~/ tpr;
        final te = rowS + ((rowE - rowS) * (k + 1)) ~/ tpr;
        final s = st.gv / 64.0;
        for (var i = ts; i < te && i < totalSamples; i++) {
          env[i - sampleBase] = s;
        }
      }
    }
  }
}

/// The single ticks-per-row scalar the whole-song render feeds to
/// [globalVolumeEnvelope] for the slide subdivision: `song.initialSpeed` for the
/// variable-timing path, the flow speed (uniform `layout.ticks`) for flow.
int _gvTicksFor(TrackerSong song, _FlowVarLayout layout) => layout.variable
    ? song.initialSpeed
    : (layout.ticks.isEmpty ? kDefaultTicksPerRow : layout.ticks.first);

/// Streams the MONO flow/variable render of [song] to [onStart] (total frame
/// count, once) then [onBlock] (PCM16 chunks) — byte-identical to
/// `replaySong(song).pcm`, in flat RAM. Precondition:
/// `songCanStreamFlowVariable(song, stereo: false)`.
void streamFlowVariableMonoPcm(
  TrackerSong song, {
  required void Function(int totalFrames) onStart,
  required void Function(Int16List block) onBlock,
  PcmDither? dither,
}) {
  song.syncCurrent();
  final played = walkFlow(song);
  final layout = _FlowVarLayout(song, played);
  onStart(layout.totalSamples);
  final channels = _planChunkChannels(song, layout, stereo: false);
  final pool = song.instruments;
  final gv = song.globalVolume;
  final total = layout.totalSamples;
  // Gxx/Hxy global-volume envelope, carried across chunks by [gvState].
  final hasGv = _flatHasGlobalVolume(song, played);
  final gvPerRow = hasGv ? _flatGvPerRow(song, played) : null;
  final gvState = hasGv ? _GvChunkState(64) : null;
  final gvTicks = hasGv ? _gvTicksFor(song, layout) : 0;
  _forEachRowChunk(layout, (rowFrom, rowTo, sampleFrom, sampleTo) {
    final frames = sampleTo - sampleFrom;
    if (frames <= 0) return;
    final mix = Float64List(frames);
    Float64List? stem; // reused per-channel un-gained sample stem
    for (final cc in channels) {
      if (cc.zone != null) {
        // Native multi-sample (NNA-zone) channel — bounded per-note-run MONO
        // render, writing each run's gained sample straight into the chunk mix
        // (mirrors the whole-song bounded [_renderLongNativeVariable]).
        _zoneRunRenderChunkMono(
          mix,
          sampleFrom,
          cc.zone!,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          rowFrom,
          rowTo,
        );
      } else if (cc.additive) {
        // Additive folds gain into volScale and writes the mix directly (matches
        // the whole-song `_renderChannelInto`/Variable additive branch).
        _additiveRenderRows(
          mix,
          sampleFrom,
          cc.state as _AddChunkState,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          pool,
          rowFrom,
          rowTo,
        );
      } else {
        stem ??= Float64List(frames);
        stem.fillRange(0, frames, 0.0);
        _sampleRenderRowsMono(
          stem,
          sampleFrom,
          cc.state as _SampChunkState,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          pool,
          rowFrom,
          rowTo,
        );
        final gain = cc.channel.gain;
        for (var j = 0; j < frames; j++) {
          mix[j] += stem[j] * gain;
        }
      }
    }
    // Global volume: multiply the running Gxx/Hxy envelope in place (matching
    // _applyGlobalVolumeMix), then the song-level scalar (matching
    // _applySongGlobalVolume) — same order and buffer precision as whole-song.
    if (gvPerRow != null) {
      final gvEnv = Float64List(frames);
      _fillGvChunk(
        gvEnv,
        sampleFrom,
        gvState!,
        gvPerRow,
        layout.rowStart,
        rowFrom,
        rowTo,
        gvTicks,
        total,
      );
      for (var j = 0; j < frames; j++) {
        mix[j] *= gvEnv[j];
      }
    }
    if (gv < 1.0) {
      for (var j = 0; j < frames; j++) {
        mix[j] *= gv;
      }
    }
    final out = Int16List(frames);
    for (var j = 0; j < frames; j++) {
      out[j] = pcm16Sample(mix[j], dither);
    }
    onBlock(out);
  });
}

/// Streams the STEREO flow/variable render of [song] as interleaved L,R PCM16 —
/// byte-identical to `replaySongStereo(song).pcm`, in flat RAM. A variable-timing
/// song accumulates in Float32 (matching [_replayVariableStereoFloat]); a flow /
/// variable-length song in Float64 (matching [_replayFlowStereoFloat]).
/// Precondition: `songCanStreamFlowVariable(song, stereo: true)`.
void streamFlowVariableStereoPcm(
  TrackerSong song, {
  required void Function(int totalFrames) onStart,
  required void Function(Int16List block) onBlock,
  PcmDither? dither,
}) {
  song.syncCurrent();
  final played = walkFlow(song);
  final layout = _FlowVarLayout(song, played);
  onStart(layout.totalSamples);
  final channels = _planChunkChannels(song, layout, stereo: true);
  final pool = song.instruments;
  final gv = song.globalVolume;
  final f32 = layout.variable;
  final total = layout.totalSamples;
  // Gxx/Hxy global-volume envelope, carried across chunks by [gvState].
  final hasGv = _flatHasGlobalVolume(song, played);
  final gvPerRow = hasGv ? _flatGvPerRow(song, played) : null;
  final gvState = hasGv ? _GvChunkState(64) : null;
  final gvTicks = hasGv ? _gvTicksFor(song, layout) : 0;
  _forEachRowChunk(layout, (rowFrom, rowTo, sampleFrom, sampleTo) {
    final frames = sampleTo - sampleFrom;
    if (frames <= 0) return;
    // Chunk mix accumulators — Float32 for the variable path, Float64 for flow,
    // reproducing each whole-song sibling's precision exactly.
    final List<double> mixL = f32 ? Float32List(frames) : Float64List(frames);
    final List<double> mixR = f32 ? Float32List(frames) : Float64List(frames);
    // Reused per-channel scratch: additive mono (matched precision) + a Float64
    // sample L/R pair (the stereo tick voice accumulates in Float64 before gain).
    List<double>? mono;
    Float64List? chL;
    Float64List? chR;
    for (final cc in channels) {
      if (cc.zone != null) {
        // Native multi-sample (NNA-zone) channel — bounded per-note-run render,
        // writing straight into the chunk mix (Float32 truncation + pan region).
        _zoneRunRenderChunkStereo(
          mixL,
          mixR,
          sampleFrom,
          cc.zone!,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          rowFrom,
          rowTo,
        );
      } else if (cc.additive) {
        mono ??= f32 ? Float32List(frames) : Float64List(frames);
        mono.fillRange(0, frames, 0.0);
        _additiveRenderRows(
          mono,
          sampleFrom,
          cc.state as _AddChunkState,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          pool,
          rowFrom,
          rowTo,
        );
        for (final reg in cc.panRegions!) {
          final s = max(reg.start, sampleFrom);
          final e = min(reg.end, sampleTo);
          if (s >= e) continue;
          final theta = (reg.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2);
          final lGain = cos(theta);
          final rGain = sin(theta);
          for (var i = s; i < e; i++) {
            final j = i - sampleFrom;
            mixL[j] += mono[j] * lGain;
            mixR[j] += mono[j] * rGain;
          }
        }
      } else {
        chL ??= Float64List(frames);
        chR ??= Float64List(frames);
        chL.fillRange(0, frames, 0.0);
        chR.fillRange(0, frames, 0.0);
        _sampleRenderRowsStereo(
          chL,
          chR,
          sampleFrom,
          cc.state as _SampChunkState,
          cc.channel,
          cc.cells,
          layout.rowStart,
          layout.ticks,
          pool,
          rowFrom,
          rowTo,
        );
        // Scale the un-gained per-channel L/R stems by gain once, then add —
        // matching the whole-song per-channel `left *= scale; mix += left`.
        final gain = cc.channel.gain;
        for (var j = 0; j < frames; j++) {
          mixL[j] += chL[j] * gain;
          mixR[j] += chR[j] * gain;
        }
      }
    }
    // Global volume: the running Gxx/Hxy envelope multiplies into both L and R in
    // place (matching _applyGlobalVolumeStereo), then the song-level scalar
    // (matching _applySongGlobalVolume) — same order + buffer precision as the
    // whole-song render (Float32 for variable, Float64 for flow).
    if (gvPerRow != null) {
      final gvEnv = Float64List(frames);
      _fillGvChunk(
        gvEnv,
        sampleFrom,
        gvState!,
        gvPerRow,
        layout.rowStart,
        rowFrom,
        rowTo,
        gvTicks,
        total,
      );
      for (var j = 0; j < frames; j++) {
        mixL[j] *= gvEnv[j];
        mixR[j] *= gvEnv[j];
      }
    }
    if (gv < 1.0) {
      for (var j = 0; j < frames; j++) {
        mixL[j] *= gv;
        mixR[j] *= gv;
      }
    }
    final out = Int16List(frames * 2);
    for (var j = 0; j < frames; j++) {
      // L,R,L,R order matches [_interleaveToPcm] so a dithered stream is
      // byte-identical to a dithered whole-render.
      out[j * 2] = pcm16Sample(mixL[j], dither);
      out[j * 2 + 1] = pcm16Sample(mixR[j], dither);
    }
    onBlock(out);
  });
}
