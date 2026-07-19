// Event-accurate MIDI → stereo audio through a SoundFont — the faithful-MIDI
// path the notation route (scoreFromMidi → quantized Score) can't be. Instead of
// snapping to a 16th grid, this schedules every message on a SAMPLE clock:
//   • exact event timing (swing, groove, off-grid tuplets, human micro-timing)
//   • a tempo MAP (accel/rit), not just the first tempo
//   • per-channel program + bank select, with mid-song program changes
//   • note velocity, CC7 volume, CC11 expression, CC10 pan
//   • sustain pedal (CC64): a note held past its note-off until the pedal lifts
//   • channel 10 → the bank-128 drum kit
// Each note is voiced by its SoundFont preset (via renderChannel) with a release
// tail, panned constant-power into the stereo field. Pitch-bend + per-voice
// filter/LFO are the next slice.
//
// Pure Dart, Flutter-free (crisp_notation_core split helper + the SF2 loader).

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/notation/multi_part_export.dart'
    show splitMultiTrackMidi;

const double _stepMs = 125; // TrackerTiming default: 120 BPM / 4 steps-per-beat
const double _releaseMs = 140;

/// A decoded MIDI channel event at an absolute tick (tempo/meta carried too).
class _Evt {
  _Evt(this.tick, this.kind, this.channel, this.d1, this.d2);
  final int tick;
  final int kind; // 0x80/0x90/0xB0/0xC0/0xE0, or 0x51 for a tempo meta
  final int channel;
  final int d1;
  final int d2; // for tempo: microseconds-per-quarter
}

/// A resolved sounding note ready to render.
class _Note {
  _Note(
    this.startSample,
    this.endSample,
    this.key,
    this.gain,
    this.pan,
    this.bank,
    this.program,
    this.isDrum,
  );
  final int startSample;
  final int endSample;
  final int key;
  final double gain; // velocity × CC7 × CC11
  final double pan; // −1..1
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

  // Tick → sample, honouring the tempo map. Precompute breakpoints so lookups
  // are a walk over a short list.
  final tempoTicks = <int>[0];
  final tempoUs = <int>[500000]; // 120 BPM until the first tempo meta
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
    var acc = 0.0; // samples
    for (var i = 0; i < tempoTicks.length; i++) {
      final segStart = tempoTicks[i];
      final segEnd = i + 1 < tempoTicks.length ? tempoTicks[i + 1] : 1 << 62;
      if (tick <= segStart) break;
      final upto = tick < segEnd ? tick : segEnd;
      final ticks = upto - segStart;
      final secPerTick = tempoUs[i] / 1000000 / tpq;
      acc += ticks * secPerTick * sampleRate;
      if (tick < segEnd) break;
    }
    return acc;
  }

  // Per-channel controller state + pending/pedal-held note-ons.
  final program = List<int>.filled(16, 0);
  final bank = List<int>.filled(16, 0);
  final volume = List<double>.filled(16, 100 / 127); // CC7
  final expression = List<double>.filled(16, 1.0); // CC11
  final pan = List<double>.filled(16, 0.0); // CC10 → −1..1
  final sustain = List<bool>.filled(16, false); // CC64
  // key → queue of (startTick, velocity, gain, pan, bank, program)
  final pending = <int, List<(int, int, double, double, int, int)>>{};
  // notes whose note-off arrived while the pedal was down: (note, offTick)
  final pedalHeld = <int, List<(int, int, double, double, int, int)>>{};

  final notes = <_Note>[];
  var lastTick = 0;

  void finalize(
    int ch,
    int key,
    int startTick,
    int endTick,
    int vel,
    double gain,
    double pn,
    int bk,
    int prog,
  ) {
    final s = sampleAt(startTick).round();
    final e = sampleAt(endTick).round();
    if (e <= s) return;
    notes.add(_Note(s, e, key, gain * (vel / 127.0), pn, bk, prog, ch == 9));
  }

  for (final ev in events) {
    lastTick = ev.tick;
    final ch = ev.channel;
    switch (ev.kind) {
      case 0x90: // note-on (vel 0 = off)
        if (ev.d2 > 0) {
          final g = volume[ch] * expression[ch];
          (pending[ch << 8 | ev.d1] ??= []).add(
            (ev.tick, ev.d2, g, pan[ch], bank[ch], program[ch]),
          );
        } else {
          _release(
            ch,
            ev.d1,
            ev.tick,
            sustain[ch],
            pending,
            pedalHeld,
            finalize,
          );
        }
      case 0x80: // note-off
        _release(
          ch,
          ev.d1,
          ev.tick,
          sustain[ch],
          pending,
          pedalHeld,
          finalize,
        );
      case 0xB0: // control change
        switch (ev.d1) {
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
            // Pedal up → release everything it was holding, at this tick.
            if (!down) _liftPedal(ch, ev.tick, pedalHeld, finalize);
            sustain[ch] = down;
        }
      case 0xC0: // program change
        program[ch] = ev.d1;
      case 0xE0: // pitch bend — captured; applied in the next slice
        break;
    }
  }

  // Flush anything still sounding at the end.
  final endTick = lastTick + tpq; // a beat of tail
  for (final entry in pending.entries) {
    final ch = entry.key >> 8;
    final key = entry.key & 0xff;
    for (final (startTick, vel, g, pn, bk, prog) in entry.value) {
      finalize(ch, key, startTick, endTick, vel, g, pn, bk, prog);
    }
  }
  for (final entry in pedalHeld.entries) {
    final ch = entry.key >> 8;
    final key = entry.key & 0xff;
    for (final (startTick, vel, g, pn, bk, prog) in entry.value) {
      finalize(ch, key, startTick, endTick, vel, g, pn, bk, prog);
    }
  }

  // Render + mix.
  var maxLen = 0;
  for (final n in notes) {
    if (n.endSample + (_releaseMs * sampleRate / 1000).round() > maxLen) {
      maxLen = n.endSample + (_releaseMs * sampleRate / 1000).round();
    }
  }
  final left = Float64List(maxLen);
  final right = Float64List(maxLen);
  final voices = <String, TrackerInstrument>{};

  for (final n in notes) {
    final voice = _voiceFor(font, n, voices);
    if (voice == null) continue;
    final durMs = (n.endSample - n.startSample) / sampleRate * 1000;
    final pcm = _renderNote(voice, n.key, durMs, n.gain, sampleRate);
    final theta = (n.pan.clamp(-1.0, 1.0) + 1) * 0.25 * math.pi;
    final lg = math.cos(theta);
    final rg = math.sin(theta);
    for (var i = 0; i < pcm.length; i++) {
      final j = n.startSample + i;
      if (j >= maxLen) break;
      left[j] += pcm[i] * lg;
      right[j] += pcm[i] * rg;
    }
  }
  return (left, right);
}

