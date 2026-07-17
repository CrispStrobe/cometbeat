// lib/core/audio/crisp_dsp/voice_fx.dart
//
// Kid voice effects for the Tracker's record-your-voice instrument. Each takes a
// recorded sample and returns a transformed one that is still usable as an
// in-tune sampled instrument — so the effects are PITCH- AND LENGTH-PRESERVING
// (timbral only): chipmunk/monster/deep via [formantShift] (change vocal-tract
// character, not pitch), robot via ring-modulation + bit-crush. This keeps the
// sample's base pitch fixed, so a channel's notes still land where the grid says.
//
// (A pitch-changing "high/low voice" mode can use granularPitchShift from
// pitch_shift.dart, but then the instrument's baseMidi must move with it — out of
// scope for the in-tune presets here.)

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/formant_shift.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

/// The voice-transform palette offered when recording an instrument.
enum VoiceEffect { normal, chipmunk, monster, deep, robot }

/// Applies [fx] to [sample], returning a new (pitch/length-preserving) buffer.
Float64List applyVoiceEffect(
  Float64List sample,
  VoiceEffect fx, {
  int sampleRate = kSampleRate,
}) {
  switch (fx) {
    case VoiceEffect.normal:
      return Float64List.fromList(sample);
    case VoiceEffect.chipmunk:
      return formantShift(sample, 0.5);
    case VoiceEffect.monster:
      return formantShift(sample, -0.5);
    case VoiceEffect.deep:
      return formantShift(sample, -0.3);
    case VoiceEffect.robot:
      return _robot(sample, sampleRate);
  }
}

/// Robot voice: ring-modulation (a metallic carrier) + bit-crush grit. Both are
/// pitch- and length-preserving.
Float64List _robot(Float64List s, int sampleRate) {
  final out = Float64List(s.length);
  const carrierHz = 60.0;
  const bits = 6;
  final levels = pow(2, bits).toDouble();
  for (var i = 0; i < s.length; i++) {
    final t = i / sampleRate;
    var v = s[i] * sin(2 * pi * carrierHz * t); // ring mod
    v = (v * levels).floorToDouble() / levels; // bit crush
    out[i] = v;
  }
  return out;
}
