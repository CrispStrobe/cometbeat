// lib/core/harmony/chart_chordpro.dart
//
// BB-D4b — a ChordPro file becomes a chart.
//
// ChordPro is what a great many players already have their songs in, so this is
// an adoption path rather than a feature. `songs/import/chordpro.dart` already
// reads the format, but into a `ChordSheet` of lyric lines — and it DROPS the
// section directives, which are the one thing a chart needs most. Reusing it
// would mean parsing twice and still missing them, so this reads the source
// itself and produces a `Chart` directly.
//
// ⚠️ THE HONEST LIMITATION, STATED RATHER THAN GUESSED AT: ChordPro has no
// barlines and no meter. There is no way to know that `[C]Twinkle [F]twinkle`
// is two bars rather than one bar split in half. So the rule is ONE CHORD, ONE
// BAR — the reading a musician would default to — and `barsAreInferred` says so
// on the result, because a chart that silently claims a bar structure it never
// had is worse than one that admits it guessed.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;

/// A chart read out of a ChordPro file.
class ChordProImport {
  const ChordProImport({
    required this.chart,
    required this.barsAreInferred,
    this.unreadable = const [],
  });

  final Chart chart;

  /// Always true today: ChordPro carries no barlines, so the bar structure is
  /// this importer's reading rather than the file's.
  final bool barsAreInferred;

  /// Chord brackets that did not parse, verbatim. Kept rather than dropped so
  /// a user can see what their file contained.
  final List<String> unreadable;

  bool get isEmpty => chart.isEmpty;
}

/// Reads ChordPro [source] as a chart. Never throws.
ChordProImport chartFromChordPro(String source) {
  var title = '';
  var composer = '';
  var tempo = 0;
  TimeSignature? meter;
  var keyFifths = 0;
  var minor = false;
  var sawKey = false;

  final sections = <ChartSection>[];
  var label = '';
  var bars = <ChartBar>[];
  final unreadable = <String>[];

  void closeSection() {
    if (bars.isEmpty) return;
    sections.add(ChartSection(label: label, bars: bars));
    bars = <ChartBar>[];
  }

  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // A comment line. `#` is ChordPro's, and it is unambiguous at line start.
    if (line.startsWith('#')) continue;

    // A directive occupying the whole line.
    final directive =
        RegExp(r'^\{\s*([^:}]+?)\s*(?::\s*(.*?))?\s*\}$').firstMatch(line);
    if (directive != null) {
      final name = directive.group(1)!.toLowerCase();
      final value = (directive.group(2) ?? '').trim();

      switch (name) {
        case 'title':
        case 't':
          title = value;
        case 'subtitle':
        case 'st':
        case 'artist':
        case 'composer':
          if (composer.isEmpty) composer = value;
        case 'tempo':
        case 'bpm':
          tempo = int.tryParse(value) ?? tempo;
        case 'time':
          meter = _meter(value) ?? meter;
        case 'key':
          final parsed = _key(value);
          if (parsed != null) {
            keyFifths = parsed.$1;
            minor = parsed.$2;
            sawKey = true;
          }
        // A new section starts here. The label is the directive's own value
        // when it has one ({soc: Chorus 2}), else the section type.
        case 'start_of_chorus':
        case 'soc':
          closeSection();
          label = value.isEmpty ? 'Chorus' : value;
        case 'start_of_verse':
        case 'sov':
          closeSection();
          label = value.isEmpty ? 'Verse' : value;
        case 'start_of_bridge':
        case 'sob':
          closeSection();
          label = value.isEmpty ? 'Bridge' : value;
        case 'end_of_chorus':
        case 'eoc':
        case 'end_of_verse':
        case 'eov':
        case 'end_of_bridge':
        case 'eob':
          closeSection();
          label = '';
        default:
          // Every other directive — comment, capo, columns, formatting — is
          // not chart data. Skipped rather than guessed at.
          break;
      }
      continue;
    }

    // A lyric line: take its chord brackets, in order.
    for (final match in RegExp(r'\[([^\]]*)\]').allMatches(line)) {
      final text = match.group(1)!.trim();
      if (text.isEmpty) continue;
      final cell = parseChartCell(text);
      switch (cell) {
        case ChordCell(:final chord):
          bars.add(ChartBar(chords: [ChartBeatChord(chord: chord)]));
        case UnreadableCell(text: final raw, :final fallback):
          // Kept AND reported: a chart short of a bar is worse than one with a
          // best guess the user can see and correct.
          unreadable.add(raw);
          bars.add(ChartBar(chords: [ChartBeatChord(chord: fallback)]));
        case NoChordCell():
          bars.add(const ChartBar());
        case RepeatCell():
          bars.add(const ChartBar());
      }
    }
  }
  closeSection();

  return ChordProImport(
    chart: Chart(
      title: title,
      composer: composer.isEmpty ? null : composer,
      keyFifths: keyFifths,
      minor: sawKey && minor,
      meter: meter ?? const TimeSignature(4, 4),
      tempoBpm: tempo > 0 ? tempo : const Chart().tempoBpm,
      sections: sections,
    ),
    barsAreInferred: true,
    unreadable: unreadable,
  );
}

TimeSignature? _meter(String value) {
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(value);
  if (m == null) return null;
  final beats = int.tryParse(m.group(1)!) ?? 0;
  final unit = int.tryParse(m.group(2)!) ?? 0;
  // TimeSignature asserts a power-of-two unit; refuse rather than throw.
  if (beats < 1 || unit < 1 || (unit & (unit - 1)) != 0 || unit > 1024) {
    return null;
  }
  return TimeSignature(beats, unit);
}

/// `Bb`, `Am`, `F# minor` → (fifths, minor).
(int, bool)? _key(String value) {
  final m = RegExp(r'^([A-Ga-g])([b#♭♯]?)\s*(m|min|minor|maj|major)?$')
      .firstMatch(value.trim());
  if (m == null) return null;

  const naturals = {'F': -1, 'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5};
  final quality = (m.group(3) ?? '').toLowerCase();
  final minor = quality.startsWith('m') && !quality.startsWith('maj');

  var fifths = naturals[m.group(1)!.toUpperCase()]!;
  final accidental = m.group(2) ?? '';
  if (accidental == 'b' || accidental == '♭') fifths -= 7;
  if (accidental == '#' || accidental == '♯') fifths += 7;
  if (minor) fifths -= 3;
  if (fifths < -7 || fifths > 7) return null;
  return (fifths, minor);
}
