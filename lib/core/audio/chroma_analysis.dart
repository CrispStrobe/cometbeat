// lib/core/audio/chroma_analysis.dart
//
// Phase 2 of automatic play-along: *fuzzy* chord recognition. Where
// pitch_analysis.dart answers "which single note?" (monophonic, exact), this
// answers "what chord did that sound like?" — deliberately approximate. It runs
// over the SAME mic capture layer (MicrophonePitchService), just a second
// analysis path on each window.
//
// The method is a **chromagram + template match**, not note-by-note
// transcription (which is research-grade and unreliable on guitar/piano decay):
//  1. FFT the windowed signal → magnitude spectrum.
//  2. Fold every bin onto its pitch class (C..B) → a 12-bin chroma vector.
//  3. Cosine-match that chroma against binary chord templates (maj, min, 7, …)
//     for all 12 roots, and return the best few as fuzzy candidates.
//
// Pure Dart, no plugins/assets — unit-tested against synth.dart chords in
// test/chroma_analysis_test.dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart' show kDefaultA4;

const _pcNames = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// In-place iterative radix-2 Cooley–Tukey FFT. [re]/[im] must be the same
/// length and a power of two. Transforms in place.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  assert(im.length == n);
  assert(n & (n - 1) == 0, 'FFT length must be a power of two');
  if (n <= 1) return;

  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  // Danielson–Lanczos butterflies.
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * pi / len;
    final wLenRe = cos(ang);
    final wLenIm = sin(ang);
    for (var i = 0; i < n; i += len) {
      var wRe = 1.0;
      var wIm = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final uRe = re[i + k];
        final uIm = im[i + k];
        final vRe = re[i + k + len ~/ 2] * wRe - im[i + k + len ~/ 2] * wIm;
        final vIm = re[i + k + len ~/ 2] * wIm + im[i + k + len ~/ 2] * wRe;
        re[i + k] = uRe + vRe;
        im[i + k] = uIm + vIm;
        re[i + k + len ~/ 2] = uRe - vRe;
        im[i + k + len ~/ 2] = uIm - vIm;
        final nWRe = wRe * wLenRe - wIm * wLenIm;
        wIm = wRe * wLenIm + wIm * wLenRe;
        wRe = nWRe;
      }
    }
  }
}

/// A chord shape as semitone offsets from the root, with the suffix used to
/// name it (e.g. C + [0,3,7] + 'm' → "Cm").
class ChordTemplate {
  const ChordTemplate(this.suffix, this.intervals);
  final String suffix;
  final List<int> intervals;
}

/// The vocabulary we try to match. Ordered roughly most→least common so ties
/// break toward the simpler/likelier chord.
const kChordTemplates = <ChordTemplate>[
  ChordTemplate('', [0, 4, 7]), // major
  ChordTemplate('m', [0, 3, 7]), // minor
  ChordTemplate('7', [0, 4, 7, 10]), // dominant 7
  ChordTemplate('m7', [0, 3, 7, 10]), // minor 7
  ChordTemplate('maj7', [0, 4, 7, 11]), // major 7
  ChordTemplate('sus4', [0, 5, 7]), // suspended 4
  ChordTemplate('dim', [0, 3, 6]), // diminished
  ChordTemplate('aug', [0, 4, 8]), // augmented
];

/// One fuzzy chord guess.
class ChordCandidate {
  const ChordCandidate({
    required this.rootPc,
    required this.suffix,
    required this.score,
  });

  /// Root pitch class, 0 = C … 11 = B.
  final int rootPc;
  final String suffix;

  /// Cosine similarity to the template, 0..1. Higher = better fit.
  final double score;

  /// e.g. "C", "Am", "G7".
  String get name => '${_pcNames[rootPc]}$suffix';

  @override
  String toString() => '$name (${(score * 100).toStringAsFixed(0)}%)';
}

/// The result of analysing one window for chords.
class ChordReading {
  const ChordReading({
    required this.candidates,
    required this.chroma,
    required this.energy,
  });

  /// Best guesses, strongest first (may be empty on silence).
  final List<ChordCandidate> candidates;

  /// The 12-bin normalized pitch-class profile (for visualisation).
  final List<double> chroma;

  /// Absolute level in the analysed band: the summed pitch-class magnitude per
  /// input sample. An absolute measure (NOT read off the peak-normalized
  /// chroma), so it actually tracks loudness and can serve as a silence gate.
  final double energy;

  factory ChordReading.silent() =>
      ChordReading(candidates: const [], chroma: List.filled(12, 0), energy: 0);

  bool get hasChord => candidates.isNotEmpty;
  ChordCandidate? get best => candidates.isEmpty ? null : candidates.first;

  @override
  String toString() =>
      hasChord ? candidates.take(3).join(', ') : 'ChordReading.silent';
}

/// Computes a chromagram and matches chord templates. Stateless per window; the
/// capture service feeds it the same windows it feeds [PitchDetector].
class ChordDetector {
  ChordDetector({
    this.sampleRate = 44100,
    this.a4 = kDefaultA4,
    this.minFrequency = 65.0, // ~C2: cover a guitar/piano's chord register.
    this.maxFrequency = 2000.0,
    this.energyGate = 1e-4,
    this.scoreThreshold = 0.6,
    this.maxCandidates = 3,
    this.templates = kChordTemplates,
  });

