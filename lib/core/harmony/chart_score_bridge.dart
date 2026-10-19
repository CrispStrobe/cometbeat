// lib/core/harmony/chart_score_bridge.dart
//
// BB-D3 — a chart prints and exports as a lead sheet; a score with chord
// symbols imports as a chart.
//
// THE VOCABULARIES ARE SHAPED DIFFERENTLY. `ChordSpec` is compositional — any
// triad, any seventh, a stack height, a set of alterations, adds, omits and a
// slash bass. A `ChordSymbol` is MusicXML's: one of its `<kind>` values plus
// `<degree>` alterations, so `C13#11` is `13` with a raised 11 — exact. What it
// cannot hold is two tones on one degree (`C7b9#9`, the `alt` chord), and the
// honest thing there is not to pick the nearest and stay quiet: it is to pick
// the nearest AND SAY WHAT WAS LOST. Every conversion here returns a loss
// report beside its result.
//
// ⚠️ The anchor is SYNTHESISED app-side, per the card's decision 7.
// `ChordSymbol` binds to a NOTE ELEMENT ID and a chart bar has chords and no
// notes, so the bridge emits one rhythm note per chord and anchors to that. It
// needs no crisp_notation API change, and it is also what makes the bar print.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Something a conversion could not carry across.
class BridgeLoss {
  const BridgeLoss({
    required this.barNumber,
    required this.symbol,
    required this.detail,
    this.keptAs,
  });

  /// 1-based bar in the chart.
  final int barNumber;

  /// The chord as written.
  final String symbol;

  /// What could not be carried, in words a musician would use.
  final String detail;

  /// What was written instead, when something was.
  final String? keptAs;

  @override
  String toString() => keptAs == null
      ? 'bar $barNumber: $symbol — $detail'
      : 'bar $barNumber: $symbol → $keptAs ($detail)';
}

/// A conversion plus everything it could not carry.
class BridgeResult<T> {
  const BridgeResult(this.value, this.losses);

  final T value;
  final List<BridgeLoss> losses;

  bool get isExact => losses.isEmpty;

  /// One line for a UI. Deliberately counts rather than lists: a chart with
  /// forty altered chords must not produce a forty-line dialog.
  String get summary => losses.isEmpty
      ? 'Every chord carried across.'
      : '${losses.length} chord${losses.length == 1 ? '' : 's'} simplified.';
}

// ---------------------------------------------------------------- chart → score

/// A chart as an engravable score.
///
/// One bar per chart bar, each carrying a rhythm note per chord with the chord
/// symbol above it. The notes exist to be an ANCHOR and a printed slash; they
/// are not a melody, and nothing should read them as one.
BridgeResult<Score> chartToScore(Chart chart, {Step slashStep = Step.b}) {
  final losses = <BridgeLoss>[];
  final measures = <Measure>[];
  final symbols = <ChordSymbol>[];

  var id = 0;
  var barNumber = 0;

  for (final bar in chart.barsInPlayOrder) {
    barNumber++;
    final meter = bar.meterChange ?? chart.meter;
    final beats = meter.beats * 4 / meter.beatUnit;
    final chords = bar.chordsInOrder;
    final elements = <MusicElement>[];

    if (chords.isEmpty) {
      // A held bar has no chord of its own; a whole-bar rest keeps the bar
      // count right, which is what makes bar 17 mean the same thing on both
      // sides of the bridge.
      elements.add(RestElement(_durationForBeats(beats)));
    } else {
      for (var i = 0; i < chords.length; i++) {
        final chord = chords[i];
        final next = i + 1 < chords.length ? chords[i + 1].beat : beats;
        final span = (next - chord.beat).clamp(0.25, beats);
        final noteId = 'c${id++}';

        elements.add(
          NoteElement(
            // A single unpitched-looking note on the middle line: the
            // conventional way to print "play the chord, rhythm as written".
            pitches: [Pitch(slashStep)],
            duration: _durationForBeats(span),
            id: noteId,
          ),
        );

        final mapped = chordSymbolFor(chord.chord);
        if (mapped.detail != null) {
          losses.add(
            BridgeLoss(
              barNumber: barNumber,
              symbol: chord.chord.text,
              detail: mapped.detail!,
              keptAs: ChordSymbol(
                '',
                chord.chord.root,
                mapped.kind,
                degrees: mapped.degrees,
              ).text,
            ),
          );
        }
        symbols.add(
          ChordSymbol(
            noteId,
            chord.chord.root,
            mapped.kind,
            bass: chord.chord.bass,
            degrees: mapped.degrees,
          ),
        );
      }
    }
    measures.add(Measure(elements));
  }

  return BridgeResult(
    Score(
      clef: Clef.treble,
      keySignature: KeySignature(chart.keyFifths),
      timeSignature: chart.meter,
      measures: measures,
      chordSymbols: symbols,
      // ⚠️ The tempo has to travel too. Without it a chart → score → chart
      // round trip silently reset to the default 120, which a play-along
      // exposes immediately: the band plays at the wrong speed and the melody
      // with it. Caught by a test asserting a 60bpm piece offsets its melody
      // twice as far as a 120bpm one.
      tempo: Tempo(chart.tempoBpm.toDouble()),
      metadata: ScoreMetadata(
        title: chart.title.isEmpty ? null : chart.title,
        composer: chart.composer,
      ),
    ),
    losses,
  );
}

