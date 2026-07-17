// bin/aec_tune/corpus.dart
//
// A synthetic AEC evaluation corpus with GROUND TRUTH — the thing an automatic
// tuner scores against. Each scenario is a converge-then-double-talk take: a
// reference (what the "speaker" plays) echoed through a room into a mic, with a
// near-end instrument note added for the second half. Because we synthesize both
// halves we KNOW the true near-end exactly, so SI-SDR and note-survival are both
// computable — the two metrics the tuner maximizes.
//
// This is CLI-only tooling (like bin/aecmos/), kept out of lib/ so it never
// ships in the app. Two builders:
//   * buildCorpus — synthetic PARAMETRIC rooms (decaying random FIRs): no
//     downloads, cheap diversity, the CI-friendly default.
//   * buildCorpusFromAssets — REAL measured room IRs (MIT IR Survey) × REAL
//     cello (Iowa MIS), the tier-2 corpus. Same AecScenario type, so the
//     objective and tuner are unchanged.
// The only realism even tier 2 lacks vs a device capture is speaker/mic
// NONLINEARITY (an RIR is a linear convolution) — that last gap needs hardware.
//
// No Random-in-workflow constraints here (this is a normal CLI), but every
// scenario is SEEDED so a tuning run is reproducible.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show midiToFrequency;
import 'package:comet_beat/core/audio/wav_io.dart';

/// One evaluation take with known ground truth.
class AecScenario {
  AecScenario({
    required this.ref,
    required this.mic,
    required this.trueNear,
    required this.doubleTalkFrom,
    required this.nearMidi,
    required this.label,
  });

  /// What the speaker played (the AEC far-end/reference).
  final Float64List ref;

  /// What the mic captured: room-echo of [ref], plus [trueNear] from
  /// [doubleTalkFrom] on.
  final Float64List mic;

  /// The near-end the user actually made — known because we synthesized it.
  /// Zero before [doubleTalkFrom].
  final Float64List trueNear;

  /// Sample index where the near-end joins (the filter converges before this).
  final int doubleTalkFrom;

  /// The MIDI note of the near-end instrument — for note-survival scoring.
  final int nearMidi;

  /// Human-readable description of the room/signal for reports.
  final String label;
}

/// A decaying random-FIR "room": [taps] samples starting at [delay], amplitude
/// decaying at [decay] per tap. Seeded for reproducibility. Real rooms are
/// sparser and longer, but this spans the axis that matters to the filter —
/// delay, tail length, and decay rate.
Float64List _roomIr(
  Random rng, {
  required int delay,
  required int taps,
  required double decay,
}) {
  final ir = Float64List(delay + taps);
  var amp = 1.0;
  for (var i = 0; i < taps; i++) {
    ir[delay + i] = amp * (rng.nextDouble() * 2 - 1);
    amp *= decay;
  }
  return ir;
}

Float64List _convolve(Float64List x, Float64List ir) {
  final out = Float64List(x.length);
  for (var t = 0; t < x.length; t++) {
    var acc = 0.0;
    final jMax = min(ir.length, t + 1);
    for (var j = 0; j < jMax; j++) {
      acc += ir[j] * x[t - j];
    }
    out[t] = acc;
  }
  return out;
}

/// Seeded broadband reference (white noise) — the well-conditioned far-end an
/// adaptive filter converges on, and a stand-in for music/speech energy.
Float64List _noiseRef(Random rng, int n, {double amp = 0.3}) {
  final r = Float64List(n);
  for (var i = 0; i < n; i++) {
    r[i] = amp * (rng.nextDouble() * 2 - 1);
  }
  return r;
}

/// A sustained instrument-like tone (a few harmonics) at [midi] — the near-end
/// whose survival we score.
Float64List _instrument(int midi, int n, int rate, {double amp = 0.3}) {
  final f = midiToFrequency(midi);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    out[i] = amp *
        (0.7 * sin(2 * pi * f * t) +
            0.2 * sin(2 * pi * 2 * f * t) +
            0.1 * sin(2 * pi * 3 * f * t));
  }
  return out;
}

