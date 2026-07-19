// A pure-Dart 7-Zip (.7z) READER.
//
// Why this exists: sample libraries (Freepats and most of the open sample-pack
// world) ship .7z, but `package:archive` has no 7z container — it only reaches
// LZMA through XZ. It DOES, however, publicly export the hard part: a complete
// `LzmaDecoder` + `RangeDecoder`. So this file is just the container layer on
// top of that — no range coder, no entropy decoding of our own.
//
// Scope (deliberately narrow, because this parses UNTRUSTED input):
//   • Coders: Copy (00), LZMA1 (03 01 01), LZMA2 (21), BZip2 (04 02 02),
//     Deflate (04 01 08), and the Delta filter (03)
//   • Linear 1-in/1-out coder CHAINS, e.g. the `Delta:2 + BZip2` that real
//     Freepats sample packs use (found by running this against one)
//   • Refused with a typed [SevenZUnsupported]: AES-256, BCJ2 (4-in),
//     PPMd, and multi-packed-stream folders — we say what we hit rather
//     than silently returning garbage.
// Everything is bounds-checked and every malformed field raises
// [SevenZFormatException] rather than a raw RangeError.
//
// Format reference: the 7z header is a tagged, variable-length structure whose
// own header may itself be LZMA-compressed (kEncodedHeader) — so parsing is
// two-pass: decode the encoded header into bytes, then re-parse those.

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The archive is malformed / truncated.
class SevenZFormatException extends FormatException {
  const SevenZFormatException(super.message);
}

/// The archive is well-formed but uses a feature this reader doesn't implement.
class SevenZUnsupported extends FormatException {
  const SevenZUnsupported(super.message);
}

/// One file inside a .7z.
class SevenZEntry {
  SevenZEntry({
    required this.name,
    required this.isDirectory,
    required this.content,
  });

  final String name;
  final bool isDirectory;

  /// Fully decompressed bytes (empty for a directory / empty file).
  final Uint8List content;

  int get size => content.length;
}

/// The 7-Zip signature: `7z¼¯' `.
const _kSignature = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C];

/// True if [bytes] begins with the 7-Zip signature.
bool isSevenZArchive(Uint8List bytes) {
  if (bytes.length < _kSignature.length) return false;
  for (var i = 0; i < _kSignature.length; i++) {
    if (bytes[i] != _kSignature[i]) return false;
  }
  return true;
}

// Property ids from the 7z spec.
const _kEnd = 0x00;
const _kHeader = 0x01;
const _kArchiveProperties = 0x02;
const _kAdditionalStreamsInfo = 0x03;
const _kMainStreamsInfo = 0x04;
const _kFilesInfo = 0x05;
const _kPackInfo = 0x06;
const _kUnPackInfo = 0x07;
const _kSubStreamsInfo = 0x08;
const _kSize = 0x09;
const _kCrc = 0x0A;
const _kFolder = 0x0B;
const _kCodersUnPackSize = 0x0C;
const _kNumUnPackStream = 0x0D;
const _kEmptyStream = 0x0E;
const _kEmptyFile = 0x0F;
const _kAnti = 0x10;
const _kName = 0x11;
const _kEncodedHeader = 0x17;
const _kDummy = 0x19;

