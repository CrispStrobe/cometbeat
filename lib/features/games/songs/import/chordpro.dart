// lib/features/games/songs/import/chordpro.dart
//
// Minimal ChordPro parser: `{title: ...}` directives and `[C]`-style inline
// chords over lyrics. Chords map to playable triads (C, Am, F7 -> F, ...) so
// every chord chip in the sheet can sound.

// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:crisp_notation/crisp_notation.dart'
    show ChordQuality, Pitch, Step, Triad;

/// One lyric fragment with an optional chord starting on it.
class ChordSegment {
  final String? chord;
  final String text;

  const ChordSegment(this.chord, this.text);
}

class ChordSheet {
  final String title;
  final List<List<ChordSegment>> lines;

  const ChordSheet({required this.title, required this.lines});

  /// All distinct chord names in order of first appearance.
  List<String> get chords {
    final seen = <String>{};
    for (final line in lines) {
      for (final segment in line) {
        if (segment.chord != null) seen.add(segment.chord!);
      }
    }
    return seen.toList();
  }
}

/// Parses ChordPro [source]. Throws [FormatException] when nothing usable
/// is found.
ChordSheet parseChordPro(String source) {
  var title = '';
  final lines = <List<ChordSegment>>[];

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    final directive =
        RegExp(r'^\{\s*(\w+)\s*:\s*(.*?)\s*\}$').firstMatch(line.trim());
    if (directive != null) {
      final key = directive.group(1)!.toLowerCase();
      if (key == 'title' || key == 't') title = directive.group(2)!;
      continue; // all other directives ignored
    }
    if (line.trim().isEmpty) {
      if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add(const []);
      continue;
    }

    final segments = <ChordSegment>[];
    String? pendingChord;
    var buffer = StringBuffer();
    var i = 0;
    while (i < line.length) {
      if (line[i] == '[') {
        final close = line.indexOf(']', i);
        if (close > i) {
          if (buffer.isNotEmpty || pendingChord != null) {
            segments.add(ChordSegment(pendingChord, buffer.toString()));
            buffer = StringBuffer();
          }
          pendingChord = line.substring(i + 1, close);
          i = close + 1;
          continue;
        }
      }
      buffer.write(line[i]);
      i++;
    }
    if (buffer.isNotEmpty || pendingChord != null) {
      segments.add(ChordSegment(pendingChord, buffer.toString()));
    }
    if (segments.isNotEmpty) lines.add(segments);
  }

  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) {
    throw const FormatException('No ChordPro content found');
  }
  return ChordSheet(title: title.isEmpty ? 'Chord sheet' : title, lines: lines);
}

/// MIDI notes for a chord symbol like `C`, `Am`, `F7`, `Bb`, `D#m` —
/// reduced to the plain major/minor triad. Returns null when unparseable.
List<int>? chordMidis(String chord) {
  final match =
      RegExp(r'^([A-Ga-g])([#b]?)(m(?!aj))?').firstMatch(chord.trim());
  if (match == null) return null;
  final step = Step.values.asNameMap()[match.group(1)!.toLowerCase()];
  if (step == null) return null;
  final alter = switch (match.group(2)) { '#' => 1, 'b' => -1, _ => 0 };
  final quality =
      match.group(3) != null ? ChordQuality.minor : ChordQuality.major;
  return Triad(Pitch(step, alter: alter), quality)
      .pitches
      .map((p) => p.midiNumber)
      .toList();
}
