// The replay RULES a tracker song plays under, and the space it bends pitch in.
//
// A leaf file on purpose: `TrackerChannel` (tracker_engine.dart) has to hold a
// profile and `ReplayVoice` (tracker_replayer.dart) has to read one, and the
// replayer already imports the engine — so neither could own these without a
// cycle. Everything here is pure arithmetic and constants with no dependencies
// of its own.
//
// `tracker_replayer.dart` re-exports this file, so the many tests and callers
// that import `periodForPitch`/`slidePitchByPeriod`/`kPortaSemitonesPerUnit`
// from there keep working unchanged.

import 'dart:math' as math;
import 'dart:math' show ln2, log, max, min, pow;

/// Semitones per porta param-unit, per tick (1xx/2xx/3xx). 16 units ≈ 1 st/tick.
const double kPortaSemitonesPerUnit = 1 / 16;

/// ProTracker's legal period window; the hardware clamps to it.
const double kModMinPeriod = 113;

const double kModMaxPeriod = 856;

/// Our `pitch` (fractional semitones, 60 = the reference note) as an Amiga
/// period. Period 428 is `modPeriods` index 12, which import maps to MIDI 60.
double periodForPitch(double pitch) => 428.0 * pow(2.0, (60.0 - pitch) / 12.0);

/// The inverse of [periodForPitch].
double pitchForPeriod(double period) =>
    60.0 - 12.0 * (log(period / 428.0) / ln2);

/// One tick of a period-space slide: [delta] period units (negative = up in
/// pitch), clamped to the hardware window, returned as a pitch.
double slidePitchByPeriod(double pitch, double delta) {
  final p = (periodForPitch(pitch) + delta).clamp(kModMinPeriod, kModMaxPeriod);
  return pitchForPeriod(p);
}

/// The space a tracker bends pitch IN.
///
/// This is the deep split between the formats, and it is not a preference: MOD
/// and S3M slide the Amiga PERIOD, XM and IT slide pitch LINEARLY. The same
/// parameter therefore bends by a different interval depending on where the
/// note sits in one and not the other, which is why the same command written
/// into both formats measures as a perfect mirror image under the wrong model
/// (PLAN.md §6):
///
///                        amigaPeriod       linearFrequency
///   porta_*.it           0.683 / 0.544     1.000 / 1.000
///   porta_*.s3m          1.000 / 1.000     0.685 / 0.543
///
/// **Every method here takes POSITIVE = higher pitch.** The period domain's own
/// convention is the opposite — a SHORTER period is a higher note — and leaving
/// that exposed at the call sites is exactly how the two vibrato branches ended
/// up bending opposite ways depending on a gate. The sign lives here now, once.
enum PitchDomain {
  /// MOD, S3M and the Amiga hardware: `f = clock / period`, and a slide is a
  /// linear step in PERIOD, so its size in cents grows with pitch.
  amigaPeriod,

  /// XM and IT (with their linear-slides flag, which is the default for both),
  /// and our own authored songs: a slide is a fixed interval, so the same
  /// parameter bends the same number of cents anywhere.
  linearFrequency;

  /// Raise [pitch] by [units] of this format's slide unit; negative lowers it.
  double slideUp(double pitch, double units) => switch (this) {
        amigaPeriod => slidePitchByPeriod(pitch, -units),
        linearFrequency => pitch + units * kPortaSemitonesPerUnit,
      };

  /// Move [pitch] toward [target] by at most [units], never overshooting.
  ///
  /// The comparison happens in the DOMAIN's own space, not in pitch: sliding up
  /// in pitch means the period is decreasing, so a "do not overshoot" test
  /// written in pitch terms gets the period case backwards.
  double toward(double pitch, double target, double units) {
    switch (this) {
      case amigaPeriod:
        final t = periodForPitch(target);
        final c = periodForPitch(pitch);
        final next = c > t ? max(t, c - units) : min(t, c + units);
        return pitchForPeriod(next.clamp(kModMinPeriod, kModMaxPeriod));
      case linearFrequency:
        final step = units * kPortaSemitonesPerUnit;
        if (pitch < target) return min(target, pitch + step);
        if (pitch > target) return max(target, pitch - step);
        return pitch;
    }
  }

