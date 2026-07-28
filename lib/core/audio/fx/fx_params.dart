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
  // Up to 20 because a NOTCH is only useful when it can be narrow; the gentler
  // shapes simply never get dragged that far.
  'q': FxParamSpec(key: 'q', min: 0.1, max: 20),
  'rateHz': FxParamSpec(key: 'rateHz', min: 0.05, max: 12, unit: 'Hz'),
  'baseFreq': FxParamSpec(key: 'baseFreq', min: 20, max: 8000, unit: 'Hz'),
  'octaves': FxParamSpec(key: 'octaves', min: 0, max: 6, unit: 'oct'),
  'waveform': FxParamSpec(
    key: 'waveform',
    min: 0,
    max: 2,
    integer: true,
    choices: ['Sine', 'Ramp', 'Square'],
  ),
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
  // WS-A9 — named for how LOW the material goes, which is the axis measurement
  // supports (see StretchQuality). Index order matches the enum.
  //
  // ⚠️ Choice labels are ALSO the CLI token in a chain string (`quality=Deep`),
  // which is the whole point of sharing one text form between the GUI and the
  // CLI — so they must stay single words. A first cut read
  // "Deep — bass (≥43 Hz)" and was simply unusable from the command line. The
  // pitch guidance belongs in the caption instead.
  'quality': FxParamSpec(
    key: 'quality',
    min: 0,
    max: 2,
    integer: true,
    choices: ['Light', 'Balanced', 'Deep'],
  ),
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
  // A1 — the filter set's own vocabulary.
  'freqHigh': FxParamSpec(key: 'freqHigh', min: 20, max: 20000, unit: 'Hz'),
  // Taps buy steepness with CPU, and the cost is linear in them; the ceiling
  // matches `kMaxFirTaps` so the slider cannot ask for what the DSP refuses.
  'taps': FxParamSpec(key: 'taps', min: 3, max: 511, integer: true),
  'shape': FxParamSpec(
    key: 'shape',
    min: 0,
    max: 3,
    integer: true,
    choices: ['Low-pass', 'High-pass', 'Band-pass', 'Band-reject'],
  ),
  // Raw biquad coefficients. The feedback pair is bounded by the stability
  // region (|a2| < 1, |a1| < 1 + a2), so ±2 covers every stable filter; the
  // feed-forward taps are gain and get a wider, still-sane range.
  'b0': FxParamSpec(key: 'b0', min: -4, max: 4),
  'b1': FxParamSpec(key: 'b1', min: -4, max: 4),
  'b2': FxParamSpec(key: 'b2', min: -4, max: 4),
  'a1': FxParamSpec(key: 'a1', min: -2, max: 2),
  'a2': FxParamSpec(key: 'a2', min: -1, max: 1),
  // A3 — dynamics.
  'ceilingDb': FxParamSpec(key: 'ceilingDb', min: -24, max: 0, unit: 'dB'),
  'lookaheadMs': FxParamSpec(key: 'lookaheadMs', min: 0.1, max: 50, unit: 'ms'),
  'lowHz': FxParamSpec(key: 'lowHz', min: 40, max: 1000, unit: 'Hz'),
  'highHz': FxParamSpec(key: 'highHz', min: 1000, max: 12000, unit: 'Hz'),
  'lowRatio': FxParamSpec(key: 'lowRatio', min: 1, max: 20, unit: ':1'),
  'midRatio': FxParamSpec(key: 'midRatio', min: 1, max: 20, unit: ':1'),
  'highRatio': FxParamSpec(key: 'highRatio', min: 1, max: 20, unit: ':1'),
  // A4 — channel and stereo field. The matrix coefficients reach ±2 so a
  // deliberate polarity flip or a boost is expressible, not just a blend.
  'leftFromLeft': FxParamSpec(key: 'leftFromLeft', min: -2, max: 2),
  'leftFromRight': FxParamSpec(key: 'leftFromRight', min: -2, max: 2),
  'rightFromLeft': FxParamSpec(key: 'rightFromLeft', min: -2, max: 2),
  'rightFromRight': FxParamSpec(key: 'rightFromRight', min: -2, max: 2),
  'width': FxParamSpec(key: 'width', min: 0, max: 4, unit: 'x'),
  'amount': FxParamSpec(key: 'amount', min: 0, max: 1),
  'cutoffHz': FxParamSpec(key: 'cutoffHz', min: 100, max: 8000, unit: 'Hz'),
  // A5 — restoration.
  'offset': FxParamSpec(key: 'offset', min: -0.5, max: 0.5),
  'harmonics': FxParamSpec(key: 'harmonics', min: 1, max: 20, integer: true),
  // Over 1 subtracts MORE than the estimate — sometimes needed, always the
  // first thing to turn down when it starts warbling.
  'reduction': FxParamSpec(key: 'reduction', min: 0, max: 3),
  'floorAmount': FxParamSpec(key: 'floorAmount', min: 0, max: 0.5),
  'sensitivity': FxParamSpec(key: 'sensitivity', min: 2, max: 50),
  'window': FxParamSpec(key: 'window', min: 8, max: 512, integer: true),
  'threshold': FxParamSpec(key: 'threshold', min: 0.1, max: 1),
  'strength': FxParamSpec(key: 'strength', min: 0, max: 2),
  // A2 / A6.
  'tiltDb': FxParamSpec(key: 'tiltDb', min: -12, max: 12, unit: 'dB'),
  'pivotHz': FxParamSpec(key: 'pivotHz', min: 200, max: 8000, unit: 'Hz'),
  'curve': FxParamSpec(
    key: 'curve',
    min: 0,
    max: 1,
    integer: true,
    choices: ['50 µs', '75 µs'],
  ),
  'endSemitones':
      FxParamSpec(key: 'endSemitones', min: -24, max: 24, unit: 'st'),
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
  // Hum is a MAINS frequency — 50 or 60 — so the useful span is tiny and the
  // general 20..18000 would bury it.
  (FxType.humRemove, 'freq'):
      FxParamSpec(key: 'freq', min: 40, max: 120, unit: 'Hz'),
  // A hum notch has to be needle-narrow or it takes the bass with it.
  (FxType.humRemove, 'q'): FxParamSpec(key: 'q', min: 5, max: 100),
  // `amount` is a 0..1 blend everywhere else; on the loudness curve it is HOW
  // FAR BELOW reference you are listening, in dB. Same word, different quantity
  // — exactly what this override table is for.
  (FxType.loudness, 'amount'):
      FxParamSpec(key: 'amount', min: 0, max: 30, unit: 'dB'),
  // A crossfeed delay is the width of a HEAD, not a musical delay — sub-
  // millisecond. The general `delayMs` range (up to 2 s) would make the useful
  // part of the control a pixel wide.
  (FxType.crossfeed, 'delayMs'):
      FxParamSpec(key: 'delayMs', min: 0.05, max: 2, unit: 'ms'),
  // A steep filter is worth reaching for precisely at the edges of the
  // spectrum — a rumble cut at 30 Hz, a hiss cut at 16 kHz — so its corner
  // spans the whole audible range rather than the general 20..18000.
  (FxType.sincFilter, 'freq'):
      FxParamSpec(key: 'freq', min: 20, max: 20000, unit: 'Hz'),
  // A LEVEL control has to reach inaudible; ±24 dB is the right span for an EQ
  // band's boost/cut, not for a fader.
  (FxType.gain, 'gainDb'):
      FxParamSpec(key: 'gainDb', min: -60, max: 24, unit: 'dB'),
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
      FxType.gate => 'Noise gate',
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
      FxType.autoWah => 'Auto-wah',
      FxType.allpass => 'All-pass',
      FxType.onePoleLowpass => 'Low-pass (gentle)',
      FxType.onePoleHighpass => 'High-pass (gentle)',
      FxType.biquadRaw => 'Biquad (coefficients)',
      FxType.sincFilter => 'Steep filter',
      FxType.hilbert => 'Hilbert (90°)',
      FxType.limiter => 'Limiter',
      FxType.deEsser => 'De-esser',
      FxType.multibandCompressor => 'Multiband compressor',
      FxType.remix => 'Channel matrix',
      FxType.swapChannels => 'Swap channels',
      FxType.stereoWidth => 'Stereo width',
      FxType.centreCancel => 'Centre cancel',
      FxType.crossfeed => 'Crossfeed',
      FxType.autoPan => 'Auto-pan',
      FxType.dcShift => 'DC shift',
      FxType.humRemove => 'Hum removal',
      FxType.noiseReduce => 'Noise reduction',
      FxType.declick => 'De-click',
      FxType.declip => 'De-clip',
      FxType.tilt => 'Tilt',
      FxType.loudness => 'Loudness',
      FxType.deEmphasis => 'De-emphasis',
      FxType.contrast => 'Presence',
      FxType.pitchBend => 'Pitch bend',
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
      'baseFreq' => 'Base',
      'octaves' => 'Sweep',
      'waveform' => 'Shape',
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
      'quality' => 'Lowest note it holds',
      'formant' => 'Formant',
      'carrierMix' => 'Ring mod',
      'radioMix' => 'Band-limit',
      'grit' => 'Grit',
      'kind' => 'Curve',
      'freqHigh' => 'Upper edge',
      'taps' => 'Steepness',
      'shape' => 'Shape',
      'b0' => 'b0',
      'b1' => 'b1',
      'b2' => 'b2',
      'a1' => 'a1',
      'a2' => 'a2',
      'ceilingDb' => 'Ceiling',
      'lookaheadMs' => 'Look-ahead',
      'lowHz' => 'Low split',
      'highHz' => 'High split',
      'lowRatio' => 'Low ratio',
      'midRatio' => 'Mid ratio',
      'highRatio' => 'High ratio',
      'leftFromLeft' => 'L from L',
      'leftFromRight' => 'L from R',
      'rightFromLeft' => 'R from L',
      'rightFromRight' => 'R from R',
      'width' => 'Width',
      'amount' => 'Amount',
      'cutoffHz' => 'Dullness',
      'offset' => 'Offset',
      'harmonics' => 'Harmonics',
      'reduction' => 'Reduction',
      'floorAmount' => 'Residual floor',
      'sensitivity' => 'Sensitivity',
      'window' => 'Window',
      'threshold' => 'Threshold',
      'strength' => 'Strength',
      'tiltDb' => 'Tilt',
      'pivotHz' => 'Pivot',
      'curve' => 'Curve',
      'endSemitones' => 'To',
      _ => key,
    };

