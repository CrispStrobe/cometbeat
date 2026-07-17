// lib/core/audio/mod/it_reader.dart
//
// Impulse Tracker `.it` IMPORT (reader): raw bytes → [ItModule]. Pure Dart.
// Implement against the byte-layout contract in it_module.dart.
//
// Contract (see it_module.dart for exact offsets):
//   • Verify "IMPM" at 0x00 (else throw [ItFormatException]); read the header
//     (name, OrdNum/InsNum/SmpNum/PatNum, Cwt/v, speed/tempo/global-volume,
//     order list @0xC0). Then the three u32 offset tables (instrument, sample,
//     pattern), in that order, right after the order list.
//   • Samples: at each sample offset read the 80-byte "IMPS" header. If Flg 0x08
//     (compressed) → decode via `decodeIt214` below (it215 = Cwt/v >= 0x0215).
//     Else decode uncompressed per Cvt (signed/unsigned, LE/BE for 16-bit,
//     running-sum if Cvt 0x04 delta). Normalize to [-1,1] into ItSample.pcm
//     (8-bit /128, 16-bit /32768).
//   • Patterns: at each non-zero pattern offset read u16 packedLen, u16 rows, skip
//     4 reserved, then unpack with per-channel "last" caches (channels 0..63) per
//     the contract. Pad each pattern's rows to (maxChannelUsed + 1) cells;
//     ItModule.channelCount = max across patterns. A pattern offset of 0 → an
//     empty pattern.
//   • Be robust to truncation: guard every read against bytes.length; a short
//     pattern/sample yields empty/partial rather than a RangeError. Only a bad
//     signature or a file too short for the fixed header throws.
//
// ─── IT214/IT215 sample decompression (validated vs libxmp itsex.c) ───────────
// The compressed sample data is a sequence of BLOCKS. For each block:
//   1. Read a u16 little-endian = number of compressed bytes that follow.
//   2. Read bits LSB-FIRST over exactly those bytes (first bit = bit 0 of the
//      first byte; leftover high bits of the final byte are padding).
//   3. A block decodes up to a quota: 0x8000 samples for 8-bit, 0x4000 for
//      16-bit. Track a global `remaining`; this block's count = min(remaining,
//      quota). Consume blocks until all `length` samples are produced.
// Per block: `width` starts at 9 (8-bit) / 17 (16-bit); `d1 = d2 = 0`.
// Per sample: if `width > 9` (8-bit) / `> 17` (16-bit) the stream is corrupt —
// stop. Read `v = readBits(width)`, then:
//   • width < 7 (both): if v == (1 << (width-1)): read n = 3 bits (8-bit) / 4
//     bits (16-bit); val = n + 1; width = (val < width) ? val : val + 1; continue.
//   • 7 <= width < max (max = 9 / 17):
//       8-bit : border = (0xFF   >> (9  - width)) - 4; band = 8.
//       16-bit: border = (0xFFFF >> (17 - width)) - 8; band = 16.
//       if border < v && v <= border + band: val = v - border;
//         width = (val < width) ? val : val + 1; continue.
//   • width == max: if (v & 0x100) [8-bit] / (v & 0x10000) [16-bit]:
//       width = (v + 1) & 0xFF; continue.
// Otherwise `v` is a delta. Sign-extend it:
//   • 8-bit : if width < 8 → signExtend(v, width); else signExtend(v & 0xFF, 8).
//   • 16-bit: if width < 16 → signExtend(v, width); else signExtend(v & 0xFFFF,16)
//   where signExtend(x, w) reads the low w bits as two's complement.
// Then integrate (wrapping in the int8 / int16 domain):
//   d1 = wrap(d1 + c); d2 = wrap(d2 + d1);
//   emit d2 if it215 else d1.  (IT214 = single delta d1; IT215 = double delta d2.)
// Emitted samples are int8 / int16; normalize to [-1,1] afterwards.
// ─────────────────────────────────────────────────────────────────────────────
//
// Verify against test/it_codec_test.dart (a hand-authored golden oracle whose
// compressed blocks were validated against libxmp itsex.c +, when present, a real
// test/fixtures/*.it).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';

