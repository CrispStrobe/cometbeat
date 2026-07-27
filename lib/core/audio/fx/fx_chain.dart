// lib/core/audio/fx/fx_chain.dart
//
// The FX dispatch: [FxSpec] (data) -> `crisp_dsp/` (DSP). Every mode renders its
// effects through [applyFxChain] / [applyFxChainStereo], so an effect sounds the
// same wherever it was authored.
//
// Invariant every caller relies on: an effect returns a buffer of the SAME
// length as its input, so stems stay aligned (`mixStems`) and clips stay on the
// timeline grid. Length-changing DSP (pitch shift, time stretch) is refitted to
// the input length before the wet/dry blend.
//
// Moved verbatim out of `daw_timeline.dart` (A1); only identifiers were renamed.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart'
    show Biquad, BiquadKind, biquadFx, biquadRawFx;
import 'package:comet_beat/core/audio/crisp_dsp/convolution_reverb.dart'
    show convolutionReverbFx;
import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart'
    show DistortionKind, distortionFx;
import 'package:comet_beat/core/audio/crisp_dsp/dynamics.dart'
    show
        compressorFx,
        compressorFxStereo,
        deEsserFx,
        gateFx,
        gateFxStereo,
        lookaheadLimiterFx,
        multibandCompressorFx;
import 'package:comet_beat/core/audio/crisp_dsp/fir.dart'
    show FirShape, hilbertFx, sincFilterFx;
import 'package:comet_beat/core/audio/crisp_dsp/lfo.dart' show lfoValue;
import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show
        chorusFx,
        chorusFxStereo,
        delayFx,
        delayFxStereo,
        flangerFx,
        flangerFxStereo;
import 'package:comet_beat/core/audio/crisp_dsp/one_pole.dart'
    show onePoleHighpassFx, onePoleLowpassFx;
import 'package:comet_beat/core/audio/crisp_dsp/phaser.dart' show phaserFx;
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart'
    show granularPitchShift, granularPitchShiftStereo;
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart'
    show resampleCubic;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart'
    show reverbFx, reverbFxStereo;
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart' show ringModFx;
import 'package:comet_beat/core/audio/crisp_dsp/stereo_ops.dart'
    show
        autoPanFx,
        centreCancelFx,
        crossfeedFx,
        remixFx,
        stereoWidthFx,
        swapChannelsFx;
import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart'
    show timeStretch, timeStretchStereo;
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart'
    show VoiceEffect, applyVoiceEffect, voiceShapeFx, voiceShapeFxStereo;
import 'package:comet_beat/core/audio/fx/fx_spec.dart';

// `decay` is deliberately read straight from the map rather than through `p()`:
// `reverbFx` takes a NULLABLE decay and falls back to `roomSize` when it is
// absent, and those are two alternative controls for the same internal room
// value. Forcing a default here would make `roomSize` unreachable, which is the
// control the Tracker's channel-reverb preset uses. `defaultFx(FxType.reverb)`
// always supplies a decay, so every DAW-authored spec is unaffected.

Float64List applyFxChain(
  Float64List input,
  List<FxSpec> effects,
  int sampleRate,
) {
  var out = input;
  for (final fx in effects) {
    if (!fx.enabled) continue;
    out = _applyFx(out, fx, sampleRate);
  }
  return out;
}

