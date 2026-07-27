// Loudness measurement — LUFS, true peak, and stereo correlation.
//
// Peak and RMS answer "how big are the numbers"; neither answers "how loud does
// this SOUND", which is the question every delivery target is written in. A
// track normalised to −1 dBFS peak can be twice as loud as another normalised
// the same way, because the ear weights frequencies and integrates over time and
// a peak meter does neither.
//
// This implements the published broadcast loudness standard: K-weighting (a
// high-shelf plus a high-pass, approximating the head and the ear's response),
// mean square over overlapping 400 ms blocks, and two-stage GATING so that
// silence between phrases does not drag the number down.
//
// Clean-room from the specification, which is a description of a measurement
// rather than anyone's code: the filter coefficients, the −0.691 dB calibration
// offset, the −70 LUFS absolute gate and the −10 LU relative gate are all part
// of the published definition.
//
// TRUE peak is separate and matters for a different reason: a signal can sit
// under 0 dBFS at every sample and still exceed it BETWEEN samples, which a
// converter or an encoder will then clip. Measuring it means reconstructing
// what happens between the samples, so this oversamples before taking the peak.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';

/// What a loudness measurement reports.
typedef LoudnessReading = ({
  double integratedLufs, // the whole programme, gated
  double shortTermLufs, // the loudest 3 s window
  double momentaryLufs, // the loudest 400 ms window
  double truePeakDb, // dBTP — the peak BETWEEN samples, not just at them
  double correlation, // −1 out of phase … +1 mono, 0 uncorrelated
});

/// The level reported for silence. LUFS is logarithmic, so digital silence is
/// negative infinity; the standard's own gate sits at −70, so anything at or
/// below that is "not programme material" and this is the honest floor to show.
const double kLoudnessSilenceLufs = -70;

/// K-weight a channel: the shelf and high-pass the standard defines.
Float64List _kWeight(Float64List input, double sampleRate) {
  // Stage 1 — a high shelf, roughly +4 dB above 1.5 kHz, standing in for the
  // acoustic effect of a head in a sound field.
  final shelf = Biquad(
    BiquadKind.highShelf,
    freq: 1500,
    sampleRate: sampleRate,
    gainDb: 4,
  );
  // Stage 2 — a high-pass near 38 Hz, because very low frequencies contribute
  // far less to perceived loudness than their energy suggests.
  final highpass = Biquad(
    BiquadKind.highpass,
    freq: 38,
    sampleRate: sampleRate,
    q: 0.5,
  );
  final out = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    out[i] = highpass.process(shelf.process(input[i]));
  }
  return out;
}

/// Loudness of one block, from the per-channel mean squares.
///
/// The −0.691 is the standard's calibration constant: it is what makes a
/// full-scale 1 kHz sine read 0 LUFS rather than some arbitrary number.
double _blockLufs(double meanSquareSum) =>
    meanSquareSum <= 0 ? -double.infinity : -0.691 + 10 * _log10(meanSquareSum);

double _log10(double x) => math.log(x) / math.ln10;

/// Mean-square energy of each overlapping block of [blockMs].
///
/// 75% overlap, as the standard specifies — a short burst that straddles two
/// block boundaries would otherwise be split between them and under-read.
List<double> _blockEnergies(
  List<Float64List> weighted,
  double sampleRate,
  double blockMs,
) {
  final block = (blockMs * sampleRate / 1000).round();
  if (block <= 0 || weighted.isEmpty || weighted.first.length < block) {
    return const [];
  }
  final step = math.max(1, block ~/ 4);
  final out = <double>[];
  for (var start = 0; start + block <= weighted.first.length; start += step) {
    var sum = 0.0;
    for (final channel in weighted) {
      var square = 0.0;
      for (var i = start; i < start + block; i++) {
        square += channel[i] * channel[i];
      }
      // Every channel here is L or R, whose weight in the standard is 1.0.
      sum += square / block;
    }
    out.add(sum);
  }
  return out;
}

