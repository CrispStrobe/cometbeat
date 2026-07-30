// lib/core/harmony/chart_to_groove.dart
//
// BB-A0 — make a real chart audible through the band we already ship.
//
// The point is to hear a `Chart` before any of BB-A1–A6 exists, by projecting it
// onto the arranger already in `loop_engine.dart`. The engine is READ, never
// modified: its `ChordDegree`/`Progression`/`ChordFollower` path renders exactly
// as it does today, so the groove render stays byte-identical.
//
// THE ENVELOPE IS SMALL, AND SAYING SO IS THE FEATURE. `ChordDegree` is six
// diatonic triads — I ii iii IV V vi — and nothing else. No sevenths, no vii°,
// no borrowed chords, no slash bass, one chord per bar. A chart is a far richer
// document than that, so most real charts do NOT fit, and the interesting design
// question is what to do about the parts that don't.
//
// A REDUCTION, NEVER A SILENT LIE. Two different failures, kept apart because
// they mean different things to a player:
//
//   * APPROXIMATED — the chord plays, but not as written. `Cmaj7` in C sounds as
//     `C`: the root and the triad are right, the colour is gone. Musically this
//     is what a beginner's band would play anyway, so it is a reduction worth
//     making — as long as it is stated.
//   * UNREPRESENTABLE — the chord cannot play at all. `Bb7` in C major has no
//     diatonic degree; `Bdim` is vii°, which the enum does not contain. These
//     are NOT quietly turned into something nearby, because a wrong chord in a
//     backing track is worse than a missing one: the player hears it and doubts
//     their own reading.
//
// The card calls this "a throwaway-able bridge, and that is the point": it
// validates BB-D2's document against a real renderer before Phase 2 commits to
// it, and it answers early whether Chart → Progression is a permanent beginner
// fallback or scaffolding. Nothing depends on it, so deleting it stays cheap.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show ChordDegree, Progression;
import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch;

/// Why one bar's chord could not be rendered as written.
enum ChartReductionKind {
  /// It plays, with detail dropped (a seventh, an extension, a slash bass).
  approximated,

  /// It cannot play: no diatonic degree of the key matches it.
  unrepresentable,
}

/// One thing the projection had to say about one bar.
class ChartReduction {
  const ChartReduction({
    required this.kind,
    required this.barIndex,
    required this.symbol,
    required this.detail,
    this.playedAs,
  });

  final ChartReductionKind kind;

  /// Index into the chart's play order (sections expanded), so a player can be
  /// pointed at the bar they are hearing rather than at a section-relative one.
  final int barIndex;

  /// The chord as written, e.g. `Bb7`.
  final String symbol;

  /// What was lost or why it failed, in words: "the seventh is dropped",
  /// "not a diatonic chord of C major".
  final String detail;

  /// The roman numeral it sounds as, when it sounds at all.
  final String? playedAs;

  bool get isFatal => kind == ChartReductionKind.unrepresentable;

  @override
  String toString() => '$symbol @bar${barIndex + 1}: $detail';
}

/// A chart projected onto the existing engine.
class ChartProjection {
  const ChartProjection({
    required this.progression,
    required this.reductions,
    required this.barsUsed,
    required this.barsAvailable,
  });

  /// Feedable to the engine, or null when nothing could be projected at all.
  final Progression? progression;

  /// Everything the projection had to compromise on or refuse. Empty means the
  /// chart fits the engine exactly.
  final List<ChartReduction> reductions;

  /// How many of the chart's bars the progression covers.
  final int barsUsed;

  /// How many bars the chart actually has, so "we played the first 4 of 32" is
  /// visible rather than implied.
  final int barsAvailable;

  bool get isExact => reductions.isEmpty && barsUsed == barsAvailable;

  bool get isPlayable => progression != null;

  /// Chords that could not be rendered at all.
  List<ChartReduction> get unrepresentable => [
        for (final r in reductions)
          if (r.isFatal) r,
      ];

