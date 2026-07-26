// Signal-level comparison metrics for A/B-ing two renders of the same music.
//
// WHY THIS IS A LIBRARY AND NOT PART OF THE HARNESS
//
// The OpenMPT A/B (`tracker_audio_regression_test.dart`) is opt-in: it needs a
// Homebrew `openmpt123` and licence-restricted modules that must never be
// committed. So on CI it never runs — and metrics that never run are metrics
// nobody can trust. These live here, exercised by `audio_compare_test.dart`
// against SYNTHESISED signals with known differences, so the measuring
// instruments are verified on every push even though the A/B itself is not.
//
// WHAT THE OLD COMPARISON MISSED
//
// The harness compared duration and RMS. Both are blind to the failure our
// architecture is most exposed to: we turn Amiga periods into MIDI notes
// (`periodToMidi`) and render at A440 equal temperament rather than from the
// Paula clock, so a systematic TUNING error would leave duration identical and
// RMS nearly identical. [spectralSimilarity] is the instrument that sees it.
// (The harness header already claimed "frequency spectrum match (FFT
// correlation)" — there was no FFT in the file.)
//
// Each metric answers a different question, and a real regression usually
// trips exactly one:
//   * [levelDeltaDb]        — is it as loud?            (gain, mixing)
//   * [envelopeCorrelation] — does it move the same?    (note timing, envelopes)
//   * [bestLagSamples]      — is it early or late?      (tempo, priming, offset)
//   * [spectralSimilarity]  — is it the same PITCHES?   (tuning, wrong sample)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

/// RMS of [pcm] (0 for an empty buffer).
double rms(Float64List pcm) {
  if (pcm.isEmpty) return 0;
  var sum = 0.0;
  for (final v in pcm) {
    sum += v * v;
  }
  return math.sqrt(sum / pcm.length);
}

/// How much louder [a] is than [b], in dB. Positive = [a] is louder.
///
/// Silence on either side floors at ±120 dB rather than returning infinity, so
/// a failure message stays readable.
double levelDeltaDb(Float64List a, Float64List b) {
  final ra = rms(a);
  final rb = rms(b);
  if (ra <= 1e-12 && rb <= 1e-12) return 0;
  if (rb <= 1e-12) return 120;
  if (ra <= 1e-12) return -120;
  return 20 * math.log(ra / rb) / math.ln10;
}

/// Block-RMS envelope of [pcm] at [block] samples per point.
Float64List rmsEnvelope(Float64List pcm, {int block = 512}) {
  if (pcm.isEmpty || block <= 0) return Float64List(0);
  final n = (pcm.length / block).ceil();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final start = i * block;
    final end = math.min(pcm.length, start + block);
    var sum = 0.0;
    for (var j = start; j < end; j++) {
      sum += pcm[j] * pcm[j];
    }
    out[i] = math.sqrt(sum / (end - start));
  }
  return out;
}

/// Pearson correlation of two sequences, in [-1, 1]; 1 = same shape.
///
/// Returns 0 when either side is constant (including all-silent): there is no
/// shape to agree about, and 0 keeps that honestly distinct from agreement.
double _pearson(Float64List a, Float64List b) {
  final n = math.min(a.length, b.length);
  if (n < 2) return 0;
  var meanA = 0.0;
  var meanB = 0.0;
  for (var i = 0; i < n; i++) {
    meanA += a[i];
    meanB += b[i];
  }
  meanA /= n;
  meanB /= n;
  var num = 0.0;
  var da = 0.0;
  var db = 0.0;
  for (var i = 0; i < n; i++) {
    final xa = a[i] - meanA;
    final xb = b[i] - meanB;
    num += xa * xb;
    da += xa * xa;
    db += xb * xb;
  }
  if (da <= 1e-20 || db <= 1e-20) return 0;
  return num / math.sqrt(da * db);
}

/// Do the two renders swell and fade together? 1 = identical shape.
///
/// Compares loudness CONTOURS, so it is deliberately indifferent to overall
/// gain — a render that is uniformly 6 dB quiet still scores 1 here and is
/// caught by [levelDeltaDb] instead. Each metric answers one question.
double envelopeCorrelation(Float64List a, Float64List b, {int block = 512}) =>
    _pearson(rmsEnvelope(a, block: block), rmsEnvelope(b, block: block));

