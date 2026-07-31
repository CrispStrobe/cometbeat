// lib/core/harmony/chart_text.dart
//
// BB-D4a — text in, text out. The chart SUPPLY, not a convenience.
//
// A keypad is how you edit a chart; typing is how you get one in the first
// place. Every musician already knows this notation, it pastes out of a forum
// post or a notes app, and it survives being mailed to someone.
//
//     [A]
//     | C      | Am     | Dm7 G7 | C      |
//     | F      | %      | G7     | C      |
//
// The grammar is deliberately tiny, because anything a chart uses that this
// cannot say is still reachable from the editor:
//
//   * `|`            bar separator. Leading and trailing pipes are optional.
//   * `[Label]`      starts a section. `Label:` on its own line works too.
//   * `[A] x2`       section repeat count.
//   * two+ chords    split the bar evenly.
//   * `%` or empty   the previous chord continues.
//   * `N.C.`         silence.
//   * `#` or `//`    comment to end of line.
//   * `key:`/`meter:`/`tempo:`/`title:`/`composer:` header lines.
//
// NOTHING HERE THROWS AND NOTHING IS SILENTLY DROPPED. `parseChartCell` already
// guarantees a cell for any text, including junk, so an unreadable chord is
// preserved verbatim as an `UnreadableCell` and reported — a chart that quietly
// lost the one chord you typed wrong is worse than one that says so.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec_parser.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;

/// A chord this build could not read, kept with where it was so the UI can
/// point at it instead of just refusing the paste.
class ChartTextProblem {
  const ChartTextProblem({
    required this.line,
    required this.text,
    required this.barNumber,
  });

  /// 1-based line in the source.
  final int line;

  /// Exactly what was typed.
  final String text;

  /// 1-based bar number in the finished chart.
  final int barNumber;

  @override
  String toString() => 'line $line, bar $barNumber: "$text"';
}

/// The result of reading a text chart.
class ChartTextResult {
  const ChartTextResult({required this.chart, required this.problems});

  final Chart chart;

  /// Chords that were kept but not understood. Empty means a clean read.
  final List<ChartTextProblem> problems;

  bool get isClean => problems.isEmpty;
}

/// Reads a text chart. Never throws.
///
/// [defaults] supplies title/key/meter/tempo for anything the text does not
/// state, so re-parsing an edited chart does not reset its header.
ChartTextResult parseChartText(String source, {Chart? defaults}) {
  final base = defaults ?? const Chart();
  var title = base.title;
  var composer = base.composer;
  var keyFifths = base.keyFifths;
  var minor = base.minor;
  var meter = base.meter;
  var tempo = base.tempoBpm;

  final sections = <ChartSection>[];
  final problems = <ChartTextProblem>[];

  // The section being filled. Bars go here until a new header appears.
  var label = '';
  var repeatCount = 1;
  var bars = <ChartBar>[];
  var barNumber = 0;

  void closeSection() {
    // A header with no bars under it is not a section — it is a label the user
    // has not filled in yet, and emitting it would put an empty box on screen.
    if (bars.isEmpty) return;
    sections.add(
      ChartSection(label: label, bars: bars, repeatCount: repeatCount),
    );
    bars = <ChartBar>[];
  }

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];

    // Comments. `#` would collide with a sharp, so it only counts when it is
    // not glued to a chord — `C#m` must survive.
    final slash = line.indexOf('//');
    if (slash >= 0) line = line.substring(0, slash);
    final hash = RegExp(r'(^|\s)#').firstMatch(line);
    if (hash != null) line = line.substring(0, hash.start);
    line = line.trim();
    if (line.isEmpty) continue;

    // Header fields: `key: Bb minor`, `tempo: 140`.
    final header = RegExp(r'^(\w+)\s*:\s*(.*)$').firstMatch(line);
    if (header != null && !line.contains('|')) {
      final key = header.group(1)!.toLowerCase();
      final value = header.group(2)!.trim();
      switch (key) {
        case 'title':
          title = value;
          continue;
        case 'composer':
        case 'by':
          composer = value;
          continue;
        case 'tempo':
        case 'bpm':
          tempo = int.tryParse(value) ?? tempo;
          continue;
        case 'meter':
        case 'time':
          final m = _parseMeter(value);
          if (m != null) meter = m;
          continue;
        case 'key':
          final k = _parseKey(value);
          if (k != null) {
            keyFifths = k.$1;
            minor = k.$2;
          }
          continue;
        default:
          // `A:` — a section label in the alternate spelling. Anything else
          // unrecognised also becomes a label rather than being discarded.
          if (value.isEmpty) {
            closeSection();
            label = header.group(1)!;
            repeatCount = 1;
            continue;
          }
      }
    }

    // `[A]`, `[Chorus] x2`
    final bracket = RegExp(r'^\[([^\]]*)\]\s*(?:[xX]\s*(\d+))?$').firstMatch(
      line,
    );
    if (bracket != null) {
      closeSection();
      label = bracket.group(1)!.trim();
      repeatCount = int.tryParse(bracket.group(2) ?? '') ?? 1;
      continue;
    }

    // Otherwise: a row of bars.
    for (final cellText in _splitBars(line)) {
      barNumber++;
      final bar = _barFrom(
        cellText,
        meter,
        onProblem: (text) => problems.add(
          ChartTextProblem(line: i + 1, text: text, barNumber: barNumber),
        ),
      );
      bars.add(bar);
    }
  }

  closeSection();

  return ChartTextResult(
    chart: Chart(
      title: title,
      composer: composer,
      keyFifths: keyFifths,
      minor: minor,
      meter: meter,
      tempoBpm: tempo,
      sections: sections,
      styleId: base.styleId,
      pickupBeats: base.pickupBeats,
    ),
    problems: problems,
  );
}