/// Parses Impulse Tracker `.it` [bytes] into an [ItModule].
ItModule parseIt(Uint8List bytes) {
  // ── signature + minimum-length guards (the only throwing conditions) ──
  if (bytes.length < 0xC0 ||
      bytes[0] != 0x49 || // 'I'
      bytes[1] != 0x4D || // 'M'
      bytes[2] != 0x50 || // 'P'
      bytes[3] != 0x4D) {
    // 'M'
    throw const ItFormatException('not an Impulse Tracker module (no "IMPM")');
  }

  final bd = ByteData.sublistView(bytes);
  final int len = bytes.length;

  int u8(int o) => (o >= 0 && o < len) ? bytes[o] : 0;
  int u16(int o) =>
      (o >= 0 && o + 2 <= len) ? bd.getUint16(o, Endian.little) : 0;
  int u32(int o) =>
      (o >= 0 && o + 4 <= len) ? bd.getUint32(o, Endian.little) : 0;

  String readCString(int start, int maxLen) {
    final sb = StringBuffer();
    for (var i = 0; i < maxLen; i++) {
      final o = start + i;
      if (o >= len) break;
      final c = bytes[o];
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().trim();
  }

  // ── header ──
  final name = readCString(0x04, 26);
  final ordNum = u16(0x20);
  final insNum = u16(0x22);
  final smpNum = u16(0x24);
  final patNum = u16(0x26);
  final cwtv = u16(0x28);
  final globalVolume = u8(0x30);
  final initialSpeed = u8(0x32);
  final initialTempo = u8(0x33);
  final it215 = cwtv >= 0x0215;

  // order list @ 0xC0, OrdNum bytes
  final order = <int>[];
  for (var i = 0; i < ordNum; i++) {
    order.add(u8(0xC0 + i));
  }

  // ── offset tables: InsNum×u32, then SmpNum×u32, then PatNum×u32 ──
  // Instrument headers are not parsed here, but we must advance past their
  // offset table to reach the sample and pattern tables. The table offsets use
  // the real declared counts (the on-disk layout); the build loops are clamped.
  final smpBase = 0xC0 + ordNum + insNum * 4;
  final patBase = smpBase + smpNum * 4;

  // Sample and pattern references (in the order list and cells) are single
  // bytes, so a module addresses at most 256 of each. A header declaring more
  // (up to the u16 max) is malformed — and unclamped it is a decode bomb: a
  // ~1 KB file with patNum=256 pointing at a pattern header declaring
  // numRows=65535 drives 256 × 65535 × 64 cell allocations (~16 s hang). See
  // also the numRows clamp in _parsePattern and the length clamp in the sample
  // decoders. Clamping is lossless for every real IT.
  const maxAddressable = 256;
  final smpCount = smpNum > maxAddressable ? maxAddressable : smpNum;
  final patCount = patNum > maxAddressable ? maxAddressable : patNum;

  // ── samples ──
  final samples = <ItSample>[];
  for (var i = 0; i < smpCount; i++) {
    final so = u32(smpBase + i * 4);
    samples.add(_parseSample(bytes, bd, so, it215));
  }

  // ── patterns ──
  final patterns = <ItPattern>[];
  var maxChannelCount = 0;
  for (var i = 0; i < patCount; i++) {
    final po = u32(patBase + i * 4);
    final pat = _parsePattern(bytes, bd, po);
    if (pat.channelCount > maxChannelCount) maxChannelCount = pat.channelCount;
    patterns.add(pat);
  }

  return ItModule(
    name: name,
    channelCount: maxChannelCount,
    instrumentCount: insNum,
    initialSpeed: initialSpeed,
    initialTempo: initialTempo,
    globalVolume: globalVolume,
    order: order,
    patterns: patterns,
    samples: samples,
  );
}

// ── sample parsing ────────────────────────────────────────────────────────────
ItSample _parseSample(
  Uint8List bytes,
  ByteData bd,
  int so,
  bool it215,
) {
  final int len = bytes.length;
  // header must fit and start with "IMPS"
  if (so < 0 ||
      so + 80 > len ||
      bytes[so] != 0x49 || // 'I'
      bytes[so + 1] != 0x4D || // 'M'
      bytes[so + 2] != 0x50 || // 'P'
      bytes[so + 3] != 0x53) {
    // 'S'
    return ItSample.empty();
  }

  int u8(int o) => (o >= 0 && o < len) ? bytes[o] : 0;
  int u32(int o) =>
      (o >= 0 && o + 4 <= len) ? bd.getUint32(o, Endian.little) : 0;

  String readCString(int start, int maxLen) {
    final sb = StringBuffer();
    for (var i = 0; i < maxLen; i++) {
      final o = start + i;
      if (o >= len) break;
      final c = bytes[o];
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().trim();
  }

  final globalVol = u8(so + 0x11);
  final flg = u8(so + 0x12);
  final defaultVol = u8(so + 0x13);
  final sampleName = readCString(so + 0x14, 26);
  final filename = readCString(so + 0x04, 12);
  final cvt = u8(so + 0x2E);
  final length = u32(so + 0x30);
  final loopStart = u32(so + 0x34);
  final loopEnd = u32(so + 0x38);
  final c5speed = u32(so + 0x3C);
  final dataPtr = u32(so + 0x48);

  final sixteenBit = (flg & 0x02) != 0;
  final compressed = (flg & 0x08) != 0;
  final hasSample = (flg & 0x01) != 0;

  Float64List pcm;
  if (!hasSample || length == 0) {
    pcm = Float64List(0);
  } else if (compressed) {
    pcm = _decodeCompressed(bytes, dataPtr, length, sixteenBit, it215);
  } else {
    pcm = _decodeUncompressed(bytes, dataPtr, length, sixteenBit, cvt);
  }

  return ItSample(
    name: sampleName,
    filename: filename,
    globalVolume: globalVol,
    defaultVolume: defaultVol,
    sixteenBit: sixteenBit,
    compressed: compressed,
    length: length,
    loopStart: loopStart,
    loopEnd: loopEnd,
    c5speed: c5speed == 0 ? 8363 : c5speed,
    pcm: pcm,
  );
}

int _wrap8(int x) => ((x + 128) & 0xFF) - 128;
int _wrap16(int x) => ((x + 32768) & 0xFFFF) - 32768;

int _signExtend(int x, int w) {
  final mask = (1 << w) - 1;
  x &= mask;
  final signBit = 1 << (w - 1);
  return (x & signBit) != 0 ? x - (1 << w) : x;
}

Float64List _decodeUncompressed(
  Uint8List bytes,
  int dataPtr,
  int length,
  bool sixteenBit,
  int cvt,
) {
  final int len = bytes.length;
  final signed = (cvt & 0x01) != 0;
  final bigEndian = (cvt & 0x02) != 0;
  final delta = (cvt & 0x04) != 0;
  // Uncompressed PCM physically occupies length × bytesPerSample bytes from
  // dataPtr, so a declared length beyond the file is malformed. Clamp before
  // the Float64List(length) allocation — an unbounded u32 length is otherwise
  // a multi-gigabyte OOM decode-bomb.
  final avail = (dataPtr >= 0 && dataPtr < len)
      ? (len - dataPtr) ~/ (sixteenBit ? 2 : 1)
      : 0;
  if (length > avail) length = avail;
  final pcm = Float64List(length);

  if (sixteenBit) {
    var running = 0;
    for (var i = 0; i < length; i++) {
      final off = dataPtr + i * 2;
      int raw = 0;
      if (off + 2 <= len) {
        final lo = bytes[off];
        final hi = bytes[off + 1];
        raw = bigEndian ? (lo << 8) | hi : (hi << 8) | lo;
      }
      int val;
      if (signed) {
        val = raw >= 0x8000 ? raw - 0x10000 : raw;
      } else {
        val = raw - 0x8000;
      }
      if (delta) {
        running = _wrap16(running + val);
        val = running;
      }
      pcm[i] = val / 32768.0;
    }
  } else {
    var running = 0;
    for (var i = 0; i < length; i++) {
      final off = dataPtr + i;
      int raw = 0;
      if (off < len) raw = bytes[off];
      int val;
      if (signed) {
        val = raw >= 0x80 ? raw - 0x100 : raw;
      } else {
        val = raw - 0x80;
      }
      if (delta) {
        running = _wrap8(running + val);
        val = running;
      }
      pcm[i] = val / 128.0;
    }
  }
  return pcm;
}

Float64List _decodeCompressed(
  Uint8List bytes,
  int dataPtr,
  int length,
  bool sixteenBit,
  bool it215,
) {
  final int len = bytes.length;
  // Compressed data expands, so length can exceed the input byte count — but
  // not without bound. Cap the decoded size at a generous multiple of the
  // remaining file bytes so a declared length near the u32 max can't drive a
  // multi-gigabyte Int32List(length) OOM allocation. Any real IT sample stays
  // far under this bound.
  final maxDecoded =
      (dataPtr >= 0 && dataPtr < len) ? (len - dataPtr) * 16 + 1024 : 0;
  if (length > maxDecoded) length = maxDecoded;
  final out = Int32List(length);
  final int quota = sixteenBit ? 0x4000 : 0x8000;
  final int maxWidth = sixteenBit ? 17 : 9;
  final int topBit = sixteenBit ? 0x10000 : 0x100;

  var produced = 0;
  var remaining = length;
  var pos = dataPtr;

  while (remaining > 0) {
    if (pos + 2 > len) break;
    final blockLen = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2;
    final blockStart = pos;
    final blockEnd = math.min(blockStart + blockLen, len);

    var bitPos = 0; // bits consumed since blockStart
    int readBits(int n) {
      var value = 0;
      for (var i = 0; i < n; i++) {
        final byteIndex = blockStart + (bitPos >> 3);
        final bit = (byteIndex < blockEnd)
            ? ((bytes[byteIndex] >> (bitPos & 7)) & 1)
            : 0;
        value |= bit << i;
        bitPos++;
      }
      return value;
    }

    final blockCount = math.min(remaining, quota);
    var width = maxWidth;
    var d1 = 0;
    var d2 = 0;
    var done = 0;

    while (done < blockCount) {
      if (width > maxWidth || width < 1) break; // corrupt
      final v = readBits(width);

      if (width < 7) {
        if (v == (1 << (width - 1))) {
          final n = readBits(sixteenBit ? 4 : 3);
          final val = n + 1;
          width = (val < width) ? val : val + 1;
          continue;
        }
      } else if (width < maxWidth) {
        final int border;
        final int band;
        if (sixteenBit) {
          border = (0xFFFF >> (17 - width)) - 8;
          band = 16;
        } else {
          border = (0xFF >> (9 - width)) - 4;
          band = 8;
        }
        if (border < v && v <= border + band) {
          final val = v - border;
          width = (val < width) ? val : val + 1;
          continue;
        }
      } else {
        // width == maxWidth
        if ((v & topBit) != 0) {
          width = (v + 1) & 0xFF;
          continue;
        }
      }

      // v is a delta — sign-extend
      final int c;
      if (sixteenBit) {
        c = (width < 16) ? _signExtend(v, width) : _signExtend(v & 0xFFFF, 16);
      } else {
        c = (width < 8) ? _signExtend(v, width) : _signExtend(v & 0xFF, 8);
      }

      if (sixteenBit) {
        d1 = _wrap16(d1 + c);
        d2 = _wrap16(d2 + d1);
      } else {
        d1 = _wrap8(d1 + c);
        d2 = _wrap8(d2 + d1);
      }

      final emit = it215 ? d2 : d1;
      if (produced < length) out[produced] = emit;
      produced++;
      done++;
    }

    remaining -= blockCount;
    pos = blockStart + blockLen; // advance to the next block
  }

  final pcm = Float64List(length);
  final divisor = sixteenBit ? 32768.0 : 128.0;
  for (var i = 0; i < length; i++) {
    pcm[i] = out[i] / divisor;
  }
  return pcm;
}

// ── pattern parsing ───────────────────────────────────────────────────────────
ItPattern _parsePattern(Uint8List bytes, ByteData bd, int po) {
  if (po == 0) return const ItPattern([], 0);

  final int len = bytes.length;
  int u16(int o) =>
      (o >= 0 && o + 2 <= len) ? bd.getUint16(o, Endian.little) : 0;

  final packedLen = u16(po + 0);
  // IT patterns hold at most 200 rows; clamp the declared count (u16, up to
  // 65535) so a crafted header can't drive a numRows × 64 grid allocation
  // decode-bomb. 256 is a lossless upper bound for every real IT.
  final declaredRows = u16(po + 2);
  if (declaredRows == 0) return const ItPattern([], 0);
  final numRows = declaredRows > 256 ? 256 : declaredRows;

  final lastMask = List<int>.filled(64, 0);
  final lastNote = List<int>.filled(64, 0);
  final lastInstr = List<int>.filled(64, 0);
  final lastVol = List<int>.filled(64, 0);
  final lastCmd = List<int>.filled(64, 0);
  final lastCmdVal = List<int>.filled(64, 0);

  // grid[row][channel]
  final grid = List.generate(
    numRows,
    (_) => List<ItCell>.filled(64, ItCell.empty),
    growable: false,
  );
  var maxCh = -1;

  var p = po + 8;
  final effEnd = math.min(po + 8 + packedLen, len);
  int rb() => (p < effEnd) ? bytes[p++] : 0;

  var row = 0;
  while (row < numRows) {
    final channelvar = rb();
    if (channelvar == 0) {
      row++;
      continue;
    }
    final channel = (channelvar - 1) & 63;
    int mask;
    if ((channelvar & 0x80) != 0) {
      mask = rb();
      lastMask[channel] = mask;
    } else {
      mask = lastMask[channel];
    }

    var note = -1;
    var instr = 0;
    var vol = -1;
    var cmd = 0;
    var cmdVal = 0;

    if ((mask & 0x01) != 0) {
      final b = rb();
      lastNote[channel] = b;
      note = b;
    }
    if ((mask & 0x02) != 0) {
      final b = rb();
      lastInstr[channel] = b;
      instr = b;
    }
    if ((mask & 0x04) != 0) {
      final b = rb();
      lastVol[channel] = b;
      vol = b;
    }
    if ((mask & 0x08) != 0) {
      final c = rb();
      final cv = rb();
      lastCmd[channel] = c;
      lastCmdVal[channel] = cv;
      cmd = c;
      cmdVal = cv;
    }
    if ((mask & 0x10) != 0) note = lastNote[channel];
    if ((mask & 0x20) != 0) instr = lastInstr[channel];
    if ((mask & 0x40) != 0) vol = lastVol[channel];
    if ((mask & 0x80) != 0) {
      cmd = lastCmd[channel];
      cmdVal = lastCmdVal[channel];
    }

    grid[row][channel] = ItCell(
      note: note,
      instrument: instr,
      volpan: vol,
      command: cmd,
      commandValue: cmdVal,
    );
    if (channel > maxCh) maxCh = channel;
  }

  final channelCount = maxCh + 1;
  final rows = <List<ItCell>>[];
  for (var r = 0; r < numRows; r++) {
    if (channelCount == 0) {
      rows.add(const <ItCell>[]);
    } else {
      rows.add(List<ItCell>.generate(channelCount, (c) => grid[r][c]));
    }
  }
  return ItPattern(rows, channelCount);
}