// ---------------------------------------------------------------- score → chart

/// A score's chord symbols as a chart.
///
/// One chart bar per measure, with the symbols that measure carries. A measure
/// with no symbol becomes a HELD bar rather than a silent one, because that is
/// what an unmarked bar means on a lead sheet.
BridgeResult<Chart> chartFromScore(Score score, {String title = ''}) {
  final losses = <BridgeLoss>[];
  // Several symbols can stand over one note, each at its own offset (a chord
  // track denser than the melody).
  final byId = <String, List<ChordSymbol>>{};
  for (final s in score.chordSymbols) {
    (byId[s.elementId] ??= []).add(s);
  }
  final bars = <ChartBar>[];

  final meter = score.timeSignature ?? const TimeSignature(4, 4);
  final beatsPerBar = meter.beats * 4 / meter.beatUnit;

  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    final chords = <ChartBeatChord>[];
    var elapsed = 0.0;

    for (final element in measure.elements) {
      if (element is NoteElement) {
        for (final symbol in byId[element.id] ?? const <ChordSymbol>[]) {
          // N.C. stops the harmony: on a chart that is a bar with no chord.
          if (symbol.quality == ChordSymbolKind.none) continue;
          chords.add(
            ChartBeatChord(
              chord: chordSpecFor(symbol),
              // The symbol sounds where its note sounds, plus its own offset,
              // so its beat is the elapsed time in the bar — not its index,
              // which would be wrong the moment a bar holds anything but
              // equal values.
              beat: (elapsed + symbol.offset.toDouble() * 4)
                  .clamp(0.0, beatsPerBar),
            ),
          );
        }
        elapsed += element.duration.toFraction().toDouble() * 4;
      } else if (element is RestElement) {
        elapsed += element.duration.toFraction().toDouble() * 4;
      }
    }
    bars.add(ChartBar(chords: chords));
  }

  return BridgeResult(
    Chart(
      title: title.isNotEmpty ? title : (score.metadata.title ?? ''),
      composer: score.metadata.composer,
      keyFifths: score.keySignature.fifths,
      meter: meter,
      tempoBpm: score.tempo == null
          ? const Chart().tempoBpm
          : score.tempo!.quarterBpm.round().clamp(1, 400),
      sections: [ChartSection(bars: bars)],
    ),
    losses,
  );
}

// ---------------------------------------------------------------- the mapping