/// How far [b] is shifted relative to [a], in samples: positive = [b] is LATE.
///
/// Cross-correlates the loudness envelopes (not the waveforms) so it survives
/// two renders that differ in phase, interpolation and dither but share their
/// note onsets — which is exactly the case when comparing two players.
/// [maxLagBlocks] bounds the search in envelope blocks.
/// Returns **0 when it cannot tell**, which matters more than it sounds: an
/// unreliable lag is worse than none, because callers shift by it and destroy
/// the very overlap they wanted to compare. Two guards, both added after this
/// misfired on real renders:
///  * the search is capped at a quarter of the shorter envelope, so it can
///    never slide past the material (the fixed ±0.74 s window exceeded the
///    entire 0.48 s render and happily "found" a 0.46 s offset);
///  * a peak below [minConfidence] is treated as no alignment at all, because
///    a flat envelope has no peak — only noise with an argmax.
int bestLagSamples(
  Float64List a,
  Float64List b, {
  int block = 512,
  int maxLagBlocks = 64,
  double minConfidence = 0.5,
}) {
  final ea = rmsEnvelope(a, block: block);
  final eb = rmsEnvelope(b, block: block);
  if (ea.length < 2 || eb.length < 2) return 0;

  final span = math.min(ea.length, eb.length) ~/ 4;
  final maxLag = math.min(maxLagBlocks, span);
  if (maxLag < 1) return 0;

  var bestLag = 0;
  var bestScore = -2.0;
  for (var lag = -maxLag; lag <= maxLag; lag++) {
    // Overlap of eb shifted by `lag` onto ea.
    final start = math.max(0, -lag);
    final end = math.min(ea.length, eb.length - lag);
    if (end - start < 2) continue;
    final sliceA = Float64List(end - start);
    final sliceB = Float64List(end - start);
    for (var i = start; i < end; i++) {
      sliceA[i - start] = ea[i];
      sliceB[i - start] = eb[i + lag];
    }
    final score = _pearson(sliceA, sliceB);
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  // No real peak — say "unknown" rather than hand back an argmax over noise.
  if (bestScore < minConfidence) return 0;
  return bestLag * block;
}

/// The overlapping region of [a] and [b] once [b] is shifted back by [lag].
///
/// [lag] is [bestLagSamples]'s convention: positive means [b] is late, so a
/// positive lag drops [lag] samples off the front of [b]. Use this before any
/// sample-aligned comparison, so a timing offset is reported by the lag rather
/// than smeared into every other metric.
(Float64List, Float64List) alignBy(Float64List a, Float64List b, int lag) {
  final startA = lag < 0 ? -lag : 0;
  final startB = lag > 0 ? lag : 0;
  final n = math.min(a.length - startA, b.length - startB);
  if (n <= 0) return (Float64List(0), Float64List(0));
  return (
    Float64List.sublistView(a, startA, startA + n),
    Float64List.sublistView(b, startB, startB + n),
  );
}

/// Magnitude spectrum of one [frame], Hann-windowed. Length = frame ~/ 2.
Float64List _magnitudeSpectrum(Float64List frame) {
  final n = frame.length;
  final re = Float64List(n);
  final im = Float64List(n);
  for (var i = 0; i < n; i++) {
    // Hann: without it, frame edges smear energy across every bin and two
    // renders look similar merely because both are broadband.
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    re[i] = frame[i] * w;
  }
  fft(re, im);
  final half = n ~/ 2;
  final mag = Float64List(half);
  for (var i = 0; i < half; i++) {
    mag[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]);
  }
  return mag;
}

