// Channel and stereo-field operations — the ops that need BOTH sides at once.
//
// Every other effect in the rack is a per-channel transform: the stereo path can
// run it on left and right independently and get the right answer. These cannot
// be done that way even in principle. Swapping channels, folding to mono,
// widening the image, pulling out what is only on one side — each is defined by
// the RELATIONSHIP between the two channels, so it has to see both.
//
// That is why they live in their own file with a stereo-in/stereo-out signature,
// and why `fx_chain.dart` gives each one an explicit case in its stereo dispatch
// instead of letting them fall through to the per-channel default. On a MONO
// buffer they are pass-throughs, which is the honest answer: there is no second
// channel to relate to.
//
// Clean-room from standard mid/side and binaural-crossfeed theory: mid = (L+R)/2
// and side = (L−R)/2, and a crossfeed is a delayed, low-passed copy of the
// opposite channel — the geometry of a head, not anyone's code.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/lfo.dart' show lfoValue;

/// A stereo pair, matching the shape the FX chain passes around.
typedef StereoPair = ({Float64List left, Float64List right});

/// Blend [wet] into [dry] by [mix], returning a new pair.
StereoPair _blend(StereoPair dry, StereoPair wet, double mix) {
  final m = mix.clamp(0.0, 1.0);
  if (m >= 1) return wet;
  final n = dry.left.length;
  final left = Float64List(n);
  final right = Float64List(n);
  for (var i = 0; i < n; i++) {
    left[i] = (1 - m) * dry.left[i] + m * wet.left[i];
    right[i] = (1 - m) * dry.right[i] + m * wet.right[i];
  }
  return (left: left, right: right);
}

/// The general 2×2 channel matrix: each output is a weighted sum of both inputs.
///
/// The escape hatch of the channel ops, the way `biquadRaw` is for filters — it
/// subsumes swap (0,1,1,0), a mono fold (0.5,0.5,0.5,0.5), a balance, a channel
/// mute, and a polarity flip on one side. The named effects beside it exist
/// because "swap the channels" is easier to find than four numbers, not because
/// they do anything this cannot.
StereoPair remixFx(
  Float64List left,
  Float64List right, {
  double leftFromLeft = 1,
  double leftFromRight = 0,
  double rightFromLeft = 0,
  double rightFromRight = 1,
  double mix = 1,
}) {
  final n = math.min(left.length, right.length);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < n; i++) {
    outLeft[i] = leftFromLeft * left[i] + leftFromRight * right[i];
    outRight[i] = rightFromLeft * left[i] + rightFromRight * right[i];
  }
  return _blend(
    (left: left, right: right),
    (left: outLeft, right: outRight),
    mix,
  );
}

/// Swap left and right.
StereoPair swapChannelsFx(
  Float64List left,
  Float64List right, {
  double mix = 1,
}) =>
    remixFx(
      left,
      right,
      leftFromLeft: 0,
      leftFromRight: 1,
      rightFromLeft: 1,
      rightFromRight: 0,
      mix: mix,
    );

/// Stereo width in mid/side space: 0 collapses to mono, 1 is unchanged, 2 is
/// twice as wide.
///
/// Widening scales the SIDE component, which is the part that differs between
/// the channels; the mid (what they share) is left alone, so the centre of the
/// image — usually the vocal and the kick — stays where it is and only the
/// edges move.
StereoPair stereoWidthFx(
  Float64List left,
  Float64List right, {
  double width = 1,
  double mix = 1,
}) {
  final w = width.clamp(0.0, 4.0).toDouble();
  final n = math.min(left.length, right.length);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < n; i++) {
    final mid = (left[i] + right[i]) * 0.5;
    final side = (left[i] - right[i]) * 0.5 * w;
    outLeft[i] = mid + side;
    outRight[i] = mid - side;
  }
  return _blend(
    (left: left, right: right),
    (left: outLeft, right: outRight),
    mix,
  );
}

