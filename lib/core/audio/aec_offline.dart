// lib/core/audio/aec_offline.dart
//
// Offline / streaming glue around the pure-Dart [EchoCanceller] — the pieces a
// CLI needs to run acoustic echo cancellation over files or pipes, headlessly.
// This is the SAME linear canceller the native Tier-3b engine is a cleanroom
// port of (ERLE cross-checked, see docs/AEC_TIER3B.md), so exercising it here
// validates the algorithm the app's jam-mode AEC runs, with no device or FFI.
//
// Two entry points:
//   * [cancelEcho] — whole-signal cancellation with automatic delay estimation
//     (offline we have both signals, so we can cross-correlate to align them —
//     the alignment a real-time AEC must otherwise track continuously).
//   * [StreamingEchoCanceller] — block-by-block over interleaved stereo PCM16
//     (channel 0 = mic/near-end+echo, channel 1 = reference), for pipes.
//
// Pure Dart, no Flutter — unit-tested in test/aec_offline_test.dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:klang_universum/core/audio/chroma_analysis.dart' show fft;
import 'package:klang_universum/core/audio/echo_canceller.dart';

/// Echo Return Loss Enhancement in dB over the first [length] samples (default:
/// all) — how much louder the mic was than the residual. Higher = more echo
/// removed. Meaningless below ~0; a good linear cancel is 20 dB+.
double erleDb(Float64List mic, Float64List cleaned, {int? length}) {
  final n = length ?? min(mic.length, cleaned.length);
  var micE = 0.0, outE = 0.0;
  for (var i = 0; i < n; i++) {
    micE += mic[i] * mic[i];
    outE += cleaned[i] * cleaned[i];
  }
  return 10 * (log((micE + 1e-12) / (outE + 1e-12)) / ln10);
}

/// FFT cross-correlation: the lag (in samples) at which [mic] best matches
/// [ref] — i.e. how far the captured echo trails the played reference. Offline
/// only (needs the whole signal); a streaming AEC must track this continuously.
int estimateEchoDelay(Float64List mic, Float64List ref) {
  final seg = min(mic.length, min(ref.length, 1 << 17));
  var n = 1;
  while (n < seg) {
    n <<= 1;
  }
  final mre = Float64List(n), mim = Float64List(n);
  final rre = Float64List(n), rim = Float64List(n);
  for (var i = 0; i < seg; i++) {
    mre[i] = mic[i];
    rre[i] = ref[i];
  }
  fft(mre, mim);
  fft(rre, rim);
  // MIC * conj(REF)
  final xre = Float64List(n), xim = Float64List(n);
  for (var k = 0; k < n; k++) {
    xre[k] = mre[k] * rre[k] + mim[k] * rim[k];
    xim[k] = -(mim[k] * rre[k] - mre[k] * rim[k]); // conjugate for inverse
  }
  fft(xre, xim); // inverse (scale irrelevant for argmax)
  var best = 0;
  var bestVal = -double.infinity;
  for (var lag = 0; lag < n ~/ 2; lag++) {
    if (xre[lag] > bestVal) {
      bestVal = xre[lag];
      best = lag;
    }
  }
  return best;
}

/// The result of an offline [cancelEcho] pass.
class AecResult {
  const AecResult({
    required this.cleaned,
    required this.erleDb,
    required this.delay,
  });

  /// The cleaned near-end estimate (length = whole blocks × blockSize).
  final Float64List cleaned;

  /// Echo return loss enhancement over [cleaned], in dB.
  final double erleDb;

  /// The reference→mic delay used to align (given or estimated), in samples.
  final int delay;
}

/// Cancels the echo of [ref] from [mic] over the whole signal. Aligns [ref] to
/// [mic] by [delay] samples (estimated with [estimateEchoDelay] when null),
/// then runs the [EchoCanceller] block by block. The trailing partial block is
/// dropped (the cleaned length is `mic.length ~/ blockSize * blockSize`).
AecResult cancelEcho(
  Float64List mic,
  Float64List ref, {
  int? delay,
  int blockSize = 1024,
}) {
  final d = delay ?? estimateEchoDelay(mic, ref);
  final aligned = Float64List(mic.length);
  for (var i = 0; i < mic.length; i++) {
    final j = i - d;
    aligned[i] = (j >= 0 && j < ref.length) ? ref[j] : 0;
  }
  final aec = EchoCanceller(blockSize: blockSize);
  final blocks = mic.length ~/ blockSize;
  final out = Float64List(blocks * blockSize);
  for (var bi = 0; bi < blocks; bi++) {
    final from = bi * blockSize;
    final cleaned = aec.process(
      Float64List.sublistView(aligned, from, from + blockSize),
      Float64List.sublistView(mic, from, from + blockSize),
    );
    out.setRange(from, from + blockSize, cleaned);
  }
  return AecResult(
    cleaned: out,
    erleDb: erleDb(mic, out, length: blocks * blockSize),
    delay: d,
  );
}