/// Reads a .7z archive and fully decompresses its entries.
///
/// Throws [SevenZFormatException] on malformed input and [SevenZUnsupported]
/// for archives using features outside this reader's scope (both are
/// [FormatException]s, so a single catch covers them).
SevenZArchive readSevenZ(Uint8List bytes) {
  if (!isSevenZArchive(bytes)) {
    throw const SevenZFormatException('Not a 7z archive');
  }
  if (bytes.length < 32) {
    throw const SevenZFormatException('Truncated 7z signature header');
  }
  final head = ByteData.sublistView(bytes);
  // 0..5 magic · 6,7 version · 8..11 startHeaderCRC · then the start header:
  final nextHeaderOffset = head.getUint64(12, Endian.little);
  final nextHeaderSize = head.getUint64(20, Endian.little);

  if (nextHeaderSize == 0) return const SevenZArchive([]); // empty archive
  final start = 32 + nextHeaderOffset;
  if (start < 32 || start + nextHeaderSize > bytes.length) {
    throw const SevenZFormatException('7z header runs past end of file');
  }
  var header = Uint8List.sublistView(
    bytes,
    start,
    start + nextHeaderSize,
  );

  var reader = _ByteReader(header);
  var id = reader.readByte();

  // The header itself may be compressed; decode it, then parse the result.
  if (id == _kEncodedHeader) {
    final streams = _readStreamsInfo(reader);
    final decoded = _decodeFolders(bytes, streams);
    if (decoded.isEmpty) {
      throw const SevenZFormatException('Encoded header decoded to nothing');
    }
    header = decoded.first;
    reader = _ByteReader(header);
    id = reader.readByte();
  }

  if (id == _kEnd) return const SevenZArchive([]);
  if (id != _kHeader) {
    throw SevenZFormatException('Unexpected 7z header id 0x${_hex(id)}');
  }
  return _readHeader(reader, bytes);
}

/// A parsed .7z.
class SevenZArchive {
  const SevenZArchive(this.entries);
  final List<SevenZEntry> entries;
}

// ── Header ─────────────────────────────────────────────────────────────────

SevenZArchive _readHeader(_ByteReader r, Uint8List raw) {
  var id = r.readByte();

  if (id == _kArchiveProperties) {
    while (true) {
      final propType = r.readByte();
      if (propType == _kEnd) break;
      r.skip(r.readNumber());
    }
    id = r.readByte();
  }
  if (id == _kAdditionalStreamsInfo) {
    throw const SevenZUnsupported('7z additional streams are not supported');
  }

  _StreamsInfo? streams;
  if (id == _kMainStreamsInfo) {
    streams = _readStreamsInfo(r);
    id = r.readByte();
  }

  // Decompress every folder up-front; substreams then slice into these.
  final folderData =
      streams == null ? const <Uint8List>[] : _decodeFolders(raw, streams);
  final contents = streams == null
      ? const <Uint8List>[]
      : _sliceSubStreams(streams, folderData);

  if (id != _kFilesInfo) {
    // No FilesInfo: expose the streams positionally.
    return SevenZArchive([
      for (var i = 0; i < contents.length; i++)
        SevenZEntry(
          name: 'stream$i',
          isDirectory: false,
          content: contents[i],
        ),
    ]);
  }
  return _readFilesInfo(r, contents);
}

SevenZArchive _readFilesInfo(_ByteReader r, List<Uint8List> contents) {
  final numFiles = r.readNumber();
  if (numFiles < 0 || numFiles > 1 << 22) {
    throw const SevenZFormatException('Implausible 7z file count');
  }
  var emptyStream = List<bool>.filled(numFiles, false);
  var emptyFile = <bool>[];
  var anti = <bool>[];
  List<String>? names;

  while (true) {
    final propType = r.readByte();
    if (propType == _kEnd) break;
    final size = r.readNumber();
    final end = r.offset + size;
    if (size < 0 || end > r.length) {
      throw const SevenZFormatException('7z FilesInfo property overruns');
    }
    switch (propType) {
      case _kEmptyStream:
        emptyStream = r.readBitVector(numFiles);
      case _kEmptyFile:
        emptyFile = r.readBitVector(emptyStream.where((e) => e).length);
      case _kAnti:
        anti = r.readBitVector(emptyStream.where((e) => e).length);
      case _kName:
        if (r.readByte() != 0) {
          throw const SevenZUnsupported('7z external file names');
        }
        names = r.readUtf16Names(end, numFiles);
      case _kDummy:
      default:
        // Timestamps, attributes, start positions… not needed to extract.
        break;
    }
    r.seek(end); // always resync to the declared property end
  }

  final entries = <SevenZEntry>[];
  var streamIndex = 0;
  var emptyIndex = 0;
  for (var i = 0; i < numFiles; i++) {
    final name = (names != null && i < names.length) ? names[i] : 'file$i';
    if (!emptyStream[i]) {
      if (streamIndex >= contents.length) {
        throw const SevenZFormatException('7z: more files than streams');
      }
      entries.add(
        SevenZEntry(
          name: name,
          isDirectory: false,
          content: contents[streamIndex++],
        ),
      );
    } else {
      // An empty stream is a directory unless flagged as an empty FILE.
      final isFile =
          emptyIndex < emptyFile.length ? emptyFile[emptyIndex] : false;
      final isAnti = emptyIndex < anti.length ? anti[emptyIndex] : false;
      emptyIndex++;
      if (isAnti) continue; // deletion marker, not real content
      entries.add(
        SevenZEntry(
          name: name,
          isDirectory: !isFile,
          content: Uint8List(0),
        ),
      );
    }
  }
  return SevenZArchive(entries);
}

