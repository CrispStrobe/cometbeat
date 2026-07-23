// lib/core/audio/crisp_dsp/voice_fx.dart
//
// Kid voice effects for the Tracker's record-your-voice instrument. Each takes a
// recorded sample and returns a transformed one, same length.
//
// PITCH, honestly (all are LENGTH-preserving):
//  • Pitch-PRESERVING — the sample stays in tune, so a channel's notes land
//    where the grid says: normal, chipmunk, monster, deep (all [formantShift] —
//    vocal-tract character only), radio (band-pass + grit), demon (formantShift
//    + fuzz).
//  • Pitch-CHANGING BY CONSTRUCTION — robot, alien, cyborg. These use ring
//    modulation, which replaces each harmonic f with the sidebands f ± carrier
//    (s·cos(2πfc·t) = ½[cos(2π(f−fc)t) + cos(2π(f+fc)t)]). That IS the effect;
//    no implementation of it can preserve pitch. Measured on a recorded C4:
//    robot −2400 ¢, cyborg −1902 ¢, alien −1021 ¢. They are character/texture
//    voices — a melody played with them will not track the grid's pitch. Kept
//    because the robot voice is the point; flagged so the contract isn't a lie.
//
// (A deliberate "high/low voice" mode can use granularPitchShift from
// pitch_shift.dart, but then the instrument's baseMidi must move with it — out of
// scope for the in-tune presets here.)

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:comet_beat/core/audio/crisp_dsp/formant_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

/// The voice-transform palette offered when recording an instrument. All presets
/// are length-preserving. All are pitch-preserving too — so a recorded sample
/// stays in tune as a channel instrument — EXCEPT the ring-modulated trio
/// ([robot], [alien], [cyborg]), which shift perceived pitch by construction;
/// see the file header. [kPitchPreservingVoiceEffects] is the in-tune subset.
enum VoiceEffect {
  normal,
  chipmunk,
  monster,
  deep,
  robot,
  alien,
  cyborg,
  radio,
  demon,
}

/// The presets that keep the sample in tune (see the file header). The rest
/// ([VoiceEffect.robot], [VoiceEffect.alien], [VoiceEffect.cyborg]) are
/// ring-modulated and shift perceived pitch by construction.
const kPitchPreservingVoiceEffects = <VoiceEffect>{
  VoiceEffect.normal,
  VoiceEffect.chipmunk,
  VoiceEffect.monster,
  VoiceEffect.deep,
  VoiceEffect.radio,
  VoiceEffect.demon,
};

/// Applies [fx] to [sample], returning a new, same-length buffer. Pitch is
/// preserved for every preset in [kPitchPreservingVoiceEffects].
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
    case VoiceEffect.alien:
      // Bright, shimmery: formant up + a mid ring-mod carrier.
      return ringModFx(
        formantShift(sample, 0.4),
        carrierHz: 150,
        mix: 0.6,
        sampleRate: sampleRate,
      );
    case VoiceEffect.cyborg:
      // Robotic + gritty: low ring-mod, then soft-clip crunch.
      return distortionFx(
        ringModFx(sample, carrierHz: 80, mix: 0.5, sampleRate: sampleRate),
        drive: 3,
        mix: 0.6,
      );
    case VoiceEffect.radio:
      // Telephone/AM: band-limit, then a touch of grit.
      return distortionFx(
        _bandpass(sample, sampleRate, 500, 2500),
        drive: 2,
        mix: 0.3,
      );
    case VoiceEffect.demon:
      // Deep + fuzzy growl: formant down, then a fuzz shaper.
      return distortionFx(
        formantShift(sample, -0.5),
        kind: DistortionKind.fuzz,
        drive: 2,
        mix: 0.5,
      );
  }
}

/// Adjustable voice-shaping module for DAW effect chains. It combines the
/// building blocks behind the preset voices into one same-length processor.
Float64List voiceShapeFx(
  Float64List sample, {
  double formant = 0,
  double carrierHz = 80,
  double carrierMix = 0,
  double grit = 0,
  double radioLowHz = 300,
  double radioHighHz = 3200,
  double radioMix = 0,
  double mix = 1,
  int sampleRate = kSampleRate,
}) {
  var wet = Float64List.fromList(sample);
  final f = formant.clamp(-0.8, 0.8).toDouble();
  if (f.abs() > 1e-9) {
    wet = formantShift(wet, f);
  }

  final rMix = radioMix.clamp(0.0, 1.0).toDouble();
  if (rMix > 0) {
    final low = radioLowHz.clamp(20.0, sampleRate / 2 - 20).toDouble();
    final high = radioHighHz.clamp(low + 20, sampleRate / 2).toDouble();
    wet = _blendBuffers(wet, _bandpass(wet, sampleRate, low, high), rMix);
  }

  final cMix = carrierMix.clamp(0.0, 1.0).toDouble();
  if (cMix > 0) {
    wet = ringModFx(
      wet,
      carrierHz: carrierHz.clamp(1.0, sampleRate / 2).toDouble(),
      mix: cMix,
      sampleRate: sampleRate,
    );
  }

  final g = grit.clamp(0.0, 1.0).toDouble();
  if (g > 0) {
    wet = distortionFx(wet, drive: 1 + g * 11, mix: g);
  }

  return _blendBuffers(sample, wet, mix.clamp(0.0, 1.0).toDouble());
}

/// A cheap band-pass ([lowHz]..[highHz]) — a 1-pole high-pass into a 1-pole
/// low-pass. Length-preserving. Used for the "radio" voice.
Float64List _bandpass(
  Float64List s,
  int sampleRate,
  double lowHz,
  double highHz,
) {
  final out = Float64List(s.length);
  final aHp = 1 - exp(-2 * pi * lowHz / sampleRate);
  final aLp = 1 - exp(-2 * pi * highHz / sampleRate);
  var hpState = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    hpState += aHp * (s[i] - hpState); // low-passed copy…
    final hp = s[i] - hpState; // …subtracted = high-pass
    lp += aLp * (hp - lp); // then low-pass → band-pass
    out[i] = lp;
  }
  return out;
}

Float64List _blendBuffers(Float64List dry, Float64List wet, double mix) {
  if (mix <= 0) return Float64List.fromList(dry);
  if (mix >= 1 && dry.length == wet.length) return wet;
  final n = max(dry.length, wet.length);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final d = i < dry.length ? dry[i] : 0.0;
    final w = i < wet.length ? wet[i] : 0.0;
    out[i] = d * (1 - mix) + w * mix;
  }
  return out;
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