/// [spec] as a `ChordSymbolKind` and the degrees that adjust it, and what
/// that cost.
///
/// crisp_notation's vocabulary is MusicXML's: a kind (`<kind>`) and degree
/// alterations (`<degree>`), so `C13#11` is `13` with `#11` and `C6/9` is `6`
/// with an added 9 — exact. [detail] is null then. It is prose rather than a
/// code because it goes straight to a musician: "the ♯9 cannot be written"
/// is actionable, `EXT_UNREPRESENTABLE` is not.
///
/// ⚠️ A symbol holds ONE tone per degree, so a chord with two ninths (`C7b9#9`,
/// or `C7alt`, which sounds both) keeps the lower and reports the other.
({ChordSymbolKind kind, List<ChordDegree> degrees, String? detail})
    chordSymbolFor(ChordSpec spec) {
  final kind = _bestKind(spec);
  final target = spec.intervals.toSet();
  // ⚠️ The chart leaves the 11th out of a 13th chord and LilyPond (whose
  // voicing crisp_notation's kinds follow) keeps it in a minor one: the same
  // chord name, a voicing convention apart — not a tone to subtract.
  if (kind == ChordSymbolKind.minorThirteenth) target.add(17);
  final base = kind.tones;
  final degrees = <ChordDegree>[];

  // A tone the kind has that the chord lacks or alters.
  final claimed = <int>{};
  for (final MapEntry(key: degree, value: semitones) in base.entries) {
    if (target.contains(semitones)) {
      claimed.add(semitones);
      continue;
    }
    final altered = [
      for (final delta in const [-1, 1, -2, 2])
        if (target.contains(semitones + delta) &&
            !base.containsValue(semitones + delta) &&
            !claimed.contains(semitones + delta))
          semitones + delta,
    ];
    if (altered.isNotEmpty && degree != 1) {
      degrees.add(ChordDegree.alter(degree, altered.first - semitones));
      claimed.add(altered.first);
    } else {
      degrees.add(ChordDegree.subtract(degree));
    }
  }
  // A tone the chord has that the kind does not, added at its usual degree.
  final taken = {for (final d in degrees) d.value, ...base.keys};
  for (final semitones in target.toList()..sort()) {
    if (claimed.contains(semitones)) continue;
    final degree = _degreeOf[semitones];
    if (degree == null || taken.contains(degree)) continue;
    degrees.add(
      ChordDegree.add(degree, alter: semitones - chordDegreeSemitones[degree]!),
    );
    taken.add(degree);
  }
  degrees.sort((a, b) => a.value.compareTo(b.value));

  final written =
      ChordSymbol('', spec.root, kind, degrees: degrees).tones.values.toSet();
  final lost = [
    for (final t in target.difference(written)) _toneName[t] ?? '$t',
  ];
  final named = spec.alterations.contains(ChordAlteration.altered);
  return (
    kind: kind,
    degrees: degrees,
    detail: lost.isEmpty && !named
        ? null
        : [
            if (named) 'the alt is written as its tones',
            if (lost.isNotEmpty) '${lost.join(', ')} cannot be written',
          ].join('; '),
  );
}

/// The degree a tone this many semitones over the root is usually written
/// as, when the kind does not already hold it.
const _degreeOf = {
  2: 2, 3: 3, 4: 3, 5: 4, 6: 5, 8: 5, 9: 6, 10: 7, 11: 7, //
  13: 9, 14: 9, 15: 9, 17: 11, 18: 11, 20: 13, 21: 13,
};

const _toneName = {
  13: 'the ♭9', 14: 'the 9th', 15: 'the ♯9', 17: 'the 11th', //
  18: 'the ♯11', 20: 'the ♭13', 21: 'the 13th',
};

/// The kind closest to [spec]: its triad, its seventh and its stack height.
ChordSymbolKind _bestKind(ChordSpec spec) {
  final minor = spec.triad == ChordTriad.minor;
  final flatFive = spec.alterations.contains(ChordAlteration.flatFive);
  switch (spec.triad) {
    case ChordTriad.fifthOnly:
      return ChordSymbolKind.power;
    case ChordTriad.sus2:
      return ChordSymbolKind.suspendedSecond;
    case ChordTriad.sus4:
      return ChordSymbolKind.suspendedFourth;
    case ChordTriad.diminished:
      return switch (spec.seventh) {
        ChordSeventh.diminished => ChordSymbolKind.diminishedSeventh,
        ChordSeventh.minor => ChordSymbolKind.halfDiminishedSeventh,
        _ => ChordSymbolKind.diminished,
      };
    case ChordTriad.augmented:
      return spec.seventh == ChordSeventh.minor
          ? ChordSymbolKind.augmentedSeventh
          : ChordSymbolKind.augmented;
    case ChordTriad.major || ChordTriad.minor:
  }
  // A minor triad with a flattened fifth IS a diminished chord, and with a
  // minor seventh on top it is half-diminished — both of which the vocabulary
  // spells exactly, so the ♭5 needs no degree.
  if (minor && flatFive) {
    return switch (spec.seventh) {
      ChordSeventh.minor => ChordSymbolKind.halfDiminishedSeventh,
      ChordSeventh.diminished => ChordSymbolKind.diminishedSeventh,
      ChordSeventh.none => ChordSymbolKind.diminished,
      _ => ChordSymbolKind.minor,
    };
  }
  return switch ((spec.seventh, spec.extension, minor)) {
    (ChordSeventh.none, _, false) => ChordSymbolKind.major,
    (ChordSeventh.none, _, true) => ChordSymbolKind.minor,
    (ChordSeventh.sixth, _, false) => ChordSymbolKind.sixth,
    (ChordSeventh.sixth, _, true) => ChordSymbolKind.minorSixth,
    (ChordSeventh.diminished, _, _) => ChordSymbolKind.diminishedSeventh,
    (ChordSeventh.major, _, true) => ChordSymbolKind.minorMajorSeventh,
    (ChordSeventh.major, 9, false) => ChordSymbolKind.majorNinth,
    (ChordSeventh.major, 11, false) => ChordSymbolKind.majorEleventh,
    (ChordSeventh.major, 13, false) => ChordSymbolKind.majorThirteenth,
    (ChordSeventh.major, _, false) => ChordSymbolKind.majorSeventh,
    (ChordSeventh.minor, 9, true) => ChordSymbolKind.minorNinth,
    (ChordSeventh.minor, 11, true) => ChordSymbolKind.minorEleventh,
    (ChordSeventh.minor, 13, true) => ChordSymbolKind.minorThirteenth,
    (ChordSeventh.minor, _, true) => ChordSymbolKind.minorSeventh,
    (ChordSeventh.minor, 9, false) => ChordSymbolKind.dominantNinth,
    (ChordSeventh.minor, 11, false) => ChordSymbolKind.dominantEleventh,
    (ChordSeventh.minor, 13, false) => ChordSymbolKind.dominantThirteenth,
    (ChordSeventh.minor, _, false) => ChordSymbolKind.dominantSeventh,
  };
}