/// Cosine similarity of two vectors, in [0, 1] for non-negative input.
double _cosine(Float64List a, Float64List b) {
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na <= 1e-20 || nb <= 1e-20) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Are the two renders playing the same PITCHES? 1 = identical spectra.
///
/// Frame-wise cosine similarity of Hann-windowed magnitude spectra, averaged
/// over frames where BOTH sides have energy — silent frames agree trivially and
/// would otherwise inflate the score on a sparse piece.
///
/// This is the metric duration and RMS cannot replace: transpose a render and
/// its length and loudness barely move while this collapses.
///
/// ⚠️ **Resolution sets what it can see.** Bin width is `sampleRate / frame`,
/// and a Hann main lobe spans ~4 bins, so two pitches closer than roughly
/// `4 * sampleRate / frame` land on top of each other and score as identical.
/// The default 8192 gives ~5.4 Hz bins at 44.1 kHz — enough to separate a
/// semitone at A440 (26 Hz apart), which the obvious 1024 (43 Hz bins) is NOT:
/// at that size 440 Hz and 466 Hz occupy the SAME bin and the metric happily
/// reports a match. Raise [frame] to catch smaller offsets (16384 resolves a
/// quarter-tone); lower it only if the material is too fast for 186 ms frames.
/// [quietFraction] skips frames quieter than that fraction of the signal's OWN
/// overall RMS. It is deliberately relative: an absolute floor makes the metric
/// depend on how loud the render happens to be, and a quiet render then reports
/// "no comparable frames" (0) rather than the truth about its pitches. A real
/// case: our `golden.mod` render has an overall RMS of 0.00037, so an absolute
/// 1e-4 floor admitted 2 frames out of 1323.
double spectralSimilarity(
  Float64List a,
  Float64List b, {
  int frame = 8192,
  int hop = 4096,
  double quietFraction = 0.1,
}) {
  assert(frame & (frame - 1) == 0, 'frame must be a power of two');
  final n = math.min(a.length, b.length);
  if (n < frame) return 0;
  // Per-signal floors, so a quiet render is judged on its own scale.
  final floorA = math.max(rms(a) * quietFraction, 1e-9);
  final floorB = math.max(rms(b) * quietFraction, 1e-9);
  var total = 0.0;
  var counted = 0;
  for (var start = 0; start + frame <= n; start += hop) {
    final fa = Float64List.sublistView(a, start, start + frame);
    final fb = Float64List.sublistView(b, start, start + frame);
    if (rms(fa) < floorA || rms(fb) < floorB) continue;
    total += _cosine(
      _magnitudeSpectrum(Float64List.fromList(fa)),
      _magnitudeSpectrum(Float64List.fromList(fb)),
    );
    counted++;
  }
  // Nothing audible in common: report 0 rather than a vacuous 1.
  if (counted == 0) return 0;
  return total / counted;
}

/// The average magnitude spectrum of [pcm], on a LOG-frequency axis.
///
/// Log spacing is what makes a tuning offset a simple SHIFT: transposing by an
/// interval multiplies every frequency by a constant, which on a log axis moves
/// the whole spectrum sideways by a constant number of bins. On a linear axis
/// the same transposition stretches it, and no amount of correlating recovers a
/// single number from that.
Float64List _logSpectrum(
  Float64List pcm, {
  required int sampleRate,
  required int binsPerOctave,
  double minHz = 80,
  double maxHz = 8000,
  int frame = 8192,
}) {
  final octaves = math.log(maxHz / minHz) / math.ln2;
  final bins = (octaves * binsPerOctave).round();
  final out = Float64List(bins);
  if (pcm.length < frame) return out;

  // One averaged linear spectrum first — averaging over frames keeps a single
  // loud note from deciding the answer for the whole piece.
  final half = frame ~/ 2;
  final avg = Float64List(half);
  var frames = 0;
  final floor = rms(pcm) * 0.1;
  for (var start = 0; start + frame <= pcm.length; start += frame ~/ 2) {
    final win = Float64List.fromList(
      Float64List.sublistView(pcm, start, start + frame),
    );
    if (rms(win) < floor) continue;
    final mag = _magnitudeSpectrum(win);
    for (var i = 0; i < half; i++) {
      avg[i] += mag[i];
    }
    frames++;
  }
  if (frames == 0) return out;

  final hzPerBin = sampleRate / frame;
  for (var b = 0; b < bins; b++) {
    final hz = minHz * math.pow(2, b / binsPerOctave);
    final pos = hz / hzPerBin;
    final i = pos.floor();
    if (i < 0 || i + 1 >= half) continue;
    // Linear interpolation between neighbouring linear bins.
    final t = pos - i;
    out[b] = (avg[i] * (1 - t) + avg[i + 1] * t) / frames;
  }
  return out;
}