/// Cancel what is common to both channels — the "take the centre out" trick.
///
/// Anything panned dead centre (typically a lead vocal) is identical in both
/// channels, so subtracting one from the other removes it while everything
/// panned to a side survives. [amount] 0 leaves the signal alone and 1 is a full
/// cancellation.
///
/// It is a blunt instrument and the docs should say so rather than promise
/// "vocal removal": it also takes out the bass and the kick, which are usually
/// centred too, and anything the centred part was sent through (its reverb) is
/// stereo and stays behind. What comes out is mono — the side signal — because
/// that is what the difference IS.
StereoPair centreCancelFx(
  Float64List left,
  Float64List right, {
  double amount = 1,
  double mix = 1,
}) {
  final a = amount.clamp(0.0, 1.0).toDouble();
  final n = math.min(left.length, right.length);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < n; i++) {
    final mid = (left[i] + right[i]) * 0.5;
    // Removing `a` of the shared component from each side.
    outLeft[i] = left[i] - a * mid;
    outRight[i] = right[i] - a * mid;
  }
  return _blend(
    (left: left, right: right),
    (left: outLeft, right: outRight),
    mix,
  );
}

/// Headphone crossfeed: each ear hears a little of the opposite channel, delayed
/// and dulled.
///
/// On speakers each ear hears both of them, slightly later and darker from the
/// far side because the head is in the way. Headphones remove that entirely,
/// which is why a hard-panned mix can feel like it is happening inside your
/// skull. This puts a modest amount of it back: [delayMs] is the path around the
/// head and [cutoffHz] the dullness of it.
StereoPair crossfeedFx(
  Float64List left,
  Float64List right, {
  required double sampleRate,
  double amount = 0.4,
  double delayMs = 0.3,
  double cutoffHz = 700,
  double mix = 1,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final a = amount.clamp(0.0, 1.0).toDouble();
  final delay = (delayMs.clamp(0.0, 5.0) * sr / 1000).round();
  final coefficient = math.exp(-2 * math.pi * cutoffHz.clamp(100, 8000) / sr);
  final k = 1 - coefficient;

  final n = math.min(left.length, right.length);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  var lowLeft = 0.0;
  var lowRight = 0.0;
  for (var i = 0; i < n; i++) {
    // The delayed opposite channel, low-passed — the far-ear path.
    final fromRight = i >= delay ? right[i - delay] : 0.0;
    final fromLeft = i >= delay ? left[i - delay] : 0.0;
    lowLeft = k * fromRight + coefficient * lowLeft;
    lowRight = k * fromLeft + coefficient * lowRight;
    outLeft[i] = left[i] + a * lowLeft;
    outRight[i] = right[i] + a * lowRight;
  }
  return _blend(
    (left: left, right: right),
    (left: outLeft, right: outRight),
    mix,
  );
}

/// Sweep the image left and right with an LFO.
///
/// Constant-power, so the perceived loudness stays put while the position
/// moves — a linear pan dips in the middle, which reads as a wobble in volume
/// rather than movement. [depth] 0 is centred and 1 sweeps hard to each side.
/// [waveform] uses the shared tracker LFO shapes (0 sine, 1 ramp, 2 square), so
/// a square gives the hard left/right ping-pong.
StereoPair autoPanFx(
  Float64List left,
  Float64List right, {
  required double sampleRate,
  double rateHz = 0.5,
  double depth = 0.8,
  int waveform = 0,
  double mix = 1,
}) {
  final sr = sampleRate <= 0 ? 44100.0 : sampleRate;
  final d = depth.clamp(0.0, 1.0).toDouble();
  final rate = rateHz.clamp(0.01, 20.0);
  final n = math.min(left.length, right.length);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < n; i++) {
    final phase = 2 * math.pi * rate * i / sr;
    final pan = lfoValue(waveform, phase) * d; // −1..1
    final angle = (pan + 1) * math.pi / 4; // 0..π/2
    outLeft[i] = left[i] * math.cos(angle) * math.sqrt2;
    outRight[i] = right[i] * math.sin(angle) * math.sqrt2;
  }
  return _blend(
    (left: left, right: right),
    (left: outLeft, right: outRight),
    mix,
  );
}