  /// [pitch] displaced by a vibrato of [depth] (the `4xy` y nibble) at LFO
  /// value [lfo] in [-1, 1].
  ///
  /// A positive lobe bends DOWN in both domains, because that is what the
  /// hardware does — it ADDS to the period. The two domains scale depth
  /// differently (255/128 period units vs 1/8 semitone per unit), so the
  /// conversion belongs here rather than at the call site.
  double vibrato(double pitch, int depth, double lfo) => switch (this) {
        amigaPeriod =>
          slidePitchByPeriod(pitch, depth * kVibratoPeriodPerDepthUnit * lfo),
        linearFrequency => pitch - depth * kVibratoDepthSemitonesPerUnit * lfo,
      };
}

/// How a pan position becomes a pair of channel gains.
///
/// Measured, not assumed. `test/fixtures/fmt/setpan_*_Xxx.it` holds a note at a
/// FIXED pan — no depth in it, so whatever it shows is the law — and both
/// references agree:
///
///   position 0xC0 (three-quarters right)   openmpt +0.485   libxmp +0.484
///   linear predicts +0.500 · constant power predicts +0.414
///
/// So trackers pan LINEARLY and we panned constant-power, which is the whole of
/// why panbrello's measured travel came out 0.89 against their 0.98 — the depth
/// constant was right all along. A magnitude discrepancy rarely identifies its
/// own cause; it took a fixture with the suspected variable removed.
enum PanLaw {
  /// `L = 1 − p`, `R = 1 + p` (halved) — what every tracker does. Louder in the
  /// middle than at the edges, which is a real artefact of the format and not
  /// something to improve away when the point is fidelity.
  linear,

  /// `L = cos θ`, `R = sin θ` — equal POWER at every position, so a sound keeps
  /// its apparent loudness as it crosses the field. The better choice for
  /// material of our own, and wrong for reproducing a module.
  constantPower;

  /// The (left, right) gains for [pan] in −1 (hard left) … +1 (hard right).
  ({double left, double right}) gains(double pan) {
    final p = pan.clamp(-1.0, 1.0);
    switch (this) {
      case linear:
        return (left: (1 - p) / 2, right: (1 + p) / 2);
      case constantPower:
        final theta = (p + 1) / 2 * (math.pi / 2);
        return (left: math.cos(theta), right: math.sin(theta));
    }
  }
}

/// How `Ixy`/`Txy` tremor gates the note. Three genuinely different machines.
///
/// What they share — and what was wrong — is that the on/off counter is
/// PERSISTENT and free-runs for as long as the command is held. It is not a
/// position within the row. `I32` at speed 6 makes that visible on purpose: the
/// five-tick cycle straddles the row boundary, so a per-row `k % 5` drifts out
/// of step immediately (envelope correlation 0.33 against references that agree
/// with each other at 1.00).
///
/// Each model below reproduces its reference EXACTLY, tick for tick, on
/// `fmt/tremor_Ixy.{it,s3m,xm}` — the patterns are quoted at each variant.
enum TremorModel {
  /// Impulse Tracker: x ticks on, y off, and a zero nibble means ONE tick.
  ///
  ///     I32 →  ###..###..###..  (openmpt and libxmp agree)
  impulse,

  /// ScreamTracker 3: **x+1 on, y+1 off** — ST3's documented off-by-one.
  ///
  ///     I32 →  ####...####...   (openmpt)
  ///
  /// ⚠️ This is the one place in the whole audit where the two references
  /// genuinely DISAGREE: libxmp plays S3M with the plain [impulse] counter,
  /// openmpt applies the ST3 quirk. There is no consensus to measure against,
  /// so this is a judgement call rather than a measurement — openmpt is picked
  /// because it carries a per-quirk regression module for this behaviour and
  /// libxmp's S3M loader comment ("Ixy Tremor with ontime x and offtime y") is
  /// the generic description rather than a claim about ST3. The fixture's
  /// tolerance is set by how far the references sit from EACH OTHER, which is
  /// wide here for exactly this reason.
  screamTracker,

