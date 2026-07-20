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
//   • sostenuto pedal (CC66): holds ONLY the notes already down when pressed
//   • channel aftertouch (0xD0): channel pressure → vibrato depth (continuous)
//   • channel 10 → the bank-128 drum kit; GS NRPN 18h retunes a single drum key
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
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show chorusFx;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart' show reverbFx;
import 'package:comet_beat/core/audio/sf2/sf2.dart'
    show Sf2Preset, Sf2Sample, Sf2SoundFont, Sf2Zone;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show splitMultiTrackMidi;

const double _maxTailSec = 3; // cap a note's release tail (buffer headroom)
// Reverb-return makeup: the per-zone SF2 reverb sends (gen 16, median ~5%) are
// far smaller than the flat CC-default we used before, so the wet return is
// scaled up to keep the same overall space while preserving the font's
// per-instrument WET/dry variation (a pad far wetter than a bass).
const double _reverbReturnGain = 4.6;
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
    this.reverb,
    this.chorus,
    this.bank,
    this.program,
    this.isDrum,
    this.tuneOffset,
  );
  final int startTick;
  final int vel;
  final double gain; // CC7 × CC11
  final double pan; // −1..1
  final double modCents; // vibrato depth from CC1 at onset
  final double reverb; // CC91 send 0..1
  final double chorus; // CC93 send 0..1
  final int bank;
  final int program;
  final bool isDrum;
  final double tuneOffset; // GS NRPN drum-pitch offset, semitones
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
    this.reverb,
    this.chorus,
    this.bank,
    this.program,
    this.isDrum,
    this.tuneOffset,
  );
  final int startSample;
  final int endSample;
  final int key;
  final int channel;
  final double gain; // velocity × CC7 × CC11
  final double velNorm; // velocity / 127 (filter cutoff)
  final double pan; // −1..1
  final double modCents; // vibrato depth
  final double reverb; // CC91 reverb send 0..1
  final double chorus; // CC93 chorus send 0..1
  final int bank;
  final int program;
  final bool isDrum;
  final double tuneOffset; // GS NRPN drum-pitch offset, semitones

  /// Absolute sample at which a same-exclusive-class note cuts this one off
  /// (1<<62 = never). Set in the render pass.
  int cutAtSample = 1 << 62;
}