({Float64List left, Float64List right}) _applyFxChainStereo(
  Float64List left,
  Float64List right,
  List<FxSpec> effects,
  int sampleRate,
) {
  var outLeft = left;
  var outRight = right;
  for (final fx in effects) {
    if (!fx.enabled) continue;
    if (fx.automation.isNotEmpty) {
      final automated = _applyAutomatedFxStereo(
        outLeft,
        outRight,
        fx,
        sampleRate,
      );
      outLeft = automated.left;
      outRight = automated.right;
      continue;
    }
    double p(String key, double fallback) => fx.params[key] ?? fallback;
    final processed = switch (fx.type) {
      FxType.pan => _panFxStereo(outLeft, outRight, pan: p('pan', 0)),
      FxType.delay => delayFxStereo(
          outLeft,
          outRight,
          delayMs: p('delayMs', 300),
          feedback: p('feedback', 0.35),
          spread: p('spread', 0),
          mix: p('mix', 0.35),
          sampleRate: sampleRate,
        ),
      FxType.chorus => chorusFxStereo(
          outLeft,
          outRight,
          rateHz: p('rateHz', 1.5),
          depthMs: p('depthMs', 6),
          mix: p('mix', 0.45),
          sampleRate: sampleRate,
        ),
      FxType.flanger => flangerFxStereo(
          outLeft,
          outRight,
          rateHz: p('rateHz', 0.35),
          depthMs: p('depthMs', 3),
          feedback: p('feedback', 0.5),
          mix: p('mix', 0.5),
          sampleRate: sampleRate,
        ),
      FxType.reverb => reverbFxStereo(
          outLeft,
          outRight,
          roomSize: p('roomSize', 0.7),
          damping: p('damping', 0.4),
          decay: fx.params['decay'],
          mix: p('mix', 0.35),
          sampleRate: sampleRate,
        ),
      FxType.vocoder => _vocoderFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate,
          carrierHz: p('carrierHz', 110),
          depth: p('depth', 0.75),
          mix: p('mix', 0.7),
        ),
      FxType.voiceShape => voiceShapeFxStereo(
          outLeft,
          outRight,
          formant: p('formant', 0),
          carrierHz: p('carrierHz', 80),
          carrierMix: p('carrierMix', 0),
          grit: p('grit', 0),
          radioLowHz: p('radioLowHz', 300),
          radioHighHz: p('radioHighHz', 3200),
          radioMix: p('radioMix', 0),
          mix: p('mix', 1),
          sampleRate: sampleRate,
        ),
      FxType.compressor => compressorFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          thresholdDb: p('thresholdDb', -18),
          ratio: p('ratio', 4),
          attackMs: p('attackMs', 10),
          releaseMs: p('releaseMs', 120),
          kneeDb: p('kneeDb', 6),
          makeupDb: p('makeupDb', 0),
          mix: p('mix', 1),
        ),
      FxType.gate => gateFxStereo(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          thresholdDb: p('thresholdDb', -40),
          ratio: p('ratio', 4),
          rangeDb: p('rangeDb', -60),
          attackMs: p('attackMs', 1),
          releaseMs: p('releaseMs', 100),
          mix: p('mix', 1),
        ),
      FxType.pitchShift => _pitchShiftFxStereo(
          outLeft,
          outRight,
          semitones: p('semitones', 12),
          mix: p('mix', 1),
        ),
      FxType.timeStretch => _timeStretchFxStereo(
          outLeft,
          outRight,
          speed: p('speed', 0.75),
          mix: p('mix', 1),
          sampleRate: sampleRate,
        ),
      // A4 — the ops that need both channels. These MUST be listed here: the
      // fallback below runs an effect on each channel independently, which for
      // a channel op would silently do nothing at all.
      FxType.remix => remixFx(
          outLeft,
          outRight,
          leftFromLeft: p('leftFromLeft', 1),
          leftFromRight: p('leftFromRight', 0),
          rightFromLeft: p('rightFromLeft', 0),
          rightFromRight: p('rightFromRight', 1),
          mix: p('mix', 1),
        ),
      FxType.swapChannels =>
        swapChannelsFx(outLeft, outRight, mix: p('mix', 1)),
      FxType.stereoWidth => stereoWidthFx(
          outLeft,
          outRight,
          width: p('width', 1.4),
          mix: p('mix', 1),
        ),
      FxType.centreCancel => centreCancelFx(
          outLeft,
          outRight,
          amount: p('amount', 1),
          mix: p('mix', 1),
        ),
      FxType.crossfeed => crossfeedFx(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          amount: p('amount', 0.4),
          delayMs: p('delayMs', 0.3),
          cutoffHz: p('cutoffHz', 700),
          mix: p('mix', 1),
        ),
      FxType.autoPan => autoPanFx(
          outLeft,
          outRight,
          sampleRate: sampleRate.toDouble(),
          rateHz: p('rateHz', 0.5),
          depth: p('depth', 0.8),
          waveform: p('waveform', 0).round(),
          mix: p('mix', 1),
        ),
      _ => (
          left: _applyFx(outLeft, fx, sampleRate),
          right: _applyFx(outRight, fx, sampleRate),
        ),
    };
    outLeft = processed.left;
    outRight = processed.right;
  }
  return (left: outLeft, right: outRight);
}