// ── StreamsInfo ────────────────────────────────────────────────────────────

class _StreamsInfo {
  int packPos = 0;
  List<int> packSizes = const [];
  List<_Folder> folders = const [];

  /// Per folder: how many substreams it holds.
  List<int> numUnpackStreams = const [];

  /// Per substream (flattened) unpacked sizes.
  List<int> subStreamSizes = const [];
}

class _Coder {
  _Coder(this.id, this.props);
  final List<int> id;
  final Uint8List props;
}

/// `inIndex` consumes the output produced at `outIndex`.
class _BindPair {
  _BindPair(this.inIndex, this.outIndex);
  final int inIndex;
  final int outIndex;
}

class _Folder {
  _Folder(this.coders, this.bindPairs, this.numPackStreams);
  final List<_Coder> coders;
  final List<_BindPair> bindPairs;
  final int numPackStreams;

  /// One unpacked size per coder output (filled from kCodersUnPackSize).
  List<int> unpackSizes = const [];

  /// The coder whose output nothing else consumes — the folder's result.
  int get finalOutIndex {
    for (var i = 0; i < coders.length; i++) {
      if (!bindPairs.any((b) => b.outIndex == i)) return i;
    }
    throw const SevenZFormatException('7z folder has no final output stream');
  }

  /// The coder fed by the packed stream (its input isn't bound to an output).
  int get packedInIndex {
    for (var i = 0; i < coders.length; i++) {
      if (!bindPairs.any((b) => b.inIndex == i)) return i;
    }
    throw const SevenZFormatException('7z folder has no packed input stream');
  }

  int get unpackSize =>
      finalOutIndex < unpackSizes.length ? unpackSizes[finalOutIndex] : 0;
}

