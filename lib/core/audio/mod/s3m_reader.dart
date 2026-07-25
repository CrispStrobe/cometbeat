// lib/core/audio/mod/s3m_reader.dart
//
// Scream Tracker 3 `.s3m` IMPORT (reader): raw bytes → [S3mModule]. Pure Dart.
// Implement against the byte-layout contract in s3m_module.dart.
//
// Contract:
//   • Verify "SCRM" at 0x2C (else throw [S3mFormatException]); read the header
//     (title, ordNum/insNum/patNum, sample-format flag, channel settings →
//     channelCount = enabled channels, global volume / speed / tempo).
//   • order = the ordNum order bytes with 254 ("skip") and 255 ("end") removed.
//   • Read insNum instrument PARAPOINTERS (u16 × 16 = offset) and patNum pattern
//     parapointers. For each instrument (type 1 PCM): name, C2 speed, volume,
//     loop, and the PCM at (memseg × 16) for `length` bytes — convert UNSIGNED
//     (sample-format == 2) to signed Int8List via (b - 128); signed passes
//     through. Non-PCM / type 0 → S3mSample.empty().
//   • For each pattern: read the u16 packed length, then unpack 64 rows ×
//     channelCount cells per the "what"-byte scheme (bit5 note+instrument, bit6
//     volume, bit7 command+info, low 5 bits = channel, 0x00 = end of row).
//   • Be robust to truncation (missing PCM / short packed data → empty).
//
// Verify against test/s3m_codec_test.dart (a hand-authored golden oracle +, when
// present, the real test/fixtures/*.s3m).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/s3m_module.dart';

const int _rowsPerPattern = 64;

/// Parses Scream Tracker 3 `.s3m` [bytes] into an [S3mModule].
S3mModule parseS3m(Uint8List bytes) {
  if (bytes.length < 96) {
    throw const S3mFormatException('too short for an S3M header');
  }
  final data = ByteData.sublistView(bytes);
  // "SCRM" signature at 0x2C.
  if (bytes[0x2C] != 0x53 ||
      bytes[0x2D] != 0x43 ||
      bytes[0x2E] != 0x52 ||
      bytes[0x2F] != 0x4D) {
    throw const S3mFormatException('missing "SCRM" signature at 0x2C');
  }

  final title = _readAsciiz(bytes, 0x00, 28);
  final ordNum = data.getUint16(0x20, Endian.little);
  final insNum = data.getUint16(0x22, Endian.little);
  final patNum = data.getUint16(0x24, Endian.little);
  final sampleFormat = data.getUint16(0x2A, Endian.little);
  final globalVolume = bytes[0x30];
  final initialSpeed = bytes[0x31];
  final initialTempo = bytes[0x32];
  final masterVolume = bytes[0x33];
  final ultraClick = bytes[0x34];
  final defaultPan = bytes[0x35];

  // Channel settings: 32 bytes @ 0x40, value < 128 = enabled.
  var channelCount = 0;
  final channelSettings = <int>[];
  for (var i = 0; i < 32; i++) {
    channelSettings.add(bytes[0x40 + i]);
    if (bytes[0x40 + i] < 128) channelCount++;
  }
  if (channelCount == 0) channelCount = 1; // defensive; must be > 0.

  // Order list: ordNum bytes @ 0x60, with 254/255 markers removed.
  const orderStart = 0x60;
  final order = <int>[];
  final rawOrder = <int>[];
  for (var i = 0; i < ordNum; i++) {
    final off = orderStart + i;
    if (off >= bytes.length) break;
    final v = bytes[off];
    rawOrder.add(v);
    if (v == 254 || v == 255) continue;
    order.add(v);
  }

  // Parapointer tables follow the order list. The pointer-table offsets use the
  // real declared counts (that's the on-disk layout), but the build loops below
  // are clamped: pattern and sample references in the order list and cells are
  // single bytes (0-255), so a module can address at most 256 of each. A header
  // declaring more (up to the u16 max, 65535) is malformed — and without this
  // clamp a 96-byte file with patNum=65535 drives ~65535 × 64 × channelCount
  // cell allocations, a multi-second hang / OOM decode-bomb. Clamping is
  // lossless for every real S3M (the extra, unaddressable entries are dropped).
  const maxAddressable = 256;
  final insPtrStart = orderStart + ordNum;
  final patPtrStart = insPtrStart + insNum * 2;
  final panStart = patPtrStart + patNum * 2;
  final defaultPans = defaultPan == 252 && panStart + 32 <= bytes.length
      ? List<int>.from(bytes.sublist(panStart, panStart + 32))
      : const <int>[];
  final insCount = insNum > maxAddressable ? maxAddressable : insNum;
  final patCount = patNum > maxAddressable ? maxAddressable : patNum;

  final samples = <S3mSample>[];
  for (var i = 0; i < insCount; i++) {
    final ptrOff = insPtrStart + i * 2;
    if (ptrOff + 2 > bytes.length) {
      samples.add(S3mSample.empty());
      continue;
    }
    final para = data.getUint16(ptrOff, Endian.little);
    samples.add(_readInstrument(bytes, data, para * 16, sampleFormat));
  }

  final patterns = <S3mPattern>[];
  for (var i = 0; i < patCount; i++) {
    final ptrOff = patPtrStart + i * 2;
    if (ptrOff + 2 > bytes.length) {
      patterns.add(_emptyPattern(channelCount));
      continue;
    }
    final para = data.getUint16(ptrOff, Endian.little);
    patterns.add(_readPattern(bytes, data, para * 16, channelCount));
  }

  return S3mModule(
    title: title,
    channelCount: channelCount,
    globalVolume: globalVolume,
    masterVolume: masterVolume,
    ultraClick: ultraClick,
    defaultPan: defaultPan,
    channelSettings: channelSettings,
    sampleFormat: sampleFormat,
    defaultPans: defaultPans,
    rawOrder: rawOrder,
    initialSpeed: initialSpeed,
    initialTempo: initialTempo,
    order: order,
    samples: samples,
    patterns: patterns,
  );
}

