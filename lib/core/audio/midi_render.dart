// Event-accurate MIDI → stereo audio through a SoundFont — the faithful-MIDI
// path the notation route (scoreFromMidi → quantized Score) can't be. Instead of
// snapping to a 16th grid, this schedules every message on a SAMPLE clock and
// voices each note by RESAMPLING its SF2 zone directly (a real synth voice, not
// a fixed-pitch sample trigger), so it does:
//   • exact event timing (swing, groove, off-grid tuplets, human micro-timing)
//   • a tempo MAP (accel/rit), not just the first tempo
//   • per-channel program + bank select, with mid-song program changes
//   • note velocity, CC7 volume, CC11 expression, CC10 pan
//   • sustain pedal (CC64): a note held past its note-off until the pedal lifts
//   • channel 10 → the bank-128 drum kit
//   • continuous PITCH BEND (glides mid-note); RPN 0 sets the range
//   • the zone's SF2 volume envelope (DAHDSR), low-pass filter (cutoff/Q), and
//     LFOs (vibrato + tremolo) — plus CC1 mod-wheel vibrato on top
//   • the zone's loop region for sustain + its tuning/attenuation
//
// Pure Dart, Flutter-free (crisp_notation_core split helper + the SF2 loader).

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart'
    show Biquad, BiquadKind;
import 'package:comet_beat/core/audio/sf2/sf2.dart'
    show Sf2Preset, Sf2SoundFont, Sf2Zone;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show splitMultiTrackMidi;

const double _maxTailSec = 3; // cap a note's release tail (buffer headroom)
const double _bendRangeSemis = 2; // GM default (RPN 0 not yet read)
const double _vibratoRateHz = 5.5;
const double _vibratoMaxCents = 50; // at full mod wheel
const double _vibratoOnsetSec = 0.25;

/// A decoded MIDI channel event at an absolute tick (tempo/meta carried too).
class _Evt {
  _Evt(this.tick, this.kind, this.channel, this.d1, this.d2);
  final int tick;
  final int kind; // 0x80/0x90/0xB0/0xC0/0xE0, or 0x51 for a tempo meta
  final int channel;
  final int d1;
  final int d2;
}

/// A note-on awaiting its off, with the controller state captured at onset.
class _Pending {
  _Pending(
    this.startTick,
    this.vel,
    this.gain,
    this.pan,
    this.modCents,
    this.bank,
    this.program,
  );
  final int startTick;
  final int vel;
  final double gain; // CC7 × CC11
  final double pan; // −1..1
  final double modCents; // vibrato depth from CC1 at onset
  final int bank;
  final int program;
}

/// A resolved sounding note.
class _Note {
  _Note(
    this.startSample,
    this.endSample,
    this.key,
    this.channel,
    this.gain,
    this.velNorm,
    this.pan,
    this.modCents,
    this.bank,
    this.program,
    this.isDrum,
  );
  final int startSample;
  final int endSample;
  final int key;
  final int channel;
  final double gain; // velocity × CC7 × CC11
  final double velNorm; // velocity / 127 (filter cutoff)
  final double pan; // −1..1
  final double modCents; // vibrato depth
  final int bank;
  final int program;
  final bool isDrum;
}

