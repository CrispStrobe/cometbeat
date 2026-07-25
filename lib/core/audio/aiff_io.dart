// lib/core/audio/aiff_io.dart
//
// A minimal AIFF / AIFF-C reader — the Apple counterpart to wav_io.dart's RIFF
// reader, and the format a Mac user is most likely to hand the app that we
// couldn't previously open. Same shape as WAV underneath (uncompressed PCM in
// chunks) with three differences that matter:
//
//   • everything is BIG-endian, not little;
//   • the sample rate is an 80-bit IEEE-754 extended float, not an int;
//   • AIFF-C adds a compression id — we accept only the uncompressed ones
//     ('NONE', and 'sowt', which is plain PCM that happens to be little-endian).
//
// Like the WAV reader, every supported depth is normalised to PCM16 so callers
// only ever see an Int16List. Pure Dart, Flutter-free.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/wav_io.dart' show WavData;

/// True if [b] looks like an AIFF or AIFF-C file (`FORM....AIFF` / `AIFC`).
bool isAiff(Uint8List b) {
  if (b.length < 12) return false;
  final form = b[0] == 0x46 && b[1] == 0x4F && b[2] == 0x52 && b[3] == 0x4D;
  if (!form) return false; // "FORM"
  final tag = String.fromCharCodes(b.sublist(8, 12));
  return tag == 'AIFF' || tag == 'AIFC';
}

/// Parse an uncompressed AIFF/AIFF-C. Throws [FormatException] on anything it
/// can't read, so callers can report a clear "couldn't read that file".
WavData readAiff(Uint8List bytes) {
  if (!isAiff(bytes)) throw const FormatException('Not a FORM/AIFF file');
  final data = ByteData.sublistView(bytes);

  var channels = 0;
  var frames = 0;
  var bitsPerSample = 0;
  var sampleRate = 0;
  var compression = 'NONE';
  var soundOffset = -1;
  var soundLength = 0;

  // Walk the chunk list. Chunk bodies are padded to an even length, and the
  // pad byte is NOT counted in the size field.
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = data.getUint32(pos + 4); // big-endian
    final body = pos + 8;
    if (size < 0 || body > bytes.length) break;

    if (id == 'COMM' && body + 18 <= bytes.length) {
      channels = data.getInt16(body);
      frames = data.getUint32(body + 2);
      bitsPerSample = data.getInt16(body + 6);
      sampleRate = _extendedToInt(data, body + 8);
      if (size >= 22 && body + 22 <= bytes.length) {
        compression = String.fromCharCodes(bytes.sublist(body + 18, body + 22));
      }
    } else if (id == 'SSND' && body + 8 <= bytes.length) {
      // offset/blockSize are for block-aligned playback; the data starts after
      // them, plus whatever `offset` says to skip.
      final offset = data.getUint32(body);
      soundOffset = body + 8 + offset;
      soundLength = size - 8 - offset;
    }

    pos = body + size + (size.isOdd ? 1 : 0);
  }

  if (channels < 1 || bitsPerSample < 1 || soundOffset < 0) {
    throw const FormatException('AIFF is missing COMM or SSND');
  }
  if (compression != 'NONE' && compression != 'sowt') {
    throw FormatException('Compressed AIFF-C ($compression) is not supported');
  }
  if (sampleRate <= 0) sampleRate = 44100;

  // 'sowt' is the one common "AIFF-C" that isn't compressed at all — it's
  // plain PCM stored little-endian, exactly like WAV.
  final littleEndian = compression == 'sowt';
  final bytesPerSample = bitsPerSample ~/ 8;
  if (bytesPerSample < 1 || bytesPerSample > 4) {
    throw FormatException('Unsupported AIFF depth: $bitsPerSample-bit');
  }

  final available = (bytes.length - soundOffset).clamp(0, soundLength);
  final total = available ~/ bytesPerSample;
  final wanted = frames * channels;
  final count = wanted > 0 && wanted < total ? wanted : total;
  final out = Int16List(count < 0 ? 0 : count);

  for (var i = 0; i < out.length; i++) {
    final at = soundOffset + i * bytesPerSample;
    if (at + bytesPerSample > bytes.length) break;
    out[i] = switch (bitsPerSample) {
      // 8-bit AIFF is SIGNED (unlike 8-bit WAV, which is unsigned).
      8 => data.getInt8(at) * 256,
      16 => littleEndian ? data.getInt16(at, Endian.little) : data.getInt16(at),
      24 => _int24(data, at, littleEndian) >> 8,
      32 =>
        (littleEndian ? data.getInt32(at, Endian.little) : data.getInt32(at)) >>
            16,
      _ => 0,
    };
  }

  return WavData(samples: out, sampleRate: sampleRate, channels: channels);
}

/// One 24-bit sample as a signed value in −2²³ … 2²³−1.
int _int24(ByteData data, int at, bool littleEndian) {
  final b0 = data.getUint8(at);
  final b1 = data.getUint8(at + 1);
  final b2 = data.getUint8(at + 2);
  final raw =
      littleEndian ? (b2 << 16) | (b1 << 8) | b0 : (b0 << 16) | (b1 << 8) | b2;
  return (raw & 0x800000) != 0 ? raw - 0x1000000 : raw; // sign-extend
}

/// The 80-bit IEEE-754 extended float AIFF stores its sample rate in, rounded
/// to an int (rates are whole numbers in practice).
int _extendedToInt(ByteData data, int at) {
  final exponent = data.getUint16(at); // sign + 15-bit exponent
  final hi = data.getUint32(at + 2);
  final lo = data.getUint32(at + 6);
  final sign = (exponent & 0x8000) != 0 ? -1 : 1;
  final e = exponent & 0x7FFF;
  if (e == 0 && hi == 0 && lo == 0) return 0;
  if (e == 0x7FFF) return 0; // inf/NaN — treat as unknown
  // value = mantissa / 2^63 * 2^(e - 16383); mantissa's top bit is explicit.
  final mantissa = hi * 4294967296.0 + lo;
  final value = sign * mantissa * _pow2(e - 16383 - 63);
  return value.isFinite && value > 0 && value < 1e9 ? value.round() : 0;
}

double _pow2(int n) {
  var v = 1.0;
  if (n >= 0) {
    for (var i = 0; i < n; i++) {
      v *= 2;
    }
  } else {
    for (var i = 0; i < -n; i++) {
      v /= 2;
    }
  }
  return v;
}
