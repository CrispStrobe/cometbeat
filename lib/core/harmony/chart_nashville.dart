// lib/core/harmony/chart_nashville.dart
//
// BB-D4b — the Nashville Number System, both ways.
//
// A session player writes `| 1 | 4 | 5 | 1 |` and plays it in whatever key the
// singer needs. That is the same two-axis idea the transposition and setlist
// work already rest on — the CHART is the shape, the key is the occasion — and
// it is why this format is worth supporting rather than merely converting.
//
// ⚠️ ONE REAL AMBIGUITY IN THE FORMAT, RESOLVED EXPLICITLY. A bare number can
// mean two things, and both conventions are in use:
//
//   * the DIATONIC chord on that degree — so `6` in C major is Am; or
//   * a MAJOR triad on that degree — so `6` in C major is A.
//
// This takes the first, which is the Nashville convention proper and what a
// chart of `| 1 | 6 | 4 | 5 |` is meant to sound like. A player who wants the
// major writes `6maj` or `6M`. The printer is the exact inverse: a quality that
// IS the diatonic one is left off, so `| 1 | 6 | 4 | 5 |` prints back exactly
// as it was read.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, TimeSignature;

/// Semitones above the tonic for each degree of a major scale, 1-indexed.
const _majorDegrees = <int>[0, 0, 2, 4, 5, 7, 9, 11];

/// …and of a natural minor scale.
const _minorDegrees = <int>[0, 0, 2, 3, 5, 7, 8, 10];

/// The triad quality a bare number means on each degree.
const _majorQualities = <ChordTriad>[
  ChordTriad.major, // unused; 1-indexed
  ChordTriad.major, // 1
  ChordTriad.minor, // 2
  ChordTriad.minor, // 3
  ChordTriad.major, // 4
  ChordTriad.major, // 5
  ChordTriad.minor, // 6
  ChordTriad.diminished, // 7
];

const _minorQualities = <ChordTriad>[
  ChordTriad.major,
  ChordTriad.minor, // 1
  ChordTriad.diminished, // 2
  ChordTriad.major, // 3
  ChordTriad.minor, // 4
  ChordTriad.minor, // 5
  ChordTriad.major, // 6
  ChordTriad.major, // 7
];

/// A chart read from Nashville numbers.
class NashvilleImport {
  const NashvilleImport({required this.chart, this.unreadable = const []});

  final Chart chart;

  /// Cells that were not numbers, verbatim. Kept, so a mistyped degree is
  /// visible rather than a missing bar.
  final List<String> unreadable;

  bool get isClean => unreadable.isEmpty;
}

/// [chart] written as Nashville numbers.
///
/// The output is the same bar-grid shape `chart_text.dart` reads, so the two
/// formats differ only in what is written inside a bar.
String chartToNashville(Chart chart) {
  final out = StringBuffer();
  if (chart.title.isNotEmpty) out.writeln('title: ${chart.title}');
  out.writeln('key: ${_keyName(chart)}');
  out.writeln('meter: ${chart.meter.beats}/${chart.meter.beatUnit}');
  out.writeln('tempo: ${chart.tempoBpm}');

  for (final section in chart.sections) {
    out.writeln();
    final repeat = section.passes > 1 ? ' x${section.passes}' : '';
    out.writeln('[${section.label}]$repeat');
    for (var i = 0; i < section.bars.length; i += 4) {
      final row = section.bars.skip(i).take(4);
      out.writeln('| ${row.map((b) => _bar(b, chart)).join(' | ')} |');
    }
  }
  return out.toString();
}

String _bar(ChartBar bar, Chart chart) => bar.chords.isEmpty
    ? '%'
    : bar.chordsInOrder.map((c) => nashvilleFor(c.chord, chart)).join(' ');

