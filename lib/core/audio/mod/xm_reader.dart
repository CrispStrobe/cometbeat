// lib/core/audio/mod/xm_reader.dart
//
// FastTracker 2 `.xm` IMPORT (reader): raw bytes → [XmModule]. Pure Dart.
// Implement against the byte-layout contract in xm_module.dart.
//
// Contract:
//   • Verify "Extended Module: " at 0x00 (else throw [XmFormatException]); read
//     the header (name, header size → pattern start = 0x3C + headerSize;
//     song length, numChannels, numPatterns, numInstruments, tempo/bpm, order).
//   • Patterns (back to back from the pattern start): 4 headerLen + 1 packType +
//     2 numRows + 2 packedSize + packed data. Unpack the mask scheme (bit0 note,
//     bit1 instrument, bit2 volume, bit3 effect, bit4 param; a byte with the high
//     bit clear IS the note with all five fields following). numChannels cells
//     per row, numRows rows. If packedSize == 0, the pattern is all-empty.
//   • Instruments (back to back after the patterns): 4 instrumentHeaderSize +
//     22 name + 1 type + 2 numSamples. Sample headers start at (instrumentStart +
//     instrumentHeaderSize) — SKIP the envelope block by jumping there. Read
//     numSamples × 40-byte headers, then the concatenated sample data.
//   • Sample data is DELTA-encoded: 8-bit → running sum of signed bytes; 16-bit
//     (type bit4) → running sum of signed 16-bit LE words. Decode to raw, then
//     NORMALIZE (8-bit /128, 16-bit /32768) into XmSample.pcm (Float64List).
//   • Be robust to truncation (short pattern / sample data → empty/partial).
//
// Verify against test/xm_codec_test.dart (a hand-authored golden oracle +, when
// present, a real test/fixtures/*.xm).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/xm_module.dart';

const String _kSignature = 'Extended Module: ';
const int _kFixedHeaderSize = 0x150;

/// Reads a NUL-terminated ASCII string from [bytes] in `[start, end)`, trimmed.
String _readName(Uint8List bytes, int start, int end) {
  if (start >= bytes.length) return '';
  final limit = end < bytes.length ? end : bytes.length;
  final buf = StringBuffer();
  for (var i = start; i < limit; i++) {
    final b = bytes[i];
    if (b == 0) break;
    buf.writeCharCode(b);
  }
  return buf.toString().trim();
}

/// Parses FastTracker 2 `.xm` [bytes] into an [XmModule].
XmModule parseXm(Uint8List bytes) {
  // 1. Signature + minimum length.
  if (bytes.length < _kFixedHeaderSize) {
    throw const XmFormatException('file too short for the fixed XM header');
  }
  for (var i = 0; i < _kSignature.length; i++) {
    if (bytes[i] != _kSignature.codeUnitAt(i)) {
      throw const XmFormatException('bad signature (not "Extended Module: ")');
    }
  }

  final bd = ByteData.sublistView(bytes);
  final len = bytes.length;

  // 2. Header.
  final name = _readName(bytes, 0x11, 0x25);
  final headerSize = bd.getUint32(0x3C, Endian.little);
  final songLength = bd.getUint16(0x40, Endian.little);
  final restart = bd.getUint16(0x42, Endian.little);
  final numChannels = bd.getUint16(0x44, Endian.little);
  final numPatterns = bd.getUint16(0x46, Endian.little);
  final numInstruments = bd.getUint16(0x48, Endian.little);
  final defaultTempo = bd.getUint16(0x4C, Endian.little);
  final defaultBpm = bd.getUint16(0x4E, Endian.little);

  final order = <int>[];
  for (var i = 0; i < songLength; i++) {
    final off = 0x50 + i;
    if (off >= len) break;
    order.add(bytes[off]);
  }

  // 3. Patterns (back to back, from 0x3C + headerSize).
  final patterns = <XmPattern>[];
  var cursor = 0x3C + headerSize;
  for (var p = 0; p < numPatterns; p++) {
    if (cursor + 9 > len) {
      // Truncated: fill remaining patterns as empty.
      patterns.add(const XmPattern([]));
      continue;
    }
    final fieldStart = cursor;
    final patternHeaderLength = bd.getUint32(fieldStart, Endian.little);
    final numRows = bd.getUint16(fieldStart + 5, Endian.little);
    final packedSize = bd.getUint16(fieldStart + 7, Endian.little);

    final dataStart = fieldStart + patternHeaderLength;
    final dataEnd = dataStart + packedSize;

    final rows = _unpackPattern(
      bytes,
      dataStart,
      dataEnd < len ? dataEnd : len,
      numRows,
      numChannels,
      packedSize,
    );
    patterns.add(XmPattern(rows));

    cursor = dataEnd;
  }

  // 4. Instruments (back to back after the last pattern).
  final instruments = <XmInstrument>[];
  var instrumentStart = cursor;
  for (var ins = 0; ins < numInstruments; ins++) {
    if (instrumentStart + 29 > len) {
      instruments.add(const XmInstrument(samples: []));
      continue;
    }
    final instrumentHeaderSize = bd.getUint32(instrumentStart, Endian.little);
    final insName = _readName(bytes, instrumentStart + 4, instrumentStart + 26);
    final numSamples = bd.getUint16(instrumentStart + 27, Endian.little);

    if (numSamples == 0) {
      instruments.add(XmInstrument(name: insName, samples: const []));
      instrumentStart += instrumentHeaderSize;
      continue;
    }

    // Sample headers begin at instrumentStart + instrumentHeaderSize.
    var headerCursor = instrumentStart + instrumentHeaderSize;
    final sampleMeta = <_SampleMeta>[];
    for (var s = 0; s < numSamples; s++) {
      if (headerCursor + 40 > len) break;
      final lengthInBytes = bd.getUint32(headerCursor, Endian.little);
      final loopStart = bd.getUint32(headerCursor + 4, Endian.little);
      final loopLength = bd.getUint32(headerCursor + 8, Endian.little);
      final volume = bytes[headerCursor + 12];
      final finetune = bd.getInt8(headerCursor + 13);
      final type = bytes[headerCursor + 14];
      // panning at +15 (unused here)
      final relativeNote = bd.getInt8(headerCursor + 16);
      // reserved at +17
      final sName = _readName(bytes, headerCursor + 18, headerCursor + 40);
      sampleMeta.add(
        _SampleMeta(
          lengthInBytes: lengthInBytes,
          loopStart: loopStart,
          loopLength: loopLength,
          volume: volume,
          finetune: finetune,
          relativeNote: relativeNote,
          sixteenBit: (type & 0x10) != 0,
          name: sName,
        ),
      );
      headerCursor += 40;
    }

    // Sample data blocks follow immediately, one per header in order.
    var dataCursor = headerCursor;
    final samples = <XmSample>[];
    for (final meta in sampleMeta) {
      final pcm = _decodeSample(bytes, dataCursor, meta, len);
      samples.add(
        XmSample(
          name: meta.name,
          volume: meta.volume,
          finetune: meta.finetune,
          relativeNote: meta.relativeNote,
          loopStart: meta.loopStart,
          loopLength: meta.loopLength,
          sixteenBit: meta.sixteenBit,
          pcm: pcm,
        ),
      );
      dataCursor += meta.lengthInBytes;
    }

    instruments.add(XmInstrument(name: insName, samples: samples));
    instrumentStart = dataCursor;
  }

  return XmModule(
    name: name,
    channelCount: numChannels,
    defaultTempo: defaultTempo,
    defaultBpm: defaultBpm,
    restart: restart,
    order: order,
    patterns: patterns,
    instruments: instruments,
  );
}