_StreamsInfo _readStreamsInfo(_ByteReader r) {
  final info = _StreamsInfo();
  var id = r.readByte();

  if (id == _kPackInfo) {
    info.packPos = r.readNumber();
    final numPackStreams = r.readNumber();
    var t = r.readByte();
    while (t != _kEnd) {
      if (t == _kSize) {
        info.packSizes = [
          for (var i = 0; i < numPackStreams; i++) r.readNumber(),
        ];
      } else if (t == _kCrc) {
        _skipDigests(r, numPackStreams);
      } else {
        throw SevenZFormatException('Bad 7z PackInfo id 0x${_hex(t)}');
      }
      t = r.readByte();
    }
    id = r.readByte();
  }

  if (id == _kUnPackInfo) {
    if (r.readByte() != _kFolder) {
      throw const SevenZFormatException('Expected 7z kFolder');
    }
    final numFolders = r.readNumber();
    if (r.readByte() != 0) {
      throw const SevenZUnsupported('7z external folder definitions');
    }
    final folders = <_Folder>[];
    for (var i = 0; i < numFolders; i++) {
      folders.add(_readFolder(r));
    }
    if (r.readByte() != _kCodersUnPackSize) {
      throw const SevenZFormatException('Expected 7z kCodersUnPackSize');
    }
    for (final folder in folders) {
      // One size per output stream; our chains are 1-out per coder.
      folder.unpackSizes = [
        for (var i = 0; i < folder.coders.length; i++) r.readNumber(),
      ];
    }
    var t = r.readByte();
    while (t != _kEnd) {
      if (t == _kCrc) {
        _skipDigests(r, folders.length);
      } else {
        throw SevenZFormatException('Bad 7z UnPackInfo id 0x${_hex(t)}');
      }
      t = r.readByte();
    }
    info.folders = folders;
    id = r.readByte();
  }

  info.numUnpackStreams = [for (final _ in info.folders) 1];

  if (id == _kSubStreamsInfo) {
    var t = r.readByte();
    if (t == _kNumUnPackStream) {
      info.numUnpackStreams = [
        for (var i = 0; i < info.folders.length; i++) r.readNumber(),
      ];
      t = r.readByte();
    }
    final sizes = <int>[];
    // Sizes are stored for all but the LAST substream of each folder, which
    // is implied by the folder's total.
    if (t == _kSize) {
      for (var f = 0; f < info.folders.length; f++) {
        final n = info.numUnpackStreams[f];
        if (n == 0) continue;
        var sum = 0;
        for (var i = 0; i < n - 1; i++) {
          final s = r.readNumber();
          sum += s;
          sizes.add(s);
        }
        sizes.add(info.folders[f].unpackSize - sum);
      }
      t = r.readByte();
    } else {
      for (var f = 0; f < info.folders.length; f++) {
        final n = info.numUnpackStreams[f];
        if (n == 1) sizes.add(info.folders[f].unpackSize);
      }
    }
    while (t != _kEnd) {
      if (t == _kCrc) {
        _skipDigests(r, sizes.length);
      } else {
        throw SevenZFormatException('Bad 7z SubStreamsInfo id 0x${_hex(t)}');
      }
      t = r.readByte();
    }
    info.subStreamSizes = sizes;
    id = r.readByte();
  } else {
    info.subStreamSizes = [for (final f in info.folders) f.unpackSize];
  }

  if (id != _kEnd) {
    throw SevenZFormatException('Unexpected 7z StreamsInfo id 0x${_hex(id)}');
  }
  return info;
}

_Folder _readFolder(_ByteReader r) {
  final numCoders = r.readNumber();
  if (numCoders < 1 || numCoders > 8) {
    throw SevenZFormatException('Implausible 7z coder count $numCoders');
  }
  final coders = <_Coder>[];
  var totalIn = 0;
  var totalOut = 0;
  for (var i = 0; i < numCoders; i++) {
    final flags = r.readByte();
    final idSize = flags & 0x0F;
    final isComplex = (flags & 0x10) != 0;
    final hasAttributes = (flags & 0x20) != 0;
    final id = r.readBytes(idSize);

    var numIn = 1;
    var numOut = 1;
    if (isComplex) {
      numIn = r.readNumber();
      numOut = r.readNumber();
      // A chain is linear here; BCJ2 (4-in/1-out) is refused at decode time.
      if (numIn != 1 || numOut != 1) {
        throw SevenZUnsupported(
          '7z coder ${_idHex(id)} has $numIn in / $numOut out streams '
          '(only linear 1-in/1-out chains are supported)',
        );
      }
    }
    totalIn += numIn;
    totalOut += numOut;
    var props = Uint8List(0);
    if (hasAttributes) {
      props = r.readBytes(r.readNumber());
    }
    coders.add(_Coder(id, props));
  }

  final numBindPairs = totalOut - 1;
  final bindPairs = <_BindPair>[];
  for (var i = 0; i < numBindPairs; i++) {
    bindPairs.add(_BindPair(r.readNumber(), r.readNumber()));
  }

  final numPackStreams = totalIn - numBindPairs;
  if (numPackStreams > 1) {
    // Which in-streams the packed data feeds; only single-packed chains are
    // supported, so this would already have been refused above.
    for (var i = 0; i < numPackStreams; i++) {
      r.readNumber();
    }
    throw const SevenZUnsupported(
      '7z folders with multiple packed streams are not supported',
    );
  }
  return _Folder(coders, bindPairs, numPackStreams);
}

