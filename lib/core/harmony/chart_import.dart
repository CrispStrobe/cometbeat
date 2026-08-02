// lib/core/harmony/chart_import.dart
//
// BB-D4b — one entry point that works out WHICH format was pasted.
//
// By now a chart can arrive as a share token, a text grid, ChordPro, Nashville
// numbers or a JAMS annotation. Asking the user to say which of five it is
// pushes our problem onto them — they pasted a chart, and which dialect it
// happens to be is a fact about the text, not a decision.
//
// The formats are distinguishable, and where two could overlap the tie is
// broken deliberately rather than by luck. The one real ambiguity is a text
// grid against Nashville numbers: both are `| … |` rows, and only the CELLS
// differ — `| C | Am |` against `| 1 | 6 |`. Decided on the cells, and stated
// in `_looksNashville` below.
library;

import 'dart:convert';

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chart_chordpro.dart';
import 'package:comet_beat/core/harmony/chart_jams.dart';
import 'package:comet_beat/core/harmony/chart_nashville.dart';
import 'package:comet_beat/core/harmony/chart_share.dart';
import 'package:comet_beat/core/harmony/chart_text.dart';

/// Which format a pasted chart turned out to be. Surfaced so the UI can say
/// what it read — a paste that silently reinterprets is worse than one that
/// reports.
enum ChartFormat { token, textGrid, chordPro, nashville, jams }

/// The result of reading pasted text as a chart.
class ChartImport {
  const ChartImport({
    required this.chart,
    required this.format,
    this.barsAreInferred = false,
    this.unreadable = const [],
  });

  final Chart chart;
  final ChartFormat format;

  /// True when the source carried no bar structure and this is our reading of
  /// it (ChordPro and JAMS). See those files for what that costs.
  final bool barsAreInferred;

  /// Cells that did not parse, verbatim.
  final List<String> unreadable;

  bool get isEmpty => chart.isEmpty;
}

/// Reads [text] as a chart in whichever format it is. Never throws.
///
/// Returns null when nothing usable was found, so a caller can tell "this is
/// not a chart" from "this is an empty chart".
ChartImport? importChart(String text) {
  final source = text.trim();
  if (source.isEmpty) return null;

  // 1. A share token. Unambiguous — it carries our own prefix — so it is tried
  //    first and its failure is not retried as anything else: text containing
  //    `CB1.` is a token attempt, not a coincidence.
  if (source.contains(kChartTokenPrefix)) {
    final chart = decodeChartToken(source);
    return chart == null
        ? null
        : ChartImport(chart: chart, format: ChartFormat.token);
  }

  // 2. JAMS. JSON with an `annotations` list; nothing else here is JSON.
  if (_looksJams(source)) {
    final imported = chartFromJams(source);
    return imported.isEmpty
        ? null
        : ChartImport(
            chart: imported.chart,
            format: ChartFormat.jams,
            barsAreInferred: imported.barsAreInferred,
            unreadable: imported.unreadable,
          );
  }

  // 3. ChordPro. `{directive}` lines or `[C]` brackets inside running text —
  //    neither of which a grid or a number chart contains.
  if (_looksChordPro(source)) {
    final imported = chartFromChordPro(source);
    if (!imported.isEmpty) {
      return ChartImport(
        chart: imported.chart,
        format: ChartFormat.chordPro,
        barsAreInferred: imported.barsAreInferred,
        unreadable: imported.unreadable,
      );
    }
  }

  // 4. Nashville numbers against a text grid — same shape, different cells.
  if (_looksNashville(source)) {
    final imported = chartFromNashville(source);
    if (!imported.chart.isEmpty) {
      return ChartImport(
        chart: imported.chart,
        format: ChartFormat.nashville,
        unreadable: imported.unreadable,
      );
    }
  }

  // 5. A text grid, which is also the fallback: it is the format this app
  //    writes, so it is the right thing to assume when nothing else matched.
  //
  //    ⚠️ But it must be held to a HIGHER bar here than in the editor.
  //    `parseChartText` is deliberately lenient — an unreadable cell is kept
  //    as a visible best guess rather than dropped, which is right while a
  //    user is typing. Applied to a pasted paragraph it is not: "just some
  //    words about a song" parses to six chords, every one of them flagged.
  //    An importer that accepts that reports success and hands back nonsense.
  //
  //    So the fallback demands actual evidence of a grid: a barline, and cells
  //    that MOSTLY parsed without complaint.
  //
  //    Being strict here costs the user nothing, which is what makes it the
  //    right call: the chart screen's text dialog feeds the same text to the
  //    same lenient parser, so a genuinely messy chart still has a home. The
  //    two paths want opposite failure modes and both exist on purpose.
  if (!source.contains('|')) return null;
  final imported = parseChartText(source);
  if (imported.chart.isEmpty) return null;

  var cells = 0;
  for (final bar in imported.chart.barsInPlayOrder) {
    cells += bar.chordsInOrder.length;
  }
  final clean = cells - imported.problems.length;
  // A MAJORITY must be clean, not merely one cell: prose is full of stray
  // single letters that read as chord names, so `a | b` would otherwise get
  // through. With no problems at all, zero clean cells is a chart of held or
  // silent bars — odd, but a real grid.
  if (imported.problems.isNotEmpty && clean <= imported.problems.length) {
    return null;
  }

  return ChartImport(
    chart: imported.chart,
    format: ChartFormat.textGrid,
    unreadable: [for (final p in imported.problems) p.text],
  );
}

