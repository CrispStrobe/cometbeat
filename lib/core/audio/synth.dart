// lib/core/audio/synth.dart
//
// Pure-Dart additive synthesizer: renders pitches, chords and sequences to
// 16-bit mono PCM WAV bytes. No assets, no licensing, works on every
// platform (playback happens in AudioService). Piano-ish timbre: a few
// decaying harmonics with a fast attack and exponential decay.

import 'dart:math';
import 'dart:typed_data';

const kSampleRate = 44100;

/// One playable segment: simultaneous frequencies for a duration.
/// A single-element [freqs] is a note; several are a chord.
typedef Segment = ({List<double> freqs, int ms});

double midiToFrequency(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);

/// A selectable instrument voice.
enum Instrument { piano, cello, flute, musicBox }

/// A timbre: the relative amplitudes of the harmonics, the attack time, and how
/// fast the note decays over its segment (small = sustained, large = plucked).
class Timbre {
  const Timbre({
    required this.harmonics,
    required this.attackMs,
    required this.decay,
  });

  final List<double> harmonics;
  final double attackMs;
  final double decay;
}

const _timbres = <Instrument, Timbre>{
  // Piano-ish: the original bright, decaying voice.
  Instrument.piano: Timbre(
    harmonics: [1.0, 0.45, 0.22, 0.1, 0.05],
    attackMs: 8,
    decay: 3.0,
  ),
  // Cello: reedy upper harmonics, a slower bow attack, and a sustained tone.
  Instrument.cello: Timbre(
    harmonics: [1.0, 0.6, 0.45, 0.32, 0.22, 0.16, 0.1],
    attackMs: 45,
    decay: 0.9,
  ),
  // Flute: almost pure, soft, sustained.
  Instrument.flute: Timbre(
    harmonics: [1.0, 0.18, 0.06, 0.02],
    attackMs: 35,
    decay: 1.1,
  ),
  // Music box: bright and bell-like, fast decay.
  Instrument.musicBox: Timbre(
    harmonics: [1.0, 0.3, 0.55, 0.2, 0.35, 0.12],
    attackMs: 2,
    decay: 6.0,
  ),
};

/// The timbre for [instrument].
Timbre timbreFor(Instrument instrument) => _timbres[instrument]!;

/// Renders [segments] back-to-back into a raw, UN-normalized Float64 buffer.
/// The mixer stage ([mixStems]) needs pre-normalization samples so it can set
/// per-track levels itself; [renderSegments] normalizes for direct playback.
Float64List renderSegmentsRaw(
  List<Segment> segments, {
  int sampleRate = kSampleRate,
  Timbre? timbre,
}) {
  final voice = timbre ?? _timbres[Instrument.piano]!;
  final harmonics = voice.harmonics;
  final attackSec = voice.attackMs / 1000;
  final decay = voice.decay;
  final totalSamples = segments.fold<int>(
    0,
    (sum, s) => sum + (s.ms * sampleRate) ~/ 1000,
  );
  final buffer = Float64List(totalSamples);

  var offset = 0;
  for (final segment in segments) {
    final n = (segment.ms * sampleRate) ~/ 1000;
    final seconds = segment.ms / 1000;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      // Instrument-specific attack, exponential decay over the segment.
      final attack = t < attackSec ? t / attackSec : 1.0;
      final envelope = attack * exp(-decay * t / seconds);
      var sample = 0.0;
      for (final freq in segment.freqs) {
        for (var h = 0; h < harmonics.length; h++) {
          sample += harmonics[h] * sin(2 * pi * freq * (h + 1) * t);
        }
      }
      buffer[offset + i] = sample * envelope;
    }
    offset += n;
  }
  return buffer;
}

/// Renders [segments] back-to-back into normalized PCM16 samples.
///
/// [gain] (0..1) scales the final level below the normalized peak — used to
/// voice dynamics (pp..ff) since the output is otherwise peak-normalized.
Int16List renderSegments(
  List<Segment> segments, {
  int sampleRate = kSampleRate,
  Timbre? timbre,
  double gain = 1.0,
}) {
  final buffer = renderSegmentsRaw(
    segments,
    sampleRate: sampleRate,
    timbre: timbre,
  );

  // Normalize to 80% full scale.
  var peak = 0.0;
  for (final v in buffer) {
    if (v.abs() > peak) peak = v.abs();
  }
  final scale = (peak > 0 ? 0.8 * 32767 / peak : 0.0) * gain.clamp(0.0, 1.0);
  final samples = Int16List(buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    samples[i] = (buffer[i] * scale).round();
  }
  return samples;
}

// --- Multi-track mixing (the Loop Mixer's mixdown stage) ---

