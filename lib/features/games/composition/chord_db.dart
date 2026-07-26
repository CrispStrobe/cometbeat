// A curated chord-voicing database for the Tab Editor, derived from
// tombatossals/chords-db (MIT, © 2016 David Rubert): real, idiomatic,
// multi-position shapes for standard guitar / ukulele — a big upgrade over one
// algorithmically-voiced shape. The raw JSON is bundled verbatim under
// assets/chords/ (with its LICENSE); this module loads it and converts each
// position to our [ChordDiagram]. The algorithmic [chordVoicing] stays the
// fallback for tunings/qualities the DB doesn't cover.

import 'dart:convert';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The Tab-Editor builder's quality label → the chords-db `suffix` name.
const Map<String, String> kQualityToChordDbSuffix = {
  'maj': 'major',
  'm': 'minor',
  '5': '5',
  '7': '7',
  'maj7': 'maj7',
  'm7': 'm7',
  'm7♭5': 'm7b5',
  'dim': 'dim',
  'dim7': 'dim7',
  'aug': 'aug',
  'sus2': 'sus2',
  'sus4': 'sus4',
  '6': '6',
  'm6': 'm6',
  'add9': 'add9',
  '9': '9',
  'm9': 'm9',
};

/// Converts one chords-db position to our [ChordDiagram]. chords-db lists frets
/// **low-string → high-string** and **relative to `baseFret`** (0 = open,
/// −1 = not played, else a 1-based offset into the position box); our diagram is
/// **high-string → low-string** and absolute. So: absolute = f + baseFret − 1
/// (open/muted pass through), then reverse. Pure + testable.
ChordDiagram diagramFromChordDbPosition(
  Map<String, dynamic> pos, {
  required String name,
}) {
  final baseFret = (pos['baseFret'] as num?)?.toInt() ?? 1;
  final raw = (pos['frets'] as List).map((f) => (f as num).toInt()).toList();
  final absolute = [
    for (final f in raw) f < 0 ? -1 : (f == 0 ? 0 : f + baseFret - 1),
  ];
  final ours = absolute.reversed.toList(); // low→high  ⇒  high→low
  final barres = (pos['barres'] as List?)?.cast<num>() ?? const [];
  final barreFret = barres.isEmpty ? null : barres.first.toInt() + baseFret - 1;
  return ChordDiagram(
    ours,
    name: name,
    baseFret: baseFret,
    barreFret: barreFret,
  );
}

/// A loaded chords-db instrument (`guitar` / `ukulele`): its chromatic keys
/// (`keys[pitchClass]` = that pc's key spelling) and its chords by key.
class ChordDb {
  ChordDb._(this._keys, this._chords);

  final List<String> _keys;
  final Map<String, List<Map<String, dynamic>>> _chords;

  static final Map<String, ChordDb> _cache = {};

  /// Loads (and caches) the bundled DB for [instrument] (`guitar`/`ukulele`).
  /// Returns null if the asset is missing/unreadable (so the caller falls back
  /// to the algorithmic voicing rather than crashing).
  static Future<ChordDb?> load(String instrument) async {
    final cached = _cache[instrument];
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString('assets/chords/$instrument.json');
      final db = ChordDb.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _cache[instrument] = db;
      return db;
    } catch (_) {
      return null;
    }
  }

  /// Builds a DB from already-parsed [json] (testable without the asset bundle).
  factory ChordDb.fromJson(Map<String, dynamic> json) => ChordDb._(
        (json['keys'] as List).cast<String>(),
        {
          for (final e in (json['chords'] as Map).entries)
            e.key as String: (e.value as List)
                .map((v) => (v as Map).cast<String, dynamic>())
                .toList(),
        },
      );

  /// The curated voicings for [rootPc] (0 = C) + a Tab-Editor quality
  /// [qualityLabel], or empty when the DB doesn't carry that chord.
  List<ChordDiagram> voicings(int rootPc, String qualityLabel) {
    final suffix = kQualityToChordDbSuffix[qualityLabel];
    if (suffix == null || rootPc < 0 || rootPc >= _keys.length) return const [];
    final key = _keys[rootPc];
    for (final entry in _chords[key] ?? const <Map<String, dynamic>>[]) {
      if (entry['suffix'] == suffix) {
        final label = suffix == 'major'
            ? ''
            : suffix == 'minor'
                ? 'm'
                : suffix;
        return [
          for (final p in (entry['positions'] as List)
              .map((v) => (v as Map).cast<String, dynamic>()))
            diagramFromChordDbPosition(p, name: '$key$label'),
        ];
      }
    }
    return const [];
  }
}
