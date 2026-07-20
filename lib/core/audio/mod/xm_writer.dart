// lib/core/audio/mod/xm_writer.dart
//
// FastTracker 2 `.xm` EXPORT (writer): [XmModule] → raw bytes. Pure Dart. The
// byte-level inverse of xm_reader.dart — a module written here must re-read via
// parseXm to an equivalent module. Used by the cross-format converters
// (docToXm/convertToXm in module_convert.dart) so any module → `.xm`.
//
// ─── Output layout (little-endian; must satisfy parseXm) ─────────────────────
// HEADER (fixed 0x150 bytes):
//   0x00 17  "Extended Module: "
//   0x11 20  module name (NUL-padded/truncated)
//   0x25 1   0x1A
//   0x26 20  tracker name (e.g. "CometBeat", NUL-padded)
//   0x3A 2   version = 0x0104
//   0x3C 4   headerSize = 276 (0x114) — pattern data starts at 0x3C+276 = 0x150
//   0x40 2   songLength = order.length (clamp ≤ 256)   · 0x42 2 restart = 0
//   0x44 2   numChannels = module.channelCount          · 0x46 2 numPatterns
//   0x48 2   numInstruments = module.instruments.length · 0x4A 2 flags = 1 (linear)
//   0x4C 2   tempo = module.defaultTempo · 0x4E 2 bpm = module.defaultBpm
//   0x50 256 order table: first songLength = order (each clamped to a byte), rest 0
//
// PATTERNS (numPatterns, back to back from 0x150):
//   4  headerLen = 9 · 1 packType = 0 · 2 numRows · 2 packedSize · packed bytes
//   Packing (row-major, numChannels cells/row): for each cell compute a mask —
//     bit0 note(>0), bit1 instrument(>0), bit2 volume(>0), bit3 effect(>0),
//     bit4 param(>0). Write ONE byte (0x80 | mask), then each PRESENT field in
//     that order. A fully empty cell writes a single 0x80. packedSize = the byte
//     length produced for that pattern.
//   note field: 1..96 pitch, 97 note-off (write the XmCell.note as-is, clamped).
//
// INSTRUMENTS (numInstruments, back to back after the patterns):
//   numSamples = instrument.samples.length.
//   If numSamples == 0: u32 headerSize = 29 · 22 name · 1 type=0 · 2 numSamples=0.
//   Else: u32 headerSize = 263 · 22 name · 1 type=0 · 2 numSamples ·
//     u32 sampleHeaderSize = 40 · zero-fill up to the 263-byte header · then
//     numSamples × 40-byte sample headers · then the sample DATA blocks in order.
//   Sample header (40): u32 lengthInBytes · u32 loopStart · u32 loopLength ·
//     u8 volume(0..64) · s8 finetune · u8 type (loop type bits0-1: 0 none /
//     1 forward / 2 ping-pong, from XmSample.pingPong | (sixteenBit?0x10:0)) ·
//     u8 panning=128 · s8 relativeNote · u8 reserved=0 ·
//     22 name.
//   Sample data: DELTA-encoded. Quantize the normalized pcm first:
//     8-bit  → (v*128).round().clamp(-128,127)   (byte = (cur-prev)&0xFF)
//     16-bit → (v*32768).round().clamp(-32768,32767) (u16 LE = (cur-prev)&0xFFFF)
//     with a running `prev` reset to 0 per sample. lengthInBytes = sampleCount ×
//     (sixteenBit ? 2 : 1). Honor XmSample.sixteenBit for bit depth.
// ─────────────────────────────────────────────────────────────────────────────
//
// Verify against test/xm_writer_test.dart: parseXm(writeXm(parseXm(golden.xm)))
// preserves the module (name, channels, patterns, notes, sample PCM), plus a
// hand-built module round-trip.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/xm_module.dart';

const String _kSignature = 'Extended Module: ';
const String _kTrackerName = 'CometBeat';

/// Writes an ASCII string into [dst] at [offset], filling exactly [length]
/// bytes: characters (truncated to `length`) then NUL padding.
void _writeName(Uint8List dst, int offset, int length, String s) {
  for (var i = 0; i < length; i++) {
    dst[offset + i] = i < s.length ? (s.codeUnitAt(i) & 0xFF) : 0;
  }
}