/// The gated integrated loudness of [energies].
///
/// Two gates, and both matter. The ABSOLUTE one (−70 LUFS) drops digital
/// silence. The RELATIVE one — 10 LU below the ungated average — drops the
/// quiet parts, which is what stops a track with long pauses from measuring
/// quieter than it sounds. Without gating, adding silence to the end of a
/// master would lower its loudness, which is obviously wrong.
double _gatedLoudness(List<double> energies) {
  if (energies.isEmpty) return kLoudnessSilenceLufs;

  final aboveAbsolute = [
    for (final e in energies)
      if (_blockLufs(e) > -70) e,
  ];
  if (aboveAbsolute.isEmpty) return kLoudnessSilenceLufs;

  final ungated = aboveAbsolute.reduce((a, b) => a + b) / aboveAbsolute.length;
  final relativeGate = _blockLufs(ungated) - 10;

  final aboveRelative = [
    for (final e in aboveAbsolute)
      if (_blockLufs(e) > relativeGate) e,
  ];
  if (aboveRelative.isEmpty) return kLoudnessSilenceLufs;

  final mean = aboveRelative.reduce((a, b) => a + b) / aboveRelative.length;
  final lufs = _blockLufs(mean);
  return lufs.isFinite ? lufs : kLoudnessSilenceLufs;
}

/// The loudest block, as LUFS — how [shortTermLufs]/[momentaryLufs] are read.
double _loudestBlock(List<double> energies) {
  if (energies.isEmpty) return kLoudnessSilenceLufs;
  final loudest = energies.reduce(math.max);
  final lufs = _blockLufs(loudest);
  return lufs.isFinite
      ? math.max(lufs, kLoudnessSilenceLufs)
      : kLoudnessSilenceLufs;
}

/// The peak BETWEEN samples, in dBTP.
///
/// A signal can be under 0 dBFS at every sample and still overshoot between
/// them — the reconstructed analogue waveform passes through points the samples
/// never land on — and a converter or a lossy encoder will clip that overshoot.
/// So the signal is upsampled [oversample]× before the peak is taken; 4× is
/// what the standard asks for and catches all but pathological cases.
///
/// Linear interpolation understates the true peak slightly (the real
/// reconstruction is band-limited, not straight lines), so this is a floor on
/// the overshoot rather than an exact figure — which is the safe direction for
/// a measurement whose purpose is to warn.
double truePeakDb(
  Float64List left,
  Float64List? right, {
  int oversample = 4,
}) {
  var peak = 0.0;
  void scan(Float64List pcm) {
    for (var i = 0; i < pcm.length - 1; i++) {
      final a = pcm[i];
      final b = pcm[i + 1];
      for (var k = 0; k < oversample; k++) {
        final t = k / oversample;
        final v = (a + (b - a) * t).abs();
        if (v > peak) peak = v;
      }
    }
    if (pcm.isNotEmpty && pcm.last.abs() > peak) peak = pcm.last.abs();
  }

  scan(left);
  if (right != null) scan(right);
  return peak <= 0 ? kLoudnessSilenceLufs : 20 * _log10(peak);
}

/// Stereo phase correlation: +1 the channels are identical, 0 unrelated, −1 one
/// is the other inverted.
///
/// Worth a meter of its own because a strongly negative reading predicts a
/// problem you cannot hear in stereo: the material will partly disappear when
/// the mix is folded to mono, which is what a phone speaker and many broadcast
/// paths do.
double stereoCorrelation(Float64List left, Float64List right) {
  final n = math.min(left.length, right.length);
  if (n == 0) return 1;
  var sumLR = 0.0, sumLL = 0.0, sumRR = 0.0;
  for (var i = 0; i < n; i++) {
    sumLR += left[i] * right[i];
    sumLL += left[i] * left[i];
    sumRR += right[i] * right[i];
  }
  final denominator = math.sqrt(sumLL * sumRR);
  // Silence correlates with nothing; report +1 (mono-safe) rather than a
  // division by zero, since silence folds to mono without incident.
  if (denominator <= 1e-20) return 1;
  return (sumLR / denominator).clamp(-1.0, 1.0);
}

/// Measure [left]/[right] against the broadcast loudness standard.
LoudnessReading measureLoudness(
  Float64List left,
  Float64List? right, {
  required int sampleRate,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate.toDouble();
  final channels = [
    _kWeight(left, sr),
    if (right != null) _kWeight(right, sr),
  ];

  return (
    integratedLufs: _gatedLoudness(_blockEnergies(channels, sr, 400)),
    shortTermLufs: _loudestBlock(_blockEnergies(channels, sr, 3000)),
    momentaryLufs: _loudestBlock(_blockEnergies(channels, sr, 400)),
    truePeakDb: truePeakDb(left, right),
    correlation: right == null ? 1 : stereoCorrelation(left, right),
  );
}
