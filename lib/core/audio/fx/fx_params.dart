// lib/core/audio/fx/fx_params.dart
//
// A4 — what each FX param MEANS, so one widget can edit all 28 effects.
//
// The FX rack has to render a control per param without knowing anything about
// the effect: a slider needs a range, a unit, and a label, and `bits`/`stages`/
// `kind` need to snap to whole numbers rather than pretending to be continuous.
// Without a table, every mode's FX panel hand-writes that per effect — which is
// exactly the duplication this arc exists to remove, and why adding a new
// [FxType] used to mean editing UI in five places.
//
// The table describes RANGES, not defaults. Defaults live in `defaultFx` and are
// read from there, so the two can never disagree — the one thing a duplicated
// table would inevitably get wrong.
//
// Ranges are keyed by param NAME, because the names are already consistent
// across effects (every `mix` is 0..1, every `freq` is audible-spectrum), with
// per-type overrides only where an effect genuinely means something different by
// the same word. `fx_params_test.dart` asserts every param of every type has a
// descriptor and that every default sits inside its own range.
//
// Pure Dart — the widget layer sits on top, this does not.

import 'package:comet_beat/core/audio/fx/fx_spec.dart';

/// How one FX parameter should be presented and constrained.
class FxParamSpec {
  const FxParamSpec({
    required this.key,
    required this.min,
    required this.max,
    this.unit = '',
    this.integer = false,
    this.choices,
  });

  /// The key in [FxSpec.params].
  final String key;

  final double min;
  final double max;

  /// A short suffix for the value readout: `dB`, `Hz`, `ms`, `st`, `x`, or ''.
  final String unit;

  /// Snap to whole numbers — a "3.7-stage phaser" is not a thing.
  final bool integer;

  /// When set, the value is an INDEX into these labels and the UI should show a
  /// picker instead of a slider (currently only the distortion curve).
  final List<String>? choices;

  bool get isChoice => choices != null;

  /// [value] clamped into range and snapped if [integer].
  double clamp(double value) {
    final v = value.clamp(min, max).toDouble();
    return integer ? v.roundToDouble() : v;
  }

  /// [value] as a 0..1 slider position.
  double normalize(double value) =>
      max == min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0).toDouble();

  /// A 0..1 slider position back to a value.
  double denormalize(double t) => clamp(min + (max - min) * t.clamp(0.0, 1.0));
}

/// The default range for a param name, used by every effect that has one.
const _byName = <String, FxParamSpec>{
  'mix': FxParamSpec(key: 'mix', min: 0, max: 1),
  'pan': FxParamSpec(key: 'pan', min: -1, max: 1),
  'gainDb': FxParamSpec(key: 'gainDb', min: -24, max: 24, unit: 'dB'),
  'makeupDb': FxParamSpec(key: 'makeupDb', min: 0, max: 24, unit: 'dB'),
  'thresholdDb': FxParamSpec(key: 'thresholdDb', min: -60, max: 0, unit: 'dB'),
  'rangeDb': FxParamSpec(key: 'rangeDb', min: -90, max: 0, unit: 'dB'),
  'kneeDb': FxParamSpec(key: 'kneeDb', min: 0, max: 24, unit: 'dB'),
  'ratio': FxParamSpec(key: 'ratio', min: 1, max: 20, unit: ':1'),
  'attackMs': FxParamSpec(key: 'attackMs', min: 0.1, max: 200, unit: 'ms'),
  'releaseMs': FxParamSpec(key: 'releaseMs', min: 5, max: 2000, unit: 'ms'),
  'freq': FxParamSpec(key: 'freq', min: 20, max: 18000, unit: 'Hz'),
  'minFreq': FxParamSpec(key: 'minFreq', min: 20, max: 4000, unit: 'Hz'),
  'maxFreq': FxParamSpec(key: 'maxFreq', min: 200, max: 12000, unit: 'Hz'),
  'radioLowHz': FxParamSpec(key: 'radioLowHz', min: 50, max: 4000, unit: 'Hz'),
  'radioHighHz':
      FxParamSpec(key: 'radioHighHz', min: 500, max: 12000, unit: 'Hz'),
  'carrierHz': FxParamSpec(key: 'carrierHz', min: 20, max: 2000, unit: 'Hz'),
  'q': FxParamSpec(key: 'q', min: 0.1, max: 12),
  'rateHz': FxParamSpec(key: 'rateHz', min: 0.05, max: 12, unit: 'Hz'),
  'depth': FxParamSpec(key: 'depth', min: 0, max: 1),
  'depthMs': FxParamSpec(key: 'depthMs', min: 0.1, max: 20, unit: 'ms'),
  'feedback': FxParamSpec(key: 'feedback', min: 0, max: 0.95),
  'delayMs': FxParamSpec(key: 'delayMs', min: 1, max: 2000, unit: 'ms'),
  'spread': FxParamSpec(key: 'spread', min: 0, max: 1),
  'roomSize': FxParamSpec(key: 'roomSize', min: 0, max: 1),
  'damping': FxParamSpec(key: 'damping', min: 0, max: 1),
  'decay': FxParamSpec(key: 'decay', min: 0.1, max: 10, unit: 's'),
  'seconds': FxParamSpec(key: 'seconds', min: 0.1, max: 8, unit: 's'),
  'predelayMs': FxParamSpec(key: 'predelayMs', min: 0, max: 200, unit: 'ms'),
  'drive': FxParamSpec(key: 'drive', min: 0, max: 20),
  'bits': FxParamSpec(key: 'bits', min: 1, max: 16, integer: true),
  'stages': FxParamSpec(key: 'stages', min: 1, max: 12, integer: true),
  'semitones': FxParamSpec(key: 'semitones', min: -24, max: 24, unit: 'st'),
  'speed': FxParamSpec(key: 'speed', min: 0.25, max: 4, unit: 'x'),
  'formant': FxParamSpec(key: 'formant', min: -0.8, max: 0.8),
  'carrierMix': FxParamSpec(key: 'carrierMix', min: 0, max: 1),
  'radioMix': FxParamSpec(key: 'radioMix', min: 0, max: 1),
  'grit': FxParamSpec(key: 'grit', min: 0, max: 1),
  'kind': FxParamSpec(
    key: 'kind',
    min: 0,
    max: 3,
    integer: true,
    choices: ['Hard clip', 'Soft clip', 'Fuzz', 'Wave fold'],
  ),
};