/// Unpacks a pattern's packed cell data into [numRows] × [numChannels] cells.
List<List<XmCell>> _unpackPattern(
  Uint8List bytes,
  int start,
  int end,
  int numRows,
  int numChannels,
  int packedSize,
) {
  final rows = <List<XmCell>>[];
  var cursor = start;
  for (var r = 0; r < numRows; r++) {
    final row = <XmCell>[];
    for (var c = 0; c < numChannels; c++) {
      if (packedSize == 0 || cursor >= end) {
        row.add(XmCell.empty);
        continue;
      }
      final b = bytes[cursor++];
      int note = 0, instrument = 0, volume = 0, effect = 0, param = 0;
      if ((b & 0x80) != 0) {
        final mask = b;
        if ((mask & 0x01) != 0 && cursor < end) note = bytes[cursor++];
        if ((mask & 0x02) != 0 && cursor < end) instrument = bytes[cursor++];
        if ((mask & 0x04) != 0 && cursor < end) volume = bytes[cursor++];
        if ((mask & 0x08) != 0 && cursor < end) effect = bytes[cursor++];
        if ((mask & 0x10) != 0 && cursor < end) param = bytes[cursor++];
      } else {
        note = b;
        if (cursor < end) instrument = bytes[cursor++];
        if (cursor < end) volume = bytes[cursor++];
        if (cursor < end) effect = bytes[cursor++];
        if (cursor < end) param = bytes[cursor++];
      }
      row.add(
        XmCell(
          note: note,
          instrument: instrument,
          volume: volume,
          effect: effect,
          effectParam: param,
        ),
      );
    }
    rows.add(row);
  }
  return rows;
}

/// Delta-decodes and normalizes a sample data block starting at [dataStart].
Float64List _decodeSample(
  Uint8List bytes,
  int dataStart,
  _SampleMeta meta,
  int len,
) {
  final lengthInBytes = meta.lengthInBytes;
  final available = dataStart >= len
      ? 0
      : ((dataStart + lengthInBytes <= len) ? lengthInBytes : len - dataStart);

  if (meta.sixteenBit) {
    final count = available ~/ 2;
    final pcm = Float64List(count);
    var running = 0;
    for (var i = 0; i < count; i++) {
      final off = dataStart + i * 2;
      final word = bytes[off] | (bytes[off + 1] << 8);
      running = (running + word) & 0xFFFF;
      final signed = running >= 0x8000 ? running - 0x10000 : running;
      pcm[i] = signed / 32768.0;
    }
    return pcm;
  } else {
    final pcm = Float64List(available);
    var running = 0;
    for (var i = 0; i < available; i++) {
      final b = bytes[dataStart + i];
      running = (running + b) & 0xFF;
      final signed = running >= 0x80 ? running - 0x100 : running;
      pcm[i] = signed / 128.0;
    }
    return pcm;
  }
}

/// Intermediate sample-header data used while parsing an instrument.
class _SampleMeta {
  const _SampleMeta({
    required this.lengthInBytes,
    required this.loopStart,
    required this.loopLength,
    required this.volume,
    required this.finetune,
    required this.relativeNote,
    required this.sixteenBit,
    required this.name,
  });

  final int lengthInBytes;
  final int loopStart, loopLength;
  final int volume, finetune, relativeNote;
  final bool sixteenBit;
  final String name;
}
