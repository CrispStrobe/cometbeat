// A persistent "My Instruments" library: named playable instruments saved
// across sessions. Where "My Samples" ([SampleClipStore]) stores raw audio
// clips, this stores a whole [TrackerInstrument] — the shaped Voice Lab voice,
// a picked SoundFont preset, a procedural voice — so it can be recalled and
// played (not just replayed).
//
// The save format is the engine's own instrument JSON codec
// ([instrumentToJsonString]) — the string IS the record, so the store is a thin
// SharedPreferences wrapper. Embedded voices (samples, sfxr, additive, …)
// round-trip synchronously; a referenced SoundFont voice ([isReference]) keeps
// only a file+preset pointer and is resolved with the font bytes elsewhere. The
// encode/decode pair is pure (testable without a platform).

import 'dart:convert';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument, TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart'
    show SampleClip, decodeClips;
import 'package:shared_preferences/shared_preferences.dart';

/// The rubrics the unified library groups items under, derived from an item's
/// [SavedInstrument.kind]. Order = tab order.
const List<String> kLibraryCategories = [
  'Instruments',
  'Samples',
  'FX',
  'SoundFonts',
  'Drums',
];

/// One saved library item = a name plus its codec JSON. Since a recorded sample
/// is itself a [SampleInstrument] (`kind == 'sample'`), the old "My Samples"
/// library folds in here: samples are just instruments that play back PCM, so
/// [license]/[sourceUrl] (needed for CC-BY attribution) ride along on this one
/// model. [source] notes where it came from (e.g. "Voice Lab") for display.
class SavedInstrument {
  const SavedInstrument({
    required this.name,
    required this.json,
    this.sampleRate,
    this.source,
    this.license,
    this.sourceUrl,
  });

  final String name;

  /// The [instrumentToJsonString] payload — the authoritative record.
  final String json;

  /// Original PCM rate for embedded sample instruments. Older records omit it
  /// and are interpreted at the engine's default rate when recalled.
  final int? sampleRate;

  final String? source;

  /// Declared licence of the origin, when known ("CC0", "CC BY 4.0") — kept so
  /// attribution-required items don't lose provenance. See [needsAttribution].
  final String? license;

  /// A URL back to the origin, for credits.
  final String? sourceUrl;

  /// The instrument's type tag (e.g. `sample`, `sfxr`, `soundfont_ref`), read
  /// straight from the JSON; `unknown` if it can't be parsed.
  String get kind {
    try {
      final m = jsonDecode(json);
      return (m is Map && m['type'] is String)
          ? m['type'] as String
          : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// The rubric this item sits under (one of [kLibraryCategories]).
  String get category => switch (kind) {
        'sample' => 'Samples',
        'sfxr' => 'FX',
        'soundfont_ref' => 'SoundFonts',
        'percussion' => 'Drums',
        _ => 'Instruments',
      };

  /// True if the licence obliges crediting the author (CC BY / BY-SA). CC0 /
  /// public-domain / unknown do not.
  bool get needsAttribution {
    final l = license?.toLowerCase() ?? '';
    return l.contains('by') || l.contains('attribution');
  }

  /// True if rebuilding needs the referenced SoundFont file (async), not just
  /// this embedded JSON — resolve those via `resolveInstrumentJson`.
  bool get isReference => kind == 'soundfont_ref';

  /// Rebuilds the instrument from its embedded JSON (synchronous). Returns null
  /// for references (need the font bytes) or malformed data.
  TrackerInstrument? get instrument {
    if (isReference) return null;
    try {
      return instrumentFromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  /// A recorded/imported [SampleClip] as a library instrument: its PCM becomes a
  /// [SampleInstrument] (`kind == 'sample'`) and its provenance is preserved.
  factory SavedInstrument.fromSampleClip(SampleClip clip) => SavedInstrument(
        name: clip.name,
        json: instrumentToJsonString(SampleInstrument(clip.name, clip.pcm)),
        sampleRate: clip.sampleRate,
        source: clip.source ?? 'Sample',
        license: clip.license,
        sourceUrl: clip.sourceUrl,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'json': json,
        if (sampleRate != null) 'rate': sampleRate,
        if (source != null) 'source': source,
        if (license != null) 'license': license,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  static SavedInstrument? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final json = j['json'];
    if (name is! String || json is! String) return null;
    final rate = j['rate'];
    String? str(Object? v) => v is String ? v : null;
    return SavedInstrument(
      name: name,
      json: json,
      sampleRate: rate is int && rate > 0 ? rate : null,
      source: str(j['source']),
      license: str(j['license']),
      sourceUrl: str(j['sourceUrl']),
    );
  }
}

/// Serializes the library to a JSON string.
String encodeInstruments(List<SavedInstrument> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// Parses a library; skips malformed entries, returns empty (never throws) for
/// null/blank/invalid input.
List<SavedInstrument> decodeInstruments(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          if (SavedInstrument.fromJson(e.cast<String, dynamic>()) case final s?)
            s,
    ];
  } catch (_) {
    return const [];
  }
}

/// SharedPreferences-backed persistence of the unified sound library (the old
/// "My Instruments" + "My Samples", now one store).
class InstrumentLibraryStore {
  static const _key = 'sound_lab_instruments';
  static const _legacySamplesKey = 'sound_lab_samples';
  static const _migratedKey = 'sound_lab_samples_merged_v1';

  Future<List<SavedInstrument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var items = decodeInstruments(prefs.getString(_key));
    // One-time: fold the old "My Samples" library in as sample instruments, so
    // both live in a single store. Guarded by a flag; the legacy key is left
    // intact (a downgrade still finds its samples). Names already present here
    // win — a re-run can't duplicate.
    if (!(prefs.getBool(_migratedKey) ?? false)) {
      final names = {for (final i in items) i.name};
      final merged = [
        for (final c in decodeClips(prefs.getString(_legacySamplesKey)))
          if (!names.contains(c.name)) SavedInstrument.fromSampleClip(c),
      ];
      if (merged.isNotEmpty) {
        items = [...items, ...merged];
        await prefs.setString(_key, encodeInstruments(items));
      }
      await prefs.setBool(_migratedKey, true);
    }
    return items;
  }

  /// Adds [inst]; a save under an existing name overwrites it. Newest last.
  Future<List<SavedInstrument>> save(SavedInstrument inst) async {
    final list = [...await load()]..removeWhere((x) => x.name == inst.name);
    list.add(inst);
    await _write(list);
    return list;
  }

  Future<List<SavedInstrument>> delete(String name) async {
    final list = [...await load()]..removeWhere((x) => x.name == name);
    await _write(list);
    return list;
  }

  Future<void> _write(List<SavedInstrument> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encodeInstruments(list));
  }
}