/// One chord as a Nashville number in [chart]'s key.
String nashvilleFor(ChordSpec chord, Chart chart) {
  final semitones = (_pc(chord.root) - chart.tonicPitchClass + 12) % 12;
  final scale = chart.minor ? _minorDegrees : _majorDegrees;

  // The degree whose scale tone this is, or the nearest below it with an
  // accidental — `b7` in a major key, `#4`, and so on.
  var degree = 0;
  var alter = 0;
  for (var d = 7; d >= 1; d--) {
    if (scale[d] == semitones) {
      degree = d;
      alter = 0;
      break;
    }
    if (scale[d] == (semitones + 1) % 12) {
      degree = d;
      alter = -1;
    }
  }
  if (degree == 0) {
    // Nothing within a semitone below: it is a raised degree.
    for (var d = 1; d <= 7; d++) {
      if (scale[d] == (semitones - 1 + 12) % 12) {
        degree = d;
        alter = 1;
        break;
      }
    }
  }
  if (degree == 0) return chord.text; // give up readably rather than wrongly

  final prefix = alter < 0 ? 'b' : (alter > 0 ? '#' : '');
  final qualities = chart.minor ? _minorQualities : _majorQualities;
  // An accidental degree has no diatonic quality to compare against, so its
  // suffix is always written.
  final implied = alter == 0 ? qualities[degree] : null;
  return '$prefix$degree${_suffix(chord, implied)}';
}

/// The suffix to print, omitting a quality the number already implies.
String _suffix(ChordSpec chord, ChordTriad? implied) {
  final full = chord.text;
  // `ChordSpec.text` is root + suffix, so the suffix is what follows the root
  // letter and any accidental — the model has no separate accessor for it.
  final rootLength = 1 + (chord.root.alter != 0 ? chord.root.alter.abs() : 0);
  var suffix = full.length > rootLength ? full.substring(rootLength) : '';

  // A bare number already says "the diatonic chord here", so `m` on a 2 or a
  // `dim` on a 7 is noise. Anything else — a seventh, an extension, a slash —
  // is information and stays.
  if (implied != null && suffix.isNotEmpty) {
    final marker = switch (implied) {
      ChordTriad.minor => 'm',
      ChordTriad.diminished => 'dim',
      _ => null,
    };
    if (marker != null && suffix == marker) return '';
  }
  // A MAJOR triad on a degree whose diatonic chord is not major has to say so,
  // or it would read back as the diatonic one.
  if (implied != null &&
      implied != ChordTriad.major &&
      chord.triad == ChordTriad.major &&
      suffix.isEmpty) {
    suffix = 'maj';
  }
  return suffix;
}

/// Nashville [source] as a chart in [key].
///
/// [keyFifths]/[minor] set the key the numbers are realised in — the whole
/// point of the format is that the same numbers serve every key.
NashvilleImport chartFromNashville(
  String source, {
  int keyFifths = 0,
  bool minor = false,
}) {
  final unreadable = <String>[];
  var title = '';
  var tempo = const Chart().tempoBpm;
  var meter = const TimeSignature(4, 4);
  var fifths = keyFifths;
  var isMinor = minor;

  final sections = <ChartSection>[];
  var label = '';
  var bars = <ChartBar>[];

  void close() {
    if (bars.isEmpty) return;
    sections.add(ChartSection(label: label, bars: bars));
    bars = <ChartBar>[];
  }

  for (final raw in source.split('\n')) {
    var line = raw;
    final slash = line.indexOf('//');
    if (slash >= 0) line = line.substring(0, slash);
    line = line.trim();
    if (line.isEmpty) continue;

    final header = RegExp(r'^(\w+)\s*:\s*(.*)$').firstMatch(line);
    if (header != null && !line.contains('|')) {
      final name = header.group(1)!.toLowerCase();
      final value = header.group(2)!.trim();
      switch (name) {
        case 'title':
          title = value;
          continue;
        case 'tempo':
        case 'bpm':
          tempo = int.tryParse(value) ?? tempo;
          continue;
        case 'meter':
        case 'time':
          final m = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(value);
          if (m != null) {
            final b = int.tryParse(m.group(1)!) ?? 0;
            final u = int.tryParse(m.group(2)!) ?? 0;
            if (b >= 1 && u >= 1 && (u & (u - 1)) == 0 && u <= 1024) {
              meter = TimeSignature(b, u);
            }
          }
          continue;
        case 'key':
          final parsed = _parseKey(value);
          if (parsed != null) {
            fifths = parsed.$1;
            isMinor = parsed.$2;
          }
          continue;
      }
    }

    final bracket =
        RegExp(r'^\[([^\]]*)\]\s*(?:[xX]\s*(\d+))?$').firstMatch(line);
    if (bracket != null) {
      close();
      label = bracket.group(1)!.trim();
      continue;
    }

    for (final cell in _splitBars(line)) {
      final tokens =
          cell.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) {
        bars.add(const ChartBar());
        continue;
      }
      final chords = <ChartBeatChord>[];
      final beats = meter.beats * 4 / meter.beatUnit;
      for (var i = 0; i < tokens.length; i++) {
        final chord = _chordFor(tokens[i], fifths, isMinor);
        if (chord == null) {
          if (tokens[i] != '%') unreadable.add(tokens[i]);
          continue;
        }
        chords.add(
          ChartBeatChord(chord: chord, beat: beats * i / tokens.length),
        );
      }
      bars.add(ChartBar(chords: chords));
    }
  }
  close();

  return NashvilleImport(
    chart: Chart(
      title: title,
      keyFifths: fifths,
      minor: isMinor,
      meter: meter,
      tempoBpm: tempo,
      sections: sections,
    ),
    unreadable: unreadable,
  );
}