void _skipDigests(_ByteReader r, int count) {
  final allDefined = r.readByte();
  final defined =
      allDefined != 0 ? List<bool>.filled(count, true) : r.readBitVector(count);
  for (final d in defined) {
    if (d) r.skip(4);
  }
}

// ── Decoding ───────────────────────────────────────────────────────────────

/// Decompresses each folder into one contiguous buffer.
List<Uint8List> _decodeFolders(Uint8List raw, _StreamsInfo info) {
  final out = <Uint8List>[];
  // Pack streams are laid out consecutively from 32 + packPos.
  var packOffset = 32 + info.packPos;
  var packIndex = 0;
  for (final folder in info.folders) {
    var packed = 0;
    for (var i = 0; i < folder.numPackStreams; i++) {
      if (packIndex >= info.packSizes.length) {
        throw const SevenZFormatException('7z pack stream index out of range');
      }
      packed += info.packSizes[packIndex++];
    }
    if (packOffset < 0 || packOffset + packed > raw.length) {
      throw const SevenZFormatException('7z packed stream runs past EOF');
    }
    final input = Uint8List.sublistView(raw, packOffset, packOffset + packed);
    out.add(_decodeFolder(folder, input));
    packOffset += packed;
  }
  return out;
}

/// Runs the folder's coder chain: the packed bytes enter at [packedInIndex],
/// and each coder's output feeds whichever coder is bound to it, until we
/// reach the output nothing consumes.
Uint8List _decodeFolder(_Folder folder, Uint8List packed) {
  var data = packed;
  var current = folder.packedInIndex;
  final visited = <int>{};
  while (true) {
    if (!visited.add(current)) {
      throw const SevenZFormatException('7z coder chain contains a cycle');
    }
    final size =
        current < folder.unpackSizes.length ? folder.unpackSizes[current] : 0;
    data = _runCoder(folder.coders[current], data, size);
    final next = folder.bindPairs.where((b) => b.outIndex == current);
    if (next.isEmpty) return data; // nothing consumes this — it's the result
    current = next.first.inIndex;
    if (current < 0 || current >= folder.coders.length) {
      throw const SevenZFormatException('7z bind pair index out of range');
    }
  }
}

Uint8List _runCoder(_Coder coder, Uint8List input, int unpackSize) {
  final id = coder.id;
  if (_idIs(id, const [0x00])) return Uint8List.fromList(input); // Copy
  if (_idIs(id, const [0x21])) return _decodeLzma2(input, unpackSize);
  if (_idIs(id, const [0x03, 0x01, 0x01])) {
    return _decodeLzma1(input, coder.props, unpackSize);
  }
  if (_idIs(id, const [0x04, 0x02, 0x02])) {
    return BZip2Decoder().decodeBytes(input);
  }
  if (_idIs(id, const [0x04, 0x01, 0x08])) {
    return Inflate(input, uncompressedSize: unpackSize).getBytes();
  }
  if (_idIs(id, const [0x03])) return _decodeDelta(input, coder.props);
  throw SevenZUnsupported(
    '7z coder ${_idHex(id)} is not supported${_hint(id)}',
  );
}