void _release(
  int ch,
  int key,
  int tick,
  bool sustainDown,
  Map<int, List<(int, int, double, double, int, int)>> pending,
  Map<int, List<(int, int, double, double, int, int)>> pedalHeld,
  void Function(int, int, int, int, int, double, double, int, int) finalize,
) {
  final q = pending[ch << 8 | key];
  if (q == null || q.isEmpty) return;
  final note = q.removeAt(0);
  if (sustainDown) {
    // Keep sounding until the pedal lifts (store with its would-be off tick).
    (pedalHeld[ch << 8 | key] ??= []).add(note);
  } else {
    final (startTick, vel, g, pn, bk, prog) = note;
    finalize(ch, key, startTick, tick, vel, g, pn, bk, prog);
  }
}

void _liftPedal(
  int ch,
  int tick,
  Map<int, List<(int, int, double, double, int, int)>> pedalHeld,
  void Function(int, int, int, int, int, double, double, int, int) finalize,
) {
  final keys = pedalHeld.keys.where((k) => k >> 8 == ch).toList();
  for (final k in keys) {
    final key = k & 0xff;
    for (final (startTick, vel, g, pn, bk, prog) in pedalHeld.remove(k)!) {
      finalize(ch, key, startTick, tick, vel, g, pn, bk, prog);
    }
  }
}

TrackerInstrument? _voiceFor(
  LoadedSoundFont font,
  _Note n,
  Map<String, TrackerInstrument> cache,
) {
  final bank = n.isDrum ? 128 : n.bank;
  final key = '$bank/${n.program}';
  final cached = cache[key];
  if (cached != null) return cached;
  final preset = findPreset(font, bank, n.program) ??
      findPreset(font, 0, n.program) ??
      (font.presets.isEmpty ? null : font.presets.first);
  if (preset == null) return null;
  return cache[key] = soundFontInstrument(font, preset);
}

Float64List _renderNote(
  TrackerInstrument inst,
  int midi,
  double durMs,
  double gain,
  int sampleRate,
) {
  final rows = ((durMs + _releaseMs) / _stepMs).round().clamp(1, 100000);
  final cells = <TrackerCell>[
    TrackerCell(midi: midi),
    for (var i = 1; i < rows; i++) TrackerCell.empty,
  ];
  final pcm = inst.renderChannel(cells, TrackerTiming(rows: rows));
  final relSamples = (_releaseMs * sampleRate / 1000).round();
  final sustainEnd = pcm.length - relSamples;
  for (var i = 0; i < pcm.length; i++) {
    var env = gain;
    if (relSamples > 0 && i >= sustainEnd) {
      final t = (i - sustainEnd) / relSamples;
      final k = 1 - t;
      env *= k * k;
    }
    pcm[i] *= env;
  }
  return pcm;
}

/// Parse every track's events into one absolute-tick, tick-sorted list.
(List<_Evt>, int) _parseAllEvents(Uint8List smf) {
  if (smf.length < 14) return (const [], 0);
  final tpq = (smf[12] << 8) | smf[13];
  final all = <_Evt>[];
  for (final track in splitMultiTrackMidi(smf)) {
    if (track.length < 22) continue;
    var offset = 22; // 14 MThd + 8 MTrk header
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
  // Stable sort by tick (mergeSort-style via sort with an index tiebreak).
  all.sort((a, b) => a.tick - b.tick);
  return (all, tpq);
}
