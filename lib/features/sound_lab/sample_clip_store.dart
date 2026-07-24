// A persistent "My Samples" library: short audio clips (mono or stereo PCM + a sample
// rate) saved across sessions. The Voice Lab saves the voice you record and
// shape here; the module Sample Extractor drops the samples it pulls out of
// tracker files here. Both then recall them without a round-trip through disk.
//
// Storage: each clip's float PCM is quantized to 16-bit and base64'd, so the
// whole library is one JSON string in SharedPreferences. The encode/decode
// pair is pure (testable without a platform).

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument;
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';

/// One saved clip = a name, its sample rate, and mono float PCM ([-1, 1]).
class SampleClip {
  const SampleClip({
    required this.name,
    required this.sampleRate,
    required this.pcm,
    this.right,
    this.source,
    this.license,
    this.sourceUrl,
  });

  final String name;
  final int sampleRate;
  final Float64List pcm;
  final Float64List? right;

  /// Where it came from (e.g. a module title or "Freepats") — may be null.
  final String? source;

  /// The declared licence of the origin, when known (e.g. "CC0", "CC BY 4.0").
  /// Kept so attribution-required samples don't lose their provenance once
  /// they're in the library — see [needsAttribution].
  final String? license;

  /// A URL back to the origin, for credits.
  final String? sourceUrl;

  /// True if the licence obliges crediting the author (CC BY / BY-SA). CC0 /
  /// public-domain / unknown do not, so this stays conservative: it only fires
  /// on an explicit attribution licence.
  bool get needsAttribution {
    final l = license?.toLowerCase() ?? '';
    return l.contains('by') || l.contains('attribution');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'rate': sampleRate,
        if (source != null) 'source': source,
        if (license != null) 'license': license,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'pcm': base64Encode(_floatToInt16Bytes(pcm)),
        if (right != null) 'right': base64Encode(_floatToInt16Bytes(right!)),
      };

  static SampleClip? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final rate = j['rate'];
    final pcm = j['pcm'];
    if (name is! String || rate is! int || pcm is! String) return null;
    String? str(Object? v) => v is String ? v : null;
    try {
      return SampleClip(
        name: name,
        sampleRate: rate,
        pcm: _int16BytesToFloat(base64Decode(pcm)),
        right: j['right'] is String
            ? _int16BytesToFloat(base64Decode(j['right'] as String))
            : null,
        source: str(j['source']),
        license: str(j['license']),
        sourceUrl: str(j['sourceUrl']),
      );
    } catch (_) {
      return null;
    }
  }
}

Uint8List _floatToInt16Bytes(Float64List pcm) {
  final bytes = Uint8List(pcm.length * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < pcm.length; i++) {
    view.setInt16(
      i * 2,
      (pcm[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

Float64List _int16BytesToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, n * 2);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Serializes a clip list to a JSON string.
String encodeClips(List<SampleClip> clips) =>
    jsonEncode([for (final c in clips) c.toJson()]);

/// Parses a clip list; skips malformed entries, returns empty (never throws)
/// for null/blank/invalid input.
List<SampleClip> decodeClips(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          if (SampleClip.fromJson(e.cast<String, dynamic>()) case final c?) c,
    ];
  } catch (_) {
    return const [];
  }
}

/// The "My Samples" API, now a thin FACADE over [InstrumentLibraryStore]: a
/// sample IS an instrument (`kind == 'sample'`), so both libraries share ONE
/// backing store. Kept as a class so the ~8 sample callers (Voice Lab, Sample
/// Extractor, Sound Lab, Perform, …) don't change — a clip round-trips through
/// the sample-instrument codec (PCM as base64 Float32, inaudibly lossy). Loading
/// also triggers the store's one-time migration of the legacy samples key.
class SampleClipStore {
  final InstrumentLibraryStore _lib = InstrumentLibraryStore();

  Future<List<SampleClip>> load() async {
    return [
      for (final s in await _lib.load())
        if (sampleClipFromSaved(s) case final c?) c,
    ];
  }

  /// Adds [clip] as a sample instrument; a save under an existing name
  /// overwrites it. Returns the sample list after the save.
  Future<List<SampleClip>> save(SampleClip clip) async {
    await _lib.save(SavedInstrument.fromSampleClip(clip));
    return load();
  }

  Future<List<SampleClip>> delete(String name) async {
    await _lib.delete(name);
    return load();
  }
}

/// A `kind == 'sample'` library item back as a [SampleClip] (its PCM restored
/// from the embedded [SampleInstrument]); null for anything that isn't a sample.
/// Lets the unified sheet hand a picked sample back to callers that still speak
/// [SampleClip]/PCM (the Tracker, DAW, Perform).
SampleClip? sampleClipFromSaved(SavedInstrument s) {
  if (s.kind != 'sample') return null;
  final inst = s.instrument;
  if (inst is! SampleInstrument) return null;
  return SampleClip(
    name: s.name,
    sampleRate: s.sampleRate ?? kSampleRate,
    pcm: inst.sample,
    source: s.source,
    license: s.license,
    sourceUrl: s.sourceUrl,
  );
}
