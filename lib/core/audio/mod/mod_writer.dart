// lib/core/audio/mod/mod_writer.dart
//
// ProTracker `.mod` EXPORT (writer): [ModModule] → raw bytes. Pure Dart.
// The exact inverse of mod_reader.dart; implement against the byte-layout
// contract in mod_module.dart.
//
// Contract:
//   • Emit the 20-byte title (NUL-padded/truncated), 31 sample descriptors
//     (name, word-length = `(pcm.length + 1) ~/ 2`, finetune as a signed nibble,
//     volume, repeat point/length in words), song length, restart, the 128-byte
//     order table (order padded with 0), the "M.K." signature for 4 channels
//     (choose the right tag for other channel counts), the pattern data
//     (64 rows × channelCount × 4 bytes, cells encoded per the spec), then each
//     sample's signed-8-bit PCM in order.
//   • Numbers are BIG-ENDIAN. Pattern count written = `module.patterns.length`.
//   • Byte-stability: for a canonical module `writeMod` must reproduce the exact
//     bytes `parseMod` read (see the golden fixtures in test/mod_codec_test.dart).

import 'dart:typed_data';

import 'package:klang_universum/core/audio/mod/mod_module.dart';

/// Serializes [module] to ProTracker `.mod` bytes.
Uint8List writeMod(ModModule module) {
  final channels = module.channelCount;

  // Sample word-length (rounded up) drives how many PCM bytes each sample emits.
  int sampleWords(ModSample s) => (s.pcm.length + 1) ~/ 2;

  // Total size: 1084-byte header + pattern data + PCM data.
  var total = 1084;
  total += module.patterns.length * 64 * channels * 4;
  for (final s in module.samples) {
    total += sampleWords(s) * 2;
  }

  final out = Uint8List(total);
  var p = 0;

  // ── 0: title (20 bytes, ASCII, NUL-padded, truncated) ──────────────────────
  _writeAscii(out, 0, 20, module.title);
  p = 20;

  // ── 20: 31 sample descriptors, 30 bytes each ───────────────────────────────
  for (var i = 0; i < 31; i++) {
    final s = i < module.samples.length ? module.samples[i] : ModSample.empty();
    _writeAscii(out, p, 22, s.name);
    p += 22;
    _writeU16be(out, p, sampleWords(s));
    p += 2;
    out[p++] = s.finetune & 0x0F; // signed nibble
    out[p++] = s.volume.clamp(0, 64);
    _writeU16be(out, p, s.repeatPoint ~/ 2);
    p += 2;
    _writeU16be(out, p, s.repeatLength ~/ 2);
    p += 2;
  }
  // p == 20 + 31*30 == 950

  // ── 950: song length ───────────────────────────────────────────────────────
  out[p++] = module.order.length & 0xFF;
  // ── 951: restart position ──────────────────────────────────────────────────
  out[p++] = module.restart & 0xFF;

  // ── 952: order table (128 bytes, order then 0-padding) ─────────────────────
  for (var i = 0; i < 128; i++) {
    out[p++] = i < module.order.length ? module.order[i] & 0xFF : 0;
  }
  // p == 1080

  // ── 1080: signature ────────────────────────────────────────────────────────
  final sig = _signatureFor(channels);
  for (var i = 0; i < 4; i++) {
    out[p++] = sig.codeUnitAt(i);
  }
  // p == 1084

  // ── 1084: pattern data ─────────────────────────────────────────────────────
  for (final pat in module.patterns) {
    for (var row = 0; row < 64; row++) {
      final cells = row < pat.rows.length ? pat.rows[row] : const <ModCell>[];
      for (var ch = 0; ch < channels; ch++) {
        final c = ch < cells.length ? cells[ch] : ModCell.empty;
        final sample = c.sample;
        final period = c.period;
        final effect = c.effect;
        final param = c.effectParam;
        out[p++] = (sample & 0xF0) | ((period >> 8) & 0x0F);
        out[p++] = period & 0xFF;
        out[p++] = ((sample & 0x0F) << 4) | (effect & 0x0F);
        out[p++] = param & 0xFF;
      }
    }
  }

  // ── sample PCM: signed 8-bit, word-rounded, in order ───────────────────────
  for (final s in module.samples) {
    final bytes = sampleWords(s) * 2;
    for (var i = 0; i < s.pcm.length && i < bytes; i++) {
      out[p + i] = s.pcm[i] & 0xFF;
    }
    // Any trailing pad byte (odd pcm length) is already 0 from Uint8List init.
    p += bytes;
  }

  return out;
}

/// Writes [text] as ASCII into [out] at [offset], NUL-padding to [width] and
/// truncating to at most [width] bytes.
void _writeAscii(Uint8List out, int offset, int width, String text) {
  final units = text.codeUnits;
  final n = units.length < width ? units.length : width;
  for (var i = 0; i < n; i++) {
    out[offset + i] = units[i] & 0xFF;
  }
  // Remaining bytes stay 0 (NUL) from the zero-initialized buffer.
}

/// Big-endian unsigned 16-bit write.
void _writeU16be(Uint8List out, int offset, int value) {
  out[offset] = (value >> 8) & 0xFF;
  out[offset + 1] = value & 0xFF;
}

/// The 4-byte signature for a given channel count: "M.K." for 4, else "%dCHN".
String _signatureFor(int channels) {
  if (channels == 4) return 'M.K.';
  return '${channels}CHN';
}