S3mSample _readInstrument(
  Uint8List bytes,
  ByteData data,
  int base,
  int sampleFormat,
) {
  // Need the whole 80-byte instrument header to trust it.
  if (base < 0 || base + 0x50 > bytes.length) return S3mSample.empty();

  final type = bytes[base];
  if (type != 1) return S3mSample.empty(); // non-PCM (0 = empty, 2 = AdLib…).

  // memseg: high byte @ 0x0D, low u16 @ 0x0E.
  final memsegHi = bytes[base + 0x0D];
  final memsegLo = data.getUint16(base + 0x0E, Endian.little);
  final memseg = (memsegHi << 16) | memsegLo;
  final pcmOffset = memseg * 16;

  final length = data.getUint32(base + 0x10, Endian.little);
  final loopBegin = data.getUint32(base + 0x14, Endian.little);
  final loopEnd = data.getUint32(base + 0x18, Endian.little);
  final volume = bytes[base + 0x1C];
  final flags = bytes[base + 0x1F];
  final loop = (flags & 0x01) != 0;
  final sixteenBit = (flags & 0x04) != 0;
  final unsigned = sampleFormat == 2;
  final c2spd = data.getUint32(base + 0x20, Endian.little);
  final name = _readAsciiz(bytes, base + 0x30, 28);

  // PCM window — robust to truncation: clamp to what's actually present. [length]
  // is in SAMPLES; a 16-bit sample is 2 bytes each. Normalize to [-1, 1] float
  // (unified with the XM/IT readers): 8-bit /128, 16-bit /32768.
  final bytesPerSample = sixteenBit ? 2 : 1;
  var available = length;
  if (pcmOffset < 0 || pcmOffset >= bytes.length) {
    available = 0;
  } else if (pcmOffset + available * bytesPerSample > bytes.length) {
    available = (bytes.length - pcmOffset) ~/ bytesPerSample;
  }
  final pcm = Float64List(available);
  for (var i = 0; i < available; i++) {
    if (sixteenBit) {
      final lo = bytes[pcmOffset + i * 2];
      final hi = bytes[pcmOffset + i * 2 + 1];
      final w = lo | (hi << 8);
      final s = unsigned ? w - 32768 : (w >= 32768 ? w - 65536 : w);
      pcm[i] = s / 32768.0;
    } else {
      final b = bytes[pcmOffset + i];
      final s = unsigned ? b - 128 : (b >= 128 ? b - 256 : b);
      pcm[i] = s / 128.0;
    }
  }

  return S3mSample(
    name: name,
    volume: volume,
    c2spd: c2spd == 0 ? 8363 : c2spd,
    loopStart: loopBegin,
    loopEnd: loopEnd,
    loop: loop,
    sixteenBit: sixteenBit,
    pcm: pcm,
    rawHeader: List<int>.from(bytes.sublist(base, base + 0x50)),
    rawData: pcmOffset >= 0 &&
            pcmOffset + available * bytesPerSample <= bytes.length
        ? Uint8List.fromList(
            bytes.sublist(pcmOffset, pcmOffset + available * bytesPerSample))
        : null,
  );
}