  /// A short, honest summary for a UI that has one line to spend.
  String get summary {
    if (progression == null) return 'Nothing here can play through this band.';
    final parts = <String>[
      if (barsUsed < barsAvailable) 'first $barsUsed of $barsAvailable bars',
      if (unrepresentable.isNotEmpty) '${unrepresentable.length} skipped',
      if (reductions.length > unrepresentable.length)
        '${reductions.length - unrepresentable.length} simplified',
    ];
    return parts.isEmpty ? 'Plays as written' : parts.join(' · ');
  }
}

/// How many bars the existing engine's progression path holds.
///
/// Four, because `Progression` is documented as "a 4-chord progression: one bar
/// per chord → a 4-bar loop" and the whole loop-length model is built on that.
/// Named rather than inlined so a later engine change is one edit here.
const int kGroovableBars = 4;

/// Projects [chart] onto the shipped engine, reporting every compromise.
///
/// [bars] is how many of the chart's bars to take; the default is the engine's
/// capacity. Only the FIRST [bars] are used — a chart longer than that is
/// truncated and says so, rather than being compressed into four bars, which
/// would change the music rather than shorten it.
ChartProjection chartToProgression(
  Chart chart, {
  String id = 'chart',
  int bars = kGroovableBars,
}) {
  final all = chart.barsInPlayOrder;
  final take = bars < 1 ? 0 : bars;
  // ⚠️ THE ENGINE HAS NO MINOR MODE, and this is where that surfaces.
  // `ChordDegree` is a MAJOR-key set (I ii iii IV V vi), so degrees for a minor
  // chart are taken relative to its RELATIVE MAJOR — which is exactly how the
  // engine already models minor elsewhere (`GrooveScale.minorPentatonic` is
  // documented as "the relative-major set, +3 semitones").
  //
  // The consequence is worth knowing before reading a report: an A-minor chart's
  // tonic chord is reported as `vi`, not `i`. The CHORDS are right — the same six
  // triads serve both keys — but the numerals are relative-major ones. Mapping
  // minor onto the minor tonic instead would put a MAJOR triad on `Am`, which is
  // a wrong chord rather than an odd label.
  final tonic =
      chart.minor ? (chart.tonicPitchClass + 3) % 12 : chart.tonicPitchClass;
  final reductions = <ChartReduction>[];
  final degrees = <ChordDegree>[];

  for (var i = 0; i < all.length && degrees.length < take; i++) {
    final bar = all[i];
    final chords = bar.chordsInOrder;
    if (chords.isEmpty) {
      // An empty bar continues the previous chord, which is what a chart's `%`
      // means. With nothing before it there is nothing to continue, so it is
      // skipped rather than guessed.
      if (degrees.isNotEmpty) {
        degrees.add(degrees.last);
      }
      continue;
    }

    // ONE chord per bar is the engine's shape. A split bar keeps its first
    // chord — the downbeat is the one a listener anchors to — and says the rest
    // were dropped.
    if (chords.length > 1) {
      reductions.add(
        ChartReduction(
          kind: ChartReductionKind.approximated,
          barIndex: i,
          symbol: chords.map((c) => c.chord.text).join(' '),
          detail: 'this band plays one chord per bar; '
              '${chords.length - 1} more in this bar are dropped',
        ),
      );
    }

    final spec = chords.first.chord;
    final degree = _degreeFor(spec, tonic);
    if (degree == null) {
      reductions.add(
        ChartReduction(
          kind: ChartReductionKind.unrepresentable,
          barIndex: i,
          symbol: spec.text,
          // The CHART's tonic, not the shifted degree-mapping one — a
          // minor chart must be told about its own key, not its relative
          // major's. (This said "C minor" for an A-minor chart until a
          // test read the message.)
          detail: _whyNot(spec, chart.tonicPitchClass, chart.minor),
        ),
      );
      continue;
    }

    final lost = _lostDetail(spec);
    if (lost != null) {
      reductions.add(
        ChartReduction(
          kind: ChartReductionKind.approximated,
          barIndex: i,
          symbol: spec.text,
          detail: lost,
          playedAs: degree.label,
        ),
      );
    }
    degrees.add(degree);
  }

  return ChartProjection(
    progression: degrees.isEmpty ? null : Progression(id, degrees),
    reductions: reductions,
    barsUsed: degrees.length,
    barsAvailable: all.length,
  );
}