/// The Delta filter: the encoder stored `x[i] - x[i-distance]`, so decoding is
/// a running sum. Very common in front of audio data (Freepats uses Delta:2).
Uint8List _decodeDelta(Uint8List input, Uint8List props) {
  final distance = (props.isEmpty ? 0 : props[0]) + 1;
  if (distance < 1 || distance > 256) {
    throw const SevenZFormatException('7z Delta distance out of range');
  }
  final out = Uint8List.fromList(input);
  for (var i = distance; i < out.length; i++) {
    out[i] = (out[i] + out[i - distance]) & 0xFF;
  }
  return out;
}

String _hint(List<int> id) {
  if (_idIs(id, const [0x06, 0xF1, 0x07, 0x01])) return ' (AES-256 encrypted)';
  if (_idIs(id, const [0x03, 0x04, 0x01])) return ' (PPMd)';
  if (_idIs(id, const [0x03, 0x03, 0x01, 0x1B])) return ' (BCJ2)';
  if (id.length == 1 && id[0] == 0x03) return ' (Delta filter)';
  return '';
}

/// LZMA1: 5 property bytes (packed lc/lp/pb + dictionary size).
Uint8List _decodeLzma1(Uint8List packed, Uint8List props, int unpackSize) {
  if (props.length < 5) {
    throw const SevenZFormatException('7z LZMA1 needs 5 property bytes');
  }
  var d = props[0];
  if (d >= 9 * 5 * 5) {
    throw const SevenZFormatException('7z LZMA1 property byte out of range');
  }
  final lc = d % 9;
  d ~/= 9;
  final lp = d % 5;
  final pb = d ~/ 5;

  final decoder = LzmaDecoder()
    ..reset(
      literalContextBits: lc,
      literalPositionBits: lp,
      positionBits: pb,
      resetDictionary: true,
    );
  return decoder.decode(InputMemoryStream(packed), unpackSize);
}

/// LZMA2: a chunk stream over the same LZMA decoder. Mirrors the framing that
/// `package:archive`'s XZ decoder uses to drive `LzmaDecoder`.
Uint8List _decodeLzma2(Uint8List packed, int unpackSize) {
  final input = InputMemoryStream(packed);
  final output = OutputMemoryStream();
  final decoder = LzmaDecoder();

  while (!input.isEOS) {
    final control = input.readByte();
    if (control == 0) break; // end marker
    if (control & 0x80 == 0) {
      if (control > 2) {
        throw SevenZFormatException(
          'Bad LZMA2 control byte 0x${_hex(control)}',
        );
      }
      // 1 = dict reset + uncompressed chunk, 2 = uncompressed chunk
      final length = (input.readByte() << 8 | input.readByte()) + 1;
      if (control == 1) {
        output.writeBytes(input.readBytes(length).toUint8List());
      } else {
        output.writeBytes(
          decoder.decodeUncompressed(input.readBytes(length), length),
        );
      }
    } else {
      final reset = (control >> 5) & 0x3;
      final chunkUnpacked =
          ((control & 0x1f) << 16 | input.readByte() << 8 | input.readByte()) +
              1;
      final chunkPacked = (input.readByte() << 8 | input.readByte()) + 1;
      int? lc, lp, pb;
      if (reset >= 2) {
        var properties = input.readByte();
        pb = properties ~/ 45;
        properties -= pb * 45;
        lp = properties ~/ 9;
        lc = properties - lp * 9;
      }
      if (reset > 0) {
        decoder.reset(
          literalContextBits: lc,
          literalPositionBits: lp,
          positionBits: pb,
          resetDictionary: reset == 3,
        );
      }
      output.writeBytes(
        decoder.decode(input.readBytes(chunkPacked), chunkUnpacked),
      );
    }
  }
  final bytes = output.getBytes();
  if (unpackSize > 0 && bytes.length != unpackSize) {
    throw SevenZFormatException(
      '7z LZMA2 produced ${bytes.length} bytes, expected $unpackSize',
    );
  }
  return bytes;
}