S3mPattern _readPattern(
  Uint8List bytes,
  ByteData data,
  int base,
  int channelCount,
) {
  final rows = List.generate(
    _rowsPerPattern,
    (_) => List<S3mCell>.filled(channelCount, S3mCell.empty),
    growable: false,
  );

  // Guard the 2-byte packed-length prefix.
  if (base < 0 || base + 2 > bytes.length) {
    return S3mPattern(rows);
  }
  final packedLen = data.getUint16(base, Endian.little);
  // Data body starts after the length word; end is bounded by both the declared
  // length and the actual file size.
  var end = base + packedLen;
  if (packedLen < 2 || end > bytes.length) end = bytes.length;

  var pos = base + 2;
  var row = 0;
  while (row < _rowsPerPattern && pos < end) {
    final what = bytes[pos++];
    if (what == 0x00) {
      row++;
      continue;
    }
    final channel = what & 0x1F;

    int? note, instrument, volume, command, info;
    if ((what & 0x20) != 0) {
      if (pos + 2 > end) break;
      note = bytes[pos++];
      instrument = bytes[pos++];
    }
    if ((what & 0x40) != 0) {
      if (pos + 1 > end) break;
      volume = bytes[pos++];
    }
    if ((what & 0x80) != 0) {
      if (pos + 2 > end) break;
      command = bytes[pos++];
      info = bytes[pos++];
    }

    if (channel < channelCount) {
      rows[row][channel] = S3mCell(
        note: note ?? S3mCell.emptyNote,
        instrument: instrument ?? 0,
        volume: volume ?? S3mCell.noVolume,
        command: command ?? 0,
        info: info ?? 0,
      );
    }
  }

  return S3mPattern(
    rows,
    rawData: base >= 0 && base + packedLen <= bytes.length
        ? Uint8List.fromList(bytes.sublist(base, base + packedLen))
        : null,
  );
}

S3mPattern _emptyPattern(int channelCount) => S3mPattern(
      List.generate(
        _rowsPerPattern,
        (_) => List<S3mCell>.filled(channelCount, S3mCell.empty),
        growable: false,
      ),
    );

/// Reads an ASCII string from [bytes] at [start], up to [maxLen] bytes, stopping
/// at the first NUL. Non-printable trailing bytes are trimmed.
String _readAsciiz(Uint8List bytes, int start, int maxLen) {
  final sb = StringBuffer();
  for (var i = 0; i < maxLen; i++) {
    final off = start + i;
    if (off >= bytes.length) break;
    final b = bytes[off];
    if (b == 0) break;
    sb.writeCharCode(b);
  }
  return sb.toString().trimRight();
}