/// Build a diverse corpus: [rooms] room variants × the near-end notes in
/// [nearMidis], each a 2-second converge-then-double-talk take. Fully seeded by
/// [seed] so a tuning run is reproducible.
List<AecScenario> buildCorpus({
  int seed = 20260717,
  int rate = 44100,
  double seconds = 2.0,
  int rooms = 4,
  List<int> nearMidis = const [57, 69, 45], // A3 (cello), A4, A2 (low cello)
  Loudspeaker loudspeaker = Loudspeaker.linear,
  double drive = 2.0,
}) {
  final rng = Random(seed);
  final n = (rate * seconds).round();
  final half = n ~/ 2;
  final out = <AecScenario>[];

  // A spread of rooms along (delay, taps, decay).
  final roomSpecs = <({int delay, int taps, double decay})>[
    (delay: 40, taps: 24, decay: 0.75),
    (delay: 120, taps: 48, decay: 0.85),
    (delay: 240, taps: 96, decay: 0.90),
    (delay: 500, taps: 160, decay: 0.93),
  ];

  for (var ri = 0; ri < rooms; ri++) {
    final spec = roomSpecs[ri % roomSpecs.length];
    final ir =
        _roomIr(rng, delay: spec.delay, taps: spec.taps, decay: spec.decay);
    final ref = _noiseRef(rng, n);
    // AEC sees the clean ref; the echo is the speaker-distorted ref (see the
    // asset builder for why this makes the echo nonlinear).
    final echo = _convolve(applyLoudspeaker(ref, loudspeaker, drive), ir);
    for (final midi in nearMidis) {
      final near = _instrument(midi, n, rate);
      final trueNear = Float64List(n);
      final mic = Float64List(n);
      for (var i = 0; i < n; i++) {
        trueNear[i] = i >= half ? near[i] : 0.0;
        mic[i] = echo[i] + trueNear[i];
      }
      out.add(
        AecScenario(
          ref: ref,
          mic: mic,
          trueNear: trueNear,
          doubleTalkFrom: half,
          nearMidi: midi,
          label: 'room${ri}_d${spec.delay}_t${spec.taps} near=$midi',
        ),
      );
    }
  }
  return out;
}

// --- Real-acoustics corpus (tier 2) ----------------------------------------
//
// The same converge-then-double-talk scenario, but the room is a REAL measured
// impulse response (MIT IR Survey WAVs) and the near-end is a REAL cello (Iowa
// MIS WAVs) instead of synthesized tones. Ground truth is still exact — we place
// the clean cello ourselves — so SI-SDR and note-survival both work. The only
// realism this still lacks vs a device capture is speaker/mic NONLINEARITY (an
// RIR is a linear convolution); that last gap needs real hardware.
//
// The near-end note isn't assumed: it's DETECTED on the clean cello window, so
// note-survival honestly asks "does the detector read the SAME note after
// cancellation as it did before". A window with no clear pitch is skipped.

/// Loudspeaker nonlinearity models applied to the reference BEFORE the echo
/// path (a Hammerstein model) — how the AEC Challenge synthesizes its nonlinear
/// echo. The AEC only ever sees the CLEAN reference, so the harmonics the
/// speaker adds are NOT in the reference and a linear filter cannot cancel them:
/// this is what makes an echo "nonlinear" and motivates a residual/nonlinear
/// stage. Memoryless and patent-free.
enum Loudspeaker {
  /// No distortion — the linear echo (drive is ignored).
  linear,

  /// Hard amplitude clipping at peak/[drive] (drive 1 = no clip, 2 = clip at
  /// half-peak). A loud speaker slamming into its excursion limit.
  hardClip,

  /// tanh soft-clip `tanh(drive·x)/drive` — unity small-signal gain, peaks
  /// compressed; the "sigmoidal" distortion of a driven speaker. Higher drive =
  /// more compression and more odd harmonics.
  sigmoid,
}

