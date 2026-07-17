// aec_offline — the offline/streaming glue over EchoCanceller that the AEC CLI
// uses. Synthetic scenarios (a known room IR): high ERLE on echo-only, near-end
// preserved under double-talk, delay recovery, and streaming≡batch equivalence.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_offline.dart';
import 'package:comet_beat/core/audio/echo_canceller.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

/// A deterministic broadband-ish reference (a few sines) — excites the adaptive
/// filter across the spectrum so it can converge.
Float64List _reference(int n) {
  final r = Float64List(n);
  for (var t = 0; t < n; t++) {
    r[t] = 0.6 * sin(2 * pi * 220 * t / _sr) +
        0.3 * sin(2 * pi * 437 * t / _sr) +
        0.2 * sin(2 * pi * 911 * t / _sr);
  }
  return r;
}

/// Deterministic broadband white noise — the well-conditioned reference an
/// adaptive filter converges on fastest (and closest to real music/speech).
Float64List _noise(int n, {int seed = 7, double amp = 0.3}) {
  final rng = Random(seed);
  final r = Float64List(n);
  for (var i = 0; i < n; i++) {
    r[i] = amp * (rng.nextDouble() * 2 - 1);
  }
  return r;
}

/// A short speaker→mic impulse response (the "room"), within one block.
const _h = [0.8, -0.35, 0.2, -0.1, 0.05];

/// Echo = ref convolved with the room IR, with the whole thing delayed by
/// [delay] samples.
Float64List _echo(Float64List ref, {int delay = 0}) {
  final out = Float64List(ref.length);
  for (var t = 0; t < ref.length; t++) {
    var acc = 0.0;
    for (var j = 0; j < _h.length; j++) {
      final s = t - delay - j;
      if (s >= 0 && s < ref.length) acc += _h[j] * ref[s];
    }
    out[t] = acc;
  }
  return out;
}

/// Normalized cross-correlation of two equal-length signals over [from, to).
double _corr(Float64List a, Float64List b, int from, int to) {
  var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0;
  final n = to - from;
  for (var i = from; i < to; i++) {
    sa += a[i];
    sb += b[i];
    saa += a[i] * a[i];
    sbb += b[i] * b[i];
    sab += a[i] * b[i];
  }
  final cov = sab - sa * sb / n;
  final va = saa - sa * sa / n;
  final vb = sbb - sb * sb / n;
  return cov / (sqrt(va * vb) + 1e-12);
}