/// Ranges that differ for one specific effect, where the same word means
/// something narrower or wider than usual.
const _byTypeAndName = <(FxType, String), FxParamSpec>{
  // A highpass sweeping to 18 kHz would just mute the track; keep it useful.
  (FxType.highpass, 'freq'):
      FxParamSpec(key: 'freq', min: 20, max: 2000, unit: 'Hz'),
  // A tremolo wants to reach genuinely fast rates.
  (FxType.tremolo, 'rateHz'):
      FxParamSpec(key: 'rateHz', min: 0.1, max: 20, unit: 'Hz'),
  // The vocoder's carrier is a pitch, not a modulation frequency.
  (FxType.vocoder, 'carrierHz'):
      FxParamSpec(key: 'carrierHz', min: 40, max: 800, unit: 'Hz'),
  // The convolution reverb's `decay` is a 0..1 SHAPE factor for its generated
  // impulse, not a time — the algorithmic reverb's `decay` is in seconds. Same
  // word, different quantity, which is exactly what this override table is for:
  // without it the slider would offer 10 and read "0.50s".
  (FxType.convolutionReverb, 'decay'):
      FxParamSpec(key: 'decay', min: 0, max: 1),
};

/// Every editable param of [type], in the order [defaultFx] declares them —
/// which is the order they are applied in, so the rack reads like the signal
/// path rather than an alphabetised list.
///
/// A param with no descriptor still appears, with a permissive 0..1 fallback, so
/// a newly added [FxType] is editable before anybody remembers to update this
/// table. `fx_params_test.dart` fails when that happens, so the fallback is a
/// safety net, not a licence.
List<FxParamSpec> fxParamSpecs(FxType type) => [
      for (final key in defaultFx(type).params.keys) fxParamSpec(type, key),
    ];

/// The descriptor for one param of one effect.
FxParamSpec fxParamSpec(FxType type, String key) =>
    _byTypeAndName[(type, key)] ??
    _byName[key] ??
    FxParamSpec(key: key, min: 0, max: 1);

/// Whether [key] has a real descriptor rather than the permissive fallback.
bool hasFxParamSpec(FxType type, String key) =>
    _byTypeAndName.containsKey((type, key)) || _byName.containsKey(key);