/// Render [smf] through [font] to a stereo (left, right) pair, scheduling every
/// event on a sample clock. Empty in → empty out.
(Float64List left, Float64List right) renderMidiFile(
  Uint8List smf,
  LoadedSoundFont font, {
  int sampleRate = kSampleRate,
  double reverbMix = 0,
  double chorusMix = 0,
}) {
  final (events, tpq, sysex) = _parseAllEvents(smf);
  if (events.isEmpty || tpq <= 0) return (Float64List(0), Float64List(0));

  // Which channels are drum channels: channel 10 by default, plus any set by a
  // GS "use-for-rhythm-part" SysEx (XG's CC0=127 is handled at note-on).
  final drumChannel = List<bool>.filled(16, false);
  drumChannel[9] = true;
  _applyGsDrumSysex(sysex, drumChannel);

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
  final bank = List<int>.filled(16, 0); // CC0 bank MSB
  final bankLsb = List<int>.filled(16, 0); // CC32 bank LSB (GS/XG)
  final volume = List<double>.filled(16, 100 / 127);
  final expression = List<double>.filled(16, 1.0);
  final pan = List<double>.filled(16, 0.0);
  final sustain = List<bool>.filled(16, false);
  final modCents = List<double>.filled(16, 0.0); // CC1 → vibrato depth
  final reverbSend = List<double>.filled(16, 40 / 127); // CC91 (GM default)
  final chorusSend = List<double>.filled(16, 0.0); // CC93
  final soft = List<bool>.filled(16, false); // CC67 soft pedal
  // Pitch-bend range (RPN 0), default ±2 st; RPN/NRPN select + data-entry state.
  final bendRange = List<double>.filled(16, _bendRangeSemis);
  final rpnMsb = List<int>.filled(16, 127);
  final rpnLsb = List<int>.filled(16, 127);
  final nrpnMsb = List<int>.filled(16, 127);
  final nrpnLsb = List<int>.filled(16, 127);
  // Which parameter CC6/38 (data entry) address: true = RPN, false = NRPN.
  final rpnActive = List<bool>.filled(16, true);
  // GS NRPN 18h: per-channel, per-drum-key pitch offset (semitones from 0x40).
  final drumTune = List.generate(16, (_) => <int, double>{});
  // Per-channel pitch-bend curve: (absolute sample, semitones), time-ordered.
  final bendByChannel = List.generate(16, (_) => <(int, double)>[]);
  // Per-channel channel-aftertouch curve: (absolute sample, vibrato cents).
  final atByChannel = List.generate(16, (_) => <(int, double)>[]);

  final pending = <int, List<_Pending>>{};
  final pedalHeld = <int, List<_Pending>>{};
  final sostHeld =
      <int, List<_Pending>>{}; // deferred note-offs (sostenuto down)
  // Per-channel: the note identities that were sounding when CC66 was pressed.
  final sostCaptured = List.generate(16, (_) => <_Pending>{});
  final notes = <_Note>[];
  var lastTick = 0;

  void finalize(int ch, int key, int endTick, _Pending p) {
    final s = sampleAt(p.startTick).round();
    final e = sampleAt(endTick).round();
    if (e <= s) return;
    final vn = p.vel / 127.0;
    // Velocity → amplitude on the SF2 concave curve (≈ its default velocity→
    // attenuation modulator): gain ∝ (vel/127)^1.5, matching a fluidsynth
    // reference within ~1 dB across the range. Linear velocity made soft notes
    // far too loud (−18 vs −28 dB at velocity 16) — flat, undynamic. The filter
    // still uses the raw linear [vn] (velNorm) for its cutoff modulation.
    final note = _Note(
      s,
      e,
      key,
      ch,
      p.gain * math.pow(vn, 1.5).toDouble(),
      vn,
      p.pan,
      p.modCents,
      p.reverb,
      p.chorus,
      p.bank,
      p.program,
      p.isDrum,
      p.tuneOffset,
    );
    notes.add(note);
  }

  void release(int ch, int key, int tick) {
    final q = pending[ch << 8 | key];
    if (q == null || q.isEmpty) return;
    final p = q.removeAt(0);
    if (sustain[ch]) {
      (pedalHeld[ch << 8 | key] ??= []).add(p);
    } else if (sostCaptured[ch].contains(p)) {
      // Sostenuto holds only the notes that were down when it was pressed.
      (sostHeld[ch << 8 | key] ??= []).add(p);
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

  void liftSostenuto(int ch, int tick) {
    for (final k in sostHeld.keys.where((k) => k >> 8 == ch).toList()) {
      for (final p in sostHeld.remove(k)!) {
        finalize(ch, k & 0xff, tick, p);
      }
    }
    sostCaptured[ch].clear(); // pedal up: captured notes release normally now
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
              volume[ch] * expression[ch] * (soft[ch] ? 0.7 : 1.0),
              pan[ch],
              modCents[ch],
              reverbSend[ch],
              chorusSend[ch],
              bank[ch],
              program[ch],
              // GS rhythm part, or XG drum channel (CC0 bank MSB = 127).
              drumChannel[ch] || bank[ch] == 127,
              drumTune[ch][ev.d1] ?? 0.0, // GS NRPN 18h per-drum pitch
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
          case 32:
            bankLsb[ch] = ev.d2;
          case 91:
            reverbSend[ch] = ev.d2 / 127.0;
          case 93:
            chorusSend[ch] = ev.d2 / 127.0;
          case 67:
            soft[ch] = ev.d2 >= 64; // soft pedal → quieter new notes
          case 64:
            final down = ev.d2 >= 64;
            if (!down) liftPedal(ch, ev.tick);
            sustain[ch] = down;
          case 66:
            final down = ev.d2 >= 64;
            if (down) {
              // Capture every note currently sounding on this channel.
              sostCaptured[ch]
                ..clear()
                ..addAll([
                  for (final k in pending.keys.where((k) => k >> 8 == ch))
                    ...pending[k]!,
                ]);
            } else {
              liftSostenuto(ch, ev.tick);
            }
          case 120: // all sound off
          case 123: // all notes off
            for (final k in pending.keys.where((k) => k >> 8 == ch).toList()) {
              for (final p in pending.remove(k)!) {
                finalize(ch, k & 0xff, ev.tick, p);
              }
            }
            liftPedal(ch, ev.tick);
            liftSostenuto(ch, ev.tick);
          case 121: // reset all controllers
            volume[ch] = 100 / 127;
            expression[ch] = 1;
            pan[ch] = 0;
            modCents[ch] = 0;
            bendRange[ch] = _bendRangeSemis;
            sustain[ch] = false;
            soft[ch] = false;
          case 101:
            rpnMsb[ch] = ev.d2;
            rpnActive[ch] = true;
          case 100:
            rpnLsb[ch] = ev.d2;
            rpnActive[ch] = true;
          case 99:
            nrpnMsb[ch] = ev.d2;
            rpnActive[ch] = false;
          case 98:
            nrpnLsb[ch] = ev.d2;
            rpnActive[ch] = false;
          case 6: // data-entry MSB → the last-selected RPN or NRPN
            if (rpnActive[ch]) {
              if (rpnMsb[ch] == 0 && rpnLsb[ch] == 0) {
                bendRange[ch] = ev.d2.toDouble();
              }
            } else if (nrpnMsb[ch] == 0x18) {
              // GS drum pitch coarse: NRPN LSB = drum key, data 0x40 = centre.
              drumTune[ch][nrpnLsb[ch]] = (ev.d2 - 64).toDouble();
            }
          case 38: // data-entry LSB: RPN 0 → the cents part of the range
            if (rpnActive[ch] && rpnMsb[ch] == 0 && rpnLsb[ch] == 0) {
              bendRange[ch] = bendRange[ch].truncateToDouble() + ev.d2 / 100.0;
            }
        }
      case 0xC0:
        program[ch] = ev.d1;
      case 0xD0: // channel aftertouch (pressure) → vibrato depth, continuous
        atByChannel[ch]
            .add((sampleAt(ev.tick).round(), ev.d1 / 127.0 * _vibratoMaxCents));
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
  for (final entry in sostHeld.entries) {
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
  // Per-channel reverb/chorus send buses (CC91/CC93), summed here and wetted
  // once at the end — only when a master mix is requested.
  final wantRev = reverbMix > 0;
  final wantChor = chorusMix > 0;
  final revL = wantRev ? Float64List(maxLen) : null;
  final revR = wantRev ? Float64List(maxLen) : null;
  final chorL = wantChor ? Float64List(maxLen) : null;
  final chorR = wantChor ? Float64List(maxLen) : null;
  final presetCache = <String, Sf2Preset?>{};

  // Exclusive class (gen 57): within a (channel, class) group, each note is cut
  // off when the next same-class note starts (open → closed hi-hat).
  final byExclusive = <int, List<_Note>>{};
  for (final n in notes) {
    final preset = _presetFor(font, n, presetCache);
    if (preset == null) continue;
    final cls = _exclusiveClassOf(preset, n);
    if (cls != 0) (byExclusive[n.channel << 16 | cls] ??= []).add(n);
  }
  for (final group in byExclusive.values) {
    group.sort((a, b) => a.startSample - b.startSample);
    for (var i = 0; i < group.length - 1; i++) {
      group[i].cutAtSample = group[i + 1].startSample;
    }
  }

  for (final n in notes) {
    final preset = _presetFor(font, n, presetCache);
    if (preset == null) continue;
    _resampleNote(
      font.font,
      preset,
      n,
      bendByChannel[n.channel],
      atByChannel[n.channel],
      left,
      right,
      revL,
      revR,
      chorL,
      chorR,
      sampleRate,
    );
  }

  // Wet the send buses once and fold them into the master. A mono send →
  // stereo return: sum the (panned) sends to one bus, then run it through two
  // decorrelated reverbs — the right offset by the Freeverb stereo spread (23
  // samples) — so even a centre-panned note gets a WIDE, spacious tail instead
  // of one stuck on its own side. A bigger room gives the tail the length that
  // reads as "air"/space (a dry mix sounds stale next to a real synth).
  if (wantRev) {
    final send = Float64List(maxLen);
    for (var i = 0; i < maxLen; i++) {
      send[i] = (revL![i] + revR![i]) * 0.5;
    }
    final wl = reverbFx(send, mix: 1, roomSize: 0.82, sampleRate: sampleRate);
    final wr = reverbFx(
      send,
      mix: 1,
      roomSize: 0.82,
      stereoSpread: 23,
      sampleRate: sampleRate,
    );
    final g = reverbMix * _reverbReturnGain;
    for (var i = 0; i < maxLen; i++) {
      left[i] += wl[i] * g;
      right[i] += wr[i] * g;
    }
  }
  if (wantChor) {
    final wl = chorusFx(chorL!, mix: 1, sampleRate: sampleRate);
    final wr = chorusFx(chorR!, mix: 1, sampleRate: sampleRate);
    for (var i = 0; i < maxLen; i++) {
      left[i] += wl[i] * chorusMix;
      right[i] += wr[i] * chorusMix;
    }
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

/// The exclusive class of the zone that voices this note (0 = none).
int _exclusiveClassOf(Sf2Preset preset, _Note n) {
  final vel = (n.velNorm * 127).round();
  for (final z in preset.zones) {
    if (z.coversKeyVel(n.key, vel)) return z.exclusiveClass;
  }
  return preset.zones.isEmpty ? 0 : preset.zones.first.exclusiveClass;
}

/// Voice the note: play EVERY zone covering its key/velocity (a stereo L/R pair
/// or a layered patch triggers all of them), each panned by the channel pan +
/// the zone's own pan (or its sample's L/R type).
void _resampleNote(
  Sf2SoundFont font,
  Sf2Preset preset,
  _Note n,
  List<(int, double)> bendCurve,
  List<(int, double)> atCurve,
  Float64List left,
  Float64List right,
  Float64List? revL,
  Float64List? revR,
  Float64List? chorL,
  Float64List? chorR,
  int sr,
) {
  final vel = (n.velNorm * 127).round();
  final covering = [
    for (final z in preset.zones)
      if (z.coversKeyVel(n.key, vel)) z,
  ];
  if (covering.isEmpty && preset.zones.isNotEmpty) {
    covering.add(preset.zones.first);
  }

  for (final zone in covering) {
    final sample = font.sampleAt(zone.sampleIndex);
    if (sample == null || sample.pcm.isEmpty) continue;
    // Stereo placement: the zone pan (gen 17), or the sample's L/R type when the
    // zone doesn't set one, added to the channel's CC10 pan.
    var zpan = zone.pan;
    if (zpan == 0) {
      if (sample.isLeft) zpan = -1;
      if (sample.isRight) zpan = 1;
    }
    final notePan = (n.pan + zpan).clamp(-1.0, 1.0);
    _renderZone(
      zone,
      sample,
      n,
      notePan,
      bendCurve,
      atCurve,
      left,
      right,
      revL,
      revR,
      chorL,
      chorR,
      sr,
    );
  }
}

/// Resample one [zone]/[sample] into [left]/[right] at the note's start, with
/// pitch bend, LFOs, the SF2 DAHDSR envelope + low-pass, loop-sustain, and a
/// constant-power pan at [notePan].
void _renderZone(
  Sf2Zone zone,
  Sf2Sample sample,
  _Note n,
  double notePan,
  List<(int, double)> bendCurve,
  List<(int, double)> atCurve,
  Float64List left,
  Float64List right,
  Float64List? revL,
  Float64List? revR,
  Float64List? chorL,
  Float64List? chorR,
  int sr,
) {
  final pcm = sample.pcm;
  final len = pcm.length;
  final root = zone.rootKey >= 0 ? zone.rootKey : sample.originalPitch;
  final baseRatio = sample.sampleRate / sr;
  // Fixed pitch offset (semitones) for this key. The key→pitch distance scales
  // by the zone's scaleTuning (100 = chromatic; 0 = a drum kit, where the key
  // picks a sample and must NOT transpose it), plus zone/sample tune and any GS
  // NRPN per-drum retune (those are absolute, not key-scaled).
  final semisFixed = (n.key - root) * zone.scaleTuning / 100.0 +
      zone.coarseTune +
      n.tuneOffset +
      (zone.fineTune + sample.pitchCorrection) / 100.0;

  // Loop only when the zone's sampleModes (gen 54) enables it (and the sample
  // has a loop region, and it isn't a one-shot drum).
  final loop = zone.loopEnabled && sample.loops && !n.isDrum;
  // The sample's loop points, adjusted by the zone's SF2 loop-point offsets
  // (gens 2/3), clamped to the sample.
  final loopStart =
      (sample.loopStart + zone.loopStartOffset).clamp(0, len).toDouble();
  final loopEnd =
      (sample.loopEnd + zone.loopEndOffset).clamp(0, len).toDouble();

  final durSamples = n.endSample - n.startSample;

  // SF2 volume envelope (DAHDSR), in samples, with small click-avoiding floors.
  // The default gens (−12000 tc ≈ 1 ms, sustain full) behave like a gate, so a
  // font without an envelope is close to the old behaviour; a font WITH one
  // (a piano's decay, a pad's swell) now plays as designed.
  final delayS = (zone.delayVolSec * sr).round();
  final attackS =
      math.max((zone.attackVolSec * sr).round(), (0.002 * sr).round());
  // Hold/decay are key-scaled (SF2 gens 39/40): a font's high notes ring shorter.
  final holdS = (zone.volEnvHoldSec(n.key) * sr).round();
  final decayS = math.max((zone.volEnvDecaySec(n.key) * sr).round(), 1);
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

  final theta = (notePan.clamp(-1.0, 1.0) + 1) * 0.25 * math.pi;
  final lg = math.cos(theta);
  final rg = math.sin(theta);
  final baseGain = n.gain * zone.gain;

  // Effects sends: the zone's OWN authored reverb/chorus (SF2 gens 16/15) is the
  // base — so a pad is wet and a bass dry, as the font intends — plus the
  // channel's CC91/93 send (scaled by the SF2 default modulator's 0.2). Before,
  // every note got the flat CC-default send regardless of instrument.
  final zReverb = (zone.reverbSend + 0.2 * n.reverb).clamp(0.0, 1.0);
  final zChorus = (zone.chorusSend + 0.2 * n.chorus).clamp(0.0, 1.0);

  // SF2 modulation envelope (a 2nd DAHDSR) → filter cutoff (+ pitch): the attack
  // "bite" that a static filter lacks — e.g. a kick's low base cutoff opens into
  // a bright click, then the envelope decays back toward the boom body. Times
  // are seconds; the sustain is a level (1 = held open).
  final meDelayS = (zone.delayModEnvSec * sr).round();
  final meAttackS = math.max((zone.attackModEnvSec * sr).round(), 1);
  final meHoldS = (zone.holdModEnvSec * sr).round();
  final meDecayS = math.max((zone.decayModEnvSec * sr).round(), 1);
  final meSustain = zone.modEnvSustain;
  final meReleaseS = math.max((zone.releaseModEnvSec * sr).round(), 1);
  final meToFilterCents = zone.modEnvToFilterCents.toDouble();
  final meToPitchSt = zone.modEnvToPitchCents / 100.0;
  final hasModEnv = zone.hasModEnv;

  // The mod-envelope value (0..1): a DAHDSR up to note-off, then a linear release
  // (the mod env is applied in the log domain — cents — so it decays linearly).
  double modEnvPre(int i) {
    if (i < meDelayS) return 0;
    var t = i - meDelayS;
    if (t < meAttackS) return t / meAttackS;
    t -= meAttackS;
    if (t < meHoldS) return 1;
    t -= meHoldS;
    if (t < meDecayS) return 1 + (meSustain - 1) * (t / meDecayS);
    return meSustain;
  }

  final meOffLevel = modEnvPre(durSamples);
  double modEnvAt(int i) {
    if (i < durSamples) return modEnvPre(i);
    final t = (i - durSamples) / meReleaseS;
    return (meOffLevel * (1 - t)).clamp(0.0, 1.0);
  }

  // SF2 2-pole resonant low-pass. Base cutoff = the zone's own cutoff modulated
  // by velocity (the SF2 default darkens soft notes; a drum kit's modulator
  // OPENS a low base cutoff on a hard hit). The mod envelope then sweeps it.
  final baseFcCents = zone.filterFcCents + zone.velFilterCents(n.velNorm);
  double cutoffHzAt(double me) =>
      (8.176 * math.pow(2, (baseFcCents + meToFilterCents * me) / 1200))
          .clamp(20.0, sr / 2 - 1)
          .toDouble();
  final filter = Biquad(
    BiquadKind.lowpass,
    freq: cutoffHzAt(modEnvAt(0)),
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

  // Exclusive-class cut: a same-class note truncates this one with a fast fade.
  final cutRel = n.cutAtSample - n.startSample;
  final cutFade = (0.006 * sr).round();

  var bi = 0;
  var ai = 0;
  // Start reading at the zone's sample-start offset (SF2 gens 0/4) — skips a
  // lead-in so the attack lands as authored (a common drum-kit trick).
  var phase = (zone.sampleStartOffset > 0 && zone.sampleStartOffset < len)
      ? zone.sampleStartOffset.toDouble()
      : 0.0;

  for (var i = 0; i < total; i++) {
    final outIdx = n.startSample + i;
    if (outIdx >= left.length) break;
    if (phase >= len) break; // one-shot ran out
    if (i >= cutRel + cutFade) break; // cut off by a same-class note

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
    // Channel aftertouch: a continuous vibrato whose depth tracks the pressure
    // curve (sampled at this output index, like the bend curve).
    while (ai + 1 < atCurve.length && atCurve[ai + 1].$1 <= outIdx) {
      ai++;
    }
    final atCents = atCurve.isEmpty ? 0.0 : atCurve[ai].$2;
    if (atCents > 0) {
      pitchMod +=
          atCents / 100.0 * math.sin(2 * math.pi * _vibratoRateHz * i / sr);
    }
    if (hasVib && i >= vibDelayS) {
      pitchMod += vibDepthSt * math.sin(vibW * (i - vibDelayS));
    }
    if (hasModPitch && i >= modDelayS) {
      pitchMod += modPitchSt * math.sin(modW * (i - modDelayS));
    }
    // Mod envelope → pitch (a kick's attack pitch-drop, etc.).
    if (hasModEnv && meToPitchSt != 0) {
      pitchMod += meToPitchSt * modEnvAt(i);
    }
    final ratio = baseRatio *
        math.pow(2, (semisFixed + bend + pitchMod) / 12.0).toDouble();

    // Cubic (Catmull-Rom) sample read — less aliasing than linear on upward
    // pitch shifts.
    final i1 = phase.floor();
    final t = phase - i1;
    final p0 = pcm[i1 > 0 ? i1 - 1 : 0];
    final p1 = i1 < len ? pcm[i1] : 0.0;
    final p2 = i1 + 1 < len ? pcm[i1 + 1] : p1;
    final p3 = i1 + 2 < len ? pcm[i1 + 2] : p2;
    var v = 0.5 *
        (2 * p1 +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);

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
    // Fast fade over the exclusive-class cut boundary (avoids a click).
    var cut = 1.0;
    if (i >= cutRel) cut = math.max(0.0, 1 - (i - cutRel) / cutFade);
    v *= env * baseGain * trem * cut;

    // The SF2 low-pass filter, swept by the mod envelope (retuned at a control
    // rate, every 16 samples, so the sweep stays cheap and click-free).
    if (hasModEnv && meToFilterCents != 0 && (i & 15) == 0) {
      filter.setFreq(cutoffHzAt(modEnvAt(i)));
    }
    v = filter.process(v);

    final vl = v * lg;
    final vr = v * rg;
    left[outIdx] += vl;
    right[outIdx] += vr;
    // Per-zone reverb/chorus send contributions (font send + CC send).
    if (revL != null && zReverb > 0) {
      revL[outIdx] += vl * zReverb;
      revR![outIdx] += vr * zReverb;
    }
    if (chorL != null && zChorus > 0) {
      chorL[outIdx] += vl * zChorus;
      chorR![outIdx] += vr * zChorus;
    }

    // Advance the read head, wrapping the loop for sustain. Loop-until-release
    // (mode 3) stops wrapping after note-off so the tail plays to the end.
    phase += ratio;
    final wrapping = loop && (!zone.loopUntilRelease || i < durSamples);
    if (wrapping && phase >= loopEnd && loopEnd > loopStart) {
      phase = loopStart + (phase - loopEnd);
    }
  }
}

/// Scan SysEx for drum-channel setup: a Roland GS "use-for-rhythm-part"
/// message marks a part as drums; a GM/GS/XG System-On resets to the default
/// (only channel 10). Everything else is ignored.
void _applyGsDrumSysex(List<Uint8List> sysex, List<bool> drumChannel) {
  void reset() {
    for (var i = 0; i < 16; i++) {
      drumChannel[i] = i == 9;
    }
  }

  for (final s in sysex) {
    // GM System On: 7E 7F 09 01.
    if (s.length >= 4 && s[0] == 0x7E && s[2] == 0x09) {
      reset();
      continue;
    }
    // Roland GS (41 .. 42 12 ..).
    if (s.length >= 8 && s[0] == 0x41 && s[2] == 0x42 && s[3] == 0x12) {
      final a1 = s[4], a2 = s[5], a3 = s[6];
      if (a1 == 0x40 && a2 == 0x00 && a3 == 0x7F) {
        reset(); // GS reset
      } else if (a1 == 0x40 && (a2 & 0xf0) == 0x10 && a3 == 0x15) {
        // Use-for-rhythm-part: block nibble → channel, data != 0 → drums.
        final n = a2 & 0x0f;
        final ch = n == 0 ? 9 : (n <= 9 ? n - 1 : n);
        if (ch >= 0 && ch < 16) drumChannel[ch] = s[7] != 0;
      }
      continue;
    }
    // Yamaha XG System On: 43 10 4C 00 00 7E 00.
    if (s.length >= 6 && s[0] == 0x43 && s[2] == 0x4C && s[5] == 0x7E) reset();
  }
}

/// Parse every track's events into one absolute-tick, tick-sorted list.
(List<_Evt>, int, List<Uint8List>) _parseAllEvents(Uint8List smf) {
  if (smf.length < 14) return (const [], 0, const []);
  final tpq = (smf[12] << 8) | smf[13];
  final all = <_Evt>[];
  final sysex = <Uint8List>[];
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
        final len = varLen();
        if (offset + len > track.length) break;
        if (status == 0xf0) {
          sysex.add(Uint8List.sublistView(track, offset, offset + len));
        }
        offset += len;
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
          kind == 0xd0 ||
          kind == 0xe0) {
        all.add(_Evt(tick, kind, channel, d1, d2));
      }
    }
  }
  all.sort((a, b) => a.tick - b.tick);
  return (all, tpq, sysex);
}
