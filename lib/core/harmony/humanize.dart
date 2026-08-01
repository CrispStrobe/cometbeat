// lib/core/harmony/humanize.dart
//
// BB-A6 — the difference between "a band" and "a sequencer".
//
// Nothing here changes WHAT is played, only exactly when and how hard. Three
// effects, in the order they matter:
//
//   1. SWING, as a continuous ratio. Off-beat eighths move late by a fraction
//      of the gap to the next beat. A triplet-only switch cannot express medium
//      swing, which is most swing.
//   2. ROLE FEEL. A drummer's hat sits fractionally early, a bassist behind the
//      beat, a comp pushed. This is the single biggest reason a sequenced band
//      sounds mechanical: everything lands on the same sample.
//   3. VELOCITY SHAPE. Downbeats louder than off-beats, and a phrase arc.
//
// TWO HARD RULES, both asserted in the tests:
//
//   * Bounded. No note moves more than a configured fraction of a subdivision,
//     so humanisation can never reorder events or push one past the next.
//   * Reproducible. Everything comes from the seed, so a shared chart sounds
//     the same on two devices — and OFF must render byte-identically to the
//     un-humanised output, or this becomes impossible to A/B.
library;

/// How much each effect applies. All zero is a no-op by construction, which is
/// what makes "humanisation off" byte-identical rather than merely similar.
class HumanizeSpec {
  const HumanizeSpec({
    this.swing = 0,
    this.timingJitter = 0,
    this.velocityJitter = 0,
    this.roleOffset = 0,
    this.accentDownbeat = 0,
  });

  /// 0 = straight, 1 = full triplet. Applies to off-beat eighths only.
  final double swing;

  /// Maximum timing move, in quarter-note beats, from the jitter alone.
  final double timingJitter;

  /// Maximum velocity move, 0..1.
  final double velocityJitter;

  /// A constant push (positive = late) for this role, in beats. A drummer's hat
  /// is slightly negative, a bassist slightly positive.
  final double roleOffset;

  /// How much louder a downbeat is than an off-beat, 0..1.
  final double accentDownbeat;

  /// Everything off. The identity.
  static const HumanizeSpec none = HumanizeSpec();

  bool get isIdentity =>
      swing == 0 &&
      timingJitter == 0 &&
      velocityJitter == 0 &&
      roleOffset == 0 &&
      accentDownbeat == 0;
}

/// Per-role feel, in beats. Small — a few milliseconds at any real tempo — but
/// this is the effect people hear as "a band" rather than "a grid".
class RoleFeel {
  /// The hat leads very slightly.
  static const double drums = -0.006;

  /// The bass sits behind.
  static const double bass = 0.010;

  /// The comp pushes.
  static const double comp = -0.004;

  /// Pads have no attack to place.
  static const double pad = 0;
}

/// One event's timing and velocity, after humanising.
typedef Humanized = ({double beat, double velocity});

/// Applies swing, feel, jitter and accent to one event.
///
/// [beat] is in quarter-note beats from the bar start; [barBeats] is the bar's
/// length, used only to clamp so nothing is pushed past the barline.
Humanized humanizeEvent({
  required double beat,
  required double velocity,
  required double barBeats,
  HumanizeSpec spec = HumanizeSpec.none,
  int seed = 0,
  int index = 0,
}) {
  if (spec.isIdentity) return (beat: beat, velocity: velocity);

  var out = beat;

  // 1. Swing: an off-beat eighth moves toward the following beat. At swing 1 it
  //    lands on the triplet, a third of the way past the halfway point.
  if (spec.swing > 0) {
    final withinBeat = beat - beat.floorToDouble();
    // Only the eighth-note off-beat swings; a sixteenth grid is a different
    // feel and moving it here would smear it.
    if ((withinBeat - 0.5).abs() < 1e-6) {
      out += spec.swing * (2 / 3 - 0.5);
    }
  }

  // 2. Role feel: a constant push, the same for every note of the role.
  out += spec.roleOffset;

  // 3. Jitter: bounded, seeded, and centred on zero so it does not drag.
  if (spec.timingJitter > 0) {
    out += _signed(seed, index, 0) * spec.timingJitter;
  }

  // Never before the bar, never past its end — humanisation must not reorder
  // events or move one into the next bar.
  out = out.clamp(0.0, barBeats <= 0 ? 0.0 : barBeats - 1e-6);

  var level = velocity;
  if (spec.accentDownbeat > 0) {
    final onBeat = (beat - beat.roundToDouble()).abs() < 1e-6;
    level += onBeat ? spec.accentDownbeat * 0.5 : -spec.accentDownbeat * 0.5;
  }
  if (spec.velocityJitter > 0) {
    level += _signed(seed, index, 1) * spec.velocityJitter;
  }

  return (beat: out, velocity: level.clamp(0.0, 1.0));
}

/// A deterministic value in −1..1 from the seed, the index and a channel.
///
/// Channel keeps timing and velocity independent: deriving both from one value
/// correlates them, so every late note would also be loud — an audible pattern
/// rather than a human one.
double _signed(int seed, int index, int channel) {
  var h = (seed * 374761393 + index * 668265263 + channel * 2147483647) &
      0x7fffffff;
  h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff;
  h ^= h >> 16;
  // 0..1 → −1..1
  return (h % 20001) / 10000.0 - 1.0;
}

/// The feel for a role name, so callers do not repeat the table.
double roleFeelFor(String role) => switch (role) {
      'drums' => RoleFeel.drums,
      'bass' => RoleFeel.bass,
      'comp' => RoleFeel.comp,
      _ => RoleFeel.pad,
    };