/// A human label for [type] — the effect's name in the rack. Deliberately here
/// rather than in the l10n ARBs: these are established audio-engineering terms
/// that are not translated in any DAW the user will meet, and keeping them with
/// the table means a new [FxType] cannot ship without one.
String fxTypeLabel(FxType type) => switch (type) {
      FxType.gain => 'Gain',
      FxType.pan => 'Pan',
      FxType.reverb => 'Reverb',
      FxType.convolutionReverb => 'Convolution reverb',
      FxType.delay => 'Delay',
      FxType.chorus => 'Chorus',
      FxType.flanger => 'Flanger',
      FxType.ringMod => 'Ring mod',
      FxType.distortion => 'Distortion',
      FxType.bitCrush => 'Bit crush',
      FxType.lowpass => 'Low-pass',
      FxType.highpass => 'High-pass',
      FxType.bandpass => 'Band-pass',
      FxType.notch => 'Notch',
      FxType.peakingEq => 'Peaking EQ',
      FxType.lowShelf => 'Low shelf',
      FxType.highShelf => 'High shelf',
      FxType.compressor => 'Compressor',
      FxType.gate => 'Gate',
      FxType.pitchShift => 'Pitch shift',
      FxType.timeStretch => 'Time stretch',
      FxType.tremolo => 'Tremolo',
      FxType.vocoder => 'Vocoder',
      FxType.phaser => 'Phaser',
      FxType.voiceShape => 'Voice shape',
      FxType.voiceChipmunk => 'Chipmunk',
      FxType.voiceDeep => 'Deep voice',
      FxType.voiceRobot => 'Robot',
      FxType.voiceRadio => 'Radio',
    };

/// A short label for one param — the slider caption.
String fxParamLabel(String key) => switch (key) {
      'mix' => 'Mix',
      'pan' => 'Pan',
      'gainDb' => 'Gain',
      'makeupDb' => 'Make-up',
      'thresholdDb' => 'Threshold',
      'rangeDb' => 'Range',
      'kneeDb' => 'Knee',
      'ratio' => 'Ratio',
      'attackMs' => 'Attack',
      'releaseMs' => 'Release',
      'freq' => 'Frequency',
      'minFreq' => 'From',
      'maxFreq' => 'To',
      'radioLowHz' => 'Band from',
      'radioHighHz' => 'Band to',
      'carrierHz' => 'Carrier',
      'q' => 'Resonance',
      'rateHz' => 'Rate',
      'depth' => 'Depth',
      'depthMs' => 'Depth',
      'feedback' => 'Feedback',
      'delayMs' => 'Time',
      'spread' => 'Spread',
      'roomSize' => 'Room',
      'damping' => 'Damping',
      'decay' => 'Decay',
      'seconds' => 'Length',
      'predelayMs' => 'Pre-delay',
      'drive' => 'Drive',
      'bits' => 'Bits',
      'stages' => 'Stages',
      'semitones' => 'Semitones',
      'speed' => 'Speed',
      'formant' => 'Formant',
      'carrierMix' => 'Ring mod',
      'radioMix' => 'Band-limit',
      'grit' => 'Grit',
      'kind' => 'Curve',
      _ => key,
    };

/// How the effects group in a picker, so a 28-item flat list does not greet the
/// user.
enum FxCategory {
  level,
  filter,
  dynamics,
  modulation,
  drive,
  space,
  pitch,
  voice
}

/// The category [type] belongs to.
FxCategory fxCategory(FxType type) => switch (type) {
      FxType.gain || FxType.pan => FxCategory.level,
      FxType.lowpass ||
      FxType.highpass ||
      FxType.bandpass ||
      FxType.notch ||
      FxType.peakingEq ||
      FxType.lowShelf ||
      FxType.highShelf =>
        FxCategory.filter,
      FxType.compressor || FxType.gate => FxCategory.dynamics,
      FxType.chorus ||
      FxType.flanger ||
      FxType.phaser ||
      FxType.tremolo ||
      FxType.ringMod =>
        FxCategory.modulation,
      FxType.distortion || FxType.bitCrush => FxCategory.drive,
      FxType.reverb ||
      FxType.convolutionReverb ||
      FxType.delay =>
        FxCategory.space,
      FxType.pitchShift || FxType.timeStretch => FxCategory.pitch,
      FxType.vocoder ||
      FxType.voiceShape ||
      FxType.voiceChipmunk ||
      FxType.voiceDeep ||
      FxType.voiceRobot ||
      FxType.voiceRadio =>
        FxCategory.voice,
    };

/// A human label for a category.
String fxCategoryLabel(FxCategory category) => switch (category) {
      FxCategory.level => 'Level',
      FxCategory.filter => 'Filter & EQ',
      FxCategory.dynamics => 'Dynamics',
      FxCategory.modulation => 'Modulation',
      FxCategory.drive => 'Drive',
      FxCategory.space => 'Space',
      FxCategory.pitch => 'Pitch & time',
      FxCategory.voice => 'Voice',
    };
