// lib/core/interop/annotation_codecs.dart
//
// How structured facts are written into (and read back out of) the symbolic
// side-car.
//
// `SymbolicAnnotations` stores plain JSON-ish values so a side-car can be saved
// alongside a document, which means anything richer than a number or a string
// needs an agreed shape. These are those agreements. They live together, and
// apart from any one converter, because the WRITER and the READER of a fact are
// usually different files — a tuning is recorded when leaving Tab and consumed
// when rebuilding one, possibly several hops later.

import 'package:comet_beat/shared/midi_pitch.dart' show pitchFromMidi;
import 'package:crisp_notation/crisp_notation.dart' show ChordDiagram, Tuning;

/// A tuning as one MIDI number per string, top string first.
List<int> tuningToAnnotation(Tuning tuning) =>
    [for (final string in tuning.strings) string.midiNumber];

/// The inverse of [tuningToAnnotation]; null when [raw] is not a tuning.
Tuning? tuningFromAnnotation(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final midis = <int>[];
  for (final entry in raw) {
    final midi = _asInt(entry);
    if (midi == null) return null;
    midis.add(midi);
  }
  return Tuning(
    [for (final midi in midis) pitchFromMidi(midi)],
    name: 'imported',
  );
}

/// A column's `{string: fret}` as `[[string, fret], …]`, ordered by string.
///
/// A list of pairs rather than a map because side-car values round-trip through
/// JSON, where an object's keys would come back as strings.
List<List<int>> frettingToAnnotation(Map<int, int> frets) {
  final pairs = [
    for (final entry in frets.entries) [entry.key, entry.value],
  ];
  pairs.sort((a, b) => a.first.compareTo(b.first));
  return pairs;
}

/// The inverse of [frettingToAnnotation]; null when [raw] is not a fretting.
Map<int, int>? frettingFromAnnotation(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final frets = <int, int>{};
  for (final pair in raw) {
    if (pair is! List || pair.length != 2) return null;
    final string = _asInt(pair[0]);
    final fret = _asInt(pair[1]);
    if (string == null || fret == null) return null;
    frets[string] = fret;
  }
  return frets;
}

/// A side-car value as an int — it may have come back from JSON as a double.
int? _asInt(Object? raw) => switch (raw) {
      final int value => value,
      final double value => value.round(),
      final String value => int.tryParse(value),
      _ => null,
    };

/// A chord diagram as a plain map, so it can sit in a side-car and round-trip
/// through JSON.
Map<String, Object?> chordDiagramToAnnotation(ChordDiagram chord) => {
      'frets': List<int>.of(chord.frets),
      if (chord.name != null) 'name': chord.name,
      if (chord.fingers != null) 'fingers': List<int?>.of(chord.fingers!),
      'baseFret': chord.baseFret,
      'fretSpan': chord.fretSpan,
      if (chord.barreFret != null) 'barreFret': chord.barreFret,
    };

/// The inverse of [chordDiagramToAnnotation]; null when [raw] is not one.
///
/// A diagram with no frets is not a diagram, so it comes back null rather than
/// as an empty grid that would draw as a blank box.
ChordDiagram? chordDiagramFromAnnotation(Object? raw) {
  if (raw is! Map) return null;
  final rawFrets = raw['frets'];
  if (rawFrets is! List || rawFrets.isEmpty) return null;
  final frets = <int>[];
  for (final entry in rawFrets) {
    final fret = _asInt(entry);
    if (fret == null) return null;
    frets.add(fret);
  }
  final rawFingers = raw['fingers'];
  return ChordDiagram(
    frets,
    name: raw['name'] as String?,
    fingers: rawFingers is List
        ? [for (final finger in rawFingers) _asInt(finger)]
        : null,
    baseFret: _asInt(raw['baseFret']) ?? 1,
    fretSpan: _asInt(raw['fretSpan']) ?? 4,
    barreFret: _asInt(raw['barreFret']),
  );
}