/// Apply a memoryless loudspeaker nonlinearity to [x] (a fresh list). The output
/// is renormalized to [x]'s RMS, so the model changes only the waveform SHAPE
/// (the added harmonics a linear filter can't cancel), NOT the overall level —
/// otherwise a compressing curve would just make the echo quieter and easier to
/// cancel, hiding the distortion behind a gain change.
Float64List applyLoudspeaker(Float64List x, Loudspeaker mode, double drive) {
  if (mode == Loudspeaker.linear) return Float64List.fromList(x);

  final out = Float64List(x.length);
  switch (mode) {
    case Loudspeaker.linear:
      return Float64List.fromList(x);
    case Loudspeaker.hardClip:
      var peak = 0.0;
      for (final v in x) {
        if (v.abs() > peak) peak = v.abs();
      }
      final t = drive > 0 ? peak / drive : peak;
      for (var i = 0; i < x.length; i++) {
        out[i] = x[i].clamp(-t, t);
      }
    case Loudspeaker.sigmoid:
      final d = drive <= 0 ? 1e-9 : drive;
      for (var i = 0; i < x.length; i++) {
        // tanh via exp; the /d keeps small-signal gain ≈ 1.
        final z = 2 * d * x[i];
        final e = exp(-z.abs());
        final th = (1 - e) / (1 + e) * (z >= 0 ? 1 : -1);
        out[i] = th / d;
      }
  }

  // Renormalize to the input RMS: shape changes, level held constant.
  var inSq = 0.0, outSq = 0.0;
  for (var i = 0; i < x.length; i++) {
    inSq += x[i] * x[i];
    outSq += out[i] * out[i];
  }
  if (outSq > 1e-30) {
    final g = sqrt(inSq / outSq);
    for (var i = 0; i < out.length; i++) {
      out[i] *= g;
    }
  }
  return out;
}

Float64List _loadMonoWav(String path) =>
    wavToMonoFloat(readWavPcm16(File(path).readAsBytesSync()));

/// Full convolution truncated to [x.length] — the mic captures only as long as
/// the reference plays.
Float64List _convolveReal(Float64List x, Float64List ir) => _convolve(x, ir);

/// The dominant MIDI note of [signal] over a centred window, or -1 if none.
int _detectMidi(Float64List signal, int rate, PitchDetector detector) {
  final w = detector.windowSize;
  if (signal.length < w) return -1;
  final start = (signal.length - w) ~/ 2;
  final r = detector.analyze(Float64List.sublistView(signal, start, start + w));
  return r.hasPitch ? r.nearestMidi : -1;
}

/// Peak absolute amplitude over `[from, to)`.
double _peak(Float64List x, int from, int to) {
  var p = 0.0;
  for (var i = from; i < to; i++) {
    final a = x[i].abs();
    if (a > p) p = a;
  }
  return p;
}

/// Scan [cello] for up to [want] LOUD, clearly-pitched note segments of
/// [len] samples — the Iowa runs are long with silence between notes, so blind
/// windowing mostly hits silence. Returns (start, midi) for each good segment,
/// spaced at least [len] apart so they're distinct notes.
List<({int start, int midi})> _findNotes(
  Float64List cello,
  int len,
  int rate,
  PitchDetector detector, {
  int want = 3,
  double minPeak = 0.05,
}) {
  final found = <({int start, int midi})>[];
  final step = len ~/ 2;
  var last = -len;
  for (var s = 0; s + len <= cello.length && found.length < want; s += step) {
    if (s - last < len) continue; // keep notes distinct
    final seg = Float64List.sublistView(cello, s, s + len);
    if (_peak(seg, 0, len) < minPeak) continue; // silence between notes
    final midi = _detectMidi(seg, rate, detector);
    if (midi < 0) continue;
    // Confirm the pitch is stable across the segment (a sustained note, not a
    // transition): the segment's two halves must read the same note.
    final a = _detectMidi(
      Float64List.sublistView(seg, 0, len ~/ 2),
      rate,
      detector,
    );
    final b = _detectMidi(
      Float64List.sublistView(seg, len ~/ 2, len),
      rate,
      detector,
    );
    if (a != midi || b != midi) continue;
    found.add((start: s, midi: midi));
    last = s;
  }
  return found;
}

