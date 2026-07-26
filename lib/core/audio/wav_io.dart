// lib/core/audio/wav_io.dart
//
// A minimal WAV *reader* — the counterpart to synth.dart's `wavBytes` writer.
// Enough to load real recordings (mono/stereo) for the CLI and tests to stream
// through the detectors. Not a general codec — no compressed encodings — but it
// accepts the uncompressed depths real sample libraries ship (8/16/24-bit int
// and 32-bit float) and normalizes them all to PCM16, so callers only ever see
// an Int16List. (24-bit in particular is common: ~a third of VCSL, and plenty
// of user-recorded WAVs, which used to be rejected outright.)

import 'dart:typed_data';

class WavData {
  const WavData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  /// Interleaved PCM16 samples (all channels).
  final Int16List samples;
  final int sampleRate;
  final int channels;
}

/// Parse a PCM16 WAV. Throws [FormatException] on anything it can't read.
WavData readWavPcm16(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));

  if (bytes.length < 44 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int sampleRate = 0;
  int channels = 0;
  int bitsPerSample = 0;
  int audioFormat = 0;
  int dataOffset = -1;
  int dataLength = 0;

  // Walk the chunks after the 12-byte RIFF/WAVE header.
  var p = 12;
  while (p + 8 <= bytes.length) {
    final id = tag(p);
    final size = data.getUint32(p + 4, Endian.little);
    final body = p + 8;
    // The loop only guarantees the 8-byte chunk header fits (body <= length);
    // the fmt chunk reads 16 more bytes (up to body + 16). A `fmt ` id within
    // 16 bytes of EOF (a truncated / crafted WAV) would otherwise read past the
    // buffer and throw a RangeError — but this reader's contract is to throw
    // FormatException on anything it can't read. Skip an under-length fmt chunk;
    // audioFormat then stays 0 and the PCM16 check below rejects it cleanly.
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      audioFormat = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = size;
    }
    p = body + size + (size & 1); // chunks are word-aligned
  }

  // Accept the uncompressed encodings real-world sample libraries actually
  // ship — 8/16/24-bit integer PCM and 32-bit IEEE float — and normalize them
  // all to PCM16 so every caller keeps the same `Int16List` contract. (Plain
  // PCM is format 1, IEEE float is 3, and WAVE_FORMAT_EXTENSIBLE is 0xFFFE,
  // which 24-bit writers commonly use; its subformat is PCM here.)
  const pcm = 1, ieeeFloat = 3, extensible = 0xFFFE;
  final isFloat = audioFormat == ieeeFloat;
  final knownFormat =
      audioFormat == pcm || isFloat || audioFormat == extensible;
  final knownDepth = isFloat
      ? bitsPerSample == 32
      : const [8, 16, 24, 32].contains(bitsPerSample);
  if (!knownFormat || !knownDepth) {
    throw FormatException(
      'Unsupported WAV encoding '
      '(format=$audioFormat, bits=$bitsPerSample)',
    );
  }
  if (dataOffset < 0) throw const FormatException('No data chunk');

  final bytesPerSample = bitsPerSample ~/ 8;
  final available = bytes.length - dataOffset;
  final n = (dataLength.clamp(0, available)) ~/ bytesPerSample;
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    final at = dataOffset + i * bytesPerSample;
    switch (bitsPerSample) {
      case 8:
        // 8-bit WAV is UNSIGNED (0..255), centred on 128 — unlike every
        // other depth, which is signed.
        out[i] = (data.getUint8(at) - 128) * 256;
      case 16:
        out[i] = data.getInt16(at, Endian.little);
      case 24:
        // Little-endian 24-bit two's complement → take the top 16 bits.
        final v = data.getUint8(at) |
            (data.getUint8(at + 1) << 8) |
            (data.getUint8(at + 2) << 16);
        final signed = (v & 0x800000) != 0 ? v - 0x1000000 : v;
        out[i] = signed >> 8;
      case 32:
        if (isFloat) {
          final f = data.getFloat32(at, Endian.little);
          out[i] = (f.clamp(-1.0, 1.0) * 32767).round();
        } else {
          out[i] = data.getInt32(at, Endian.little) >> 16;
        }
    }
  }
  return WavData(samples: out, sampleRate: sampleRate, channels: channels);
}

/// De-interleave into planar channels in [-1, 1], PRESERVING stereo — the
/// channel-keeping sibling of [wavToMonoFloat], which folds a stereo file down
/// before the caller ever sees the sides.
///
/// [right] is null for a mono file, which is the same shape the DAW's edit and
/// FX functions take (`left, right?`), so a file read this way flows straight
/// into them. A file with more than two channels keeps its first two: an editor
/// that silently discarded them would be worse, but pretending to handle 5.1
/// would be worse still — the timeline is stereo.
({Float64List left, Float64List? right}) wavToChannels(WavData wav) {
  final ch = wav.channels < 1 ? 1 : wav.channels;
  final frames = wav.samples.length ~/ ch;
  final left = Float64List(frames);
  final right = ch >= 2 ? Float64List(frames) : null;
  for (var f = 0; f < frames; f++) {
    left[f] = wav.samples[f * ch] / 32768.0;
    if (right != null) right[f] = wav.samples[f * ch + 1] / 32768.0;
  }
  return (left: left, right: right);
}

/// Downmix interleaved samples to a mono float list in [-1, 1].
Float64List wavToMonoFloat(WavData wav) {
  final ch = wav.channels < 1 ? 1 : wav.channels;
  final frames = wav.samples.length ~/ ch;
  final out = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < ch; c++) {
      sum += wav.samples[f * ch + c];
    }
    out[f] = (sum / ch) / 32768.0;
  }
  return out;
}