/// Writes one XM envelope into an instrument header: up to 12 `(tick, value)`
/// points + the count, sustain/loop indices, and type byte (bit0 on · bit1
/// sustain · bit2 loop). A disabled/empty envelope leaves the block zeroed (off).
void _writeXmEnvelope(
  ByteData ihb,
  XmEnvelope env, {
  required int pointsAt,
  required int numAt,
  required int sustainAt,
  required int loopStartAt,
  required int loopEndAt,
  required int typeAt,
}) {
  if (!env.enabled || env.points.isEmpty) return;
  final n = env.points.length.clamp(0, 12);
  for (var i = 0; i < n; i++) {
    ihb.setUint16(
      pointsAt + i * 4,
      env.points[i].$1.clamp(0, 0xFFFF),
      Endian.little,
    );
    ihb.setUint16(
      pointsAt + i * 4 + 2,
      env.points[i].$2.clamp(0, 0xFFFF),
      Endian.little,
    );
  }
  ihb.setUint8(numAt, n);
  var type = 0x01; // enabled
  if (env.sustain != null) {
    type |= 0x02;
    ihb.setUint8(sustainAt, env.sustain!.clamp(0, 255));
  }
  if (env.loopStart != null && env.loopEnd != null) {
    type |= 0x04;
    ihb.setUint8(loopStartAt, env.loopStart!.clamp(0, 255));
    ihb.setUint8(loopEndAt, env.loopEnd!.clamp(0, 255));
  }
  ihb.setUint8(typeAt, type);
}

