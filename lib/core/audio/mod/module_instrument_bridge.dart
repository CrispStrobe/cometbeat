// lib/core/audio/mod/module_instrument_bridge.dart
//
// "Borrow a sample from a module" — turn a sample inside any tracker module
// (.mod/.s3m/.xm/.it) into a playable Tracker [SampleInstrument]. The module
// readers already expose each sample as normalized PCM (via the ModuleDoc hub);
// this bridges that PCM onto the engine's sampled-instrument seam so a kid can
// steal an instrument sound from a classic module and play a tune with it.
//
// The one subtlety is sample rate: a module sample's PCM is authored for playback
// at its own `c5speed` (that's the rate at which it sounds the "C-5" reference).
// The engine plays samples at the engine rate and pitches them by frequency ratio
// (SampleInstrument.renderChannel), so we pre-resample the module PCM from
// `c5speed` to the engine rate — then playing it unshifted (at baseMidi) reproduces
// the sample's native pitch, and other notes shift correctly around it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument;

/// Builds a [SampleInstrument] from a module [DocSample]. The PCM is resampled
/// from the sample's native `c5speed` to [engineRate]; [baseMidi] (default 60 =
/// IT's C-5) is the note at which it plays unshifted.
SampleInstrument sampleInstrumentFromDoc(
  String id,
  DocSample sample, {
  int baseMidi = 60,
  int engineRate = kSampleRate,
}) {
  if (sample.isEmpty) {
    return SampleInstrument(id, Float64List(0), baseMidi: baseMidi);
  }
  final c5 = sample.c5speed > 0 ? sample.c5speed : 8363;
  final atEngineRate = resampleCubic(sample.pcm, c5 / engineRate);
  return SampleInstrument(id, atEngineRate, baseMidi: baseMidi);
}

/// Borrows sample [index] from a module's raw [bytes] as a [SampleInstrument].
/// Throws [ArgumentError] if the format is unrecognized, the index is out of
/// range, or the sample is empty. Propagates the reader's *FormatException on
/// malformed input.
SampleInstrument sampleInstrumentFromModule(
  String id,
  Uint8List bytes,
  int index, {
  int baseMidi = 60,
  int engineRate = kSampleRate,
}) {
  final doc = parseAnyModule(bytes);
  if (index < 0 || index >= doc.samples.length) {
    throw ArgumentError(
      'sample index $index out of range (0..${doc.samples.length - 1})',
    );
  }
  final sample = doc.samples[index];
  if (sample.isEmpty) throw ArgumentError('sample $index is empty');
  return sampleInstrumentFromDoc(
    id,
    sample,
    baseMidi: baseMidi,
    engineRate: engineRate,
  );
}

/// The non-empty samples of a module, as `(index, DocSample)` pairs — for a
/// "pick a sample" UI. The index is the 1-based instrument number minus 1
/// (matching [sampleInstrumentFromModule]'s `index`).
List<(int, DocSample)> borrowableSamples(Uint8List bytes) {
  final doc = parseAnyModule(bytes);
  final out = <(int, DocSample)>[];
  for (var i = 0; i < doc.samples.length; i++) {
    if (!doc.samples[i].isEmpty) out.add((i, doc.samples[i]));
  }
  return out;
}