  /// FastTracker II: the counter does not advance on tick 0, and a fresh note
  /// or volume event SUPPRESSES the gate until the next advance.
  ///
  ///     I32 →  #####....#####...#####....  (openmpt and libxmp agree)
  ///
  /// The irregular period is real, not a rounding artefact: with the counter
  /// advancing on five of every six ticks, a five-tick cycle and a six-tick row
  /// beat against each other. FT2 also reads a zero nibble literally, where the
  /// others treat it as one.
  fastTracker;
}

/// Everything about a source format that changes how its commands REPLAY.
///
/// This replaces three separate booleans that accreted onto `TrackerChannel`
/// one investigation at a time — `protrackerMemory`, `volumeSlideAllTicks`,
/// `linearSlides` — each of which had to be threaded through the same eight
/// `ReplayVoice` construction sites by hand. I missed one of those sites once,
/// and a defaulted parameter hid it; the next quirk should be a FIELD here, not
/// another thread through the same eight places.
///
/// Both reference players are organised this way and it is worth copying:
/// libxmp keeps a quirk bitfield per loader, OpenMPT a player-behaviour set.
///
/// ⬜ Quirks we know exist and have NOT measured get a named field with a
/// comment rather than silence — an empty documented slot is a better record
/// than an absence.
class ReplayProfile {
  const ReplayProfile({
    required this.name,
    required this.pitch,
    required this.latchPortaParam,
    required this.latchVolSlideParam,
    required this.volumeSlideOnTick0,
    required this.tremor,
    required this.panLaw,
  });

  /// For diagnostics and test failure messages — "which rules was this playing
  /// under" is the first question when a fixture disagrees.
  final String name;

  /// The space pitch slides in. See [PitchDomain].
  final PitchDomain pitch;

  /// Whether a zero parameter REUSES the last one for `1xx`/`2xx`.
  ///
  /// ProTracker reads `ch->n_cmd` directly, so a bare `100` slides by zero;
  /// XM/S3M/IT latch. `3xx` and `4xy` latch under BOTH, so this is per-command
  /// rather than a blanket rule and only names the commands that differ.
  final bool latchPortaParam;

  /// The same question for `Axy`/`Dxy`.
  final bool latchVolSlideParam;

  /// S3M/IT slide volume on EVERY tick including tick 0; MOD and XM skip the
  /// first. libxmp calls it `QUIRK_VSALL`.
  final bool volumeSlideOnTick0;

  /// Which tremor machine `Ixy`/`Txy` runs. See [TremorModel] — the three
  /// formats disagree about the counter, the tick-0 rule AND the meaning of a
  /// zero nibble, so this is a model rather than a flag.
  final TremorModel tremor;

  /// How a pan position becomes channel gains. Every tracker is [PanLaw.linear];
  /// our own songs keep [PanLaw.constantPower], which sounds better and is not
  /// what a module playback is trying to be.
  final PanLaw panLaw;

  /// The same rules but bending pitch in [PitchDomain.linearFrequency].
  ///
  /// This is what the "authentic pitch slides" setting turns OFF. The hardware
  /// model is measurably correct — it is what every reference player does, and
  /// what took the portamento fixtures from 0.55 to 1.000 — but it is also
  /// harsher: a fixed period step bends further the higher the note, so a long
  /// slide accelerates. The linear model is the gentler, more "musical" reading
  /// and some listeners prefer it on material that was never written for an
  /// Amiga. Neither is a bug; it is a preference, which is why it is a setting
  /// rather than a constant.
  ///
  /// Only MOD and S3M have a choice to make here. XM and IT are linear by
  /// definition, and our own authored songs use [native].
  ReplayProfile musical() => ReplayProfile(
        name: '$name (musical slides)',
        pitch: PitchDomain.linearFrequency,
        latchPortaParam: latchPortaParam,
        latchVolSlideParam: latchVolSlideParam,
        volumeSlideOnTick0: volumeSlideOnTick0,
        tremor: tremor,
        panLaw: panLaw,
      );

  /// ProTracker. Period slides, no portamento or volume-slide memory.
  static const protracker = ReplayProfile(
    name: 'ProTracker',
    pitch: PitchDomain.amigaPeriod,
    latchPortaParam: false,
    latchVolSlideParam: false,
    volumeSlideOnTick0: false,
    tremor: TremorModel.impulse,
    panLaw: PanLaw.linear,
  );