/// Applies an ordered FX chain to stereo analysis buffers using the same path
/// as timeline rendering.
({Float64List left, Float64List right}) applyFxChainStereo(
  Float64List left,
  Float64List right,
  List<FxSpec> effects,
  int sampleRate,
) =>
    _applyFxChainStereo(left, right, effects, sampleRate);

Float64List _applyFx(Float64List input, FxSpec fx, int sampleRate) {
  if (fx.automation.isNotEmpty) {
    return _applyAutomatedFx(input, fx, sampleRate);
  }
  double p(String key, double fallback) => fx.params[key] ?? fallback;
  return switch (fx.type) {
    FxType.gain => _gainFx(input, gainDb: p('gainDb', 0), mix: p('mix', 1)),
    // The mono wrapper folds the stereo render after the full FX graph.
    FxType.pan => Float64List.fromList(input),
    // A4 — every channel op is defined by the RELATIONSHIP between the two
    // channels, so on a mono buffer there is nothing to relate to and the
    // honest answer is to pass it through. (Swapping one channel, widening a
    // field with no width, or cancelling a centre that is the whole signal are
    // all either no-ops or destroy-everything; a pass-through is the only one
    // that is not surprising.) The real work is in the stereo dispatch.
    FxType.remix ||
    FxType.swapChannels ||
    FxType.stereoWidth ||
    FxType.centreCancel ||
    FxType.crossfeed ||
    FxType.autoPan =>
      Float64List.fromList(input),
    FxType.reverb => reverbFx(
        input,
        roomSize: p('roomSize', 0.7),
        damping: p('damping', 0.4),
        decay: fx.params['decay'],
        mix: p('mix', 0.35),
        sampleRate: sampleRate,
      ),
    FxType.delay => delayFx(
        input,
        delayMs: p('delayMs', 300),
        feedback: p('feedback', 0.35),
        mix: p('mix', 0.35),
        sampleRate: sampleRate,
      ),
    FxType.chorus => chorusFx(
        input,
        rateHz: p('rateHz', 1.5),
        depthMs: p('depthMs', 6),
        mix: p('mix', 0.45),
        sampleRate: sampleRate,
      ),
    FxType.flanger => flangerFx(
        input,
        rateHz: p('rateHz', 0.35),
        depthMs: p('depthMs', 3),
        feedback: p('feedback', 0.5),
        mix: p('mix', 0.5),
        sampleRate: sampleRate,
      ),
    FxType.ringMod => ringModFx(
        input,
        carrierHz: p('carrierHz', 180),
        mix: p('mix', 0.5),
        sampleRate: sampleRate,
      ),
    FxType.distortion => distortionFx(
        input,
        // A3: the shaper CURVE, as an index into DistortionKind. The DSP has
        // always had four (hard clip / soft clip / fuzz / wave fold) but the
        // rack only ever reached soft clip, so a fuzz — which the Instrument
        // mode's "demon" voice is built on — was unreachable from a chain. The
        // default is soft clip's own index, so every existing spec is
        // unaffected.
        kind: _distortionKind(p('kind', 1)),
        drive: p('drive', 4),
        mix: p('mix', 0.55),
      ),
    FxType.bitCrush => _bitCrushFx(
        input,
        bits: p('bits', 8),
        mix: p('mix', 0.55),
      ),
    FxType.lowpass => biquadFx(
        input,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 8000),
        q: p('q', 0.707),
        mix: p('mix', 1),
      ),
    FxType.highpass => biquadFx(
        input,
        kind: BiquadKind.highpass,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 180),
        q: p('q', 0.707),
        mix: p('mix', 1),
      ),
    FxType.bandpass => biquadFx(
        input,
        kind: BiquadKind.bandpass,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 1000),
        q: p('q', 2),
        mix: p('mix', 1),
      ),
    FxType.notch => biquadFx(
        input,
        kind: BiquadKind.notch,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 1000),
        q: p('q', 4),
        mix: p('mix', 1),
      ),
    FxType.peakingEq => biquadFx(
        input,
        kind: BiquadKind.peaking,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 1000),
        q: p('q', 1),
        gainDb: p('gainDb', 6),
        mix: p('mix', 1),
      ),
    FxType.lowShelf => biquadFx(
        input,
        kind: BiquadKind.lowShelf,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 200),
        q: p('q', 0.707),
        gainDb: p('gainDb', 6),
        mix: p('mix', 1),
      ),
    FxType.highShelf => biquadFx(
        input,
        kind: BiquadKind.highShelf,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 4000),
        q: p('q', 0.707),
        gainDb: p('gainDb', 6),
        mix: p('mix', 1),
      ),
    FxType.phaser => phaserFx(
        input,
        sampleRate: sampleRate.toDouble(),
        rateHz: p('rateHz', 0.5),
        depth: p('depth', 0.7),
        feedback: p('feedback', 0.3),
        minFreq: p('minFreq', 200),
        maxFreq: p('maxFreq', 2000),
        stages: p('stages', 4).round(),
      ),
    // The IR is synthesized from the params (no audio asset) and the seed is
    // fixed, so the same settings always render the same tail — which is what
    // lets a baked clip stay byte-identical across renders.
    FxType.convolutionReverb => convolutionReverbFx(
        input,
        sampleRate: sampleRate.toDouble(),
        seconds: p('seconds', 1.5),
        decay: p('decay', 0.5),
        predelayMs: p('predelayMs', 0),
        mix: p('mix', 0.35),
      ),
    FxType.autoWah => _autoWahFx(
        input,
        sampleRate: sampleRate,
        baseFreq: p('baseFreq', 350),
        octaves: p('octaves', 2.5),
        rateHz: p('rateHz', 1.2),
        depth: p('depth', 1),
        q: p('q', 4),
        waveform: p('waveform', 0).round(),
        mix: p('mix', 1),
      ),
    // A1 — the rest of the filter set.
    FxType.allpass => biquadFx(
        input,
        kind: BiquadKind.allpass,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 1000),
        q: p('q', 0.707),
        mix: p('mix', 1),
      ),
    FxType.onePoleLowpass => onePoleLowpassFx(
        input,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 4000),
        mix: p('mix', 1),
      ),
    FxType.onePoleHighpass => onePoleHighpassFx(
        input,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 200),
        mix: p('mix', 1),
      ),
    FxType.biquadRaw => biquadRawFx(
        input,
        b0: p('b0', 1),
        b1: p('b1', 0),
        b2: p('b2', 0),
        a1: p('a1', 0),
        a2: p('a2', 0),
        mix: p('mix', 1),
      ),
    FxType.sincFilter => sincFilterFx(
        input,
        sampleRate: sampleRate.toDouble(),
        shape: FirShape
            .values[p('shape', 0).round().clamp(0, FirShape.values.length - 1)],
        freq: p('freq', 1000),
        freqHigh: p('freqHigh', 8000),
        taps: p('taps', 127).round(),
        mix: p('mix', 1),
      ),
    FxType.hilbert => hilbertFx(
        input,
        taps: p('taps', 127).round(),
        mix: p('mix', 1),
      ),
    // A3.
    FxType.limiter => lookaheadLimiterFx(
        input,
        sampleRate: sampleRate.toDouble(),
        ceilingDb: p('ceilingDb', -0.3),
        lookaheadMs: p('lookaheadMs', 5),
        releaseMs: p('releaseMs', 100),
        mix: p('mix', 1),
      ),
    FxType.deEsser => deEsserFx(
        input,
        sampleRate: sampleRate.toDouble(),
        freq: p('freq', 6000),
        thresholdDb: p('thresholdDb', -28),
        ratio: p('ratio', 6),
        attackMs: p('attackMs', 1),
        releaseMs: p('releaseMs', 60),
        mix: p('mix', 1),
      ),
    FxType.multibandCompressor => multibandCompressorFx(
        input,
        sampleRate: sampleRate.toDouble(),
        lowHz: p('lowHz', 200),
        highHz: p('highHz', 3000),
        thresholdDb: p('thresholdDb', -24),
        lowRatio: p('lowRatio', 1),
        midRatio: p('midRatio', 1),
        highRatio: p('highRatio', 1),
        attackMs: p('attackMs', 10),
        releaseMs: p('releaseMs', 120),
        makeupDb: p('makeupDb', 0),
        mix: p('mix', 1),
      ),
    FxType.compressor => compressorFx(
        input,
        sampleRate: sampleRate.toDouble(),
        thresholdDb: p('thresholdDb', -18),
        ratio: p('ratio', 4),
        attackMs: p('attackMs', 10),
        releaseMs: p('releaseMs', 120),
        kneeDb: p('kneeDb', 6),
        makeupDb: p('makeupDb', 0),
        mix: p('mix', 1),
      ),
    FxType.gate => gateFx(
        input,
        sampleRate: sampleRate.toDouble(),
        thresholdDb: p('thresholdDb', -40),
        ratio: p('ratio', 4),
        rangeDb: p('rangeDb', -60),
        attackMs: p('attackMs', 1),
        releaseMs: p('releaseMs', 100),
        mix: p('mix', 1),
      ),
    FxType.pitchShift => _blendWetDry(
        input,
        _fitLength(granularPitchShift(input, p('semitones', 12)), input.length),
        p('mix', 1),
      ),
    FxType.timeStretch => _blendWetDry(
        input,
        _fitLength(
          timeStretch(
            input,
            1 / p('speed', 0.75).clamp(0.1, 4.0),
            sampleRate: sampleRate,
          ),
          input.length,
        ),
        p('mix', 1),
      ),
    FxType.tremolo => _tremoloFx(
        input,
        sampleRate: sampleRate,
        rateHz: p('rateHz', 6),
        depth: p('depth', 0.6),
        mix: p('mix', 1),
      ),
    FxType.vocoder => _vocoderFx(
        input,
        sampleRate: sampleRate,
        carrierHz: p('carrierHz', 110),
        depth: p('depth', 0.75),
        mix: p('mix', 0.7),
      ),
    FxType.voiceShape => voiceShapeFx(
        input,
        sampleRate: sampleRate,
        formant: p('formant', 0),
        carrierHz: p('carrierHz', 80),
        carrierMix: p('carrierMix', 0),
        grit: p('grit', 0),
        radioLowHz: p('radioLowHz', 300),
        radioHighHz: p('radioHighHz', 3200),
        radioMix: p('radioMix', 0),
        mix: p('mix', 1),
      ),
    FxType.voiceChipmunk => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.chipmunk, sampleRate: sampleRate),
        p('mix', 1),
      ),
    FxType.voiceDeep => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.deep, sampleRate: sampleRate),
        p('mix', 1),
      ),
    FxType.voiceRobot => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.robot, sampleRate: sampleRate),
        p('mix', 1),
      ),
    FxType.voiceRadio => _blendWetDry(
        input,
        applyVoiceEffect(input, VoiceEffect.radio, sampleRate: sampleRate),
        p('mix', 1),
      ),
  };
}

