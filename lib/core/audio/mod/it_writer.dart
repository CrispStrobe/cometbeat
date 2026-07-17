// lib/core/audio/mod/it_writer.dart
//
// Impulse Tracker `.it` EXPORT (writer): [ItModule] → raw bytes. Pure Dart.
// The byte-level inverse of it_reader.dart — a module written here must re-read
// via parseIt to an equivalent module. Used by the cross-format converters
// (docToIt/convertToIt in module_convert.dart) so any module → `.it`.
//
// Writes SAMPLE MODE (InsNum = 0; a cell's "instrument" is a sample number) and
// UNCOMPRESSED sample data. The IT214/215 sample compressor is NOT implemented —
// samples read from a compressed source are written back uncompressed (their PCM
// is preserved; the `compressed` flag is not). IT uses absolute u32 file offsets,
// so — unlike S3M — NO paragraph alignment is needed; just lay out sequentially
// and patch the offset tables + each sample header's data pointer.
//
// ─── Output layout (little-endian; must satisfy parseIt) ─────────────────────
// HEADER (0xC0 bytes):
//   0x00 4  "IMPM" · 0x04 26 song name (NUL-pad) · 0x1E 2 = 0
//   0x20 2  ordNum = order.length · 0x22 2 insNum = 0 · 0x24 2 smpNum =
//           samples.length · 0x26 2 patNum = patterns.length
//   0x28 2  Cwt/v = 0x0214 · 0x2A 2 Cmwt = 0x0200 · 0x2C 2 flags = 0x0009 (bit2
//           "use instruments" MUST be clear for sample mode) · 0x2E 2 special = 0
//   0x30 1  globalVolume · 0x31 mixVolume = 48 · 0x32 initialSpeed ·
//   0x33 1  initialTempo · 0x34 panSep = 128 · 0x35 pwd = 0
//   0x36 2  msgLength = 0 · 0x38 4 msgOffset = 0 · 0x3C 4 reserved = 0
//   0x40 64 channel pan (write 32 each) · 0x80 64 channel vol (write 64 each)
//   0xC0 ordNum bytes  order list
//   then smpNum × u32 sample-header offsets (patched after layout)
//   then patNum × u32 pattern offsets (patched after layout)
//   (insNum is 0 → no instrument-offset table.)
//
// Then, in any order (record offsets to patch the tables above):
//   SAMPLE HEADERS (80 bytes each): 0x00 "IMPS" · 0x04 12 filename · 0x10 0 ·
//     0x11 globalVol = 64 · 0x12 Flg = 0x01 | (16-bit?0x02:0) | (loop?0x10:0) ·
//     0x13 defaultVolume · 0x14 26 name · 0x2E Cvt = 0x01 (SIGNED) · 0x2F pan = 32 ·
//     0x30 u32 length(samples) · 0x34 u32 loopStart · 0x38 u32 loopEnd ·
//     0x3C u32 C5Speed · 0x40 u32 susLoopStart = 0 · 0x44 u32 susLoopEnd = 0 ·
//     0x48 u32 samplePointer (patched to the data offset) · 0x4C..0x4F vibrato = 0.
//   SAMPLE DATA: uncompressed, signed (Cvt 0x01). 8-bit = 1 signed byte each;
//     16-bit = 1 signed LE word each. No delta. Quantize normalized pcm: 8-bit
//     (v*128).round().clamp(-128,127); 16-bit (v*32768).round().clamp(-32768,32767).
//     length(field) = pcm.length (in SAMPLES). An empty sample: Flg 0 (no
//     has-sample bit), length 0, no data block.
//   PATTERNS: 0x00 u16 packedLength (data bytes only, EXCLUDING this 8-byte
//     header) · 0x02 u16 rows · 0x04 4 reserved = 0 · 0x08 packed data.
//     Packing: for each row, for each NON-empty cell, write channelvar =
//     ((channel+1) & 0x7F) | 0x80, then a mask byte — bit0 note (ItCell.note != -1),
//     bit1 instrument (!=0), bit2 volpan (!=-1), bit3 command (command!=0 ||
//     commandValue!=0) — then, in order: note byte, instrument byte, volpan byte,
//     command byte + commandValue byte (only those whose mask bit is set). End
//     EVERY row with a 0x00 byte. Emit exactly `numRows` rows.
// ─────────────────────────────────────────────────────────────────────────────
//
// Verify against test/it_writer_test.dart: parseIt(writeIt(parseIt(golden.it)))
// preserves the module (note the compressed source samples come back uncompressed
// with their PCM intact), plus a hand-built module round-trip.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';