  /// FastTracker II. Linear slides, latches, skips tick 0.
  static const fastTracker = ReplayProfile(
    name: 'FastTracker II',
    pitch: PitchDomain.linearFrequency,
    latchPortaParam: true,
    latchVolSlideParam: true,
    volumeSlideOnTick0: false,
    tremor: TremorModel.fastTracker,
    panLaw: PanLaw.linear,
  );

  /// ScreamTracker 3. Period slides like ProTracker, but latches and slides
  /// volume on every tick.
  static const screamTracker = ReplayProfile(
    name: 'ScreamTracker 3',
    pitch: PitchDomain.amigaPeriod,
    latchPortaParam: true,
    latchVolSlideParam: true,
    volumeSlideOnTick0: true,
    tremor: TremorModel.screamTracker,
    panLaw: PanLaw.linear,
  );

  /// Impulse Tracker. Linear slides plus ScreamTracker's volume behaviour.
  static const impulse = ReplayProfile(
    name: 'Impulse Tracker',
    pitch: PitchDomain.linearFrequency,
    latchPortaParam: true,
    latchVolSlideParam: true,
    volumeSlideOnTick0: true,
    tremor: TremorModel.impulse,
    panLaw: PanLaw.linear,
  );

  /// Our OWN authored songs — the Loop Mixer, the Tracker screens, anything
  /// built in the app rather than imported.
  ///
  /// This profile is the point of the whole class. Authored songs are not MOD
  /// imports and were never meant to inherit ProTracker's quirks; conflating
  /// the two is why deciding the `PORTA_PERIOD` default felt risky, because it
  /// silently governed both. They keep the musical (linear) model and the
  /// forgiving latching that authoring expects.
  static const native = ReplayProfile(
    name: 'native',
    pitch: PitchDomain.linearFrequency,
    latchPortaParam: true,
    latchVolSlideParam: true,
    volumeSlideOnTick0: false,
    // The one field where `native` differs on TASTE rather than on format:
    // constant power keeps a sound's apparent loudness as it crosses the
    // field, which is what we want for our own material. Modules get the
    // linear law the trackers actually used.
    tremor: TremorModel.impulse,
    panLaw: PanLaw.constantPower,
  );
}

/// Vibrato depth: semitones per depth-unit (y). 8 ⇒ ±1 semitone.
///
/// This is the DEFAULT (semitone-space) model, the vibrato twin of
/// [kPortaSemitonesPerUnit] — a musical approximation, not period-accurate. Under
/// [kVibratoPeriodAccurate] it is replaced by [kVibratoPeriodPerDepthUnit].
const double kVibratoDepthSemitonesPerUnit = 1 / 8;

/// Period-accurate vibrato depth: PERIOD units per depth-unit (y), at the LFO's
/// peak. ProTracker adds `(vibratoTable[pos] * y) >> 7` to the period, with the
/// table peaking at 255, so the peak period wobble is `255/128 · y` units
/// (`pt2_replayer.c` vibrato). `trackerLfo` is that table normalized to ±1.
///
/// This is the vibrato half of the same period-vs-pitch correction B3 made for
/// portamento (see [kPortaPeriodAccurate]): a fixed semitone depth is ~1.6× too
/// deep AND wrong in shape, because a period wobble is not a constant-semitone
/// wobble. In force only under [kVibratoPeriodAccurate].
const double kVibratoPeriodPerDepthUnit = 255.0 / 128.0;

/// The app-wide default for the "authentic pitch slides" preference, consulted
/// by `songFromModuleDoc` when a caller does not pass one explicitly.
///
/// A plain top-level variable, set once from `SettingsService` at startup,
/// rather than a service lookup inside the importer — that keeps module import a
/// pure function the CLI tools and tests can call without wiring up settings,
/// which is how the audit harnesses use it.
///
/// TRUE (the hardware model) is the default because it is the measurably
/// correct one: it is what libopenmpt, libxmp and micromod all do, and it took
/// the portamento fixtures from 0.55 to 1.000 against them. The setting exists
/// because the other reading is gentler on material never written for an Amiga,
/// not because the question is open.
bool trackerAuthenticSlidesDefault = true;