/// The diatonic degree [spec] sounds as in the key whose tonic is [tonic], or
/// null when there is none.
///
/// Matches on ROOT and TRIAD QUALITY together. Root alone would map `Bb7` in C
/// onto nothing (correct) but would also map `Cm` in C onto `I` (wrong — a minor
/// tonic is not the major triad the engine would play).
ChordDegree? _degreeFor(ChordSpec spec, int tonic) {
  final rootPc = _pitchClass(spec.root);
  final wantMinor = switch (spec.triad) {
    ChordTriad.minor => true,
    ChordTriad.major => false,
    // Diminished, augmented and suspended triads are not major or minor, so
    // there is no degree that plays them — reported, never approximated.
    _ => null,
  };
  if (wantMinor == null) return null;

  for (final degree in ChordDegree.values) {
    if ((tonic + degree.rootOffset) % 12 != rootPc) continue;
    // `ChordDegree.triad` is the interval set; a minor third at index 1 is what
    // makes it minor. Read from the data rather than hard-coding which numerals
    // are minor, so the two cannot drift apart.
    final isMinor = degree.triad.length > 1 && degree.triad[1] == 3;
    if (isMinor == wantMinor) return degree;
  }
  return null;
}

/// What the engine drops from a chord it CAN otherwise play, or null when it
/// plays as written.
String? _lostDetail(ChordSpec spec) {
  final lost = <String>[
    if (spec.seventh != ChordSeventh.none) 'the seventh',
    if (spec.extension != 0) 'the ${spec.extension}th',
    if (spec.alterations.isNotEmpty) 'its alterations',
    if (spec.added.isNotEmpty) 'its added tones',
    if (spec.omitted.isNotEmpty) 'its omissions',
    if (spec.bass != null) 'the slash bass',
  ];
  if (lost.isEmpty) return null;
  return '${lost.join(', ')} '
      '${lost.length == 1 ? 'is' : 'are'} dropped — it plays as a plain triad';
}

/// Why a chord has no degree, in words a player can act on.
String _whyNot(ChordSpec spec, int tonic, bool minor) {
  final keyName = _pitchClassName(tonic);
  final mode = minor ? 'minor' : 'major';
  return switch (spec.triad) {
    ChordTriad.major || ChordTriad.minor => minor
        // Say relative-major, or the numerals in the rest of the report look
        // wrong to anyone reading a minor chart.
        ? 'not a diatonic chord of $keyName minor — this band plays the six '
            'triads of its relative major and nothing else'
        : 'not a diatonic chord of $keyName $mode — this band plays '
            'I ii iii IV V vi and nothing else',
    ChordTriad.diminished =>
      'a diminished triad; this band has no diminished chord',
    ChordTriad.augmented =>
      'an augmented triad; this band has no augmented chord',
    _ => 'this band plays only major and minor triads',
  };
}

/// The pitch class (0 = C) of [pitch], octave and spelling ignored.
///
/// ⚠️ Uses `midiNumber`, a real instance getter, rather than reading `step.name`
/// off a `dynamic`. The first version of this did the latter to avoid importing
/// `Pitch`, and it compiled and threw at runtime: an enum's `.name` comes from a
/// dart:core EXTENSION, and extension members are invisible to dynamic
/// dispatch. The analyzer cannot warn about that, which is the whole cost of
/// reaching for `dynamic` to save an import.
int _pitchClass(Pitch pitch) => pitch.midiNumber % 12;

const _pcNames = [
  'C',
  'C♯',
  'D',
  'E♭',
  'E',
  'F',
  'F♯',
  'G',
  'A♭',
  'A',
  'B♭',
  'B',
];

String _pitchClassName(int pc) => _pcNames[((pc % 12) + 12) % 12];