/// One pre-rendered mixer stem: raw float samples plus its authored level.
typedef MixStem = ({Float64List samples, double gain});

double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Mixes [stems] into one PCM16 buffer of exactly [totalSamples] at
/// combo-independent levels.
///
/// Each stem is normalized to unit peak on its own, scaled by its authored
/// gain, summed, and run through a tanh soft-knee limiter. A track therefore
/// contributes the *same* loudness no matter which other tracks are enabled —
/// normalizing the mix peak per combo (or per track post-quantization) would
/// make overall levels pump every time a track toggles. Stems shorter or
/// longer than [totalSamples] are zero-padded / truncated, which absorbs any
/// per-segment sample-rounding drift between tracks. An empty [stems] list is
/// [totalSamples] of silence.
Int16List mixStems(List<MixStem> stems, {required int totalSamples}) {
  final mix = Float64List(totalSamples);
  for (final stem in stems) {
    var peak = 0.0;
    for (final v in stem.samples) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) continue;
    final scale = stem.gain / peak;
    final n = min(stem.samples.length, totalSamples);
    for (var i = 0; i < n; i++) {
      mix[i] += stem.samples[i] * scale;
    }
  }
  final samples = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    samples[i] = (_tanh(mix[i]) * 0.95 * 32767).round();
  }
  return samples;
}

// --- Stereo mixing + panning (Tracker Feature C) -----------------------------
//
// The mono [mixStems]/[wavBytes] above stay the canonical path; these are their
// ADDITIVE stereo siblings, used only when a song actually pans a channel. Each
// stem is unit-peaked × gain exactly like [mixStems], then placed in the stereo
// field with a CONSTANT-POWER pan law (L = cos θ, R = sin θ, θ = (pan+1)/2·π/2)
// so a centre pan splits equally (−3 dB per side) and a hard pan sends all the
// energy to one side. Panned stems are summed and run through the SAME tanh
// soft-knee (× 0.95) as [mixStems], so a non-panned song rendered stereo would
// match the mono mix duplicated across both channels.

/// One pre-rendered mixer stem plus its authored level and stereo [pan]
/// (−1 = hard left … 0 = centre … +1 = hard right).
typedef MixStemPan = ({Float64List samples, double gain, double pan});

/// Mixes [stems] into one INTERLEAVED stereo PCM16 buffer (L,R,L,R…) of length
/// `totalSamples * 2`. Per stem: unit-peak × gain (as [mixStems]), constant-power
/// pan, summed, tanh soft-knee (same 0.95). An empty [stems] list is silence.
Int16List mixStemsStereo(
  List<MixStemPan> stems, {
  required int totalSamples,
}) {
  final left = Float64List(totalSamples);
  final right = Float64List(totalSamples);
  for (final stem in stems) {
    var peak = 0.0;
    for (final v in stem.samples) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) continue;
    final scale = stem.gain / peak;
    final theta = (stem.pan.clamp(-1.0, 1.0) + 1) / 2 * (pi / 2);
    final lGain = cos(theta);
    final rGain = sin(theta);
    final n = min(stem.samples.length, totalSamples);
    for (var i = 0; i < n; i++) {
      final s = stem.samples[i] * scale;
      left[i] += s * lGain;
      right[i] += s * rGain;
    }
  }
  final out = Int16List(totalSamples * 2);
  for (var i = 0; i < totalSamples; i++) {
    out[i * 2] = (_tanh(left[i]) * 0.95 * 32767).round();
    out[i * 2 + 1] = (_tanh(right[i]) * 0.95 * 32767).round();
  }
  return out;
}