/// `5`, `2m`, `b7`, `1maj7`, `5/7` → a real chord in the key.
ChordSpec? _chordFor(String token, int fifths, bool minor) {
  final m = RegExp(r'^([b#]?)([1-7])(.*)$').firstMatch(token.trim());
  if (m == null) return null;

  final alter = m.group(1) == 'b' ? -1 : (m.group(1) == '#' ? 1 : 0);
  final degree = int.parse(m.group(2)!);
  var suffix = m.group(3)!;

  final scale = minor ? _minorDegrees : _majorDegrees;
  final tonic = _tonicPc(fifths, minor: minor);
  final pc = (tonic + scale[degree] + alter + 12) % 12;

  // A bare number means the diatonic chord — the convention this file states
  // in its header. `maj`/`M` is how a player overrides it.
  if (suffix.isEmpty && alter == 0) {
    final implied = (minor ? _minorQualities : _majorQualities)[degree];
    suffix = switch (implied) {
      ChordTriad.minor => 'm',
      ChordTriad.diminished => 'dim',
      _ => '',
    };
  } else if (suffix == 'maj' || suffix == 'M') {
    suffix = '';
  }

  // ⚠️ The DEGREE's accidental drives the spelling, not just the key's.
  // `b7` is a flattened degree and spells `Bb` even in C major, whose
  // signature would otherwise select sharps and print `A#` — a different
  // name for a note the player asked for by its flat.
  return parseChordSpec('${_spell(pc, fifths, alter)}$suffix');
}

List<String> _splitBars(String line) {
  if (!line.contains('|')) return [line.trim()];
  final parts = line.split('|');
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i].trim();
    if (part.isEmpty && (i == 0 || i == parts.length - 1)) continue;
    out.add(part);
  }
  return out;
}

int _pc(Pitch pitch) => (pitch.midiNumber % 12 + 12) % 12;

int _tonicPc(int fifths, {required bool minor}) {
  final major = (fifths * 7) % 12;
  final pc = minor ? major + 9 : major;
  return ((pc % 12) + 12) % 12;
}

/// A pitch class spelled to suit the degree first, then the key.
String _spell(int pc, int fifths, [int degreeAlter = 0]) {
  const sharps = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  const flats = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  if (degreeAlter < 0) return flats[pc];
  if (degreeAlter > 0) return sharps[pc];
  return fifths < 0 ? flats[pc] : sharps[pc];
}

String _keyName(Chart chart) {
  const majors = [
    'Cb',
    'Gb',
    'Db',
    'Ab',
    'Eb',
    'Bb',
    'F',
    'C',
    'G',
    'D',
    'A',
    'E',
    'B',
    'F#',
    'C#',
  ];
  final index = (chart.keyFifths + 7).clamp(0, 14);
  final name = majors[index];
  if (!chart.minor) return name;
  // The minor key three fifths sharper shares this signature.
  const minors = [
    'Ab',
    'Eb',
    'Bb',
    'F',
    'C',
    'G',
    'D',
    'A',
    'E',
    'B',
    'F#',
    'C#',
    'G#',
    'D#',
    'A#',
  ];
  return '${minors[index]}m';
}

(int, bool)? _parseKey(String value) {
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