/// A [DistortionKind] from its enum index, clamped — a corrupt or
/// future-versioned value falls back to soft clip rather than throwing.
DistortionKind _distortionKind(double raw) => DistortionKind
    .values[raw.round().clamp(0, DistortionKind.values.length - 1)];

Float64List _gainFx(
  Float64List input, {
  required double gainDb,
  required double mix,
}) {
  final gain = math.pow(10, gainDb.clamp(-80.0, 48.0) / 20).toDouble();
  final wet = mix.clamp(0.0, 1.0);
  final dry = 1 - wet;
  final out = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    out[i] = input[i] * (dry + gain * wet);
  }
  return out;
}

({Float64List left, Float64List right}) _pitchShiftFxStereo(
  Float64List left,
  Float64List right, {
  required double semitones,
  required double mix,
}) {
  final shifted = granularPitchShiftStereo(left, right, semitones);
  return (
    left: _blendWetDry(left, _fitLength(shifted.left, left.length), mix),
    right: _blendWetDry(right, _fitLength(shifted.right, right.length), mix),
  );
}

({Float64List left, Float64List right}) _timeStretchFxStereo(
  Float64List left,
  Float64List right, {
  required double speed,
  required double mix,
  required int sampleRate,
}) {
  final stretched = timeStretchStereo(
    left,
    right,
    1 / speed.clamp(0.1, 4.0),
    sampleRate: sampleRate,
  );
  return (
    left: _blendWetDry(left, _fitLength(stretched.left, left.length), mix),
    right: _blendWetDry(right, _fitLength(stretched.right, right.length), mix),
  );
}