/// Streaming echo canceller for a pipe. Feed interleaved stereo PCM16 (channel
/// 0 = mic/near-end+echo, channel 1 = reference) as it arrives; get cleaned
/// mono PCM16 back one block at a time. Identical output to [cancelEcho] for
/// the same aligned input — the state lives in one [EchoCanceller].
///
/// Streaming can't cross-correlate the whole signal, so alignment is a fixed
/// [refDelay] (samples the reference trails the mic); 0 suits a pre-aligned
/// full-duplex / loopback capture.
class StreamingEchoCanceller {
  StreamingEchoCanceller({this.blockSize = 1024, this.refDelay = 0})
      : assert(refDelay >= 0),
        _aec = EchoCanceller(blockSize: blockSize),
        // Seed the reference with `refDelay` zeros so ref[i] lines up with
        // mic[i-refDelay] — the reference arriving delayed relative to the mic.
        _ref = List<double>.filled(refDelay, 0, growable: true);

  final int blockSize;
  final int refDelay;
  final EchoCanceller _aec;
  final _mic = <double>[];
  final List<double> _ref;

  /// Leftover bytes of a partial stereo frame carried to the next chunk (input
  /// need not arrive on frame boundaries — a pipe can split anywhere).
  final _byteRem = BytesBuilder(copy: false);

  var _micEnergy = 0.0;
  var _residualEnergy = 0.0;

  /// Running echo return loss enhancement (dB) over everything processed so far.
  double get erleDb =>
      10 * (log((_micEnergy + 1e-12) / (_residualEnergy + 1e-12)) / ln10);

  /// Feed interleaved stereo PCM16 (LE) bytes; returns cleaned mono PCM16 (LE)
  /// for every block that completed. Odd trailing bytes/samples are buffered.
  Uint8List addInterleavedPcm16(Uint8List stereo) {
    _byteRem.add(stereo);
    final buf = _byteRem.toBytes();
    final frames = buf.length ~/ 4; // 2ch × 2 bytes
    final view = ByteData.sublistView(buf);
    for (var f = 0; f < frames; f++) {
      _mic.add(view.getInt16(f * 4, Endian.little) / 32768.0);
      _ref.add(view.getInt16(f * 4 + 2, Endian.little) / 32768.0);
    }
    // Carry the partial trailing frame (0..3 bytes) to the next call.
    _byteRem.clear();
    if (buf.length % 4 != 0) {
      _byteRem.add(Uint8List.sublistView(buf, frames * 4));
    }
    return _drain();
  }

  /// Process the trailing partial block (zero-padded) so no audio is lost.
  Uint8List flush() {
    if (_mic.isEmpty) return Uint8List(0);
    while (_mic.length < blockSize) {
      _mic.add(0);
    }
    while (_ref.length < blockSize) {
      _ref.add(0);
    }
    return _drain();
  }

  Uint8List _drain() {
    final builder = BytesBuilder(copy: false);
    while (_mic.length >= blockSize && _ref.length >= blockSize) {
      final micBlock = Float64List(blockSize);
      final refBlock = Float64List(blockSize);
      for (var i = 0; i < blockSize; i++) {
        micBlock[i] = _mic[i];
        refBlock[i] = _ref[i];
      }
      final cleaned = _aec.process(refBlock, micBlock);
      final bytes = Uint8List(blockSize * 2);
      final out = ByteData.sublistView(bytes);
      for (var i = 0; i < blockSize; i++) {
        final c = cleaned[i];
        out.setInt16(
          i * 2,
          (c.clamp(-1.0, 1.0) * 32767).round(),
          Endian.little,
        );
        _micEnergy += micBlock[i] * micBlock[i];
        _residualEnergy += c * c;
      }
      builder.add(bytes);
      _mic.removeRange(0, blockSize);
      _ref.removeRange(0, blockSize);
    }
    return builder.toBytes();
  }
}
