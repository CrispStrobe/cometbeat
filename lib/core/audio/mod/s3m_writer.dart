// lib/core/audio/mod/s3m_writer.dart
//
// Scream Tracker 3 `.s3m` EXPORT (writer): [S3mModule] → raw bytes. Pure Dart.
// The byte-level inverse of s3m_reader.dart — a module written here must re-read
// via parseS3m to an equivalent module. Used by the cross-format converters
// (docToS3m/convertToS3m in module_convert.dart) so any module → `.s3m`.
//
// ─── Output layout (little-endian; must satisfy parseS3m) ────────────────────
// Everything after the fixed header + tables is PARAGRAPH-aligned (16 bytes);
// parapointers are storedOffset = fileOffset / 16.
//
// HEADER (96 bytes @ 0x00):
//   0x00 28  title (ASCII, NUL-pad/truncate) · 0x1C 1 = 0x1A · 0x1D 1 type = 16
//   0x1E 2   = 0 · 0x20 2 ordNum (order length, PADDED UP TO EVEN) ·
//   0x22 2   insNum (= samples.length) · 0x24 2 patNum (= patterns.length) ·
//   0x26 2   flags = 0 · 0x28 2 version = 0x1320 · 0x2A 2 sampleFormat = 1 (SIGNED
//            — so PCM bytes are written as-is, no unsigned flip) ·
//   0x2C 4   "SCRM" · 0x30 globalVolume · 0x31 initialSpeed · 0x32 initialTempo ·
//   0x33 masterVolume = 48 · 0x34 ultraClick = 0 · 0x35 defaultPan = 0 (NOT 252,
//            so NO 32-byte pan block is emitted) · 0x36..0x3F = 0 ·
//   0x40 32  channel settings: byte i = i for i < channelCount (enabled, < 128),
//            else 255 (disabled). parseS3m counts (value < 128) as channelCount.
// Then contiguously (still un-aligned, right after the header):
//   ordNum bytes  order list: order entries, then pad up to the even ordNum with
//                 255 (end marker).
//   insNum × 2    instrument parapointers (patched after layout).
//   patNum × 2    pattern parapointers (patched after layout).
//   (No pan block — defaultPan != 252.)
// Then PARAGRAPH-align (pad with 0 to the next multiple of 16).
//
// INSTRUMENTS: for each sample, at a paragraph boundary write the 80-byte header,
//   record its parapointer (offset/16). Then paragraph-align and write the sample
//   PCM (record memseg = pcmOffset/16, patched into the header).
//   Header (80): 0x00 type (1 if non-empty else 0) · 0x01 12-byte DOS filename
//   (may be empty) · 0x0D memseg high byte · 0x0E memseg low u16 · 0x10 u32 length
//   (samples) · 0x14 u32 loopBegin · 0x18 u32 loopEnd · 0x1C volume · 0x1D 0 ·
//   0x1E pack = 0 · 0x1F flags (1 if loop else 0) · 0x20 u32 C2 speed · 0x30
//   28-byte sample name · 0x4C "SCRS". PCM at memseg×16 = `length` signed bytes.
//   An empty sample: type 0, length 0, memseg 0 (no data block).
//
// PATTERNS: for each, at a paragraph boundary reserve a u16 length then write the
//   packed rows; set the u16 = total packed length INCLUDING those 2 bytes. Record
//   the pattern parapointer (offset/16). Emit exactly 64 rows. For each row, for
//   each channel whose cell is non-empty: write a "what" byte = channel(low 5 bits)
//   | (0x20 if a note/instrument is present) | (0x40 if volume != 255) | (0x80 if
//   command/info present); then, in that order: note byte + instrument byte (if
//   0x20), volume byte (if 0x40), command byte + info byte (if 0x80). End every row
//   with a 0x00 byte. note byte = S3mCell.note as-is (255 empty, 254 off).
//   Include the note/instrument pair (0x20) whenever note != 255 OR instrument != 0.
//
// After emitting everything, PATCH the instrument + pattern parapointer tables and
// each instrument header's memseg with the recorded offsets/16.
// ─────────────────────────────────────────────────────────────────────────────
//
// Verify against test/s3m_writer_test.dart: parseS3m(writeS3m(parseS3m(golden.s3m)))
// preserves the module, plus a hand-built module round-trip.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';