/// Drops points a project file should never have contained (non-finite times
/// or values), clamps negative times to 0, sorts by time, and discards a
/// parameter whose points all fell away.
///
/// Both the mono and the stereo renderer go through here so the SAME
/// automation cannot render two different ways: a clip must not change shape
/// the moment a pan makes it stereo.
///
/// [FxAutomationPoint.curve] is carried through. Rebuilding the point without
/// it silently reset every ramp to linear at render time while the editor and
/// the saved file both still showed the authored curve — audible only as "that
/// fade isn't the shape I drew".
Map<String, List<FxAutomationPoint>> _sanitizedAutomation(FxSpec fx) {
  final automation = <String, List<FxAutomationPoint>>{};
  for (final entry in fx.automation.entries) {
    final points = [
      for (final point in entry.value)
        if (point.ms.isFinite && point.value.isFinite)
          FxAutomationPoint(
            ms: point.ms < 0 ? 0 : point.ms,
            value: point.value,
            curve: point.curve,
          ),
    ]..sort((a, b) => a.ms.compareTo(b.ms));
    if (points.isNotEmpty) automation[entry.key] = points;
  }
  return automation;
}

Float64List _applyAutomatedFx(Float64List input, FxSpec fx, int sampleRate) {
  if (input.isEmpty) return input;
  final automation = _sanitizedAutomation(fx);
  if (automation.isEmpty) {
    return _applyFx(input, fx.copyWith(automation: const {}), sampleRate);
  }
  final block = math.max(64, (sampleRate / 50).round());
  final out = Float64List(input.length);
  for (var start = 0; start < input.length; start += block) {
    final end = math.min(input.length, start + block);
    final ms = start * 1000 / sampleRate;
    final params = {...fx.params};
    for (final entry in automation.entries) {
      params[entry.key] = _paramAutomationValue(
        entry.value,
        ms,
        fx.params[entry.key] ?? 0,
      );
    }
    final processed = _fitLength(
      _applyFx(
        Float64List.sublistView(input, start, end),
        fx.copyWith(params: params, automation: const {}),
        sampleRate,
      ),
      end - start,
    );
    out.setRange(start, end, processed);
  }
  return out;
}

