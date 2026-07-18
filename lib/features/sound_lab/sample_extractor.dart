// Pulls the individual samples out of a tracker module (.mod/.xm/.s3m/.it).
//
// A module bundles its instrument samples as raw PCM; the app already decodes
// every format to a common `ModuleDoc` (normalized float PCM + per-sample
// name + C-5 playback rate). This just surfaces those as standalone clips so a
// user's OWN module files can feed the sample library / the Labs. It reads the
// public `parseAnyModule` — it does not touch the module codecs.
//
// (Legality note: this extracts from a file the user supplies, exactly like
// importing a WAV — no redistribution. Whether a given module's samples are
// free to reuse is the user's call; the app makes no claim about them.)

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';

/// One sample lifted from a module.
class ExtractedSample {
  const ExtractedSample({
    required this.name,
    required this.sampleRate,
    required this.pcm,
    required this.moduleName,
    required this.index,
  });

  final String name;
  final int sampleRate;
  final Float64List pcm;
  final String moduleName; // the source module's title / filename
  final int index; // 1-based slot within the module

  /// A library entry for this sample (name prefixed with the module).
  SampleClip toClip() => SampleClip(
        name: '$moduleName – $displayName',
        sampleRate: sampleRate,
        pcm: pcm,
        source: moduleName,
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

/// The C-5 reference rate a tracker sample plays at when no rate is stored.
const _kDefaultC5Speed = 8363;

/// Extracts every non-empty sample from [bytes]. [moduleName] labels the source
/// (use the filename). Throws [FormatException] on unrecognized/corrupt input
/// (from `parseAnyModule`) — callers should catch per-file in a batch.
List<ExtractedSample> extractModuleSamples(
  Uint8List bytes, {
  String moduleName = 'module',
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
        moduleName: moduleName,
        index: i + 1,
      ),
    );
  }
  return out;
}