/// Build a corpus from measured RIR WAVs in [rirDir] and cello WAVs in
/// [celloDir] (both mono, [rate] Hz). Each (room × cello-window) pair becomes a
/// scenario; windows whose clean pitch is unclear are dropped. [windowsPerCello]
/// takes that many sustained windows from each cello file (they are long
/// chromatic runs, so different windows are different notes).
List<AecScenario> buildCorpusFromAssets({
  required String rirDir,
  required String celloDir,
  int rate = 44100,
  double seconds = 4.0,
  int windowsPerCello = 3,
  int seed = 20260717,
  double echoToNear = 2.0,
  int irTaps = 4096,
  Loudspeaker loudspeaker = Loudspeaker.linear,
  double drive = 2.0,
}) {
  final rng = Random(seed);
  final n = (rate * seconds).round();
  final half = n ~/ 2;

  double rms(Float64List x, int from, int to) {
    var s = 0.0;
    for (var i = from; i < to; i++) {
      s += x[i] * x[i];
    }
    return sqrt(s / (to - from));
  }

  // Truncate each measured IR to its early field ([irTaps] samples ≈ the first
  // ~90 ms). This is the high-energy, cancellable part a single-block filter can
  // model — the probe showed it cancels BETTER than the full IR (whose long
  // reverb tail exceeds the filter and just adds unmodellable residual). It also
  // keeps the O(n·taps) convolution tractable. Real early reflections, real room.
  Float64List earlyIr(Float64List ir) =>
      ir.length <= irTaps ? ir : Float64List.sublistView(ir, 0, irTaps);

  final rirs = Directory(rirDir)
      .listSync()
      .where((e) => e.path.toLowerCase().endsWith('.wav'))
      .map(
        (e) =>
            (name: e.uri.pathSegments.last, ir: earlyIr(_loadMonoWav(e.path))),
      )
      .toList();
  final cellos = Directory(celloDir)
      .listSync()
      .where((e) => e.path.toLowerCase().endsWith('.wav'))
      .map((e) => (name: e.uri.pathSegments.last, sig: _loadMonoWav(e.path)))
      .toList();
  if (rirs.isEmpty || cellos.isEmpty) {
    throw StateError(
      'need at least one RIR ($rirDir) and one cello ($celloDir)',
    );
  }

  // The near-end occupies the double-talk half; find that many real cello notes.
  final detector = PitchDetector(sampleRate: rate);
  final notesPerCello = <String, List<({int start, int midi})>>{};
  for (final cello in cellos) {
    notesPerCello[cello.name] = _findNotes(
      cello.sig,
      half,
      rate,
      detector,
      want: windowsPerCello,
    );
  }

  final out = <AecScenario>[];
  for (final room in rirs) {
    // A seeded broadband reference "played" through this real room. The AEC is
    // given the CLEAN ref; the ECHO is the SPEAKER-DISTORTED ref through the
    // room, so any loudspeaker nonlinearity is in the mic but not the reference
    // — a linear filter can't cancel it (the point of the nonlinear corpus).
    final ref = _noiseRef(rng, n);
    final played = applyLoudspeaker(ref, loudspeaker, drive);
    final rawEcho = _convolveReal(played, room.ir);
    for (final cello in cellos) {
      for (final note in notesPerCello[cello.name]!) {
        // The clean cello note, held through the double-talk half, normalized
        // to a sensible near-end level.
        final clean = Float64List.sublistView(
          cello.sig,
          note.start,
          note.start + half,
        );
        final peak = _peak(clean, 0, half);
        final gain = peak > 1e-6 ? 0.3 / peak : 0.0;

        final trueNear = Float64List(n);
        for (var i = 0; i < half; i++) {
          trueNear[half + i] = clean[i] * gain; // near-end in the 2nd half
        }

        // Level-calibrate: real RIRs aren't energy-normalized, so scale the
        // echo to a realistic echo-to-near ratio over the double-talk region.
        // Without this the raw echo dwarfs the near-end and no achievable
        // cancellation brings residual below it (SI-SDR stays negative) — a
        // level artefact, not an AEC failure.
        final nearRms = rms(trueNear, half, n);
        final echoRms = rms(rawEcho, half, n);
        final echoGain = echoRms > 1e-9 ? echoToNear * nearRms / echoRms : 1.0;

        final mic = Float64List(n);
        for (var i = 0; i < n; i++) {
          mic[i] = rawEcho[i] * echoGain + trueNear[i];
        }
        out.add(
          AecScenario(
            ref: ref,
            mic: mic,
            trueNear: trueNear,
            doubleTalkFrom: half,
            nearMidi: note.midi,
            label: '${room.name} × ${cello.name} note=${note.midi}',
          ),
        );
      }
    }
  }
  return out;
}
