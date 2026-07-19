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
// [TrackerSong.instruments]): a note can switch the additive voice's timbre,
// persisting per channel — so one channel can play piano then flute. Honoured on
// ADDITIVE channels only for now (a non-additive/sample channel, or a per-cell
// reference to a non-additive pool instrument, keeps the channel's own voice).
//
// 9xx sample-offset works on SAMPLE voices — [SampleInstrument.renderChannel]
// starts the note at param×256 (it already receives the cells that carry the
// effect column). MID-SONG speed/tempo CHANGES are now handled by the variable
// render (see the Fxx note above). Still TODO: per-cell instrument on SAMPLE
// voices — wants a per-note non-additive render (the shared next step).
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

/// Txy — tremor: pulse the note ON for x ticks then OFF for y, repeating. A new
/// non-colliding command (XM effect 0x1D); importers can map XM effect T onto it.
const int kFxTremor = 0x1D;

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

  // LFO waveform select (E4x/E7x) + glissando control (E3x) — persist across
  // rows like a real tracker's per-channel control state.
  int _vibWave = 0;
  int _tremWave = 0;
  bool _glissando = false;

  // LFO phases (radians), reset on a new note.
  double _vibPhase = 0;
  double _tremPhase = 0;

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

  /// Arm the row: parse the cell, (re)trigger the note if pitched, set the target
  /// for tone-porta, load the volume for Cxx, and fill effect memory. Call once
  /// at tick 0.
  void armRow(TrackerCell cell) {
    _cmd = cell.fxCmd;
    _param = cell.fxParam;
    _retriggered = false;
    _pendingDelayTick = null;

    // EDx note delay: defer the trigger to tick x instead of triggering now.
    final noteDelay =
        _cmd == kFxExtended && _exSub == kExNoteDelay && cell.midi != null;

    if (noteDelay) {
      _pendingNote = cell.midi!.toDouble();
      _pendingNoteVolume = cell.volume ?? 1.0;
      _pendingDelayTick = _exVal;
    } else if (cell.midi != null) {
      final m = cell.midi!.toDouble();
      if (_isTonePorta) {
        targetPitch = m;
        if (!active) {
          pitch = m;
          active = true;
          _retriggered = true;
          noteVolume = cell.volume ?? 1.0;
          _vibPhase = 0;
          _tremPhase = 0;
        }
      } else {
        pitch = m;
        targetPitch = m;
        active = true;
        _retriggered = true;
        noteVolume = cell.volume ?? 1.0;
        _vibPhase = 0;
        _tremPhase = 0;
      }
    } else if (cell.volume != null) {
      // A volume-column-only cell (no note) sets the RINGING note's volume — a
      // mid-note change, like a set-volume, without re-triggering.
      noteVolume = cell.volume!;
    }

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

  /// Advance one tick [k] (0-based within the row) and return the effective
  /// (pitch, volume0to64) to synthesize this tick. [ticksPerRow] is the row's
  /// speed. Slide-type effects act on ticks 1.. (tick 0 holds), matching classic
  /// tracker behaviour; arpeggio and the LFOs act on every tick.
  ({double pitch, double volume, bool retrigger}) tick(int k, int ticksPerRow) {
    var retrigger = false;

    // EDx note delay: the deferred note triggers at its tick.
    if (_pendingDelayTick != null && k == _pendingDelayTick) {
      pitch = _pendingNote;
      targetPitch = _pendingNote;
      noteVolume = _pendingNoteVolume;
      active = true;
      retrigger = true;
      _vibPhase = 0;
      _tremPhase = 0;
      _pendingDelayTick = null;
    }

    var effPitch = pitch;
    var effVol = volume.toDouble();

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
      } else if (_exSub == kExNoteCut && k >= _exVal) {
        effVol = 0;
      }
    }

    // Rxy: retrigger every y ticks, changing volume by code x each time.
    if (_cmd == kFxRetrigVolSlide) {
      final y = _memRetrig & 0xF;
      if (y > 0 && k > 0 && k % y == 0) {
        retrigger = true;
        _vibPhase = 0;
        _tremPhase = 0;
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

    return (pitch: effPitch, volume: effVol, retrigger: retrigger);
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
  final rows = cells.length;
  var curInst = channelInstrument;
  var startStep = 0;
  for (final (midi, steps) in cellRuns(cells)) {
    final trigger = cells[startStep];
    if (trigger.instrument > 0 && trigger.instrument - 1 < pool.length) {
      curInst = pool[trigger.instrument - 1];
    }
    if (midi != null) {
      final capRow = startStep + steps;
      final one = List<TrackerCell>.filled(rows, TrackerCell.empty)
        ..[startStep] = trigger;
      if (capRow < rows) one[capRow] = TrackerCell(midi: midi); // cap the run
      final buf = curInst.renderChannel(one, timing);
      final s = timing.stepStartSample(startStep);
      final e =
          capRow < rows ? timing.stepStartSample(capRow) : timing.totalSamples;
      final lim = min(e, min(buf.length, stem.length));
      if (envelope == null) {
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
        cmd == kFxExtended) {
      return true;
    }
    if (cmd == kFxArpeggio && c.fxParam != 0) return true;
  }
  return false;
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

  for (var r = 0; r < rows; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      cur = pool[cellInst - 1];
    }
    voice.armRow(cells[r]);
    if (voice.retriggeredThisRow) {
      final c = cells[r];
      final os = cur is SampleInstrument ? cur.offsetScale : 1.0;
      readPos =
          c.fxCmd == kFxSampleOffset ? (c.fxParam * 256 * os).toDouble() : 0.0;
      noteStartSample = timing.stepStartSample(r);
    }
    if ((!voice.active && !voice.hasPendingNote) ||
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
    final loopEnd = loopStart + loopLen;
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
      if (!voice.active) continue;
      final ratio = pow(2.0, (state.pitch - baseMidi) / 12.0).toDouble();
      final vol = (state.volume / kMaxVolume) * voice.noteVolume;
      for (var i = ts; i < te && i < stem.length; i++) {
        // Forward loop wraps readPos in place (byte-identical); a ping-pong loop
        // keeps readPos monotonic and folds it into a bouncing read position.
        if (loops && !pingPong && readPos >= loopEnd) {
          readPos = loopStart + ((readPos - loopStart) % loopLen);
        }
        final src = loops && pingPong
            ? foldLoopPosition(readPos, loopStart, loopLen, pingPong: true)
            : readPos;
        final idx = src.floor();
        if (idx >= s.length - 1 && !loops) break; // one-shot: sample exhausted
        final frac = src - idx;
        final next =
            idx + 1 < s.length ? s[idx + 1] : (loops ? s[loopStart] : 0.0);
        final sampleVal = s[idx] * (1 - frac) + next * frac;
        final t = (i - noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final el = hasEnv ? env.levelAt(t * 1000) : 1.0;
        stem[i] += sampleVal * vol * attack * el;
        readPos += ratio;
      }
    }
  }

  var peak = 0.0;
  for (final v in stem) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) return;
  final scale = channel.gain / peak;
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
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  List<TrackerInstrument>? pool,
) {
  final env = channel.volumeEnvelope;
  final hasEnv = env != null && !env.isEmpty;
  const declickSec = 0.003;
  final rows = cells.length;
  final stem = Float64List(rowStart[rows]);
  var cur = channel.instrument is SampleInstrument ? channel.instrument : null;
  final voice = ReplayVoice();
  var readPos = 0.0;
  var noteStartSample = 0;

  for (var r = 0; r < rows; r++) {
    final cellInst = cells[r].instrument;
    if (cellInst > 0 &&
        pool != null &&
        cellInst - 1 < pool.length &&
        pool[cellInst - 1] is SampleInstrument) {
      cur = pool[cellInst - 1];
    }
    voice.armRow(cells[r]);
    if (voice.retriggeredThisRow) {
      final c = cells[r];
      final os = cur is SampleInstrument ? cur.offsetScale : 1.0;
      readPos =
          c.fxCmd == kFxSampleOffset ? (c.fxParam * 256 * os).toDouble() : 0.0;
      noteStartSample = rowStart[r];
    }
    if ((!voice.active && !voice.hasPendingNote) ||
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
    final loopEnd = loopStart + loopLen;
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
      if (!voice.active) continue;
      final ratio = pow(2.0, (state.pitch - baseMidi) / 12.0).toDouble();
      final vol = (state.volume / kMaxVolume) * voice.noteVolume;
      for (var i = ts; i < te && i < stem.length; i++) {
        // Forward loop wraps readPos in place (byte-identical); a ping-pong loop
        // keeps readPos monotonic and folds it into a bouncing read position.
        if (loops && !pingPong && readPos >= loopEnd) {
          readPos = loopStart + ((readPos - loopStart) % loopLen);
        }
        final src = loops && pingPong
            ? foldLoopPosition(readPos, loopStart, loopLen, pingPong: true)
            : readPos;
        final idx = src.floor();
        if (idx >= s.length - 1 && !loops) break; // one-shot: sample exhausted
        final frac = src - idx;
        final next =
            idx + 1 < s.length ? s[idx + 1] : (loops ? s[loopStart] : 0.0);
        final sampleVal = s[idx] * (1 - frac) + next * frac;
        final t = (i - noteStartSample) / kSampleRate;
        final attack = t < declickSec ? t / declickSec : 1.0;
        final el = hasEnv ? env.levelAt(t * 1000) : 1.0;
        stem[i] += sampleVal * vol * attack * el;
        readPos += ratio;
      }
    }
  }

  var peak = 0.0;
  for (final v in stem) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) return;
  final scale = channel.gain / peak;
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

  final inst = _additiveOf(channel.instrument);
  if (inst == null) {
    // A SAMPLE channel that carries per-tick pitch/volume effects (porta/
    // vibrato/tremolo/Cxx/Axy/arp/extended) renders through the sample TICK
    // voice so those effects actually SOUND (the whole-channel render can't do
    // per-tick modulation). Effect-free sample channels — and sfxr/percussion —
    // keep the unchanged non-additive render below (byte-identical).
    if (channel.instrument is SampleInstrument && _hasPerTickEffect(cells)) {
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
    final scale = channel.gain / peak;
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

/// Converts a Float64 mix to PCM16 with the same tanh soft-knee as [mixStems].
Int16List _mixToPcm(Float64List mix) {
  final out = Int16List(mix.length);
  for (var i = 0; i < mix.length; i++) {
    out[i] = (_tanh(mix[i]) * 0.95 * 32767).round();
  }
  return out;
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
Int16List _interleaveToPcm(Float64List left, Float64List right) {
  final out = Int16List(left.length * 2);
  for (var i = 0; i < left.length; i++) {
    out[i * 2] = (_tanh(left[i]) * 0.95 * 32767).round();
    out[i * 2 + 1] = (_tanh(right[i]) * 0.95 * 32767).round();
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
  int totalSamples,
) {
  final regions = <({int start, int end, double pan})>[];
  var pan = basePan;
  var regionStart = 0;
  for (var r = 0; r < cells.length; r++) {
    final c = cells[r];
    if (c.fxCmd == kFxSetPan) {
      final newPan = _panFromParam(c.fxParam);
      if (newPan != pan) {
        final s = timing.stepStartSample(r);
        if (s > regionStart) {
          regions.add((start: regionStart, end: s, pan: pan));
        }
        regionStart = s;
        pan = newPan;
      }
    }
  }
  regions.add((start: regionStart, end: totalSamples, pan: pan));
  return regions;
}

/// Renders one channel's [cells] mono (via [_renderChannelInto]) then pans it
/// into the [left]/[right] stereo mixes at [sampleOffset], honouring the
/// channel's base pan and any 8xx pan changes ([_panRegions]).
void _renderChannelIntoStereo(
  Float64List left,
  Float64List right,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset, {
  List<TrackerInstrument>? pool,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;
  final total = timing.totalSamples;
  final mono = Float64List(total);
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

  for (final reg in _panRegions(channel.pan, cells, timing, total)) {
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
  return ReplayResult(_mixToPcm(mix), const [RowTiming(0, 0, 0, 0)]);
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

/// Whether any cell in [song] carries an `Fxx` speed/tempo command at all — a
/// cheap pre-filter so the common command-free/single-tempo song never pays for
/// the [walkFlow] scan in [songUsesVariableTiming].
bool _songHasFxx(TrackerSong song) => song.patterns.any(
      (p) => p.cells.any((col) => col.any((c) => c.fxCmd == kFxSetSpeed)),
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
  if (!_songHasFxx(song)) return false;
  final played = walkFlow(song);
  if (played.length < 2) return false;
  final tempo0 = played.first.tempoBpm;
  final speed0 = played.first.ticksPerRow;
  for (final p in played) {
    if (p.tempoBpm != tempo0 || p.ticksPerRow != speed0) return true;
  }
  return false;
}

/// The step (row) duration in ms at [tempoBpm], matching [TrackerTiming.stepMs]
/// for the same tempo — the per-row timebase of the variable render.
int _stepMsForTempo(int tempoBpm, int stepsPerBeat) =>
    (60000 / tempoBpm) ~/ stepsPerBeat;

/// The wall-clock duration (ms) of a played row, honouring BOTH its tempo and
/// its SPEED (ticks/row). In a real tracker a row lasts `speed × tickDuration`;
/// our musical grid pins the INITIAL speed [speed0] to the tempo-derived step,
/// so a later speed change scales the row proportionally (`ticks/speed0`) —
/// matching openmpt's relative behaviour. Speed == speed0 ⇒ the plain tempo step
/// (byte-identical to before for tempo-only changes).
int _rowMsFor(int tempoBpm, int stepsPerBeat, int ticks, int speed0) {
  final base = _stepMsForTempo(tempoBpm, stepsPerBeat);
  if (speed0 <= 0 || ticks <= 0 || ticks == speed0) return base;
  return (base * ticks / speed0).round();
}

/// The accumulated onset (ms) of each played row, honouring per-row tempo. Entry
/// `i` is the ms offset where played row `i` begins; the sum of all step
/// durations is the song length ([variableSongTotalMs]).
List<int> _variableRowStartMs(TrackerSong song, List<PlayedRow> played) {
  final spb = song.timing.stepsPerBeat;
  final def = song.timing.tempoBpm;
  final speed0 =
      played.isEmpty ? kDefaultTicksPerRow : played.first.ticksPerRow;
  final starts = List<int>.filled(played.length, 0);
  var acc = 0;
  for (var i = 0; i < played.length; i++) {
    starts[i] = acc;
    acc += _rowMsFor(
      played[i].tempoBpm > 0 ? played[i].tempoBpm : def,
      spb,
      played[i].ticksPerRow,
      speed0,
    );
  }
  return starts;
}

/// The total song length (ms) as the SUM of per-row durations under a mid-song
/// tempo change — used by [TrackerSong.songTotalMs] when [songUsesVariableTiming].
int variableSongTotalMs(TrackerSong song) {
  final played = walkFlow(song);
  final spb = song.timing.stepsPerBeat;
  final def = song.timing.tempoBpm;
  final speed0 =
      played.isEmpty ? kDefaultTicksPerRow : played.first.ticksPerRow;
  var ms = 0;
  for (final p in played) {
    ms += _rowMsFor(
      p.tempoBpm > 0 ? p.tempoBpm : def,
      spb,
      p.ticksPerRow,
      speed0,
    );
  }
  return ms;
}

/// Expands [song]'s order/pattern/row walk under the flow rules (Bxx jump, Dxx
/// break, E6x pattern loop) into the flat sequence of rows actually played. Bxx
/// wins the order, Dxx sets the landing row; both on one row ⇒ jump order + break
/// row. E60 marks a loop start, E6x (x>0) repeats the marked span x extra times.
/// Guarded by [maxRows] so a backward loop terminates (documented cap, not an
/// error).
List<PlayedRow> walkFlow(TrackerSong song, {int maxRows = 4096}) {
  final order = song.order;
  final played = <PlayedRow>[];
  var oi = 0;
  var row = 0;
  var loopStartRow = 0; // E6x pattern-loop start (defaults to row 0)
  var loopCount = 0; // remaining E6x repeats
  // Fxx state carried across rows: speed (ticks/row) + tempo (BPM). A value takes
  // effect ON its own row and persists until the next Fxx of that kind.
  var curSpeed = kDefaultTicksPerRow;
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

    // Apply any Fxx on this row BEFORE recording it (effect is on its own row):
    // param < 0x20 → speed (min 1); param >= 0x20 → tempo (BPM). (Feature A)
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxSetSpeed) {
        if (c.fxParam >= 0x20) {
          curTempo = c.fxParam;
        } else if (c.fxParam > 0) {
          curSpeed = c.fxParam; // already >= 1
        }
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

    if (jumpToOrder != null) {
      oi = jumpToOrder;
      row = breakToRow ?? 0;
    } else if (breakToRow != null) {
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
/// granularity. The INITIAL speed subdivides the row (effect granularity) and is
/// pinned to the tempo-derived grid step, so it alone doesn't change the song
/// length. A MID-SONG speed CHANGE, however, scales that row's duration relative
/// to the initial speed (see [_rowMsFor]) — matching real trackers/openmpt.
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
}) {
  song.syncCurrent();
  // A MID-SONG tempo/speed change needs per-row durations — render that first
  // (it also expands flow via [walkFlow], so it subsumes flow+variable songs).
  if (songUsesVariableTiming(song)) return _replayVariable(song);
  // An Fxx set-speed command overrides the default ticks/row (effect
  // granularity); timing-safe (speed subdivides the row, not its duration).
  final ticks = songInitialSpeed(song, fallback: ticksPerRow);
  // Flow OR variable-length patterns both flatten the played sequence.
  if (songNeedsWalkRender(song)) return _replayFlow(song, ticks);

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
  return ReplayResult(_mixToPcm(mix), timingMap);
}

/// The stereo sibling of [replaySong]: same order walk / flow expansion, but each
/// channel is panned (per-channel [TrackerChannel.pan] + 8xx) into an INTERLEAVED
/// stereo mix. [ReplayResult.pcm] is interleaved L,R — wrap with [wavBytesStereo].
ReplayResult replaySongStereo(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  song.syncCurrent();
  final ticks = songInitialSpeed(song, fallback: ticksPerRow);
  // Mirror the mono replaySong routing: mid-song tempo/speed → the per-row
  // stereo render; flow OR variable-length → the flattened stereo render.
  if (songUsesVariableTiming(song)) return _replayVariableStereo(song);
  if (songNeedsWalkRender(song)) return _replayFlowStereo(song, ticks);

  final timing = effectiveTiming(song);
  final channels = song.channels;
  final order = song.order;
  final patternSamples = timing.totalSamples;
  final left = Float64List(patternSamples * order.length);
  final right = Float64List(patternSamples * order.length);
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
      _renderChannelIntoStereo(
        left,
        right,
        channels[c],
        cells[c],
        timing,
        ticks,
        sampleOffset,
        pool: song.instruments,
      );
    }
  }
  return ReplayResult(_interleaveToPcm(left, right), timingMap);
}

/// The flow render: expand the order via [walkFlow], flatten the played rows into
/// one long column per channel, and render that flattened song. Voice state
/// (porta/vibrato/oscillator phase) stays continuous across the flat rows, and
/// non-additive voices trigger at their flattened positions, so both stay
/// aligned with the reordered timeline.
ReplayResult _replayFlow(TrackerSong song, int ticksPerRow) {
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

  final timingMap = [
    for (var i = 0; i < played.length; i++)
      RowTiming(
        flatTiming.stepOnsetMs(i).round(),
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return ReplayResult(_mixToPcm(mix), timingMap);
}

/// The stereo sibling of [_replayFlow]: flatten the played rows then pan each
/// channel (per-channel [TrackerChannel.pan] + 8xx) into an interleaved mix.
ReplayResult _replayFlowStereo(TrackerSong song, int ticksPerRow) {
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
  final timingMap = [
    for (var i = 0; i < played.length; i++)
      RowTiming(
        flatTiming.stepOnsetMs(i).round(),
        played[i].orderIndex,
        played[i].patternIndex,
        played[i].row,
      ),
  ];
  return ReplayResult(_interleaveToPcm(left, right), timingMap);
}

// --- Variable-timing render (mid-song tempo/speed changes) -------------------

/// The mid-song-timing render: expand the order via [walkFlow] (which annotates
/// every played row with the tempo/speed in effect), lay the rows back-to-back
/// at accumulated sample offsets whose lengths follow each row's OWN tempo, and
/// render each channel across those variable boundaries. Additive voices use each
/// row's [PlayedRow.ticksPerRow] for tick granularity; non-additive voices are
/// placed per note over their run's summed duration. The row-timing map + length
/// use the ms-summed onsets so [TrackerSong.songTotalMs] and the transport agree.
ReplayResult _replayVariable(TrackerSong song) {
  final played = walkFlow(song);
  final channels = song.channels;
  final spb = song.timing.stepsPerBeat;
  final def = song.timing.tempoBpm;
  final n = played.length;

  // Per-row sample boundaries: rowStart[i]..rowStart[i+1] is played row i.
  final speed0 =
      played.isEmpty ? kDefaultTicksPerRow : played.first.ticksPerRow;
  final rowStart = List<int>.filled(n + 1, 0);
  final ticks = List<int>.filled(n, kDefaultTicksPerRow);
  var acc = 0;
  for (var i = 0; i < n; i++) {
    rowStart[i] = acc;
    ticks[i] = played[i].ticksPerRow;
    final tempo = played[i].tempoBpm > 0 ? played[i].tempoBpm : def;
    final stepMs = _rowMsFor(tempo, spb, played[i].ticksPerRow, speed0);
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
      spb,
      pool: song.instruments,
    );
  }

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
  return ReplayResult(_mixToPcm(mix), timingMap);
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
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  List<int> rowStart,
  List<int> ticksPerRow,
  int stepsPerBeat, {
  List<TrackerInstrument>? pool,
}) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;
  final rows = cells.length;

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
  Float64List mix,
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
  for (final (midi, steps) in cellRuns(cells)) {
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
            TrackerTiming(tempoBpm: tempo, rows: 1, stepsPerBeat: 1);
        final buf = curInst.renderChannel([trigger], noteTiming);
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
  final scale = channel.gain / peak;
  final n = min(stem.length, mix.length);
  for (var i = 0; i < n; i++) {
    mix[i] += stem[i] * scale;
  }
}

/// The stereo sibling of [_replayVariable]: the mid-song per-row-duration render,
/// each channel panned (base pan + 8xx) into an interleaved mix — so a PANNED
/// song with a mid-song tempo/speed change stays in sync (length matches
/// [variableSongTotalMs]). Each channel is rendered mono over the variable
/// boundaries then split L/R, exactly like [_renderChannelIntoStereo] does for
/// the uniform case.
ReplayResult _replayVariableStereo(TrackerSong song) {
  final played = walkFlow(song);
  final channels = song.channels;
  final spb = song.timing.stepsPerBeat;
  final def = song.timing.tempoBpm;
  final n = played.length;

  final speed0 =
      played.isEmpty ? kDefaultTicksPerRow : played.first.ticksPerRow;
  final rowStart = List<int>.filled(n + 1, 0);
  final ticks = List<int>.filled(n, kDefaultTicksPerRow);
  var acc = 0;
  for (var i = 0; i < n; i++) {
    rowStart[i] = acc;
    ticks[i] = played[i].ticksPerRow;
    final tempo = played[i].tempoBpm > 0 ? played[i].tempoBpm : def;
    acc += (_rowMsFor(tempo, spb, played[i].ticksPerRow, speed0) *
            kSampleRate /
            1000)
        .round();
  }
  rowStart[n] = acc;

  final left = Float64List(acc);
  final right = Float64List(acc);
  for (var c = 0; c < channels.length; c++) {
    final flatCells = [
      for (final pr in played) song.patterns[pr.patternIndex].cells[c][pr.row],
    ];
    final mono = Float64List(acc);
    _renderChannelIntoVariable(
      mono,
      channels[c],
      flatCells,
      rowStart,
      ticks,
      spb,
      pool: song.instruments,
    );
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
      for (final reg
          in _panRegionsVariable(channels[c].pan, flatCells, rowStart)) {
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
  return ReplayResult(_interleaveToPcm(left, right), timingMap);
}

/// Variable-timing pan regions: like [_panRegions] but 8xx boundaries come from
/// the per-row sample offsets [rowStart] (the flattened length is `rowStart.last`).
List<({int start, int end, double pan})> _panRegionsVariable(
  double basePan,
  List<TrackerCell> cells,
  List<int> rowStart,
) {
  final total = rowStart.last;
  final regions = <({int start, int end, double pan})>[];
  var pan = basePan;
  var regionStart = 0;
  for (var r = 0; r < cells.length && r < rowStart.length - 1; r++) {
    final c = cells[r];
    if (c.fxCmd == kFxSetPan) {
      final newPan = _panFromParam(c.fxParam);
      if (newPan != pan) {
        final s = rowStart[r];
        if (s > regionStart) {
          regions.add((start: regionStart, end: s, pan: pan));
        }
        regionStart = s;
        pan = newPan;
      }
    }
  }
  regions.add((start: regionStart, end: total, pan: pan));
  return regions;
}