/// Wraps INTERLEAVED (L,R,L,R…) PCM16 [interleaved] into a valid 2-channel WAV
/// container. [interleaved.length] must be even (whole L,R frames).
Uint8List wavBytesStereo(
  Int16List interleaved, {
  int sampleRate = kSampleRate,
}) {
  assert(interleaved.length.isEven, 'interleaved length must be even (L,R)');
  final dataLength = interleaved.length * 2;
  final bytes = ByteData(44 + dataLength);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 2, Endian.little); // numChannels = stereo
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 4, Endian.little); // byteRate = sr*ch*2
  bytes.setUint16(32, 4, Endian.little); // blockAlign = ch*2
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < interleaved.length; i++) {
    bytes.setInt16(44 + i * 2, interleaved[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

// --- Percussion (noise-based one-shots for the Loop Mixer's drum track) ---
//
// The additive synth above is tonal; drums need noise. These render short
// unit-peak one-shots with seeded Randoms, so output is deterministic (the
// loop cache and the tests rely on byte-identical renders).

/// The percussion voices the drum pattern can place.
/// The percussion palette. The first three (kick/snare/hat) are the classic
/// grid rows; the rest widen the kit (open hat, clap, tom, rim, cowbell). New
/// voices are APPENDED so existing index/order mappings stay stable.
// Appended, never reordered: some call sites index the kit by `Drum.values[i]`
// (tracker drum channel) and share tokens/stored patterns may reference the
// ordinal, so indices 0–7 must stay put.
enum Drum {
  kick,
  snare,
  hat,
  openHat,
  clap,
  tom,
  rim,
  cowbell,
  crash,
  ride,
  lowTom,
  highTom,
}

/// A timbre profile applied to every drum voice — same hit *timing*, different
/// *sound*. All multipliers are 1.0 (crush 0) for the clean synth kit; other
/// kits scale the oscillator frequencies ([tune]), the decay rates ([decay];
/// < 1 = longer/rounder), the noise-component gain ([noise]), the pitch-sweep
/// depth of kick/tom ([sweep]), and add a soft-saturation "grit" ([crush], the
/// dusty lo-fi flavour). Pure timbre — the onset grid never moves.
class DrumKit {
  const DrumKit(
    this.id, {
    this.tune = 1.0,
    this.decay = 1.0,
    this.noise = 1.0,
    this.sweep = 1.0,
    this.crush = 0.0,
  });

  final String id;
  final double tune;
  final double decay;
  final double noise;
  final double sweep;
  final double crush;
}

/// The default clean synth kit (the original voices, all multipliers neutral).
const DrumKit kDrumKitClean = DrumKit('clean');

/// The offered kits: clean synth, a deep round electronic kit, a warm soft kit,
/// and a dusty/crushed lo-fi kit. Ids are stable (they go in the share token).
const List<DrumKit> kDrumKits = [
  kDrumKitClean,
  DrumKit('deep', tune: 0.80, decay: 0.62, noise: 0.82, sweep: 1.30),
  DrumKit('warm', tune: 0.94, decay: 0.80, noise: 1.12, sweep: 0.82),
  DrumKit(
    'lofi',
    tune: 0.88,
    decay: 1.18,
    noise: 1.28,
    sweep: 0.90,
    crush: 0.7,
  ),
];

/// Resolve a kit id to its profile (unknown ids → the clean kit).
DrumKit drumKitById(String id) =>
    kDrumKits.firstWhere((k) => k.id == id, orElse: () => kDrumKitClean);

/// Soft-saturate [x] by [crush] (0 = passthrough) — adds harmonics/grit.
double _crush(double x, double crush) =>
    crush <= 0 ? x : _tanhApprox(x * (1 + 3 * crush));

double _tanhApprox(double x) {
  final e2 = exp(2 * x);
  return (e2 - 1) / (e2 + 1);
}

Float64List _normalizedToUnitPeak(Float64List buffer) {
  var peak = 0.0;
  for (final v in buffer) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0) {
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] /= peak;
    }
  }
  return buffer;
}

/// Applies the kit's [crush] grit (if any) then normalizes to unit peak. The
/// buffer length is kit-independent, so the onset grid never shifts.
Float64List _finishDrum(Float64List out, double crush) {
  if (crush > 0) {
    for (var i = 0; i < out.length; i++) {
      out[i] = _crush(out[i], crush);
    }
  }
  return _normalizedToUnitPeak(out);
}

