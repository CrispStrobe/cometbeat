// Pulls the individual samples out of a container the user supplies: either a
// tracker module (.mod/.xm/.s3m/.it) or a sample-pack archive
// (.zip/.7z/.tar and its gz/bz2/xz variants).
//
// A module bundles its instrument samples as raw PCM; the app already decodes
// every format to a common `ModuleDoc` (normalized float PCM + per-sample
// name + C-5 playback rate). This just surfaces those as standalone clips so a
// user's OWN module files can feed the sample library / the Labs. It reads the
// public `parseAnyModule` — it does not touch the module codecs.
//
// Archives go through `package:archive` (MIT, pure Dart — so this works on web
// too) for zip/tar/gz/bz2/xz, and through our own pure-Dart `sevenz_reader`
// for .7z (which `package:archive` has no codec for) — the format real
// Freepats sample packs ship in.
//
// (Legality note: this extracts from a file the user supplies, exactly like
// importing a WAV — no redistribution. Whether a given module's or pack's
// samples are free to reuse is the user's call; the app makes no claim.)

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:comet_beat/core/archive/sevenz_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';

/// One sample lifted from a module or sample pack.
class ExtractedSample {
  const ExtractedSample({
    required this.name,
    required this.sampleRate,
    required this.pcm,
    required this.sourceFile,
    required this.index,
  });

  final String name;
  final int sampleRate;
  final Float64List pcm;

  /// The containing file this came from — a module's title/filename, or the
  /// name of the sample pack archive.
  final String sourceFile;
  final int index; // 1-based slot within the module

  /// A library entry for this sample (name prefixed with the module).
  SampleClip toClip() => SampleClip(
        name: '$sourceFile – $displayName',
        sampleRate: sampleRate,
        pcm: pcm,
        source: sourceFile,
      );

  /// A non-empty display label (falls back to the slot number).
  String get displayName => name.trim().isEmpty ? 'sample $index' : name.trim();
}

/// Sanitizes [name] into a filesystem-safe base (no extension).
String safeSampleFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
  return cleaned.isEmpty ? 'sample' : cleaned;
}

/// Turns display names into unique `.wav` filenames: sanitized, and any
/// collision disambiguated with a `-2`, `-3`, … suffix. Order-preserving.
List<String> uniqueWavNames(Iterable<String> displayNames) {
  final used = <String>{};
  final out = <String>[];
  for (final n in displayNames) {
    final base = safeSampleFileName(n);
    var candidate = base;
    var k = 2;
    while (!used.add('$candidate.wav')) {
      candidate = '$base-${k++}';
    }
    out.add('$candidate.wav');
  }
  return out;
}

/// True if [bytes] starts with the 7-Zip signature.
bool isSevenZip(Uint8List bytes) => isSevenZArchive(bytes);

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

/// True if [bytes] looks like an archive container we can open.
bool looksLikeArchive(Uint8List bytes) =>
    _startsWith(bytes, const [0x50, 0x4B]) || // Zip "PK"
    _startsWith(bytes, const [0x1F, 0x8B]) || // GZip
    _startsWith(bytes, const [0xFD, 0x37, 0x7A, 0x58, 0x5A]) || // XZ
    _startsWith(bytes, const [0x42, 0x5A, 0x68]) || // BZip2 "BZh"
    isSevenZip(bytes);

/// Opens a sample-pack archive, transparently un-wrapping a compressed tar.
/// (.7z is handled separately by [extractArchiveSamples] — our own reader.)
Archive _openArchive(Uint8List bytes) {
  try {
    if (_startsWith(bytes, const [0x50, 0x4B])) {
      return ZipDecoder().decodeBytes(bytes);
    }
    if (_startsWith(bytes, const [0x1F, 0x8B])) {
      return TarDecoder().decodeBytes(const GZipDecoder().decodeBytes(bytes));
    }
    if (_startsWith(bytes, const [0xFD, 0x37, 0x7A, 0x58, 0x5A])) {
      return TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
    }
    if (_startsWith(bytes, const [0x42, 0x5A, 0x68])) {
      return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
    }
    return TarDecoder().decodeBytes(bytes); // uncompressed tar
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Could not read the archive: $e');
  }
}

/// Extracts every decodable WAV from a sample-pack archive. Entries that
/// aren't WAVs — or are WAVs in an encoding we can't read — are skipped, so
/// one odd file never sinks the whole pack. Throws [FormatException] if the
/// container itself can't be opened.
List<ExtractedSample> extractArchiveSamples(
  Uint8List bytes, {
  String sourceFile = 'pack',
}) {
  // .7z goes through our own pure-Dart reader; everything else through
  // package:archive. Both yield (name, bytes) pairs we treat identically.
  final entries = <(String, Uint8List)>[];
  if (isSevenZip(bytes)) {
    for (final e in readSevenZ(bytes).entries) {
      if (!e.isDirectory) entries.add((e.name, e.content));
    }
  } else {
    for (final e in _openArchive(bytes)) {
      if (!e.isFile) continue;
      final data = e.readBytes();
      if (data != null && data.isNotEmpty) entries.add((e.name, data));
    }
  }

  final out = <ExtractedSample>[];
  for (final (name, data) in entries) {
    if (!name.toLowerCase().endsWith('.wav')) continue;
    if (data.isEmpty) continue;
    try {
      final wav = readWavPcm16(data);
      final pcm = wavToMonoFloat(wav);
      if (pcm.isEmpty) continue;
      out.add(
        ExtractedSample(
          name: _entryName(name),
          sampleRate: wav.sampleRate > 0 ? wav.sampleRate : _kDefaultC5Speed,
          pcm: pcm,
          sourceFile: sourceFile,
          index: out.length + 1,
        ),
      );
    } catch (_) {
      continue; // unreadable entry — skip, keep the rest of the pack
    }
  }
  return out;
}

/// The bare filename of an archive entry path, without its `.wav` extension.
String _entryName(String path) {
  final slash = path.lastIndexOf('/');
  final file = slash >= 0 ? path.substring(slash + 1) : path;
  return file.length > 4 ? file.substring(0, file.length - 4) : file;
}

/// The C-5 reference rate a tracker sample plays at when no rate is stored.
const _kDefaultC5Speed = 8363;

/// Extracts every non-empty sample from [bytes]. [sourceFile] labels the source
/// (use the filename). Throws [FormatException] on unrecognized/corrupt input
/// (from `parseAnyModule`) — callers should catch per-file in a batch.
List<ExtractedSample> extractModuleSamples(
  Uint8List bytes, {
  String sourceFile = 'module',
}) {
  final doc = parseAnyModule(bytes);
  final out = <ExtractedSample>[];
  for (var i = 0; i < doc.samples.length; i++) {
    final s = doc.samples[i];
    if (s.pcm.isEmpty) continue; // empty slots are placeholders, not sounds
    out.add(
      ExtractedSample(
        name: s.name,
        sampleRate: s.c5speed > 0 ? s.c5speed : _kDefaultC5Speed,
        pcm: s.pcm,
        sourceFile: sourceFile,
        index: i + 1,
      ),
    );
  }
  return out;
}
