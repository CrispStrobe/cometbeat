// Fuzz-robustness lock for the WAV reader. readWavPcm16 loads real user
// recordings and sample-library files (via the CLI `--wav` and the My Samples
// import), so a malformed or crafted WAV must throw a FormatException — never a
// bare Error (RangeError from a lying chunk size, etc.) and never hang. The
// reader was hardened for the truncated-fmt-chunk case; this pins the whole
// contract against arbitrary bytes, including RIFF/WAVE-stamped inputs with
// garbage chunk sizes/depths. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

void _stamp(Uint8List b, int at, String sig) {
  for (var i = 0; i < sig.length && at + i < b.length; i++) {
    b[at + i] = sig.codeUnitAt(i);
  }
}

void _mustNotError(Uint8List input) {
  try {
    final wav = readWavPcm16(input);
    // If it parsed, the mono downmix must also be safe (guards channels == 0).
    wavToMonoFloat(wav);
  } on FormatException {
    // The declared contract for unreadable input.
  } on Exception {
    // Any other clean Exception is acceptable too.
  } catch (e) {
    fail('readWavPcm16 threw a non-Exception ${e.runtimeType}: $e');
  }
}

void main() {
  group('WAV reader fuzz (malformed input never throws an Error)', () {
    test('600 random + RIFF/WAVE-stamped inputs stay Exception-only', () {
      final rng = Random(7788);
      for (var iter = 0; iter < 600; iter++) {
        final len = rng.nextInt(400);
        final b = Uint8List(len);
        for (var i = 0; i < len; i++) {
          b[i] = rng.nextInt(256);
        }
        if (rng.nextBool() && len >= 12) {
          _stamp(b, 0, 'RIFF');
          _stamp(b, 8, 'WAVE');
          if (len >= 16) _stamp(b, 12, 'fmt '); // often present
        }
        _mustNotError(b);
      }
    });

    test('a WAVE with a fmt chunk claiming a huge data size does not Error',
        () {
      // A well-formed header whose data chunk lies about its length must clamp,
      // not read past the buffer.
      final b = BytesBuilder();
      b.add('RIFF'.codeUnits);
      b.add(_u32(0xFFFFFFFF)); // bogus RIFF size
      b.add('WAVE'.codeUnits);
      b.add('fmt '.codeUnits);
      b.add(_u32(16));
      b.add(_u16(1)); // PCM
      b.add(_u16(1)); // mono
      b.add(_u32(44100));
      b.add(_u32(88200));
      b.add(_u16(2));
      b.add(_u16(16)); // 16-bit
      b.add('data'.codeUnits);
      b.add(_u32(0xFFFFFFFF)); // lies: claims ~4 GB of data
      b.add([0, 0, 0, 0]); // ...but only 4 bytes follow
      _mustNotError(b.toBytes());
    });

    test('empty and sub-header inputs throw cleanly', () {
      for (final n in const [0, 1, 11, 12, 43, 44]) {
        _mustNotError(Uint8List(n));
      }
    });
  });
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _u16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