/// Serializes an [XmModule] to FastTracker 2 `.xm` bytes (re-readable by parseXm).
Uint8List writeXm(XmModule module) {
  final out = BytesBuilder();

  // ─── HEADER (fixed 0x150 bytes) ───────────────────────────────────────────
  final header = Uint8List(0x150);
  final hb = ByteData.sublistView(header);

  // Signature.
  for (var i = 0; i < _kSignature.length; i++) {
    header[i] = _kSignature.codeUnitAt(i);
  }
  // Module name + separator + tracker name.
  _writeName(header, 0x11, 20, module.name);
  header[0x25] = 0x1A;
  _writeName(header, 0x26, 20, _kTrackerName);

  hb.setUint16(0x3A, 0x0104, Endian.little); // version
  hb.setUint32(0x3C, 276, Endian.little); // header size

  final songLength = module.order.length > 256 ? 256 : module.order.length;
  hb.setUint16(0x40, songLength, Endian.little);
  hb.setUint16(0x42, 0, Endian.little); // restart
  hb.setUint16(0x44, module.channelCount, Endian.little);
  hb.setUint16(0x46, module.patterns.length, Endian.little);
  hb.setUint16(0x48, module.instruments.length, Endian.little);
  hb.setUint16(0x4A, 1, Endian.little); // flags (linear)
  hb.setUint16(0x4C, module.defaultTempo, Endian.little);
  hb.setUint16(0x4E, module.defaultBpm, Endian.little);

  // Order table (256 bytes; first songLength = order entries, rest 0).
  for (var i = 0; i < songLength; i++) {
    header[0x50 + i] = module.order[i] & 0xFF;
  }

  out.add(header);

  // ─── PATTERNS ─────────────────────────────────────────────────────────────
  final numChannels = module.channelCount;
  for (final pattern in module.patterns) {
    final packed = BytesBuilder();
    final numRows = pattern.numRows;
    for (var r = 0; r < numRows; r++) {
      final row = r < pattern.rows.length ? pattern.rows[r] : const <XmCell>[];
      for (var c = 0; c < numChannels; c++) {
        final cell = c < row.length ? row[c] : XmCell.empty;
        var mask = 0;
        if (cell.note > 0) mask |= 0x01;
        if (cell.instrument > 0) mask |= 0x02;
        if (cell.volume > 0) mask |= 0x04;
        if (cell.effect > 0) mask |= 0x08;
        if (cell.effectParam > 0) mask |= 0x10;
        packed.addByte(0x80 | mask);
        if ((mask & 0x01) != 0) packed.addByte(cell.note & 0xFF);
        if ((mask & 0x02) != 0) packed.addByte(cell.instrument & 0xFF);
        if ((mask & 0x04) != 0) packed.addByte(cell.volume & 0xFF);
        if ((mask & 0x08) != 0) packed.addByte(cell.effect & 0xFF);
        if ((mask & 0x10) != 0) packed.addByte(cell.effectParam & 0xFF);
      }
    }
    final packedBytes = packed.toBytes();

    final ph = ByteData(9);
    ph.setUint32(0, 9, Endian.little); // header length
    ph.setUint8(4, 0); // packing type
    ph.setUint16(5, numRows, Endian.little);
    ph.setUint16(7, packedBytes.length, Endian.little);
    out.add(ph.buffer.asUint8List());
    out.add(packedBytes);
  }

  // ─── INSTRUMENTS ──────────────────────────────────────────────────────────
  for (final instrument in module.instruments) {
    final numSamples = instrument.samples.length;

    if (numSamples == 0) {
      final ih = Uint8List(29);
      final ihb = ByteData.sublistView(ih);
      ihb.setUint32(0, 29, Endian.little);
      _writeName(ih, 4, 22, instrument.name);
      ih[26] = 0; // type
      ihb.setUint16(27, 0, Endian.little); // numSamples
      out.add(ih);
      continue;
    }

    // Instrument header padded to 263 bytes.
    final ih = Uint8List(263);
    final ihb = ByteData.sublistView(ih);
    ihb.setUint32(0, 263, Endian.little);
    _writeName(ih, 4, 22, instrument.name);
    ih[26] = 0; // type
    ihb.setUint16(27, numSamples, Endian.little);
    ihb.setUint32(29, 40, Endian.little); // sampleHeaderSize
    // Keymap (33..128) stays zero (every note → sample 0). Emit the volume/pan
    // envelope block from the instrument's envelopes (left zeroed = disabled).
    _writeXmEnvelope(
      ihb,
      instrument.volumeEnvelope,
      pointsAt: 129,
      numAt: 225,
      sustainAt: 227,
      loopStartAt: 228,
      loopEndAt: 229,
      typeAt: 233,
    );
    _writeXmEnvelope(
      ihb,
      instrument.panEnvelope,
      pointsAt: 177,
      numAt: 226,
      sustainAt: 230,
      loopStartAt: 231,
      loopEndAt: 232,
      typeAt: 234,
    );
    out.add(ih);

    // Sample headers, then sample data blocks (same order).
    final dataBlocks = <Uint8List>[];
    for (final sample in instrument.samples) {
      final sixteen = sample.sixteenBit;
      final count = sample.pcm.length;
      final data = BytesBuilder();
      var prev = 0;
      if (sixteen) {
        for (var i = 0; i < count; i++) {
          final cur = (sample.pcm[i] * 32768).round().clamp(-32768, 32767);
          final delta = (cur - prev) & 0xFFFF;
          data.addByte(delta & 0xFF);
          data.addByte((delta >> 8) & 0xFF);
          prev = cur;
        }
      } else {
        for (var i = 0; i < count; i++) {
          final cur = (sample.pcm[i] * 128).round().clamp(-128, 127);
          data.addByte((cur - prev) & 0xFF);
          prev = cur;
        }
      }
      final dataBytes = data.toBytes();
      dataBlocks.add(dataBytes);

      final sh = Uint8List(40);
      final shb = ByteData.sublistView(sh);
      shb.setUint32(0, dataBytes.length, Endian.little); // lengthInBytes
      shb.setUint32(4, sample.loopStart, Endian.little);
      shb.setUint32(8, sample.loopLength, Endian.little);
      sh[12] = sample.volume.clamp(0, 64);
      shb.setInt8(13, sample.finetune);
      // Loop type: bits 0-1 (0 none / 1 forward / 2 ping-pong) | bit4 16-bit.
      final loopType =
          sample.loopLength > 0 ? (sample.pingPong ? 0x02 : 0x01) : 0;
      sh[14] = loopType | (sixteen ? 0x10 : 0);
      sh[15] = sample.pan.clamp(0, 255); // panning (128 = centre)
      shb.setInt8(16, sample.relativeNote);
      sh[17] = 0; // reserved
      _writeName(sh, 18, 22, sample.name);
      out.add(sh);
    }

    for (final block in dataBlocks) {
      out.add(block);
    }
  }

  return out.toBytes();
}