/// Renders one unit-peak percussion hit in the given [kit]'s timbre (default =
/// the clean synth kit). [kit] changes the *sound* only; the buffer length —
/// and thus every hit's position in a pattern — is identical across kits.
Float64List renderDrum(
  Drum drum, {
  int sampleRate = kSampleRate,
  DrumKit kit = kDrumKitClean,
}) {
  final tn = kit.tune, dk = kit.decay, nz = kit.noise, sw = kit.sweep;
  switch (drum) {
    case Drum.kick:
      // A sine sweeping 120→40 Hz with a fast decay: the classic synth kick.
      final n = (130 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      var phase = 0.0;
      final startF = 120 * tn, depth = (120 - 40) * tn * sw;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final freq = startF - depth * (t / 0.130);
        phase += freq / sampleRate;
        out[i] = sin(2 * pi * phase) * exp(-18 * dk * t);
      }
      return _finishDrum(out, kit.crush);
    case Drum.snare:
      // A 190 Hz body under a noise burst.
      final n = (150 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(2);
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final body = 0.5 * sin(2 * pi * 190 * tn * t) * exp(-25 * dk * t);
        final rattle = (noise.nextDouble() * 2 - 1) * nz * exp(-22 * dk * t);
        out[i] = body + rattle;
      }
      return _finishDrum(out, kit.crush);
    case Drum.hat:
      // Differentiated (high-passed) noise, very short.
      final n = (50 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(3);
      var prev = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final white = noise.nextDouble() * 2 - 1;
        out[i] = (white - prev) * exp(-60 * dk * t);
        prev = white;
      }
      return _finishDrum(out, kit.crush);
    case Drum.openHat:
      // Like the hat but a long, sizzling decay (an open hi-hat).
      final n = (280 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(4);
      var prev = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final white = noise.nextDouble() * 2 - 1;
        out[i] = (white - prev) * exp(-11 * dk * t);
        prev = white;
      }
      return _finishDrum(out, kit.crush);
    case Drum.clap:
      // Three quick noise bursts ~9 ms apart (the hand transients) into a
      // slightly longer diffuse tail — the classic clap shape.
      final n = (200 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(5);
      final burstGap = (9 * sampleRate) ~/ 1000;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final white = noise.nextDouble() * 2 - 1;
        // Sum three sharply-decaying transients, then a soft tail after them.
        var env = 0.0;
        for (var b = 0; b < 3; b++) {
          final bt = (i - b * burstGap) / sampleRate;
          if (bt >= 0) env += exp(-140 * dk * bt);
        }
        final tail = 0.35 * exp(-18 * dk * t);
        out[i] = white * (env + tail);
      }
      return _finishDrum(out, kit.crush);
    case Drum.tom:
      // A mid tom: a sine gliding 190→95 Hz with a medium decay (a softer,
      // higher, longer sibling of the kick).
      final n = (220 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      var phase = 0.0;
      final startF = 190 * tn, depth = (190 - 95) * tn * sw;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final freq = startF - depth * (t / 0.220);
        phase += freq / sampleRate;
        out[i] = sin(2 * pi * phase) * exp(-9 * dk * t);
      }
      return _finishDrum(out, kit.crush);
    case Drum.rim:
      // A rimshot: a short ~1700 Hz tone click with a hint of noise, very fast
      // decay.
      final n = (35 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(6);
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final tone = sin(2 * pi * 1700 * tn * t);
        final click = (noise.nextDouble() * 2 - 1) * 0.4 * nz;
        out[i] = (tone + click) * exp(-90 * dk * t);
      }
      return _finishDrum(out, kit.crush);
    case Drum.cowbell:
      // Two detuned square-ish tones (~540 + ~800 Hz), medium decay — the 808
      // cowbell.
      final n = (250 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      double sq(double x) => sin(2 * pi * x) >= 0 ? 1.0 : -1.0;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final a = sq(540 * tn * t);
        final b = sq(800 * tn * t);
        out[i] = (a + b) * exp(-8 * dk * t);
      }
      return _finishDrum(out, kit.crush);
    case Drum.crash:
      // A bright cymbal wash: differentiated (high-passed) noise with a long,
      // slow decay — the openHat's big sibling. Longer + brighter than any hat.
      final n = (900 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(7);
      var prev = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final white = noise.nextDouble() * 2 - 1;
        // A quick swell into the crash, then a long shimmering tail.
        final swell = t < 0.006 ? t / 0.006 : 1.0;
        out[i] = (white - prev) * swell * exp(-3.2 * dk * t);
        prev = white;
      }
      return _finishDrum(out, kit.crush);
    case Drum.ride:
      // A ride cymbal: a metallic "ping" (a cluster of inharmonic high partials)
      // over a quieter shimmering noise bed, medium-long decay. The ping gives it
      // a defined pitch the crash lacks.
      final n = (620 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      final noise = Random(8);
      var prev = 0.0;
      // Inharmonic, bell-like partials.
      const partials = [3010.0, 4200.0, 5300.0, 7100.0];
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        var ping = 0.0;
        for (final f in partials) {
          ping += sin(2 * pi * f * tn * t);
        }
        ping *=
            exp(-9 * dk * t) / partials.length; // the attack ping decays fast
        final white = noise.nextDouble() * 2 - 1;
        final bed =
            (white - prev) * nz * 0.5 * exp(-5 * dk * t); // shimmer tail
        prev = white;
        out[i] = ping + bed;
      }
      return _finishDrum(out, kit.crush);
    case Drum.lowTom:
      // A floor tom: a sine gliding 130→70 Hz, a long decay (lower + longer than
      // the mid tom).
      final n = (280 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      var phase = 0.0;
      final startF = 130 * tn, depth = (130 - 70) * tn * sw;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final freq = startF - depth * (t / 0.280);
        phase += freq / sampleRate;
        out[i] = sin(2 * pi * phase) * exp(-7 * dk * t);
      }
      return _finishDrum(out, kit.crush);
    case Drum.highTom:
      // A rack tom: a sine gliding 260→150 Hz, a shorter decay (higher + tighter
      // than the mid tom) — a tom fill reads low→mid→high across the three.
      final n = (170 * sampleRate) ~/ 1000;
      final out = Float64List(n);
      var phase = 0.0;
      final startF = 260 * tn, depth = (260 - 150) * tn * sw;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final freq = startF - depth * (t / 0.170);
        phase += freq / sampleRate;
        out[i] = sin(2 * pi * phase) * exp(-11 * dk * t);
      }
      return _finishDrum(out, kit.crush);
  }
}