/// Render [smf] through [font] to a stereo (left, right) pair, scheduling every
/// event on a sample clock. Empty in → empty out.
(Float64List left, Float64List right) renderMidiFile(
  Uint8List smf,
  LoadedSoundFont font, {
  int sampleRate = kSampleRate,
}) {
  final (events, tpq) = _parseAllEvents(smf);
  if (events.isEmpty || tpq <= 0) return (Float64List(0), Float64List(0));

  // Tick → sample, honouring the tempo map.
  final tempoTicks = <int>[0];
  final tempoUs = <int>[500000];
  for (final e in events) {
    if (e.kind == 0x51) {
      if (e.tick == tempoTicks.last) {
        tempoUs[tempoUs.length - 1] = e.d2;
      } else {
        tempoTicks.add(e.tick);
        tempoUs.add(e.d2);
      }
    }
  }
  double sampleAt(int tick) {
    var acc = 0.0;
    for (var i = 0; i < tempoTicks.length; i++) {
      final segStart = tempoTicks[i];
      final segEnd = i + 1 < tempoTicks.length ? tempoTicks[i + 1] : 1 << 62;
      if (tick <= segStart) break;
      final upto = tick < segEnd ? tick : segEnd;
      acc += (upto - segStart) * (tempoUs[i] / 1000000 / tpq) * sampleRate;
      if (tick < segEnd) break;
    }
    return acc;
  }

  final program = List<int>.filled(16, 0);
  final bank = List<int>.filled(16, 0);
  final volume = List<double>.filled(16, 100 / 127);
  final expression = List<double>.filled(16, 1.0);
  final pan = List<double>.filled(16, 0.0);
  final sustain = List<bool>.filled(16, false);
  final modCents = List<double>.filled(16, 0.0); // CC1 → vibrato depth
  // Pitch-bend range (RPN 0), default ±2 st; RPN select + data-entry state.
  final bendRange = List<double>.filled(16, _bendRangeSemis);
  final rpnMsb = List<int>.filled(16, 127);
  final rpnLsb = List<int>.filled(16, 127);
  // Per-channel pitch-bend curve: (absolute sample, semitones), time-ordered.
  final bendByChannel = List.generate(16, (_) => <(int, double)>[]);

  final pending = <int, List<_Pending>>{};
  final pedalHeld = <int, List<_Pending>>{};
  final notes = <_Note>[];
  var lastTick = 0;

  void finalize(int ch, int key, int endTick, _Pending p) {
    final s = sampleAt(p.startTick).round();
    final e = sampleAt(endTick).round();
    if (e <= s) return;
    final vn = p.vel / 127.0;
    final note = _Note(
      s,
      e,
      key,
      ch,
      p.gain * vn,
      vn,
      p.pan,
      p.modCents,
      p.bank,
      p.program,
      ch == 9,
    );
    notes.add(note);
  }

  void release(int ch, int key, int tick) {
    final q = pending[ch << 8 | key];
    if (q == null || q.isEmpty) return;
    final p = q.removeAt(0);
    if (sustain[ch]) {
      (pedalHeld[ch << 8 | key] ??= []).add(p);
    } else {
      finalize(ch, key, tick, p);
    }
  }

  void liftPedal(int ch, int tick) {
    for (final k in pedalHeld.keys.where((k) => k >> 8 == ch).toList()) {
      for (final p in pedalHeld.remove(k)!) {
        finalize(ch, k & 0xff, tick, p);
      }
    }
  }

  for (final ev in events) {
    lastTick = ev.tick;
    final ch = ev.channel;
    switch (ev.kind) {
      case 0x90:
        if (ev.d2 > 0) {
          (pending[ch << 8 | ev.d1] ??= []).add(
            _Pending(
              ev.tick,
              ev.d2,
              volume[ch] * expression[ch],
              pan[ch],
              modCents[ch],
              bank[ch],
              program[ch],
            ),
          );
        } else {
          release(ch, ev.d1, ev.tick);
        }
      case 0x80:
        release(ch, ev.d1, ev.tick);
      case 0xB0:
        switch (ev.d1) {
          case 1:
            modCents[ch] = ev.d2 / 127.0 * _vibratoMaxCents;
          case 7:
            volume[ch] = ev.d2 / 127.0;
          case 11:
            expression[ch] = ev.d2 / 127.0;
          case 10:
            pan[ch] = (ev.d2 - 64) / 64.0;
          case 0:
            bank[ch] = ev.d2;
          case 64:
            final down = ev.d2 >= 64;
            if (!down) liftPedal(ch, ev.tick);
            sustain[ch] = down;
          case 101:
            rpnMsb[ch] = ev.d2;
          case 100:
            rpnLsb[ch] = ev.d2;
          case 6: // data-entry MSB: RPN 0 → bend range in semitones
            if (rpnMsb[ch] == 0 && rpnLsb[ch] == 0) {
              bendRange[ch] = ev.d2.toDouble();
            }
          case 38: // data-entry LSB: RPN 0 → the cents part of the range
            if (rpnMsb[ch] == 0 && rpnLsb[ch] == 0) {
              bendRange[ch] = bendRange[ch].truncateToDouble() + ev.d2 / 100.0;
            }
        }
      case 0xC0:
        program[ch] = ev.d1;
      case 0xE0:
        final value = (ev.d2 << 7) | ev.d1; // 0..16383, 8192 = centre
        final semis = (value - 8192) / 8192.0 * bendRange[ch];
        bendByChannel[ch].add((sampleAt(ev.tick).round(), semis));
    }
  }

  // Flush anything still sounding.
  final endTick = lastTick + tpq;
  for (final entry in pending.entries) {
    for (final p in entry.value) {
      finalize(entry.key >> 8, entry.key & 0xff, endTick, p);
    }
  }
  for (final entry in pedalHeld.entries) {
    for (final p in entry.value) {
      finalize(entry.key >> 8, entry.key & 0xff, endTick, p);
    }
  }

  // Render each note by resampling its zone. Leave room for the longest
  // possible release tail after the last note-off.
  var maxLen = 0;
  final tail = (_maxTailSec * sampleRate).round();
  for (final n in notes) {
    if (n.endSample + tail > maxLen) maxLen = n.endSample + tail;
  }
  final left = Float64List(maxLen);
  final right = Float64List(maxLen);
  final presetCache = <String, Sf2Preset?>{};

  for (final n in notes) {
    final preset = _presetFor(font, n, presetCache);
    if (preset == null) continue;
    _resampleNote(
      font.font,
      preset,
      n,
      bendByChannel[n.channel],
      left,
      right,
      sampleRate,
    );
  }
  return (left, right);
}