/// Writes [chart] back out in the same notation, so the text view is an editor
/// rather than a one-way import.
String formatChartText(Chart chart) {
  final out = StringBuffer();
  if (chart.title.isNotEmpty) out.writeln('title: ${chart.title}');
  if (chart.composer != null && chart.composer!.isNotEmpty) {
    out.writeln('composer: ${chart.composer}');
  }
  out.writeln('key: ${_formatKey(chart.keyFifths, chart.minor)}');
  out.writeln('meter: ${chart.meter.beats}/${chart.meter.beatUnit}');
  out.writeln('tempo: ${chart.tempoBpm}');

  for (final section in chart.sections) {
    out.writeln();
    final repeat = section.passes > 1 ? ' x${section.passes}' : '';
    out.writeln('[${section.label}]$repeat');

    // Four bars to a line — the conventional lead-sheet row, and short enough
    // that a phone-width text field does not wrap it.
    for (var i = 0; i < section.bars.length; i += 4) {
      final row = section.bars.skip(i).take(4);
      out.writeln('| ${row.map(_formatBar).join(' | ')} |');
    }
  }
  return out.toString();
}

String _formatBar(ChartBar bar) {
  if (bar.chords.isEmpty) return '%';
  return bar.chordsInOrder.map((c) => c.chord.text).join(' ');
}

/// Splits one line into bar cells on `|`, dropping the empty cells that the
/// optional leading and trailing pipes create.
List<String> _splitBars(String line) {
  if (!line.contains('|')) return [line.trim()];
  final parts = line.split('|');
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i].trim();
    // Only the outermost empties are separator artefacts; `| C || G |` in the
    // middle is a genuinely empty (held) bar and must be kept.
    if (part.isEmpty && (i == 0 || i == parts.length - 1)) continue;
    out.add(part);
  }
  return out;
}

/// One bar's worth of text into a [ChartBar], distributing its chords.
ChartBar _barFrom(
  String text,
  TimeSignature meter, {
  required void Function(String) onProblem,
}) {
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return const ChartBar();

  final beats = meter.beats * 4 / meter.beatUnit;
  final chords = <ChartBeatChord>[];

  for (var i = 0; i < tokens.length; i++) {
    final cell = parseChartCell(tokens[i]);
    // Chords divide the bar evenly. Two in 4/4 land on beats 0 and 2, which is
    // what a split bar means; three land on 0, 1⅓, 2⅔, which is unusual to
    // write but is the only reading that does not invent an accent.
    final beat = beats * i / tokens.length;

    switch (cell) {
      case ChordCell(:final chord):
        chords.add(ChartBeatChord(chord: chord, beat: beat));
      case UnreadableCell(:final text, :final fallback):
        // Kept, so the bar is not silently short, and reported so the user can
        // see which one needs fixing.
        onProblem(text);
        chords.add(ChartBeatChord(chord: fallback, beat: beat));
      case NoChordCell():
        // Deliberately contributes no chord: the bar is silent, which is
        // different from a held bar.
        break;
      case RepeatCell():
        // An empty bar IS the held-chord notation; leaving it out is the
        // representation, not a loss.
        break;
    }
  }
  return ChartBar(chords: chords);
}

TimeSignature? _parseMeter(String value) {
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(value.trim());
  if (m == null) return null;
  final beats = int.tryParse(m.group(1)!) ?? 0;
  final unit = int.tryParse(m.group(2)!) ?? 0;
  // `TimeSignature` asserts a power-of-two unit, so an invalid meter has to be
  // refused here rather than thrown from the model.
  if (beats < 1 || unit < 1 || (unit & (unit - 1)) != 0 || unit > 1024) {
    return null;
  }
  return TimeSignature(beats, unit);
}

/// `Bb`, `F# minor`, `Am` → (fifths, minor).
(int, bool)? _parseKey(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final m = RegExp(
    r'^([A-Ga-g])([b#♭♯]?)\s*(m|min|minor|maj|major)?$',
  ).firstMatch(text);
  if (m == null) return null;

  final letter = m.group(1)!.toUpperCase();
  final accidental = m.group(2) ?? '';
  final quality = (m.group(3) ?? '').toLowerCase();
  final minor = quality.startsWith('m') && !quality.startsWith('maj');

  // Fifths of the natural major keys, then ±7 per accidental.
  const naturals = {'F': -1, 'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5};
  var fifths = naturals[letter]!;
  if (accidental == 'b' || accidental == '♭') fifths -= 7;
  if (accidental == '#' || accidental == '♯') fifths += 7;
  // A minor key's signature is its relative major's: three fifths flatter.
  if (minor) fifths -= 3;
  if (fifths < -7 || fifths > 7) return null;
  return (fifths, minor);
}

String _formatKey(int fifths, bool minor) {
  const majors = [
    'Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F', //
    'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#',
  ];
  const minors = [
    'ab', 'eb', 'bb', 'f', 'c', 'g', 'd', //
    'a', 'e', 'b', 'f#', 'c#', 'g#', 'd#', 'a#',
  ];
  final index = (fifths + 7).clamp(0, 14);
  return minor
      ? '${minors[index][0].toUpperCase()}${minors[index].substring(1)}m'
      : majors[index];
}