/// Cuts each folder's buffer into its substreams.
List<Uint8List> _sliceSubStreams(_StreamsInfo info, List<Uint8List> folders) {
  final out = <Uint8List>[];
  var sizeIndex = 0;
  for (var f = 0; f < folders.length; f++) {
    final data = folders[f];
    final n = f < info.numUnpackStreams.length ? info.numUnpackStreams[f] : 1;
    var offset = 0;
    for (var i = 0; i < n; i++) {
      if (sizeIndex >= info.subStreamSizes.length) {
        throw const SevenZFormatException('7z substream size list too short');
      }
      final size = info.subStreamSizes[sizeIndex++];
      if (size < 0 || offset + size > data.length) {
        throw const SevenZFormatException('7z substream overruns its folder');
      }
      out.add(Uint8List.sublistView(data, offset, offset + size));
      offset += size;
    }
  }
  return out;
}

// ── Primitives ─────────────────────────────────────────────────────────────

bool _idIs(List<int> id, List<int> want) {
  if (id.length != want.length) return false;
  for (var i = 0; i < id.length; i++) {
    if (id[i] != want[i]) return false;
  }
  return true;
}

String _hex(int v) => v.toRadixString(16).padLeft(2, '0');
String _idHex(List<int> id) => id.map(_hex).join();

/// A bounds-checked cursor over the header bytes. Every overrun becomes a
/// [SevenZFormatException] — this parses untrusted input, so a raw RangeError
/// escaping would be a bug.
class _ByteReader {
  _ByteReader(this._bytes);
  final Uint8List _bytes;
  int offset = 0;

  int get length => _bytes.length;

  void _need(int n) {
    if (n < 0 || offset + n > _bytes.length) {
      throw const SevenZFormatException('Unexpected end of 7z header');
    }
  }

  int readByte() {
    _need(1);
    return _bytes[offset++];
  }

  Uint8List readBytes(int n) {
    _need(n);
    final out = Uint8List.sublistView(_bytes, offset, offset + n);
    offset += n;
    return out;
  }

  void skip(int n) {
    _need(n);
    offset += n;
  }

  void seek(int to) {
    if (to < 0 || to > _bytes.length) {
      throw const SevenZFormatException('7z header seek out of range');
    }
    offset = to;
  }

  /// 7z's variable-length integer: the first byte's high bits say how many
  /// extra little-endian bytes follow, and its low bits are the high part.
  int readNumber() {
    final first = readByte();
    var mask = 0x80;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      if ((first & mask) == 0) {
        final high = first & (mask - 1);
        return value | (high << (i * 8));
      }
      value |= readByte() << (8 * i);
      mask >>= 1;
    }
    return value;
  }

  /// MSB-first bit vector of [count] bits.
  List<bool> readBitVector(int count) {
    if (count < 0 || count > 1 << 24) {
      throw const SevenZFormatException('Implausible 7z bit-vector length');
    }
    final out = List<bool>.filled(count, false);
    var b = 0;
    var mask = 0;
    for (var i = 0; i < count; i++) {
      if (mask == 0) {
        b = readByte();
        mask = 0x80;
      }
      out[i] = (b & mask) != 0;
      mask >>= 1;
    }
    return out;
  }

  /// UTF-16LE, NUL-separated names, up to [end].
  List<String> readUtf16Names(int end, int expected) {
    final names = <String>[];
    final units = <int>[];
    while (offset + 1 < end && names.length < expected) {
      final unit = readByte() | (readByte() << 8);
      if (unit == 0) {
        names.add(String.fromCharCodes(units));
        units.clear();
      } else {
        units.add(unit);
      }
    }
    if (units.isNotEmpty) names.add(String.fromCharCodes(units));
    // 7z stores paths with backslashes on Windows-made archives.
    return [for (final n in names) n.replaceAll(r'\', '/')];
  }
}