Sf2Preset? _presetFor(
  LoadedSoundFont font,
  _Note n,
  Map<String, Sf2Preset?> cache,
) {
  final bank = n.isDrum ? 128 : n.bank;
  final key = '$bank/${n.program}';
  return cache.putIfAbsent(
    key,
    () =>
        findPreset(font, bank, n.program) ??
        findPreset(font, 0, n.program) ??
        (font.presets.isEmpty ? null : font.presets.first),
  );
}

/// Resample the note's zone into [left]/[right] at its start, with continuous
/// pitch bend, mod-wheel vibrato, loop-sustain, a release tail, a velocity
/// low-pass, and constant-power pan.
void _resampleNote(
  Sf2SoundFont font,
  Sf2Preset preset,
  _Note n,
  List<(int, double)> bendCurve,
  Float64List left,
  Float64List right,
  int sr,
) {
  final vel = (n.velNorm * 127).round();
  Sf2Zone? zone;
  for (final z in preset.zones) {
    if (z.coversKeyVel(n.key, vel)) {
      zone = z;
      break;
    }
  }
  zone ??= preset.zones.isEmpty ? null : preset.zones.first;
  if (zone == null) return;
  final sample = font.sampleAt(zone.sampleIndex);
  if (sample == null || sample.pcm.isEmpty) return;

  final pcm = sample.pcm;
  final len = pcm.length;
  final root = zone.rootKey >= 0 ? zone.rootKey : sample.originalPitch;
  final baseRatio = sample.sampleRate / sr;
  // Fixed pitch offset (semitones) for this key: key vs root + zone/sample tune.
  final semisFixed = (n.key - root + zone.coarseTune) +
      (zone.fineTune + sample.pitchCorrection) / 100.0;

  final loop = sample.loops && !n.isDrum;
  final loopStart = sample.loopStart.toDouble();
  final loopEnd = sample.loopEnd.toDouble();

  final durSamples = n.endSample - n.startSample;

  // SF2 volume envelope (DAHDSR), in samples, with small click-avoiding floors.
  // The default gens (−12000 tc ≈ 1 ms, sustain full) behave like a gate, so a
  // font without an envelope is close to the old behaviour; a font WITH one
  // (a piano's decay, a pad's swell) now plays as designed.
  final delayS = (zone.delayVolSec * sr).round();
  final attackS =
      math.max((zone.attackVolSec * sr).round(), (0.002 * sr).round());
  final holdS = (zone.holdVolSec * sr).round();
  final decayS = math.max((zone.decayVolSec * sr).round(), 1);
  final sus = zone.sustainGain;
  final releaseS = math
      .max((zone.releaseVolSec * sr).round(), (0.006 * sr).round())
      .clamp(1, (_maxTailSec * sr).round());
  final total = durSamples + releaseS;

  // The envelope value during attack→sustain (pre note-off).
  double preRelease(int i) {
    if (i < delayS) return 0;
    var t = i - delayS;
    if (t < attackS) return t / attackS; // linear attack 0→1
    t -= attackS;
    if (t < holdS) return 1; // hold at peak
    t -= holdS;
    if (t < decayS) {
      return math.exp(t / decayS * math.log(math.max(sus, 1e-4))); // 1→sustain
    }
    return sus;
  }

  final offLevel = preRelease(durSamples); // level when note-off begins release

  final theta = (n.pan.clamp(-1.0, 1.0) + 1) * 0.25 * math.pi;
  final lg = math.cos(theta);
  final rg = math.sin(theta);
  final baseGain = n.gain * zone.gain;

  // SF2 2-pole resonant low-pass at the zone's own cutoff/Q. The SF2 default
  // velocity→filter modulator darkens soft notes (−2400 cents at velocity 0).
  final velCents = (n.velNorm - 1) * 2400;
  final cutoffHz = (zone.filterCutoffHz * math.pow(2, velCents / 1200))
      .clamp(20.0, sr / 2 - 1)
      .toDouble();
  final filter = Biquad(
    BiquadKind.lowpass,
    freq: cutoffHz,
    sampleRate: sr.toDouble(),
    q: zone.filterQ,
  );

  final vibOnset = (_vibratoOnsetSec * sr).round();

  // Font LFOs (hoisted): vibLFO→pitch, modLFO→pitch, modLFO→volume. Depths
  // default 0 (no effect), so an unset font is unchanged.
  final hasVib = zone.vibLfoToPitchCents != 0;
  final hasModPitch = zone.modLfoToPitchCents != 0;
  final hasTrem = zone.modLfoToVolumeCb != 0;
  final vibDepthSt = zone.vibLfoToPitchCents / 100.0;
  final modPitchSt = zone.modLfoToPitchCents / 100.0;
  final vibW = 2 * math.pi * zone.vibLfoHz / sr;
  final modW = 2 * math.pi * zone.modLfoHz / sr;
  final vibDelayS = (zone.delayVibLfoSec * sr).round();
  final modDelayS = (zone.delayModLfoSec * sr).round();

  var bi = 0;
  var phase = 0.0;

  for (var i = 0; i < total; i++) {
    final outIdx = n.startSample + i;
    if (outIdx >= left.length) break;
    if (phase >= len) break; // one-shot ran out

    // Pitch: fixed + continuous bend (from the channel curve) + vibrato.
    while (bi + 1 < bendCurve.length && bendCurve[bi + 1].$1 <= outIdx) {
      bi++;
    }
    final bend = bendCurve.isEmpty ? 0.0 : bendCurve[bi].$2;
    // Pitch modulation (semitones): CC1 mod-wheel vibrato + the font's own
    // vibLFO and modLFO→pitch.
    var pitchMod = 0.0;
    if (n.modCents > 0) {
      final depth = i < vibOnset ? n.modCents * (i / vibOnset) : n.modCents;
      pitchMod +=
          depth / 100.0 * math.sin(2 * math.pi * _vibratoRateHz * i / sr);
    }
    if (hasVib && i >= vibDelayS) {
      pitchMod += vibDepthSt * math.sin(vibW * (i - vibDelayS));
    }
    if (hasModPitch && i >= modDelayS) {
      pitchMod += modPitchSt * math.sin(modW * (i - modDelayS));
    }
    final ratio = baseRatio *
        math.pow(2, (semisFixed + bend + pitchMod) / 12.0).toDouble();

    // Linear-interpolated sample read.
    final i0 = phase.floor();
    final frac = phase - i0;
    final s0 = i0 < len ? pcm[i0] : 0.0;
    final s1 = i0 + 1 < len ? pcm[i0 + 1] : s0;
    var v = s0 + (s1 - s0) * frac;

    // Amplitude envelope: the SF2 DAHDSR up to note-off, then an exponential
    // release from the note-off level.
    final double env;
    if (i < durSamples) {
      env = preRelease(i);
    } else {
      final t = (i - durSamples) / releaseS; // 0→1
      env = offLevel * math.exp(t * math.log(1e-4)); // → ~0
    }
    // modLFO → volume (tremolo): the level swings ±(cB/10) dB.
    var trem = 1.0;
    if (hasTrem && i >= modDelayS) {
      final lfo = math.sin(modW * (i - modDelayS));
      trem = math.pow(10, zone.modLfoToVolumeCb / 10 * lfo / 20).toDouble();
    }
    v *= env * baseGain * trem;

    // The SF2 low-pass filter.
    v = filter.process(v);

    left[outIdx] += v * lg;
    right[outIdx] += v * rg;

    // Advance the read head, wrapping the loop for sustain.
    phase += ratio;
    if (loop && phase >= loopEnd && loopEnd > loopStart) {
      phase = loopStart + (phase - loopEnd);
    }
  }
}

