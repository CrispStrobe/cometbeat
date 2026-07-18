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
// sequence. Implemented too: Exy extended — E1x/E2x fine porta, E9x retrigger,
// EAx/EBx fine volume, ECx note cut, EDx note delay (per-tick, in ReplayVoice) +
// E6x pattern loop (a row-level flow, in walkFlow). Fxx SET-SPEED (first Fxx
// param <0x20 → ticks/row, [songInitialSpeed]) AND SET-TEMPO (first Fxx param
// ≥0x20 → BPM, [songInitialTempo]/[effectiveTiming]) too: both are applied
// UNIFORMLY to the whole render (the value a module sets at the top), so timing
// stays uniform and songTotalMs matches. Still TODO: MID-SONG speed/tempo
// CHANGES (need per-row row-duration timing), 9xx sample-offset.
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
      case kFxVibratoVolSlide:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memVibSpeed = x;
        if (y != 0) _memVibDepth = y;
        if (_cmd == kFxVibratoVolSlide && _param != 0) _memVolSlide = _param;
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

    // Tone porta: slide toward the target, never overshoot.
    if (_isTonePorta && k > 0) {
      final step = _memTonePorta * kPortaSemitonesPerUnit;
      if (pitch < targetPitch) {
        pitch = min(targetPitch, pitch + step);
      } else if (pitch > targetPitch) {
        pitch = max(targetPitch, pitch - step);
      }
      effPitch = pitch;
    }

    // Vibrato: zero-mean sine on pitch; phase advances each tick.
    if (_isVibrato) {
      final depth = _memVibDepth * kVibratoDepthSemitonesPerUnit;
      effPitch = pitch + depth * sin(_vibPhase);
      _vibPhase += _memVibSpeed * kVibratoRadPerSpeedUnit;
    }

    // Tremolo: zero-mean sine on volume; phase advances each tick.
    if (_cmd == kFxTremolo) {
      final depth = _memTremDepth * kTremoloDepthPerUnit;
      effVol = (volume + depth * sin(_tremPhase)).clamp(0.0, kMaxVolume + 0.0);
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

/// Whether [instrument] is an additive voice the replayer synthesizes tick-wise.
Instrument? _additiveOf(TrackerInstrument instrument) =>
    instrument is AdditiveInstrument ? instrument.instrument : null;

/// Renders one channel's [cells] into [mix] starting at [sampleOffset]. Additive
/// voices synthesize per tick (honouring commands); other instruments fall back
/// to the offline whole-channel render (unit-peak × gain), so they still sound.
void _renderChannelInto(
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset,
) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;

  final inst = _additiveOf(channel.instrument);
  if (inst == null) {
    // Non-additive: offline render, unit-peak, × gain, summed at true amplitude.
    final stem = channel.instrument.renderChannel(cells, timing);
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

  final timbre = timbreFor(inst);
  final harmonics = timbre.harmonics;
  final attackSec = timbre.attackMs / 1000;
  final decay = timbre.decay;
  var harmNorm = 0.0;
  for (final h in harmonics) {
    harmNorm += h.abs();
  }
  if (harmNorm == 0) harmNorm = 1;
  final gain = channel.gain;

  final voice = ReplayVoice();
  final rows = cells.length;
  for (var r = 0; r < rows; r++) {
    voice.armRow(cells[r]);
    if (voice.startsNoteThisRow) {
      if (voice.retriggeredThisRow) voice.oscPhase = 0;
      voice.noteStartSample = sampleOffset + timing.stepStartSample(r);
      final runEnd = _nextTriggerRow(cells, r);
      final endSample =
          runEnd < rows ? timing.stepStartSample(runEnd) : timing.totalSamples;
      final runSamples = endSample - timing.stepStartSample(r);
      voice.noteSeconds = runSamples > 0 ? runSamples / kSampleRate : 0.001;
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
      // A retrigger (E9x) or a delayed note (EDx) restarts the envelope here.
      if (state.retrigger) {
        voice.oscPhase = 0;
        voice.noteStartSample = ts;
      }
      if (!voice.active) continue; // pre-delay silence / never triggered
      final freq = _freqOfMidi(state.pitch);
      final volScale = (state.volume / kMaxVolume) * voice.noteVolume * gain;
      final phaseInc = 2 * pi * freq / kSampleRate;
      for (var i = ts; i < te && i < mix.length; i++) {
        final t = (i - voice.noteStartSample) / kSampleRate;
        if (t < 0) continue;
        final attack = t < attackSec ? t / attackSec : 1.0;
        final env = attack * exp(-decay * t / voice.noteSeconds);
        var sample = 0.0;
        for (var h = 0; h < harmonics.length; h++) {
          sample += harmonics[h] * sin(voice.oscPhase * (h + 1));
        }
        mix[i] += (sample / harmNorm) * env * volScale;
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

/// Replays a single pattern ([cells] per channel of [channels]) at [timing],
/// returning the mixed PCM16. Used for the current-pattern preview.
ReplayResult replayPattern(
  List<TrackerChannel> channels,
  List<List<TrackerCell>> cells,
  TrackerTiming timing, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final speed = _firstFxx(cells, timing.rows, wantTempo: false);
  final ticks = speed > 0 ? speed : ticksPerRow;
  final mix = Float64List(timing.totalSamples);
  for (var c = 0; c < channels.length && c < cells.length; c++) {
    _renderChannelInto(mix, channels[c], cells[c], timing, ticks, 0);
  }
  return ReplayResult(_mixToPcm(mix), const [RowTiming(0, 0, 0, 0)]);
}

// --- Flow (phase 3): Bxx position jump + Dxx pattern break -------------------

/// One row actually played, in playback order — the output of [walkFlow].
class PlayedRow {
  const PlayedRow(this.orderIndex, this.patternIndex, this.row);

  final int orderIndex;
  final int patternIndex;
  final int row;

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
                  ((c.fxParam >> 4) & 0xF) == kExPatternLoop),
        ),
      ),
    );

/// Expands [song]'s order/pattern/row walk under the flow rules (Bxx jump, Dxx
/// break, E6x pattern loop) into the flat sequence of rows actually played. Bxx
/// wins the order, Dxx sets the landing row; both on one row ⇒ jump order + break
/// row. E60 marks a loop start, E6x (x>0) repeats the marked span x extra times.
/// Guarded by [maxRows] so a backward loop terminates (documented cap, not an
/// error).
List<PlayedRow> walkFlow(TrackerSong song, {int maxRows = 4096}) {
  final order = song.order;
  final rows = song.timing.rows;
  final played = <PlayedRow>[];
  var oi = 0;
  var row = 0;
  var loopStartRow = 0; // E6x pattern-loop start (defaults to row 0)
  var loopCount = 0; // remaining E6x repeats
  while (oi >= 0 && oi < order.length && played.length < maxRows) {
    final patternIndex = order[oi];
    final cells = song.patterns[patternIndex].cells;
    if (row < 0 || row >= rows) row = 0;
    played.add(PlayedRow(oi, patternIndex, row));

    // Scan the row across channels for flow commands (first of each wins).
    int? jumpToOrder;
    int? breakToRow;
    int? loopValue; // E6x low nibble (0 = set the loop start)
    for (final col in cells) {
      final c = col[row];
      if (c.fxCmd == kFxPositionJump) {
        jumpToOrder ??= c.fxParam;
      } else if (c.fxCmd == kFxPatternBreak) {
        breakToRow ??=
            ((c.fxParam >> 4) * 10 + (c.fxParam & 0xF)).clamp(0, rows - 1);
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
/// granularity. (Speed subdivides the row — it does NOT change row duration in
/// our musical-timing model, so it never affects the song length.)
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
  final timing = effectiveTiming(song); // match the render's Fxx set-tempo
  if (songUsesFlow(song)) {
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
  // An Fxx set-speed command overrides the default ticks/row (effect
  // granularity); timing-safe (speed subdivides the row, not its duration).
  final ticks = songInitialSpeed(song, fallback: ticksPerRow);
  if (songUsesFlow(song)) return _replayFlow(song, ticks);

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
      );
    }
  }
  return ReplayResult(_mixToPcm(mix), timingMap);
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
    _renderChannelInto(mix, channels[c], flatCells, flatTiming, ticksPerRow, 0);
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