/// Serializes an [S3mModule] to Scream Tracker 3 `.s3m` bytes (parseS3m-readable).
Uint8List writeS3m(S3mModule module) {
  final out = BytesBuilder();

  int len() => out.length;

  void u8(int v) => out.addByte(v & 0xFF);
  void u16(int v) {
    out.addByte(v & 0xFF);
    out.addByte((v >> 8) & 0xFF);
  }

  void u32(int v) {
    out.addByte(v & 0xFF);
    out.addByte((v >> 8) & 0xFF);
    out.addByte((v >> 16) & 0xFF);
    out.addByte((v >> 24) & 0xFF);
  }

  // Writes [text] as [fieldLen] bytes: ASCII, NUL-padded and truncated.
  void asciiFixed(String text, int fieldLen) {
    final codes = text.codeUnits;
    for (var i = 0; i < fieldLen; i++) {
      out.addByte(i < codes.length ? (codes[i] & 0xFF) : 0);
    }
  }

  void align16() {
    while (len() % 16 != 0) {
      out.addByte(0);
    }
  }

  final samples = module.samples;
  final patterns = module.patterns;
  final insNum = samples.length;
  final patNum = patterns.length;

  // ordNum = order length padded up to even.
  var ordNum = module.order.length;
  if (ordNum.isOdd) ordNum++;
  if (ordNum == 0) ordNum = 0; // an empty order stays empty (even).

  final channelCount = module.channelCount;

  // ── HEADER (96 bytes) ──────────────────────────────────────────────────────
  asciiFixed(module.title, 28); // 0x00
  u8(0x1A); // 0x1C
  u8(16); // 0x1D type
  u16(0); // 0x1E
  u16(ordNum); // 0x20
  u16(insNum); // 0x22
  u16(patNum); // 0x24
  u16(0); // 0x26 flags
  u16(0x1320); // 0x28 version
  u16(1); // 0x2A sample format = signed
  asciiFixed('SCRM', 4); // 0x2C
  u8(module.globalVolume); // 0x30
  u8(module.initialSpeed); // 0x31
  u8(module.initialTempo); // 0x32
  u8(48); // 0x33 master volume
  u8(0); // 0x34 ultra-click
  u8(0); // 0x35 default pan (not 252 → no pan block)
  for (var i = 0x36; i < 0x40; i++) {
    u8(0); // 0x36..0x3F
  }
  // 0x40 channel settings (32 bytes).
  for (var i = 0; i < 32; i++) {
    u8(i < channelCount ? i : 255);
  }

  // ── Order list (ordNum bytes, pad with 255) ────────────────────────────────
  for (var i = 0; i < ordNum; i++) {
    u8(i < module.order.length ? module.order[i] : 255);
  }

  // ── Instrument parapointers (patched later) ────────────────────────────────
  final insPtrTable = len();
  for (var i = 0; i < insNum; i++) {
    u16(0);
  }

  // ── Pattern parapointers (patched later) ───────────────────────────────────
  final patPtrTable = len();
  for (var i = 0; i < patNum; i++) {
    u16(0);
  }

  // No pan block.

  // Records to patch after the whole file is laid out.
  final insHeaderOffsets = List<int>.filled(insNum, 0);
  final insParapointers = List<int>.filled(insNum, 0);
  final insMemsegs = List<int>.filled(insNum, 0);
  final patParapointers = List<int>.filled(patNum, 0);

  // ── INSTRUMENTS ────────────────────────────────────────────────────────────
  for (var s = 0; s < insNum; s++) {
    final sample = samples[s];
    final isEmpty = sample.isEmpty;

    align16();
    final headerOff = len();
    insHeaderOffsets[s] = headerOff;
    insParapointers[s] = headerOff ~/ 16;

    u8(isEmpty ? 0 : 1); // 0x00 type
    asciiFixed('', 12); // 0x01 DOS filename
    u8(0); // 0x0D memseg high (patched)
    u16(0); // 0x0E memseg low (patched)
    final pcmLen = sample.pcm.length;
    u32(isEmpty ? 0 : pcmLen); // 0x10 length
    u32(sample.loopStart); // 0x14 loopBegin
    u32(sample.loopEnd); // 0x18 loopEnd
    u8(sample.volume); // 0x1C
    u8(0); // 0x1D
    u8(0); // 0x1E pack
    u8(sample.loop ? 1 : 0); // 0x1F flags
    u32(sample.c2spd); // 0x20 C2 speed
    // 0x24..0x2F reserved (12 bytes).
    for (var i = 0x24; i < 0x30; i++) {
      u8(0);
    }
    asciiFixed(sample.name, 28); // 0x30 name
    asciiFixed('SCRS', 4); // 0x4C

    if (!isEmpty) {
      align16();
      final pcmOff = len();
      insMemsegs[s] = pcmOff ~/ 16;
      for (var i = 0; i < pcmLen; i++) {
        u8(sample.pcm[i] & 0xFF); // signed byte written as-is
      }
    }
  }

  // ── PATTERNS ───────────────────────────────────────────────────────────────
  for (var p = 0; p < patNum; p++) {
    final pattern = patterns[p];
    align16();
    final patOff = len();
    patParapointers[p] = patOff ~/ 16;

    // Pack the rows into a temporary buffer, then prefix with the length word.
    final body = BytesBuilder();
    void bu8(int v) => body.addByte(v & 0xFF);

    final rows = pattern.rows;
    for (var r = 0; r < 64; r++) {
      final row = (r < rows.length) ? rows[r] : const <S3mCell>[];
      final cellCount = row.length;
      for (var ch = 0; ch < cellCount && ch < 32; ch++) {
        final cell = row[ch];
        if (cell.isEmpty) continue;

        final hasNoteIns =
            cell.note != S3mCell.emptyNote || cell.instrument != 0;
        final hasVol = cell.volume != S3mCell.noVolume;
        final hasCmd = cell.command != 0 || cell.info != 0;

        var what = ch & 0x1F;
        if (hasNoteIns) what |= 0x20;
        if (hasVol) what |= 0x40;
        if (hasCmd) what |= 0x80;
        bu8(what);
        if (hasNoteIns) {
          bu8(cell.note);
          bu8(cell.instrument);
        }
        if (hasVol) bu8(cell.volume);
        if (hasCmd) {
          bu8(cell.command);
          bu8(cell.info);
        }
      }
      bu8(0x00); // end of row
    }

    final packed = body.toBytes();
    final total = packed.length + 2; // includes the length word itself
    u16(total);
    out.add(packed);
  }

  // ── PATCH the tables + memseg fields ───────────────────────────────────────
  final bytes = out.toBytes(); // mutable Uint8List
  final data = ByteData.sublistView(bytes);

  for (var s = 0; s < insNum; s++) {
    data.setUint16(insPtrTable + s * 2, insParapointers[s], Endian.little);
    final memseg = insMemsegs[s];
    final headerOff = insHeaderOffsets[s];
    bytes[headerOff + 0x0D] = (memseg >> 16) & 0xFF; // high byte
    data.setUint16(headerOff + 0x0E, memseg & 0xFFFF, Endian.little); // low u16
  }
  for (var p = 0; p < patNum; p++) {
    data.setUint16(patPtrTable + p * 2, patParapointers[p], Endian.little);
  }

  return bytes;
}
