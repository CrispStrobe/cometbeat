// lib/core/harmony/chart_level.dart
//
// BB-U6 — the beginner↔expert dial.
//
// One setting, several surfaces. It exists because of the project's rule 5:
// the MODEL stays full and only the SURFACE is gated. Without this the chart
// feature silently becomes an adults-only one — a chord grid that offers
// thirteen alterations and prints `ø` is not a thing a nine-year-old opens
// twice.
//
// ⚠️ THE INVARIANT, and it is the whole point of the card: this NEVER gates
// the model, the codec or playback. A chart written on an expert device opens,
// plays and prints correctly on a beginner one — it simply cannot be EDITED
// into every corner there. Every getter below is about what the UI offers or
// how it labels things. If one ever starts deciding what a chart may CONTAIN
// or how it SOUNDS, rule 5 is broken and the test in
// `chart_level_test.dart` should be the thing that says so.
//
// The three steps mirror `AnalysisDepth` in `score_analysis_view.dart`, which
// is the app's existing kids↔expert dial. Deliberately the same shape, so the
// two read as one idea rather than two competing ones.
library;

import 'package:comet_beat/core/harmony/chord_spec.dart';

/// How much chart machinery a player wants shown.
enum ChartLevel {
  /// Pre-reader / first year. Triads and simple sevenths, no roman numerals,
  /// two styles, one intensity. The chord grid is a picture of the song.
  beginner,

  /// The common working vocabulary — everything a pop or folk chart needs,
  /// plus function labels once they mean something.
  learner,

  /// The full altered vocabulary, jazz glyphs, every style and intensity, and
  /// repeats/codas editable rather than merely readable.
  expert;

  /// Persisted as the NAME, not the index, so reordering or inserting a level
  /// cannot silently reinterpret everyone's saved setting.
  static ChartLevel fromName(String? name) => ChartLevel.values.firstWhere(
        (l) => l.name == name,
        orElse: () => ChartLevel.learner,
      );
}

/// What each level offers. Kept as one object rather than switches scattered
/// through the widgets, so "what does a beginner see" has a single answer that
/// can be read and tested.
extension ChartLevelPolicy on ChartLevel {
  /// The chord qualities the keypad offers, by their keypad label.
  ///
  /// A beginner gets the triads and the two sevenths that carry most songs;
  /// `dim`/`aug` are included because folk and pop use them and a player who
  /// meets one needs to be able to write it. `m7b5` is NOT — it belongs to a
  /// vocabulary that arrives with function labels.
  Set<String> get qualities => switch (this) {
        ChartLevel.beginner => const {
            '',
            'm',
            '7',
            'm7',
            'maj7',
            'sus4',
            '5',
          },
        ChartLevel.learner => const {
            '',
            'm',
            '7',
            'm7',
            'maj7',
            '6',
            'm6',
            'sus4',
            'sus2',
            '7sus4',
            'dim',
            'aug',
            '5',
          },
        // Everything the table has.
        ChartLevel.expert => const {},
      };

  /// Whether [label] is offered here. Expert offers everything, which is why
  /// its set is empty rather than an exhaustive duplicate of the table — a
  /// list that has to be kept in sync is a list that will drift.
  bool offersQuality(String label) =>
      this == ChartLevel.expert || qualities.contains(label);

  /// Whether the keypad's extensions / alterations / slash-bass panel exists.
  /// A 9, a ♯11 and an inversion are all things you go looking for once you
  /// know they exist.
  bool get offersExtras => this != ChartLevel.beginner;

  /// Roman numerals and cadence names in the analysis panel.
  bool get showsRomanNumerals => this != ChartLevel.beginner;

  /// Whether repeats, endings and D.S./coda marks can be EDITED. They are
  /// always readable and always play — a beginner opening an expert's chart
  /// hears the form exactly as written; they just cannot rewrite it.
  bool get editsForm => this == ChartLevel.expert;

  /// How chord symbols print. `ø`/`∆`/`°` are lead-sheet engraving
  /// conventions, and reading them is a skill; below expert they print as the
  /// ASCII names the player already knows.
  ChordSymbolStyle get symbolStyle => this == ChartLevel.expert
      ? ChordSymbolStyle.jazz
      : ChordSymbolStyle.plain;

  /// The styles to LIST, narrowed from everything the library has. A first
  /// chart does not need six.
  ///
  /// Narrowing is expressed as an operation rather than a count so that
  /// "unlimited" needs no sentinel — and so the CURRENT style is always kept
  /// even when it falls outside the narrowed set. Opening someone's bossa
  /// chart on a beginner device must not silently re-style it; rule 5 again.
  List<T> stylesFrom<T>(List<T> all, {T? keep}) {
    if (this == ChartLevel.expert) return all;
    final limit = this == ChartLevel.beginner ? 2 : 4;
    final shown = all.take(limit).toList();
    if (keep != null && !shown.contains(keep) && all.contains(keep)) {
      shown.add(keep);
    }
    return shown;
  }

  /// How many intensity steps to offer out of [available], counting from the
  /// quietest. Never returns 0 for a style that has any.
  int intensityCount(int available) {
    final limit = switch (this) {
      ChartLevel.beginner => 1,
      ChartLevel.learner => 3,
      ChartLevel.expert => available,
    };
    return available < limit ? available : limit;
  }
}
