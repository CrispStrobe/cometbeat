// lib/core/audio/mod/mod_reader.dart
//
// ProTracker `.mod` IMPORT (reader): raw bytes → [ModModule]. Pure Dart.
// Implement against the byte-layout contract documented in mod_module.dart.
//
// Contract:
//   • Parse the 20-byte title, 31 sample descriptors, song length + restart +
//     128-byte order table, the 4-byte signature (→ channelCount), the patterns
//     (count = max order entry + 1; 64 rows × channelCount × 4 bytes), then the
//     per-sample signed-8-bit PCM.
//   • Convert word lengths (×2) to samples/bytes; decode finetune as a signed
//     4-bit value; decode each cell (sample/period/effect/param) per the spec.
//   • `order` in the result has length = song length (the used positions only).
//   • Throw [ModFormatException] when the input is too short or the signature is
//     not a known MOD tag.
//   • Round-trip: `writeMod(parseMod(bytes))` must reproduce the same
//     [ModModule] (see test/mod_codec_test.dart golden fixtures).

import 'dart:typed_data';

import 'package:klang_universum/core/audio/mod/mod_module.dart';

/// Number of instrument slots in a ProTracker module (always 31 for M.K.).
const int _sampleCount = 31;

/// Parses ProTracker `.mod` [bytes] into a [ModModule].
ModModule parseMod(Uint8List bytes) {
  // Minimum size: title(20) + 31×30 descriptors + length + restart +
  // 128-byte order table + 4-byte signature = 1084 bytes (pattern data + PCM
  // follow but may be absent/truncated on a robust read).
  if (bytes.length < 1084) {
    throw ModFormatException(
      'file too short: ${bytes.length} bytes (need at least 1084)',
    );
  }

  final channelCount = _channelCountFor(_readAscii(bytes, 1080, 4));

  final title = _readAscii(bytes, 0, 20);

  // 31 sample descriptors, 30 bytes each, starting at offset 20. PCM bytes are
  // laid out after the pattern data in the same order; we record each slot's
  // byte length here and slice the PCM in a second pass below.
  final descriptors = <_SampleDescriptor>[];
  for (var i = 0; i < _sampleCount; i++) {
    final base = 20 + i * 30;
    final name = _readAscii(bytes, base, 22);
    final lengthWords = _readU16(bytes, base + 22);
    final finetune = _signedNibble(bytes[base + 24]);
    final volume = bytes[base + 25];
    final repeatPointWords = _readU16(bytes, base + 26);
    final repeatLengthWords = _readU16(bytes, base + 28);
    descriptors.add(
      _SampleDescriptor(
        name: name,
        lengthBytes: lengthWords * 2,
        finetune: finetune,
        volume: volume,
        repeatPoint: repeatPointWords * 2,
        repeatLength: repeatLengthWords * 2,
      ),
    );
  }

  final songLength = bytes[950].clamp(0, 128);
  final restart = bytes[951];

  // Full 128-entry order table drives the pattern count (standard ProTracker
  // behaviour: scan all positions for the highest pattern reference); the
  // returned `order` keeps only the `songLength` used positions.
  var maxPatternRef = 0;
  for (var i = 0; i < 128; i++) {
    final ref = bytes[952 + i];
    if (ref > maxPatternRef) maxPatternRef = ref;
  }
  final patternCount = maxPatternRef + 1;

  final order = List<int>.generate(songLength, (i) => bytes[952 + i]);

  // Pattern data: `patternCount` patterns, each 64 rows × channelCount × 4
  // bytes, starting at offset 1084. Read defensively so a truncated file
  // yields empty cells instead of throwing.
  const patternDataStart = 1084;
  final patterns = <ModPattern>[];
  var cursor = patternDataStart;
  for (var p = 0; p < patternCount; p++) {
    final rows = <List<ModCell>>[];
    for (var row = 0; row < 64; row++) {
      final cells = <ModCell>[];
      for (var ch = 0; ch < channelCount; ch++) {
        cells.add(_readCell(bytes, cursor));
        cursor += 4;
      }
      rows.add(cells);
    }
    patterns.add(ModPattern(rows));
  }

  // PCM immediately follows the pattern data, concatenated in sample order.
  final pcmStart = patternDataStart + patternCount * 64 * channelCount * 4;
  var pcmCursor = pcmStart;
  final samples = <ModSample>[];
  for (final d in descriptors) {
    final available = (bytes.length - pcmCursor).clamp(0, d.lengthBytes);
    final Int8List pcm;
    if (available <= 0) {
      pcm = Int8List(0);
    } else {
      // Reinterpret the unsigned window as signed 8-bit PCM.
      pcm = Int8List.sublistView(bytes, pcmCursor, pcmCursor + available);
    }
    // Advance by the declared length even when truncated, so subsequent
    // samples stay aligned to their declared offsets where bytes remain.
    pcmCursor += d.lengthBytes;
    samples.add(
      ModSample(
        name: d.name,
        volume: d.volume,
        finetune: d.finetune,
        repeatPoint: d.repeatPoint,
        repeatLength: d.repeatLength,
        pcm: pcm,
      ),
    );
  }

  return ModModule(
    title: title,
    channelCount: channelCount,
    restart: restart,
    samples: samples,
    order: order,
    patterns: patterns,
  );
}

