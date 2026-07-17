// aec_offline — the offline/streaming glue over EchoCanceller that the AEC CLI
// uses. Synthetic scenarios (a known room IR): high ERLE on echo-only, near-end
// preserved under double-talk, delay recovery, and streaming≡batch equivalence.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/aec_offline.dart';

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
        streamer.addInterleavedPcm16(
          Uint8List.sublistView(stereo, off, end),
        ),
      );
    }
    final streamed = acc.toBytes();

    // Both drop the same trailing partial block → identical bytes.
    expect(streamed.length, batchPcm.length);
    expect(streamed, orderedEquals(batchPcm));
    // Same running-ERLE accounting as the batch pass (warmup-dominated → >0).
    expect(streamer.erleDb, greaterThan(0));
  });
}