/// A `ChordSymbol` as a `ChordSpec`.
///
/// Lossless for every kind a chart can hold: the kind sets the triad, seventh
/// and stack height, and the symbol's degrees (`G7(b9)`, `C6/9`, `C(omit3)`)
/// become alterations, added and omitted tones. The functional kinds (the
/// augmented sixths, Neapolitan, Tristan) and a pedal come across as the chord
/// they sound; `other` and N.C. as a major triad (a chart bar with no chord is
/// a held bar, which [chartFromScore] makes of an N.C. by leaving it out).
ChordSpec chordSpecFor(ChordSymbol symbol) {
  const flat5 = ChordAlteration.flatFive;
  final alterations = <ChordAlteration>{};
  final omitted = <int>{};
  final (triad, seventh, extension) = switch (symbol.quality) {
    ChordSymbolKind.major ||
    ChordSymbolKind.neapolitan ||
    ChordSymbolKind.other ||
    ChordSymbolKind.none =>
      (ChordTriad.major, ChordSeventh.none, 0),
    ChordSymbolKind.minor => (ChordTriad.minor, ChordSeventh.none, 0),
    ChordSymbolKind.diminished => (ChordTriad.diminished, ChordSeventh.none, 0),
    ChordSymbolKind.augmented => (ChordTriad.augmented, ChordSeventh.none, 0),
    ChordSymbolKind.dominantSeventh || ChordSymbolKind.german => (
        ChordTriad.major,
        ChordSeventh.minor,
        0
      ),
    ChordSymbolKind.majorSeventh => (ChordTriad.major, ChordSeventh.major, 0),
    ChordSymbolKind.minorSeventh => (ChordTriad.minor, ChordSeventh.minor, 0),
    // ⚠️ NOT a diminished triad. `chord_spec.dart` documents the canonical
    // spelling: a half-diminished IS a minor core with a flat five, and its
    // formatter treats a diminished triad carrying a minor seventh as a TRUE
    // diminished chord — so returning (diminished, minor) here printed `Cdim7`
    // for a `Cm7♭5`, which is a different chord. A round trip must land back on
    // the representation the parser produces. The Tristan chord is one too.
    ChordSymbolKind.halfDiminishedSeventh || ChordSymbolKind.tristan => (
        ChordTriad.minor,
        ChordSeventh.minor,
        0
      ),
    ChordSymbolKind.diminishedSeventh => (
        ChordTriad.diminished,
        ChordSeventh.diminished,
        0
      ),
    ChordSymbolKind.minorMajorSeventh => (
        ChordTriad.minor,
        ChordSeventh.major,
        0
      ),
    ChordSymbolKind.sixth => (ChordTriad.major, ChordSeventh.sixth, 0),
    ChordSymbolKind.minorSixth => (ChordTriad.minor, ChordSeventh.sixth, 0),
    ChordSymbolKind.dominantNinth => (ChordTriad.major, ChordSeventh.minor, 9),
    ChordSymbolKind.majorNinth => (ChordTriad.major, ChordSeventh.major, 9),
    ChordSymbolKind.minorNinth => (ChordTriad.minor, ChordSeventh.minor, 9),
    ChordSymbolKind.dominantEleventh => (
        ChordTriad.major,
        ChordSeventh.minor,
        11
      ),
    ChordSymbolKind.majorEleventh => (ChordTriad.major, ChordSeventh.major, 11),
    ChordSymbolKind.minorEleventh => (ChordTriad.minor, ChordSeventh.minor, 11),
    ChordSymbolKind.dominantThirteenth => (
        ChordTriad.major,
        ChordSeventh.minor,
        13
      ),
    ChordSymbolKind.majorThirteenth => (
        ChordTriad.major,
        ChordSeventh.major,
        13
      ),
    ChordSymbolKind.minorThirteenth => (
        ChordTriad.minor,
        ChordSeventh.minor,
        13
      ),
    ChordSymbolKind.augmentedSeventh => (
        ChordTriad.augmented,
        ChordSeventh.minor,
        0
      ),
    // The Italian sixth is a dominant seventh without its fifth, the French
    // one with its fifth flattened.
    ChordSymbolKind.italian => (ChordTriad.major, ChordSeventh.minor, 0),
    ChordSymbolKind.french => (ChordTriad.major, ChordSeventh.minor, 0),
    ChordSymbolKind.suspendedFourth => (ChordTriad.sus4, ChordSeventh.none, 0),
    ChordSymbolKind.suspendedSecond => (ChordTriad.sus2, ChordSeventh.none, 0),
    ChordSymbolKind.power => (ChordTriad.fifthOnly, ChordSeventh.none, 0),
    ChordSymbolKind.pedal => (ChordTriad.fifthOnly, ChordSeventh.none, 0),
  };
  switch (symbol.quality) {
    case ChordSymbolKind.halfDiminishedSeventh ||
          ChordSymbolKind.tristan ||
          ChordSymbolKind.french:
      alterations.add(flat5);
    case ChordSymbolKind.italian || ChordSymbolKind.pedal:
      omitted.add(5);
    default:
  }

  // The symbol's degrees, as the chart vocabulary writes them.
  final added = <int>{};
  var seventhSlot = seventh;
  var stack = extension;
  for (final d in symbol.degrees) {
    if (d.type == ChordDegreeType.subtract) {
      if (d.value == 3 || d.value == 5) omitted.add(d.value);
      continue;
    }
    final alteration = switch ((d.value, d.alter)) {
      (5, -1) => flat5,
      (5, 1) => ChordAlteration.sharpFive,
      (9, -1) => ChordAlteration.flatNine,
      (9, 1) => ChordAlteration.sharpNine,
      (11, 1) => ChordAlteration.sharpEleven,
      (13, -1) => ChordAlteration.flatThirteen,
      _ => null,
    };
    if (alteration != null) {
      alterations.add(alteration);
    } else if (d.type == ChordDegreeType.add &&
        d.value == 7 &&
        seventhSlot == ChordSeventh.none) {
      // An added 7 is a minor seventh (MusicXML counts an added degree from a
      // dominant chord), raised a semitone a major one.
      seventhSlot = switch (d.alter) {
        1 => ChordSeventh.major,
        -1 => ChordSeventh.diminished,
        _ => ChordSeventh.minor,
      };
    } else if (d.type == ChordDegreeType.add && d.alter == 0) {
      // The other added tones are the chart's adds.
      if (d.value == 9 &&
          stack == 0 &&
          (seventhSlot == ChordSeventh.minor ||
              seventhSlot == ChordSeventh.major)) {
        // A ninth over a seventh is the stack reaching it: `C9sus4`, not
        // `C7sus4add9` (a sixth keeps its added 9: `C6/9`).
        stack = 9;
      } else if (const {2, 4, 6, 9, 11, 13}.contains(d.value)) {
        added.add(d.value);
      }
    }
  }

  return ChordSpec(
    root: symbol.root,
    triad: triad,
    seventh: seventhSlot,
    extension: stack,
    alterations: alterations,
    added: added,
    omitted: omitted,
    bass: symbol.bass,
  );
}

// ---------------------------------------------------------------- helpers

/// The note value closest to [beats], never longer than it.
///
/// A chart bar is divided by chord CHANGES, not by note values, so a chord
/// lasting three beats has no single symbol. Rounding DOWN keeps the bar from
/// overflowing, which the engraver would otherwise reflow.
NoteDuration _durationForBeats(double beats) {
  const table = <(double, NoteDuration)>[
    (4, NoteDuration(DurationBase.whole)),
    (3, NoteDuration(DurationBase.half, dots: 1)),
    (2, NoteDuration(DurationBase.half)),
    (1.5, NoteDuration(DurationBase.quarter, dots: 1)),
    (1, NoteDuration(DurationBase.quarter)),
    (0.75, NoteDuration(DurationBase.eighth, dots: 1)),
    (0.5, NoteDuration(DurationBase.eighth)),
  ];
  for (final (value, duration) in table) {
    if (beats >= value - 1e-6) return duration;
  }
  return const NoteDuration(DurationBase.sixteenth);
}