/// How far [b] is detuned from [a], in CENTS. Positive = [b] is sharp.
///
/// This is the number the whole metric set was built to produce. We map Amiga
/// periods through `periodToMidi` and render at A440 rather than deriving pitch
/// from the Paula clock, so a systematic tuning offset is a live possibility —
/// and it is invisible to duration, RMS and envelope alike. `spectralSimilarity`
/// can tell you two renders disagree; only this says by how much, which is what
/// decides whether the difference is worth changing anything for.
///
/// Cross-correlates the two log-frequency spectra and parabolically interpolates
/// the peak, so it resolves well below one bin. Returns 0 when either side has
/// no usable spectrum — "no evidence", not "perfectly in tune".
double detuneCents(
  Float64List a,
  Float64List b, {
  int sampleRate = 44100,
  int binsPerOctave = 240, // 5 cents per bin before interpolation
  double maxCents = 600, // half an octave either way
}) {
  final sa =
      _logSpectrum(a, sampleRate: sampleRate, binsPerOctave: binsPerOctave);
  final sb =
      _logSpectrum(b, sampleRate: sampleRate, binsPerOctave: binsPerOctave);
  if (sa.isEmpty || sb.isEmpty) return double.nan;
  if (rms(sa) <= 1e-20 || rms(sb) <= 1e-20) return double.nan;

  final maxShift = (maxCents / 1200 * binsPerOctave).round();
  var bestShift = 0;
  var bestScore = -2.0;
  final scores = <int, double>{};
  for (var shift = -maxShift; shift <= maxShift; shift++) {
    final start = math.max(0, -shift);
    final end = math.min(sa.length, sb.length - shift);
    if (end - start < binsPerOctave) continue;
    final va = Float64List(end - start);
    final vb = Float64List(end - start);
    for (var i = start; i < end; i++) {
      va[i - start] = sa[i];
      vb[i - start] = sb[i + shift];
    }
    final score = _cosine(va, vb);
    scores[shift] = score;
    if (score > bestScore) {
      bestScore = score;
      bestShift = shift;
    }
  }
  // A peak sitting ON the search rail is not a measurement — it means the true
  // offset is outside the window, or there is no peak and the argmax wandered
  // to the edge. The degenerate golden.* fixtures do exactly this, and
  // reporting the rail as "-600 cents" would read like a finding. NaN says
  // "no answer" in a way a number never can.
  if (bestScore < 0 || bestShift.abs() >= maxShift) return double.nan;

  // Parabolic interpolation across the peak — the true offset rarely lands on
  // a bin centre, and without this the answer quantises to 5-cent steps.
  var refined = bestShift.toDouble();
  final l = scores[bestShift - 1];
  final r = scores[bestShift + 1];
  if (l != null && r != null) {
    final denom = l - 2 * bestScore + r;
    if (denom.abs() > 1e-12) refined += 0.5 * (l - r) / denom;
  }
  return refined / binsPerOctave * 1200;
}

/// Every metric at once, for a one-line diagnostic when an A/B fails.
class AudioComparison {
  const AudioComparison({
    required this.levelDb,
    required this.envelope,
    required this.lagSamples,
    required this.spectral,
    required this.detune,
  });

  /// Measures all four, **aligning by the detected lag before comparing
  /// spectra**.
  ///
  /// Without that step the spectral score answers the wrong question. It
  /// compares frame *i* of one render against frame *i* of the other, so a
  /// render that is merely LATE scores as though it were playing different
  /// notes — and the two faults need different fixes. Measured against
  /// OpenMPT our renders sit up to ~0.6 s apart (start-up priming and trailing
  /// silence differ between engines), which was enough to drag every spectral
  /// score toward zero and make the metric useless for its actual purpose.
  ///
  /// So: lag is reported on its own, and spectra are compared after removing
  /// it. Each number then isolates one fault.
  factory AudioComparison.of(Float64List a, Float64List b) {
    final lag = bestLagSamples(a, b);
    final (alignedA, alignedB) = alignBy(a, b, lag);
    return AudioComparison(
      levelDb: levelDeltaDb(a, b),
      envelope: envelopeCorrelation(a, b),
      lagSamples: lag,
      spectral: spectralSimilarity(alignedA, alignedB),
      detune: detuneCents(alignedA, alignedB),
    );
  }

  final double levelDb;
  final double envelope;
  final int lagSamples;
  final double spectral;

  /// Cents the SECOND render is sharp of the first. The number that decides
  /// whether a pitch difference is worth acting on.
  final double detune;

  @override
  String toString() => 'level ${levelDb.toStringAsFixed(2)} dB · '
      'envelope ${envelope.toStringAsFixed(3)} · '
      'lag $lagSamples samples · '
      'spectral ${spectral.toStringAsFixed(3)} · '
      'detune ${detune.isNaN ? "n/a" : "${detune.toStringAsFixed(1)} cents"}';
}