  /// The chord vocabulary to match against. Defaults to [kChordTemplates], so
  /// every existing caller is unaffected.
  ///
  /// Injectable because extending this vocabulary has to be MEASURED, not argued
  /// about — more templates is not automatically better, since a denser template
  /// has more ones and partially matches more things. `tool/
  /// chord_template_ab.dart` A/Bs a candidate set against the shipped one; the
  /// first thing it measured was a **−19pp regression** from the obvious
  /// extension, which is why nothing here changes without a number.
  final List<ChordTemplate> templates;

  final int sampleRate;
  final double a4;
  final double minFrequency;
  final double maxFrequency;

  /// Below this absolute band level ([ChordReading.energy]), treat the window as
  /// silence and report no chord.
  final double energyGate;

  /// Best-candidate cosine below this → report no chord (too ambiguous).
  final double scoreThreshold;

  final int maxCandidates;

  /// The window this detector wants: larger than the pitch detector's, for the
  /// finer FFT frequency resolution chord matching needs (≈10 Hz at 44.1 kHz).
  int get windowSize => 4096;

  /// Pre-computed L2-normalized template vectors, one per (root, template).
  late final List<({int rootPc, String suffix, List<double> vec})> _templates =
      _buildTemplates();

  List<({int rootPc, String suffix, List<double> vec})> _buildTemplates() {
    final out = <({int rootPc, String suffix, List<double> vec})>[];
    for (var root = 0; root < 12; root++) {
      for (final t in templates) {
        final v = List<double>.filled(12, 0);
        for (final iv in t.intervals) {
          v[(root + iv) % 12] = 1.0;
        }
        _l2Normalize(v);
        out.add((rootPc: root, suffix: t.suffix, vec: v));
      }
    }
    return out;
  }

  /// Analyse one window of mono samples in [-1, 1].
  ChordReading analyze(Float64List samples) {
    // A window shorter than 2 samples can't be Hann-windowed or FFT-binned
    // (the bin clamp would be `clamp(1, 0)`), and a bad/empty mic frame must
    // never crash the chord listener — treat it as silence.
    if (samples.length < 2) return ChordReading.silent();
    // Gate on the ABSOLUTE band level, which means measuring it *before* peak
    // normalization: `chromagram` scales its output so the loudest bin is 1, so
    // any sum over it is scale-invariant (always ≈1..12 for any non-zero input).
    // Gating on that can only ever catch bit-exact silence — inaudible noise
    // sails through and is emitted as a confident chord.
    final raw = _rawChroma(samples);
    var sum = 0.0;
    for (final v in raw) {
      sum += v;
    }
    // Per input sample, so the gate is window-size independent and stays
    // comparable to the signal's amplitude.
    final energy = sum / samples.length;
    if (energy < energyGate) return ChordReading.silent();

    final chroma = List<double>.of(raw);
    _peakNormalize(chroma);

    final norm = List<double>.of(chroma);
    _l2Normalize(norm);

    final scored = <ChordCandidate>[];
    for (final t in _templates) {
      var dot = 0.0;
      for (var i = 0; i < 12; i++) {
        dot += norm[i] * t.vec[i];
      }
      scored.add(
        ChordCandidate(rootPc: t.rootPc, suffix: t.suffix, score: dot),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty || scored.first.score < scoreThreshold) {
      return ChordReading(candidates: const [], chroma: chroma, energy: energy);
    }
    return ChordReading(
      candidates: scored.take(maxCandidates).toList(),
      chroma: chroma,
      energy: energy,
    );
  }

  /// The 12-bin pitch-class energy profile of [samples], normalized so its max
  /// is 1 (0 for silence). Public for tests and visualisation.
  List<double> chromagram(Float64List samples) {
    if (samples.length < 2) return List<double>.filled(12, 0);
    final chroma = _rawChroma(samples);
    _peakNormalize(chroma);
    return chroma;
  }

  /// The un-normalized 12-bin pitch-class magnitude profile — the absolute
  /// spectral level, which the silence gate needs (see [analyze]).
  List<double> _rawChroma(Float64List samples) {
    final n = _pow2AtLeast(samples.length);
    final re = Float64List(n);
    final im = Float64List(n);
    // Hann window to cut spectral leakage; zero-pad up to the FFT size.
    final m = samples.length;
    for (var i = 0; i < m; i++) {
      final w = 0.5 - 0.5 * cos(2 * pi * i / (m - 1));
      re[i] = samples[i] * w;
    }
    fft(re, im);

    final chroma = List<double>.filled(12, 0);
    final loBin = (minFrequency * n / sampleRate).floor().clamp(1, n ~/ 2);
    final hiBin = (maxFrequency * n / sampleRate).ceil().clamp(1, n ~/ 2);
    for (var bin = loBin; bin <= hiBin; bin++) {
      final freq = bin * sampleRate / n;
      final mag = sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
      // A NaN/Inf sample (bad mic frame) yields a non-finite magnitude; skip it
      // so the chroma — and everything derived from it (energy gate, cosine
      // scores) — stays finite instead of leaking NaN downstream.
      if (!mag.isFinite) continue;
      final midi = 69.0 + 12.0 * (log(freq / a4) / ln2);
      final pc = (midi.round() % 12 + 12) % 12;
      chroma[pc] += mag;
    }
    return chroma;
  }

  /// Scale [v] so its largest entry is 1 (a no-op on an all-zero profile).
  static void _peakNormalize(List<double> v) {
    var peak = 0.0;
    for (final x in v) {
      if (x > peak) peak = x;
    }
    if (peak > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= peak;
      }
    }
  }

  static void _l2Normalize(List<double> v) {
    var sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = sqrt(sumSq);
    if (norm > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
    }
  }

  static int _pow2AtLeast(int x) {
    var n = 1;
    while (n < x) {
      n <<= 1;
    }
    return n;
  }
}