/// Parse every track's events into one absolute-tick, tick-sorted list.
(List<_Evt>, int) _parseAllEvents(Uint8List smf) {
  if (smf.length < 14) return (const [], 0);
  final tpq = (smf[12] << 8) | smf[13];
  final all = <_Evt>[];
  for (final track in splitMultiTrackMidi(smf)) {
    if (track.length < 22) continue;
    var offset = 22;
    var tick = 0;
    var runningStatus = 0;
    int varLen() {
      var v = 0;
      while (offset < track.length) {
        final b = track[offset++];
        v = (v << 7) | (b & 0x7f);
        if (b & 0x80 == 0) break;
      }
      return v;
    }

    while (offset < track.length) {
      tick += varLen();
      if (offset >= track.length) break;
      var status = track[offset];
      if (status & 0x80 != 0) {
        offset++;
      } else {
        status = runningStatus;
      }
      if (status == 0xff) {
        if (offset >= track.length) break;
        final metaType = track[offset++];
        final len = varLen();
        if (offset + len > track.length) break;
        if (metaType == 0x51 && len == 3) {
          final us = (track[offset] << 16) |
              (track[offset + 1] << 8) |
              track[offset + 2];
          all.add(_Evt(tick, 0x51, 0, 0, us));
        }
        offset += len;
        continue;
      }
      if (status == 0xf0 || status == 0xf7) {
        offset += varLen();
        continue;
      }
      runningStatus = status;
      final kind = status & 0xf0;
      final channel = status & 0x0f;
      final dataLen = (kind == 0xc0 || kind == 0xd0) ? 1 : 2;
      if (offset + dataLen > track.length) break;
      final d1 = track[offset];
      final d2 = dataLen == 2 ? track[offset + 1] : 0;
      offset += dataLen;
      if (kind == 0x80 ||
          kind == 0x90 ||
          kind == 0xb0 ||
          kind == 0xc0 ||
          kind == 0xe0) {
        all.add(_Evt(tick, kind, channel, d1, d2));
      }
    }
  }
  all.sort((a, b) => a.tick - b.tick);
  return (all, tpq);
}