bool _looksJams(String source) {
  if (!source.startsWith('{')) return false;
  try {
    final root = jsonDecode(source);
    return root is Map && root['annotations'] is List;
  } catch (_) {
    // Starts with `{` but is not JSON — a ChordPro directive line does exactly
    // that, so falling through rather than refusing is the point.
    return false;
  }
}

bool _looksChordPro(String source) {
  // An inline bracket is decisive; `[A]` alone is a text-grid section label,
  // so a bracket only counts when something follows it ON THE SAME LINE.
  var bracketLine = false;
  for (final line in source.split('\n')) {
    if (RegExp(r'\[[^\]]*\]\s*\S').hasMatch(line)) return true;
    bracketLine |= RegExp(r'^\s*\[[^\]]+\]\s*$').hasMatch(line);
  }

  // A bracket ALONE on its line is ambiguous — a ChordPro chord with no lyric
  // under it, or a text-grid section label — and `[A]` is a valid reading of
  // both. What breaks the tie is that a text grid needs BARLINES to carry any
  // music: section labels with no `| … |` rows under them are a chart of
  // nothing. So with brackets and no barline anywhere, ChordPro is the only
  // reading that yields a tune, which makes it the right one.
  if (bracketLine && !source.contains('|')) return true;
  // Otherwise a known directive. `{title: …}` is shared with nothing else.
  return RegExp(
    r'^\{\s*(title|t|subtitle|st|artist|composer|tempo|bpm|time|key|'
    r'start_of_\w+|so[cvb]|end_of_\w+|eo[cvb]|comment|c|capo)\b',
    multiLine: true,
  ).hasMatch(source);
}

/// Whether the `| … |` rows hold NUMBERS rather than chord names.
///
/// Decided on the cells, and by majority rather than on the first one: a
/// Nashville chart may open on a held bar (`%`) and a grid may contain a stray
/// number, so either read from a single cell would be a coin toss. Ties go to
/// the text grid, since that is what the app itself writes.
bool _looksNashville(String source) {
  var numbers = 0;
  var names = 0;
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    for (final cell in trimmed.split('|')) {
      for (final token in cell.trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty || token == '%') continue;
        if (RegExp(r'^[b#]?[1-7]').hasMatch(token)) {
          numbers++;
        } else if (RegExp('^[A-G]').hasMatch(token)) {
          names++;
        }
      }
    }
  }
  return numbers > names;
}