({Float64List left, Float64List right}) _applyAutomatedFxStereo(
  Float64List left,
  Float64List right,
  FxSpec fx,
  int sampleRate,
) {
  if (left.isEmpty && right.isEmpty) return (left: left, right: right);
  final automation = _sanitizedAutomation(fx);
  if (automation.isEmpty) {
    return _applyFxChainStereo(
      left,
      right,
      [fx.copyWith(automation: const {})],
      sampleRate,
    );
  }
  final block = math.max(64, (sampleRate / 50).round());
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var start = 0; start < left.length; start += block) {
    final end = math.min(left.length, start + block);
    final ms = start * 1000 / sampleRate;
    final params = {...fx.params};
    for (final entry in automation.entries) {
      params[entry.key] = _paramAutomationValue(
        entry.value,
        ms,
        fx.params[entry.key] ?? 0,
      );
    }
    final processed = _applyFxChainStereo(
      Float64List.sublistView(left, start, end),
      Float64List.sublistView(right, start, end),
      [fx.copyWith(params: params, automation: const {})],
      sampleRate,
    );
    outLeft.setRange(start, end, processed.left);
    outRight.setRange(start, end, processed.right);
  }
  return (left: outLeft, right: outRight);
}

double _paramAutomationValue(
  List<FxAutomationPoint> points,
  double ms,
  double fallback,
) {
  if (points.length == 1) {
    return (ms - points.single.ms).abs() < 0.5 ? points.single.value : fallback;
  }
  if (ms < points.first.ms || ms > points.last.ms) return fallback;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (ms < a.ms || ms > b.ms) continue;
    if (b.ms <= a.ms) return b.value;
    final t = fadeCurveValue((ms - a.ms) / (b.ms - a.ms), a.curve);
    return a.value + (b.value - a.value) * t;
  }
  return points.last.value;
}