/// The caption an FX panel should put on [spec]'s slider: its label, plus the
/// unit when the unit is a dimensional one the reader needs ("Gain dB", "Time
/// ms").
///
/// `:1`, `st` and `x` are left off because the label already says it — "Ratio
/// :1" and "Semitones st" read as noise, where "Gain" without its dB does not
/// say enough. Here rather than in a widget so every mode's FX panel captions a
/// parameter the same way.
String fxParamCaption(FxParamSpec spec) {
  const dimensional = {'dB', 'Hz', 'ms', 's', 'oct'};
  final label = fxParamLabel(spec.key);
  return dimensional.contains(spec.unit) ? '$label ${spec.unit}' : label;
}

/// A sensible slider increment for [spec] — the last thing an FX panel needs
/// that the descriptor did not already say.
///
/// Derived rather than tabulated for the same reason the ranges are: a step
/// hand-written per effect is one more table to forget to update. The unit is
/// what decides it, because that is what sets the scale a human thinks in —
/// nobody drags a frequency in 200 Hz jumps just because the range is wide.
double fxSliderStep(FxParamSpec spec) {
  if (spec.integer) return 1;
  final span = spec.max - spec.min;
  if (span <= 0) return 0.01;
  return switch (spec.unit) {
    'Hz' => span > 2000 ? 10 : (span > 200 ? 1 : 0.1),
    'ms' => span > 500 ? 10 : 1,
    'dB' => span > 40 ? 1 : 0.5,
    's' => 0.1,
    _ => _snappedStep(span / 100),
  };
}

