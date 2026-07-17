// lib/core/audio/tracker_effects.dart
//
// Per-note effect commands for the Tracker (Studio depth): arpeggio, vibrato and
// pitch slides, applied DURING additive synthesis (they modulate frequency, so
// they can't be a post-process on a rendered buffer). Pure Dart; reuses
// synth.dart's [Timbre] additive voice.
//
// TO BE IMPLEMENTED BY A SUB-AGENT against the contract below + the tests in
// test/tracker_effects_test.dart.
//
// ─── Effects ────────────────────────────────────────────────────────────────
//   none      — a plain sustained additive note.
//   arpeggio  — rapidly cycle midi, midi+4, midi+7 (a major chord), switching
//               every ~40 ms (the classic chiptune arp).
//   vibrato   — a sine LFO on the pitch (≈ 6 Hz), depth scaled by [depth].
//   slideUp   — bend the pitch up over the note by [depth] semitones.
//   slideDown — bend the pitch down over the note by [depth] semitones.
// All apply the same attack/decay envelope as the plain note; output is
// un-normalized Float64 in roughly [-1, 1], length = (ms * sampleRate) ~/ 1000.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';

/// The per-cell effect commands the Tracker supports.
enum TrackerEffect { none, arpeggio, vibrato, slideUp, slideDown }

/// Renders one note ([midi], [ms] long) with [effect] applied, as an
/// un-normalized additive buffer. [depth] tunes vibrato width / slide range
/// (semitones); [timbre] defaults to the piano voice.
///
/// Because arpeggio/vibrato/slide modulate the *frequency* over time, this can't
/// be a post-process on a rendered buffer — the instantaneous frequency is fed
/// through the same additive voice as [renderSegmentsRaw], but the base phase is
/// integrated sample-by-sample (`phase += 2*pi*freq/sr`) so a time-varying
/// frequency stays phase-continuous. Harmonic `h` then reads `sin(phase*(h+1))`.
Float64List renderNoteWithEffect(
  int midi,
  int ms,
  TrackerEffect effect, {
  Timbre? timbre,
  int sampleRate = kSampleRate,
  double depth = 2.0,
}) {
  final voice = timbre ?? timbreFor(Instrument.piano);
  final harmonics = voice.harmonics;
  final attackSec = voice.attackMs / 1000;
  final decay = voice.decay;

  final n = (ms * sampleRate) ~/ 1000;
  final seconds = ms / 1000;
  final buffer = Float64List(n);
  if (n == 0) return buffer;

  final baseFreq = midiToFrequency(midi);

  // Vibrato LFO: ~6 Hz sine, ±depth semitones (a ratio of 2^(cents/12)).
  const vibHz = 6.0;
  // Arpeggio: cycle root / +4 / +7 every ~40 ms.
  const arpMs = 40;
  final arpFreqs = <double>[
    baseFreq,
    midiToFrequency(midi + 4),
    midiToFrequency(midi + 7),
  ];
  final samplesPerArpStep = max(1, (arpMs * sampleRate) ~/ 1000);

  var phase = 0.0; // integrated base phase, in radians
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;

    // Instantaneous frequency for this sample, per effect.
    double freq;
    switch (effect) {
      case TrackerEffect.none:
        freq = baseFreq;
      case TrackerEffect.arpeggio:
        freq = arpFreqs[(i ~/ samplesPerArpStep) % arpFreqs.length];
      case TrackerEffect.vibrato:
        final semis = depth * sin(2 * pi * vibHz * t);
        freq = baseFreq * pow(2.0, semis / 12.0);
      case TrackerEffect.slideUp:
        final semis = depth * (t / seconds);
        freq = baseFreq * pow(2.0, semis / 12.0);
      case TrackerEffect.slideDown:
        final semis = -depth * (t / seconds);
        freq = baseFreq * pow(2.0, semis / 12.0);
    }

    // Same attack + exponential-decay envelope as a plain note.
    final attack = t < attackSec ? t / attackSec : 1.0;
    final envelope = attack * exp(-decay * t / seconds);

    var sample = 0.0;
    for (var h = 0; h < harmonics.length; h++) {
      sample += harmonics[h] * sin(phase * (h + 1));
    }
    buffer[i] = sample * envelope;

    // Advance the base phase by this sample's frequency (phase-continuous).
    phase += 2 * pi * freq / sampleRate;
  }
  return buffer;
}