Float64List _blendWetDry(Float64List dry, Float64List wet, double mix) {
  final m = mix.clamp(0.0, 1.0);
  if (m == 0) {
    final out = Float64List(dry.length);
    out.setAll(0, dry);
    return out;
  }
  if (m == 1 && wet.length == dry.length) return wet;
  final n = dry.length > wet.length ? dry.length : wet.length;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final d = i < dry.length ? dry[i] : 0.0;
    final w = i < wet.length ? wet[i] : 0.0;
    out[i] = (1 - m) * d + m * w;
  }
  return out;
}

({Float64List left, Float64List right}) _panFxStereo(
  Float64List left,
  Float64List right, {
  required double pan,
}) {
  final p = pan.clamp(-1.0, 1.0).toDouble();
  final leftGain = p <= 0 ? 1.0 : math.cos(p * math.pi / 2);
  final rightGain = p >= 0 ? 1.0 : math.cos(p * math.pi / 2);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  for (var i = 0; i < left.length; i++) {
    outLeft[i] = left[i] * leftGain;
  }
  for (var i = 0; i < right.length; i++) {
    outRight[i] = right[i] * rightGain;
  }
  return (left: outLeft, right: outRight);
}

Float64List _tremoloFx(
  Float64List input, {
  required int sampleRate,
  double rateHz = 6,
  double depth = 0.6,
  double mix = 1,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) return Float64List.fromList(input);
  final hz = rateHz.clamp(0.05, sampleRate / 2).toDouble();
  final out = Float64List(input.length);
  for (var i = 0; i < input.length; i++) {
    final lfo = (1 + math.sin(2 * math.pi * hz * i / sampleRate)) * 0.5;
    final amp = 1 - d + d * lfo;
    final wet = input[i] * amp;
    out[i] = input[i] * (1 - m) + wet * m;
  }
  return out;
}

/// Auto-wah: one resonant low-pass [Biquad] whose cutoff is swept by the shared
/// tracker LFO ([lfoValue]) between [baseFreq] and `baseFreq · 2^octaves`. The
/// cutoff is retuned every sample via [Biquad.setFreq] — which recomputes the
/// coefficients WITHOUT clearing the filter memory — so a fast sweep never
/// clicks (the same trick the tracker's IT filter uses across streaming chunks).
///
/// [depth] (0..1) scales how much of the sweep is applied (0 pins the cutoff at
/// [baseFreq]); [waveform] picks the LFO shape (0 sine / 1 ramp / 2 square).
Float64List _autoWahFx(
  Float64List input, {
  required int sampleRate,
  double baseFreq = 350,
  double octaves = 2.5,
  double rateHz = 1.2,
  double depth = 1,
  double q = 4,
  int waveform = 0,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) return Float64List.fromList(input);
  final nyquist = sampleRate / 2;
  final base = baseFreq.clamp(20.0, nyquist - 1).toDouble();
  final sweep = octaves.clamp(0.0, 8.0) * depth.clamp(0.0, 1.0);
  final hz = rateHz.clamp(0.01, 40.0).toDouble();
  // Resonant Q > 0.707 gives the vocal "wah" peak; construct once, retune below.
  final filter = Biquad(
    BiquadKind.lowpass,
    freq: base,
    sampleRate: sampleRate.toDouble(),
    q: q.clamp(0.1, 24.0).toDouble(),
  );
  final out = Float64List(input.length);
  final twoPiRate = 2 * math.pi * hz / sampleRate;
  for (var i = 0; i < input.length; i++) {
    // LFO in [0, 1]: 0 → base cutoff, 1 → base·2^sweep.
    final lfo01 = (lfoValue(waveform, twoPiRate * i) + 1) * 0.5;
    final cutoff = base * math.pow(2.0, sweep * lfo01).toDouble();
    filter.setFreq(cutoff.clamp(1.0, nyquist - 1).toDouble());
    final wet = filter.process(input[i]);
    out[i] = input[i] * (1 - m) + wet * m;
  }
  return out;
}