/// One 4-byte cell → [ModCell]; out-of-range offsets decode to an empty cell.
ModCell _readCell(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return ModCell.empty;
  final b0 = bytes[offset];
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];
  final b3 = bytes[offset + 3];
  return ModCell(
    sample: (b0 & 0xF0) | (b2 >> 4),
    period: ((b0 & 0x0F) << 8) | b1,
    effect: b2 & 0x0F,
    effectParam: b3,
  );
}

/// Big-endian unsigned 16-bit read.
int _readU16(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

/// Low-nibble signed 4-bit finetune: 0..7 → 0..+7, 8..15 → −8..−1.
int _signedNibble(int byte) {
  final n = byte & 0x0F;
  return n >= 8 ? n - 16 : n;
}

/// Reads a fixed-length NUL-padded ASCII field, trimming at the first NUL.
String _readAscii(Uint8List bytes, int offset, int maxLen) {
  final end = (offset + maxLen).clamp(0, bytes.length);
  final buf = StringBuffer();
  for (var i = offset; i < end; i++) {
    final c = bytes[i];
    if (c == 0) break;
    buf.writeCharCode(c);
  }
  return buf.toString();
}

/// Maps a 4-byte signature tag to a channel count, throwing on unknown tags.
int _channelCountFor(String sig) {
  switch (sig) {
    case 'M.K.':
    case 'M!K!':
    case 'M&K!':
    case 'FLT4':
    case '4CHN':
      return 4;
    case '6CHN':
      return 6;
    case '8CHN':
    case 'OCTA':
    case 'CD81':
    case 'FLT8':
      return 8;
  }
  // Generic "%dCHN" (e.g. 2CHN) and "%dCH" (e.g. 16CH, 32CH) tags.
  final chn = RegExp(r'^(\d)CHN$').firstMatch(sig);
  if (chn != null) return int.parse(chn.group(1)!);
  final ch = RegExp(r'^(\d\d)CH$').firstMatch(sig);
  if (ch != null) return int.parse(ch.group(1)!);
  throw ModFormatException('unrecognized module signature: "$sig"');
}

/// Scratch holder for a sample descriptor before its PCM window is sliced.
class _SampleDescriptor {
  _SampleDescriptor({
    required this.name,
    required this.lengthBytes,
    required this.finetune,
    required this.volume,
    required this.repeatPoint,
    required this.repeatLength,
  });

  final String name;
  final int lengthBytes;
  final int finetune;
  final int volume;
  final int repeatPoint;
  final int repeatLength;
}