Uint8List _interleave(Float64List mic, Float64List ref) {
  final n = min(mic.length, ref.length);
  final bytes = Uint8List(n * 4);
  final v = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    v.setInt16(i * 4, (mic[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    v.setInt16(
      i * 4 + 2,
      (ref[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  const n = 1024 * 40;

  test('cancels a linear echo — high ERLE', () {
    final ref = _reference(n);
    final mic = _echo(ref); // echo only, no near-end
    final result = cancelEcho(mic, ref, delay: 0);

    // Over the converged tail, the echo is deeply suppressed.
    const tail = 1024 * 24;
    final tailErle = erleDb(
      Float64List.sublistView(mic, tail, result.cleaned.length),
      Float64List.sublistView(result.cleaned, tail),
    );
    expect(
      tailErle,
      greaterThan(20),
      reason: 'tail ERLE = ${tailErle.toStringAsFixed(1)} dB',
    );
    // The whole-signal figure carries the from-scratch warmup, so it's only
    // net-positive — the converged tail above is the meaningful number.
    expect(result.erleDb, greaterThan(0), reason: 'whole-signal ERLE');
  });

  test('preserves the near-end while removing the echo (double-talk)', () {
    final ref = _reference(n);
    final echo = _echo(ref);
    // An independent near-end voice the mic also hears.
    final near = Float64List(n);
    for (var t = 0; t < n; t++) {
      near[t] = 0.4 * sin(2 * pi * 330 * t / _sr);
    }
    final mic = Float64List(n);
    for (var t = 0; t < n; t++) {
      mic[t] = echo[t] + near[t];
    }

    final result = cancelEcho(mic, ref, delay: 0);
    // The cleaned output should track the near-end, not the echo.
    const tail = 1024 * 24;
    final withNear = _corr(result.cleaned, near, tail, result.cleaned.length);
    final withEcho = _corr(result.cleaned, echo, tail, result.cleaned.length);
    expect(withNear, greaterThan(0.8), reason: 'near-end survives');
    expect(
      withNear,
      greaterThan(withEcho),
      reason: 'cleaned tracks the voice, not the speaker',
    );
  });

  test('estimateEchoDelay recovers a known lag', () {
    final ref = _reference(n);
    final mic = _echo(ref, delay: 137);
    expect(estimateEchoDelay(mic, ref), closeTo(137, 2));
  });

  test('streaming matches the batch cancel for the same aligned input', () {
    final ref = _reference(n);
    final mic = _echo(ref); // aligned (delay 0)
    final stereo = _interleave(mic, ref);

    // Decode the PCM16-quantized mic/ref exactly as the streamer sees them, so
    // the batch reference runs on byte-identical input.
    final qmic = Float64List(n), qref = Float64List(n);
    final sv = ByteData.sublistView(stereo);
    for (var i = 0; i < n; i++) {
      qmic[i] = sv.getInt16(i * 4, Endian.little) / 32768.0;
      qref[i] = sv.getInt16(i * 4 + 2, Endian.little) / 32768.0;
    }

    // Batch, quantized to PCM16 the same way the stream emits.
    final batch = cancelEcho(qmic, qref, delay: 0).cleaned;
    final batchPcm = Uint8List(batch.length * 2);
    final bv = ByteData.sublistView(batchPcm);
    for (var i = 0; i < batch.length; i++) {
      bv.setInt16(
        i * 2,
        (batch[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }

    // Stream the interleaved stereo in awkward, non-block-aligned chunks.
    final streamer = StreamingEchoCanceller();
    final acc = BytesBuilder();
    for (var off = 0; off < stereo.length; off += 777) {
      final end = min(off + 777, stereo.length);
      acc.add(
        streamer.addInterleavedPcm16(Uint8List.sublistView(stereo, off, end)),
      );
    }
    final streamed = acc.toBytes();

    // Both drop the same trailing partial block → identical bytes.
    expect(streamed.length, batchPcm.length);
    expect(streamed, orderedEquals(batchPcm));
    // Same running-ERLE accounting as the batch pass (warmup-dominated → >0).
    expect(streamer.erleDb, greaterThan(0));
  });

  group('broadband (noise) reference', () {
    test('converges fast with high segmental ERLE + exact delay', () {
      final ref = _noise(n);
      final mic = _echo(ref, delay: 300);
      final result = cancelEcho(mic, ref); // auto delay
      expect(
        result.delay,
        closeTo(300, 1),
        reason: 'broadband ⇒ unambiguous delay',
      );

      final seg = segmentalErleDb(mic, result.cleaned);
      expect(seg, greaterThan(20), reason: 'segmental ERLE = $seg dB');

      final conv = convergenceSample(mic, result.cleaned);
      expect(conv, greaterThanOrEqualTo(0), reason: 'converged');
      expect(conv, lessThan(_sr ~/ 2), reason: 'within ~500 ms');
    });

    test('a smaller block size still cancels', () {
      final ref = _noise(n, seed: 3);
      final mic = _echo(ref);
      final out = cancelEcho(
        mic,
        ref,
        delay: 0,
        tuning: const AecTuning(blockSize: 512),
      ).cleaned;
      expect(segmentalErleDb(mic, out, segment: 512), greaterThan(20));
    });

    test('output is finite (no NaN/Inf) under a loud reference', () {
      final ref = _noise(n, amp: 0.9);
      final out = cancelEcho(_echo(ref), ref, delay: 0).cleaned;
      expect(out.every((s) => s.isFinite), isTrue);
    });
  });

  test('far-end silence passes the near-end through untouched', () {
    // Reference silent ⇒ nothing to cancel and the VAD pauses adaptation, so
    // the mic (a pure near-end voice) must come out bit-for-bit.
    final ref = Float64List(n); // all zeros
    final near = _noise(n, seed: 11, amp: 0.4);
    final out = cancelEcho(near, ref, delay: 0).cleaned;
    for (var i = 0; i < out.length; i++) {
      expect(out[i], near[i]);
    }
  });

  group('metrics', () {
    test('siSdrDb: identical is huge, and it is scale-invariant', () {
      final s = _noise(n, seed: 5);
      expect(siSdrDb(s, s), greaterThan(100));

      // A pure overall gain is not distortion → still huge.
      final scaled = Float64List.fromList([for (final x in s) 2.0 * x]);
      expect(siSdrDb(s, scaled), greaterThan(100));

      // Adding independent noise lowers it, monotonically.
      Float64List plus(double a) {
        final ns = _noise(n, seed: 99);
        return Float64List.fromList([
          for (var i = 0; i < n; i++) s[i] + a * ns[i],
        ]);
      }

      final little = siSdrDb(s, plus(0.05));
      final lots = siSdrDb(s, plus(0.5));
      expect(little, greaterThan(lots));
      expect(lots, greaterThan(0));
    });

    test('segmentalErleDb skips silent segments and floors per-segment', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final result = cancelEcho(mic, ref, delay: 0);
      // Global vs segmental: the segmental (mean of dB) rewards the converged
      // majority and isn't dragged to ~0 by the warmup like the global figure.
      expect(segmentalErleDb(mic, result.cleaned), greaterThan(result.erleDb));

      // An all-silent pair contributes no active segments → 0, not NaN.
      final z = Float64List(4096);
      expect(segmentalErleDb(z, z), 0);
    });

    test('convergenceSample returns -1 when ERLE never reaches the target', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      // "cleaned" == mic ⇒ 0 dB ERLE everywhere ⇒ never hits the target.
      expect(convergenceSample(mic, mic), -1);
    });

    test('AecMetrics.measure + report bundle the numbers', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final m = AecMetrics.measure(mic, cancelEcho(mic, ref, delay: 0).cleaned);
      expect(m.segErle, greaterThan(20));
      expect(m.convergedAtSample, greaterThanOrEqualTo(0));
      expect(m.report(), contains('converged'));
    });

    test('SI-SDR improves under converge-then-double-talk', () {
      // Filter converges on echo-only (first half), near-end joins (second).
      final ref = _noise(n);
      final echo = _echo(ref);
      final near = Float64List(n);
      for (var t = 0; t < n; t++) {
        near[t] = 0.35 * sin(2 * pi * 440 * t / _sr);
      }
      const half = n ~/ 2;
      final mic = Float64List(n);
      for (var t = 0; t < n; t++) {
        mic[t] = echo[t] + (t >= half ? near[t] : 0);
      }
      final out = cancelEcho(mic, ref, delay: 0).cleaned;
      final gain =
          siSdrDb(near, out, from: half) - siSdrDb(near, mic, from: half);
      // A positive gain from the linear core alone (the double-talk detector,
      // tested below, pushes it much higher).
      expect(gain, greaterThan(2), reason: 'SI-SDR gain = $gain dB');
    });
  });

  group('streaming edge cases', () {
    test('matches the batch cancel with a fixed refDelay', () {
      const d = 128;
      final ref = _noise(n);
      final mic = _echo(ref, delay: d);
      final stereo = _interleave(mic, ref);

      final qmic = Float64List(n), qref = Float64List(n);
      final sv = ByteData.sublistView(stereo);
      for (var i = 0; i < n; i++) {
        qmic[i] = sv.getInt16(i * 4, Endian.little) / 32768.0;
        qref[i] = sv.getInt16(i * 4 + 2, Endian.little) / 32768.0;
      }
      final batch = cancelEcho(qmic, qref, delay: d).cleaned;

      final streamer = StreamingEchoCanceller(refDelay: d);
      final streamed = streamer.addInterleavedPcm16(stereo);
      // Streaming holds d samples of ref latency, so it emits d fewer samples;
      // compare the overlap.
      final cmp = min(streamed.length ~/ 2, batch.length);
      final sd = ByteData.sublistView(streamed);
      for (var i = 0; i < cmp; i++) {
        final b = (batch[i].clamp(-1.0, 1.0) * 32767).round();
        expect(sd.getInt16(i * 2, Endian.little), b);
      }
      expect(cmp, greaterThan(0));
    });

    test('flush pads the final partial block; empty input is safe', () {
      final streamer = StreamingEchoCanceller();
      expect(streamer.addInterleavedPcm16(Uint8List(0)), isEmpty);
      // Feed 1.5 blocks of frames, then flush the remainder.
      final frames = (1024 * 1.5).round();
      final stereo = _interleave(_noise(frames), _noise(frames, seed: 2));
      final mid = streamer.addInterleavedPcm16(stereo); // one full block
      final tail = streamer.flush(); // the padded remainder
      expect(mid.length, 1024 * 2, reason: 'one 1024-sample block, 2 B each');
      expect(tail.length, 1024 * 2, reason: 'the padded second block');
    });

    test('empty streamer flush is a no-op', () {
      expect(StreamingEchoCanceller().flush(), isEmpty);
    });
  });

  group('double-talk detector', () {
    // Converge on echo-only (first half), near-end voice joins (second half).
    ({Float64List mic, Float64List near, Float64List ref}) scene() {
      final ref = _noise(n);
      final echo = _echo(ref);
      final near = Float64List(n);
      for (var t = 0; t < n; t++) {
        near[t] = 0.35 * sin(2 * pi * 440 * t / _sr);
      }
      const half = n ~/ 2;
      final mic = Float64List(n);
      for (var t = 0; t < n; t++) {
        mic[t] = echo[t] + (t >= half ? near[t] : 0);
      }
      return (mic: mic, near: near, ref: ref);
    }

    test('lifts double-talk SI-SDR well over the linear-only path', () {
      final s = scene();
      const half = n ~/ 2;
      final linear = cancelEcho(s.mic, s.ref, delay: 0);
      final dtd = cancelEcho(s.mic, s.ref, delay: 0, doubleTalkDetect: true);

      final siLinear = siSdrDb(s.near, linear.cleaned, from: half);
      final siDtd = siSdrDb(s.near, dtd.cleaned, from: half);
      expect(
        siDtd,
        greaterThan(siLinear + 3),
        reason: 'linear $siLinear dB → DTD $siDtd dB',
      );
      expect(dtd.frozenBlocks, greaterThan(0), reason: 'froze on double-talk');
    });

    test('stays out of the way on far-end single-talk (echo only)', () {
      final ref = _noise(n, seed: 4);
      final mic = _echo(ref);
      final dtd = cancelEcho(mic, ref, delay: 0, doubleTalkDetect: true);
      final plain = cancelEcho(mic, ref, delay: 0);

      // Rarely freezes with no near-end present…
      final totalBlocks = mic.length ~/ 1024;
      expect(
        dtd.frozenBlocks,
        lessThan(totalBlocks * 0.1),
        reason: '${dtd.frozenBlocks}/$totalBlocks blocks frozen',
      );
      // …and cancellation is not meaningfully degraded.
      expect(
        segmentalErleDb(mic, dtd.cleaned),
        greaterThan(segmentalErleDb(mic, plain.cleaned) - 3),
      );
    });

    test('adapt:false freezes the filter — no learning, no cancellation', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final aec = EchoCanceller();
      const blocks = n ~/ 1024;
      final out = Float64List(blocks * 1024);
      for (var bi = 0; bi < blocks; bi++) {
        final from = bi * 1024;
        final cleaned = aec.process(
          Float64List.sublistView(ref, from, from + 1024),
          Float64List.sublistView(mic, from, from + 1024),
          adapt: false, // never learn
        );
        out.setRange(from, from + 1024, cleaned);
      }
      // The filter stays at zero ⇒ the echo is essentially untouched.
      expect(segmentalErleDb(mic, out), lessThan(3));
    });

    test('streaming exposes frozenBlocks under double-talk', () {
      final s = scene();
      final streamer = StreamingEchoCanceller(doubleTalkDetect: true);
      streamer.addInterleavedPcm16(_interleave(s.mic, s.ref));
      streamer.flush();
      expect(streamer.frozenBlocks, greaterThan(0));
    });
  });

  group('residual echo suppression', () {
    test('deepens echo-only suppression well past the linear filter', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final linear = cancelEcho(mic, ref, delay: 0);
      final withRes = cancelEcho(mic, ref, delay: 0, residualSuppress: true);

      final segLinear = segmentalErleDb(mic, linear.cleaned);
      final segRes = segmentalErleDb(mic, withRes.cleaned);
      expect(
        segRes,
        greaterThan(segLinear + 5),
        reason: 'linear $segLinear dB → +RES $segRes dB',
      );
    });

    test(
      'does not chew the near-end under double-talk (DTD-gated leakage)',
      () {
        final ref = _noise(n);
        final echo = _echo(ref);
        final near = Float64List(n);
        for (var t = 0; t < n; t++) {
          near[t] = 0.35 * sin(2 * pi * 440 * t / _sr);
        }
        const half = n ~/ 2;
        final mic = Float64List(n);
        for (var t = 0; t < n; t++) {
          mic[t] = echo[t] + (t >= half ? near[t] : 0);
        }
        final dtd = cancelEcho(mic, ref, delay: 0, doubleTalkDetect: true);
        final full = cancelEcho(
          mic,
          ref,
          delay: 0,
          doubleTalkDetect: true,
          residualSuppress: true,
        );
        final siDtd = siSdrDb(near, dtd.cleaned, from: half);
        final siFull = siSdrDb(near, full.cleaned, from: half);
        // RES may cost a hair of fidelity, but must not meaningfully damage it.
        expect(
          siFull,
          greaterThan(siDtd - 1.5),
          reason: 'DTD $siDtd dB → +RES $siFull dB',
        );
      },
    );

    test('passes a pure near-end through when there is no echo estimate', () {
      // Far-end silent ⇒ echoEst is 0 ⇒ nothing to subtract ⇒ unity gain.
      final ref = Float64List(n); // silent
      final near = _noise(n, seed: 13, amp: 0.4);
      final out = cancelEcho(near, ref, delay: 0, residualSuppress: true);
      // The suppressor must not attenuate a signal it has no echo model for.
      final si = siSdrDb(near, out.cleaned);
      expect(si, greaterThan(30), reason: 'near-end SI-SDR $si dB');
    });

    test('output stays finite and bounded', () {
      final ref = _noise(n, amp: 0.9);
      final out = cancelEcho(
        _echo(ref),
        ref,
        delay: 0,
        residualSuppress: true,
      ).cleaned;
      expect(out.every((s) => s.isFinite), isTrue);
      expect(out.every((s) => s.abs() <= 2.0), isTrue);
    });

    test('streaming supports RES and stays byte-stable', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final streamer = StreamingEchoCanceller(residualSuppress: true);
      final outBytes = streamer.addInterleavedPcm16(_interleave(mic, ref));
      expect(outBytes, isNotEmpty);
      // Cancellation still happens end-to-end through the streaming path.
      expect(streamer.erleDb, greaterThan(0));
    });
  });

  // A tuning knob that silently doesn't reach its stage is worse than no knob:
  // a sweep over it reports the SAME number every time and reads as "this
  // parameter doesn't matter". Each test below drives one knob to a value whose
  // effect is unmistakable, so the wiring — not the DSP — is what's pinned.
  group('tuning reaches the stages', () {
    test('mu drives the linear filter (mu=0 ⇒ it never adapts)', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final frozen = cancelEcho(
        mic,
        ref,
        delay: 0,
        tuning: const AecTuning(mu: 0),
      );
      final adapting = cancelEcho(mic, ref, delay: 0);
      expect(
        frozen.erleDb,
        lessThan(1),
        reason: 'mu=0 must not cancel at all, got ${frozen.erleDb} dB',
      );
      // Segmental, not global: a global figure averages in the pre-convergence
      // warmup, which is exactly what a working mu is still climbing out of.
      expect(
        segmentalErleDb(mic, adapting.cleaned),
        greaterThan(20),
        reason: 'the default mu still converges',
      );
    });

    test('blockSize reaches both the canceller and the stream framing', () {
      final ref = _noise(n);
      final streamer = StreamingEchoCanceller(
        tuning: const AecTuning(blockSize: 512),
        residualSuppress: true,
      );
      expect(streamer.blockSize, 512);
      // Cleaned mono PCM16 comes back one block at a time: 512 samples = 1024 B.
      final out = streamer.addInterleavedPcm16(_interleave(_echo(ref), ref));
      expect(out.length % 1024, 0);
      expect(streamer.erleDb, greaterThan(10));
    });

    test('dtdThreshold reaches the detector', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      // Correlation is bounded by 1, so a threshold above it reads every block
      // as double-talk and freezes past the warmup; 0 is below it, so never.
      final always = cancelEcho(
        mic,
        ref,
        delay: 0,
        doubleTalkDetect: true,
        tuning: const AecTuning(dtdThreshold: 1.1),
      );
      final never = cancelEcho(
        mic,
        ref,
        delay: 0,
        doubleTalkDetect: true,
        tuning: const AecTuning(dtdThreshold: 0),
      );
      expect(always.frozenBlocks, greaterThan(0));
      expect(never.frozenBlocks, 0);
    });

    test('resGainFloor reaches the suppressor (floor=1 ⇒ no attenuation)', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final linear = cancelEcho(mic, ref, delay: 0).cleaned;
      final floored = cancelEcho(
        mic,
        ref,
        delay: 0,
        residualSuppress: true,
        tuning: const AecTuning(resGainFloor: 1),
      ).cleaned;
      // A gain floor of 1 pins every bin's gain at "untouched", so the RES is a
      // pass-through and the output is the linear canceller's, sample for sample.
      for (var i = 0; i < linear.length; i++) {
        expect(floored[i], closeTo(linear[i], 1e-9));
      }
    });

    test('streaming and batch agree on a non-default tuning', () {
      const tuning = AecTuning(mu: 0.3, blockSize: 512, leak: 1e-2);
      final ref = _noise(n);
      final mic = _echo(ref);
      final batch = cancelEcho(mic, ref, delay: 0, tuning: tuning).cleaned;
      final streamer = StreamingEchoCanceller(tuning: tuning);
      final bytes = streamer.addInterleavedPcm16(_interleave(mic, ref));
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < view.lengthInBytes ~/ 2; i++) {
        final streamed = view.getInt16(i * 2, Endian.little) / 32768.0;
        expect(streamed, closeTo(batch[i], 1e-4));
      }
    });

    test('describe() names only the knobs that differ from the defaults', () {
      expect(const AecTuning().describe(), 'defaults');
      expect(const AecTuning(mu: 0.3).describe(), 'mu=0.3');
      final both = const AecTuning(
        blockSize: 512,
        resGainFloor: 0.5,
      ).describe();
      expect(both, contains('block=512'));
      expect(both, contains('resGainFloor=0.5'));
      expect(both, isNot(contains('mu=')));
    });
  });
}