Float64List _vocoderFx(
  Float64List input, {
  required int sampleRate,
  double carrierHz = 110,
  double depth = 0.75,
  double mix = 0.7,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  if (m == 0 || input.isEmpty) return Float64List.fromList(input);
  final hz = carrierHz.clamp(20.0, sampleRate / 2).toDouble();
  final out = Float64List(input.length);
  var envelope = 0.0;
  const attack = 0.18;
  const release = 0.018;
  for (var i = 0; i < input.length; i++) {
    final level = input[i].abs();
    envelope += (level - envelope) * (level > envelope ? attack : release);
    final carrier = math.sin(2 * math.pi * hz * i / sampleRate);
    final wet = input[i] * (1 - d) + carrier * envelope * d;
    out[i] = input[i] * (1 - m) + wet * m;
  }
  return out;
}

({Float64List left, Float64List right}) _vocoderFxStereo(
  Float64List left,
  Float64List right, {
  required int sampleRate,
  double carrierHz = 110,
  double depth = 0.75,
  double mix = 0.7,
}) {
  final d = depth.clamp(0.0, 1.0);
  final m = mix.clamp(0.0, 1.0);
  final outLeft = Float64List(left.length);
  final outRight = Float64List(right.length);
  if (m == 0) {
    outLeft.setAll(0, left);
    outRight.setAll(0, right);
    return (left: outLeft, right: outRight);
  }
  final hz = carrierHz.clamp(20.0, sampleRate / 2).toDouble();
  const attack = 0.18;
  const release = 0.018;
  var envelopeLeft = 0.0;
  var envelopeRight = 0.0;
  final frames = math.min(left.length, right.length);
  for (var i = 0; i < frames; i++) {
    final levelLeft = left[i].abs();
    final levelRight = right[i].abs();
    envelopeLeft += (levelLeft - envelopeLeft) *
        (levelLeft > envelopeLeft ? attack : release);
    envelopeRight += (levelRight - envelopeRight) *
        (levelRight > envelopeRight ? attack : release);
    final phase = 2 * math.pi * hz * i / sampleRate;
    final wetLeft = left[i] * (1 - d) + math.sin(phase) * envelopeLeft * d;
    final wetRight =
        right[i] * (1 - d) + math.sin(phase + math.pi / 2) * envelopeRight * d;
    outLeft[i] = left[i] * (1 - m) + wetLeft * m;
    outRight[i] = right[i] * (1 - m) + wetRight * m;
  }
  for (var i = frames; i < left.length; i++) {
    outLeft[i] = left[i];
  }
  for (var i = frames; i < right.length; i++) {
    outRight[i] = right[i];
  }
  return (left: outLeft, right: outRight);
}

Float64List _fitLength(Float64List input, int length) {
  if (input.length == length) return input;
  if (length <= 0) return Float64List(0);
  if (input.isEmpty) return Float64List(length);
  final resized = resampleCubic(input, input.length / length);
  if (resized.length == length) return resized;
  final out = Float64List(length);
  out.setRange(0, math.min(length, resized.length), resized);
  return out;
}

Float64List _bitCrushFx(
  Float64List input, {
  double bits = 8,
  double mix = 0.55,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final b = bits.round().clamp(1, 16);
  final levels = math.pow(2, b - 1).toDouble();
  for (var i = 0; i < input.length; i++) {
    final dry = input[i];
    final wet = (dry * levels).floorToDouble() / levels;
    out[i] = (1 - m) * dry + m * wet;
  }
  return out;
}