/// Places drum one-shots on a silent [totalMs] timeline: each hit is
/// `(atMs, drum)`. Hits whose tail crosses the end are truncated (the loop
/// wraps, so authored patterns keep tails inside the loop instead).
Float64List renderDrumPattern(
  List<(int, Drum)> hits, {
  required int totalMs,
  int sampleRate = kSampleRate,
  DrumKit kit = kDrumKitClean,
}) {
  final totalSamples = (totalMs * sampleRate) ~/ 1000;
  final out = Float64List(totalSamples);
  final oneShots = <Drum, Float64List>{};
  for (final (atMs, drum) in hits) {
    final shot =
        oneShots[drum] ??= renderDrum(drum, sampleRate: sampleRate, kit: kit);
    final start = (atMs * sampleRate) ~/ 1000;
    final n = min(shot.length, totalSamples - start);
    for (var i = 0; i < n; i++) {
      out[start + i] += shot[i];
    }
  }
  return out;
}

/// Wraps PCM16 mono samples into a WAV container.
Uint8List wavBytes(Int16List samples, {int sampleRate = kSampleRate}) {
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Convenience: render [segments] straight to WAV bytes.
Uint8List renderWav(
  List<Segment> segments, {
  Timbre? timbre,
  double gain = 1.0,
}) =>
    wavBytes(renderSegments(segments, timbre: timbre, gain: gain));

// --- Retro game SFX (CrispFXR-style: square waves, pitch sweeps) ---
//
// Procedural feedback sounds in the spirit of the maintainer's CrispFXR
// (sfxr-like 8-bit synthesizer): no assets, instantly recognizable.

/// A square-wave segment sweeping from [startFreq] to [endFreq].
Float64List _squareSweep(
  double startFreq,
  double endFreq,
  int ms, {
  int sampleRate = kSampleRate,
}) {
  final n = (ms * sampleRate) ~/ 1000;
  final out = Float64List(n);
  final seconds = ms / 1000;
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final freq = startFreq + (endFreq - startFreq) * (t / seconds);
    phase += freq / sampleRate;
    final attack = t < 0.005 ? t / 0.005 : 1.0;
    final envelope = attack * exp(-2.5 * t / seconds);
    out[i] = (phase % 1.0 < 0.5 ? 1.0 : -1.0) * envelope;
  }
  return out;
}

Uint8List _sfxWav(List<Float64List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final samples = Int16List(total);
  var offset = 0;
  for (final part in parts) {
    for (var i = 0; i < part.length; i++) {
      samples[offset + i] = (part[i] * 0.35 * 32767).round();
    }
    offset += part.length;
  }
  return wavBytes(samples);
}

/// "Correct!" — the classic two-blip pickup coin (B5 → E6).
Uint8List renderSfxCorrect() => _sfxWav([
      _squareSweep(988, 988, 80),
      _squareSweep(1319, 1319, 220),
    ]);

/// "Wrong" — a short, soft descending buzz.
Uint8List renderSfxWrong() => _sfxWav([_squareSweep(220, 150, 250)]);

/// Game finished — an ascending power-up arpeggio with a final sweep.
Uint8List renderSfxFanfare() => _sfxWav([
      _squareSweep(523, 523, 110), // C5
      _squareSweep(659, 659, 110), // E5
      _squareSweep(784, 784, 110), // G5
      _squareSweep(1047, 1319, 450), // C6 sweeping up
    ]);

/// A short metronome tick — a brief high blip, [accent]ed (higher) on the
/// downbeat. Kept high and short to be unobtrusive; it does not need to be
/// mic-safe by itself because the play-along only clicks during the (unscored)
/// count-in (see metronome.dart's CountInClicker).
Uint8List renderSfxTick({bool accent = false}) => _sfxWav([
      _squareSweep(
        accent ? 1760 : 1320,
        accent ? 1760 : 1320,
        accent ? 45 : 32,
      ),
    ]);