/// [raw] rounded to the nearest 1, 2 or 5 times a power of ten, so a derived
/// step still lands on numbers a person would have chosen.
double _snappedStep(double raw) {
  if (raw <= 0) return 0.01;
  var magnitude = 1.0;
  while (magnitude > raw) {
    magnitude /= 10;
  }
  while (magnitude * 10 <= raw) {
    magnitude *= 10;
  }
  final normalized = raw / magnitude;
  final snapped = normalized <= 1
      ? 1.0
      : normalized <= 2
          ? 2.0
          : normalized <= 5
              ? 5.0
              : 10.0;
  return snapped * magnitude;
}

/// How the effects group in a picker, so a 28-item flat list does not greet the
/// user.
enum FxCategory {
  level,

  /// A5 — the repair tools. Their own group because they answer a different
  /// question from every other effect: not "how should this sound" but "what is
  /// wrong with this recording".
  restoration,
  filter,
  dynamics,
  modulation,
  drive,
  space,
  pitch,
  voice,

  /// A4 — the ops defined by the RELATIONSHIP between the two channels. Their
  /// own group rather than filed under level, because "what the stereo image
  /// does" is the question a user has when reaching for any of them.
  stereo,
}

/// The category [type] belongs to.
FxCategory fxCategory(FxType type) => switch (type) {
      FxType.gain || FxType.pan => FxCategory.level,
      FxType.dcShift ||
      FxType.humRemove ||
      FxType.noiseReduce ||
      FxType.declick ||
      FxType.declip =>
        FxCategory.restoration,
      FxType.remix ||
      FxType.swapChannels ||
      FxType.stereoWidth ||
      FxType.centreCancel ||
      FxType.crossfeed ||
      FxType.autoPan =>
        FxCategory.stereo,
      FxType.lowpass ||
      FxType.highpass ||
      FxType.bandpass ||
      FxType.notch ||
      FxType.peakingEq ||
      FxType.lowShelf ||
      FxType.highShelf ||
      FxType.tilt ||
      FxType.loudness ||
      FxType.deEmphasis ||
      FxType.contrast ||
      FxType.autoWah ||
      FxType.allpass ||
      FxType.onePoleLowpass ||
      FxType.onePoleHighpass ||
      FxType.biquadRaw ||
      FxType.sincFilter ||
      FxType.hilbert =>
        FxCategory.filter,
      FxType.compressor ||
      FxType.gate ||
      FxType.limiter ||
      FxType.deEsser ||
      FxType.multibandCompressor =>
        FxCategory.dynamics,
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
      FxType.pitchShift ||
      FxType.timeStretch ||
      FxType.pitchBend =>
        FxCategory.pitch,
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
      FxCategory.stereo => 'Stereo & channels',
      FxCategory.restoration => 'Repair',
    };
