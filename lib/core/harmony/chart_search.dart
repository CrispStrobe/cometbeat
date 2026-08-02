// lib/core/harmony/chart_search.dart
//
// BB-U4b — finding a saved chart.
//
// One free-text box rather than five filter controls, because that is how a
// player asks for a tune: "that F blues", "the bossa at 140". Splitting it into
// dropdowns for key, tempo, style and form would be more precise and less
// usable, and the corpus here is at most `ChartStore.maxCharts` rows.
//
// The rule is ALL tokens must match SOMETHING (an AND of ORs). "f 120" finds
// the F chart at 120 and not the F chart at 90 — which is what typing two
// words means. A token that matches nothing eliminates the row rather than
// being ignored, or the search would quietly widen as the query got longer.
//
// Pure Dart on purpose: the matching is the part with the edge cases, and it
// should be unit-testable without pumping a sheet.
library;

import 'package:comet_beat/core/harmony/chart.dart';

/// The key signature written as a musician says it — `F`, `Bb`, `C#m`.
///
/// Returns null past the circle of fifths rather than inventing a name.
String? keyNameOf(int fifths, {bool minor = false}) {
  const major = [
    'Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F', //
    'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#',
  ];
  const minors = [
    'Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D', //
    'A', 'E', 'B', 'F#', 'C#', 'G#', 'D#', 'A#',
  ];
  final index = fifths + 7;
  if (index < 0 || index >= major.length) return null;
  return minor ? '${minors[index]}m' : major[index];
}

/// Whether [chart] (saved as [name]) answers [query].
///
/// An empty query matches everything, so an unfiltered list is the same code
/// path as a filtered one.
bool chartMatchesQuery(String name, Chart? chart, String query) {
  final tokens = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return true;

  final haystack = <String>{
    name.toLowerCase(),
    if (chart != null) ...[
      chart.title.toLowerCase(),
      if (chart.composer != null) chart.composer!.toLowerCase(),
      if (chart.styleId != null) chart.styleId!.toLowerCase(),
      '${chart.tempoBpm}',
      // Both spellings, so "am" finds A minor and "a" does too.
      if (keyNameOf(chart.keyFifths, minor: chart.minor) case final key?) ...[
        key.toLowerCase(),
        // The bare letter, so searching "f" finds F major without the player
        // having to know we would have written it "F".
        key.replaceAll(RegExp('m\$'), '').toLowerCase(),
      ],
      '${chart.meter.beats}/${chart.meter.beatUnit}',
      for (final section in chart.sections)
        if (section.label.isNotEmpty) section.label.toLowerCase(),
    ],
  };

  return tokens.every(
    (token) => haystack.any((field) => field.contains(token)),
  );
}

/// [saved] narrowed to [query], optionally to starred rows only.
///
/// Takes the decoded chart alongside each row because the caller already has
/// it — decoding here would parse the whole library on every keystroke.
List<T> filterCharts<T>(
  List<T> saved, {
  required String Function(T) nameOf,
  required Chart? Function(T) chartOf,
  required bool Function(T) isFavourite,
  String query = '',
  bool favouritesOnly = false,
}) =>
    [
      for (final row in saved)
        if ((!favouritesOnly || isFavourite(row)) &&
            chartMatchesQuery(nameOf(row), chartOf(row), query))
          row,
    ];