/// Serializes an [ItModule] to Impulse Tracker `.it` bytes (parseIt-readable).
Uint8List writeIt(ItModule module) {
  final samples = module.samples;
  final patterns = module.patterns;
  final order = module.order;
  final smpNum = samples.length;
  final patNum = patterns.length;
  final ordNum = order.length;

  final out = <int>[];

  void u8(int v) => out.add(v & 0xFF);
  void u16(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }

  void u32(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 24) & 0xFF);
  }

  void writeString(String s, int fieldLen) {
    final codes = s.codeUnits;
    for (var i = 0; i < fieldLen; i++) {
      out.add(i < codes.length ? (codes[i] & 0xFF) : 0);
    }
  }

  // ── HEADER (0xC0 bytes) ──
  writeString('IMPM', 4); // 0x00
  writeString(module.name, 26); // 0x04
  u16(0); // 0x1E
  u16(ordNum); // 0x20 OrdNum
  u16(0); // 0x22 InsNum
  u16(smpNum); // 0x24 SmpNum
  u16(patNum); // 0x26 PatNum
  u16(0x0214); // 0x28 Cwt/v
  u16(0x0200); // 0x2A Cmwt
  u16(0x0009); // 0x2C Flags (bit2 clear)
  u16(0); // 0x2E Special
  u8(module.globalVolume); // 0x30 global volume
  u8(48); // 0x31 mix volume
  u8(module.initialSpeed); // 0x32 initial speed
  u8(module.initialTempo); // 0x33 initial tempo
  u8(128); // 0x34 pan separation
  u8(0); // 0x35 pitch-wheel depth
  u16(0); // 0x36 message length
  u32(0); // 0x38 message offset
  u32(0); // 0x3C reserved
  for (var i = 0; i < 64; i++) {
    u8(32); // 0x40 channel pan
  }
  for (var i = 0; i < 64; i++) {
    u8(64); // 0x80 channel volume
  }

  // 0xC0 order list
  for (var i = 0; i < ordNum; i++) {
    u8(order[i]);
  }

  // sample-header offset table (zeros; patched later)
  final smpTableOffset = out.length;
  for (var i = 0; i < smpNum; i++) {
    u32(0);
  }
  // pattern offset table (zeros; patched later)
  final patTableOffset = out.length;
  for (var i = 0; i < patNum; i++) {
    u32(0);
  }

  // ── SAMPLE HEADERS ──
  final sampleHeaderOffsets = <int>[];
  for (var i = 0; i < smpNum; i++) {
    final s = samples[i];
    sampleHeaderOffsets.add(out.length);
    final empty = s.pcm.isEmpty;
    final loop = s.loopEnd > s.loopStart;
    final flg =
        empty ? 0 : (0x01 | (s.sixteenBit ? 0x02 : 0) | (loop ? 0x10 : 0));
    final length = empty ? 0 : s.pcm.length;

    writeString('IMPS', 4); // 0x00
    writeString('', 12); // 0x04 filename
    u8(0); // 0x10
    u8(64); // 0x11 global volume
    u8(flg); // 0x12 Flg
    u8(s.defaultVolume); // 0x13 default volume
    writeString(s.name, 26); // 0x14 name
    u8(0x01); // 0x2E Cvt (signed)
    u8(32); // 0x2F default pan
    u32(length); // 0x30 length (samples)
    u32(s.loopStart); // 0x34 loop start
    u32(s.loopEnd); // 0x38 loop end
    u32(s.c5speed); // 0x3C C5Speed
    u32(0); // 0x40 sustain-loop start
    u32(0); // 0x44 sustain-loop end
    u32(0); // 0x48 sample pointer (patched)
    u32(0); // 0x4C vibrato
  }

  // ── SAMPLE DATA ──
  final sampleDataOffsets = List<int>.filled(smpNum, 0);
  for (var i = 0; i < smpNum; i++) {
    final s = samples[i];
    if (s.pcm.isEmpty) continue;
    sampleDataOffsets[i] = out.length;
    if (s.sixteenBit) {
      for (final v in s.pcm) {
        final q = (v * 32768).round().clamp(-32768, 32767);
        u16(q & 0xFFFF);
      }
    } else {
      for (final v in s.pcm) {
        final q = (v * 128).round().clamp(-128, 127);
        u8(q & 0xFF);
      }
    }
  }

  // ── PATTERNS ──
  final patternOffsets = <int>[];
  for (var p = 0; p < patNum; p++) {
    final pat = patterns[p];
    patternOffsets.add(out.length);
    final numRows = pat.numRows;

    // reserve the 8-byte pattern header
    final headerAt = out.length;
    u16(0); // packed length (patched)
    u16(numRows); // rows
    u32(0); // reserved

    final dataStart = out.length;
    for (var r = 0; r < numRows; r++) {
      final row = (r < pat.rows.length) ? pat.rows[r] : const <ItCell>[];
      for (var ch = 0; ch < row.length; ch++) {
        final cell = row[ch];
        if (cell.isEmpty) continue;
        final hasNote = cell.note != -1;
        final hasInstr = cell.instrument != 0;
        final hasVol = cell.volpan != -1;
        final hasCmd = cell.command != 0 || cell.commandValue != 0;
        u8(((ch + 1) & 0x7F) | 0x80);
        final mask = (hasNote ? 0x01 : 0) |
            (hasInstr ? 0x02 : 0) |
            (hasVol ? 0x04 : 0) |
            (hasCmd ? 0x08 : 0);
        u8(mask);
        if (hasNote) u8(cell.note);
        if (hasInstr) u8(cell.instrument);
        if (hasVol) u8(cell.volpan);
        if (hasCmd) {
          u8(cell.command);
          u8(cell.commandValue);
        }
      }
      u8(0); // end of row
    }
    final packedLen = out.length - dataStart;
    out[headerAt] = packedLen & 0xFF;
    out[headerAt + 1] = (packedLen >> 8) & 0xFF;
  }

  // ── convert + patch the offset tables ──
  final bytes = Uint8List.fromList(out);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < smpNum; i++) {
    bd.setUint32(smpTableOffset + i * 4, sampleHeaderOffsets[i], Endian.little);
    bd.setUint32(
      sampleHeaderOffsets[i] + 0x48,
      sampleDataOffsets[i],
      Endian.little,
    );
  }
  for (var i = 0; i < patNum; i++) {
    bd.setUint32(patTableOffset + i * 4, patternOffsets[i], Endian.little);
  }

  return bytes;
}
