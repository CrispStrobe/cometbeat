// lib/core/audio/crisp_dsp/pitch_shift.dart
//
// Granular pitch shifter — pure-Dart port of crispaudio's dsp/PitchShifter.ts
// (MIT, ours). Overlap-add of Hann-windowed grains, each linearly resampled to
// shift pitch. The only upstream Web-Audio dependency was OfflineAudioContext
// used as a buffer allocator — replaced here with a plain Float64List.
//
// Available for standalone voice processing (a "deep voice" toy) and future
// instrument modes. The Tracker's per-note pitching uses plain [resampleLinear]
// (classic tracker resampling); its voice-effect presets lean on the
// pitch-stable [formantShift] so sampled instruments stay in tune.

import 'dart:math';
import 'dart:typed_data';

Float64List _hannWindow(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 * (1 - cos((2 * pi * i) / (size - 1)));
  }
  return w;
}

/// Pitch-shifts [input] by [semitones] (−24..+24) via granular overlap-add.
/// [grainSize] is the grain length in samples; [overlap] is the grain overlap
/// fraction (0..1). Returns a new buffer (length scales by 1/pitchRatio, as in
/// the upstream algorithm).
Float64List granularPitchShift(
  Float64List input,
  double semitones, {
  int grainSize = 2048,
  double overlap = 0.75,
}) {
  if (semitones == 0 || input.isEmpty) return input;

  final pitchRatio = pow(2, semitones / 12).toDouble();
  final inputLength = input.length;
  final outputLength = (inputLength / pitchRatio).floor();
  final output = Float64List(outputLength);
  if (outputLength == 0) return output;

  final window = _hannWindow(grainSize);
  final hopInput = (grainSize * (1 - overlap)).floor().clamp(1, grainSize);
  final hopOutput = (hopInput / pitchRatio).floor().clamp(1, grainSize);

  var inputPos = 0;
  var outputPos = 0;
  while (inputPos + grainSize < inputLength &&
      outputPos + grainSize < outputLength) {
    // Extract and window a grain.
    final grain = Float64List(grainSize);
    for (var i = 0; i < grainSize; i++) {
      if (inputPos + i < inputLength) {
        grain[i] = input[inputPos + i] * window[i];
      }
    }

    // Resample the grain (linear interpolation) to shift its pitch.
    final resampledLength = (grainSize / pitchRatio).floor();
    for (var i = 0; i < resampledLength && outputPos + i < outputLength; i++) {
      final srcIndex = i * pitchRatio;
      final f = srcIndex.floor();
      final c = min(f + 1, grainSize - 1);
      final frac = srcIndex - f;
      output[outputPos + i] += grain[f] * (1 - frac) + grain[c] * frac;
    }

    inputPos += hopInput;
    outputPos += hopOutput;
  }
  return output;
}

/// Applies the same deterministic grain schedule to a stereo pair. Keeping
/// this as one DSP operation makes the channel contract explicit and prevents
/// future channel-specific pitch settings from silently widening the image.
({Float64List left, Float64List right}) granularPitchShiftStereo(
  Float64List left,
  Float64List right,
  double semitones, {
  int grainSize = 2048,
  double overlap = 0.75,
}) =>
    (
      left: granularPitchShift(
        left,
        semitones,
        grainSize: grainSize,
        overlap: overlap,
      ),
      right: granularPitchShift(
        right,
        semitones,
        grainSize: grainSize,
        overlap: overlap,
      ),
    );
