// lib/core/harmony/chart_score_bridge.dart
//
// BB-D3 — a chart prints and exports as a lead sheet; a score with chord
// symbols imports as a chart.
//
// THE VOCABULARIES ARE NOT THE SAME SIZE, and that is the whole difficulty.
// `ChordSpec` is compositional — any triad, any seventh, a stack height, a set
// of alterations, adds, omits and a slash bass. `ChordSymbolKind` is a closed
// list of 15 MusicXML `<kind>` values. So `C13#11` has no faithful
// `ChordSymbolKind`, and the honest thing is not to pick the nearest and stay
// quiet: it is to pick the nearest AND SAY WHAT WAS LOST. Every conversion here
// returns a loss report beside its result.
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
              keptAs: '${_rootText(chord.chord.root)}${mapped.kind.suffix}',
            ),
          );
        }
        symbols.add(
          ChordSymbol(
            noteId,
            chord.chord.root,
            mapped.kind,
            bass: chord.chord.bass,
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
  final byId = {for (final s in score.chordSymbols) s.elementId: s};
  final bars = <ChartBar>[];

  final meter = score.timeSignature ?? const TimeSignature(4, 4);
  final beatsPerBar = meter.beats * 4 / meter.beatUnit;

  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    final chords = <ChartBeatChord>[];
    var elapsed = 0.0;

    for (final element in measure.elements) {
      if (element is NoteElement) {
        final symbol = element.id == null ? null : byId[element.id];
        if (symbol != null) {
          chords.add(
            ChartBeatChord(
              chord: chordSpecFor(symbol),
              // The symbol sounds where its note sounds, so its beat is the
              // elapsed time in the bar — not its index, which would be wrong
              // the moment a bar holds anything but equal values.
              beat: elapsed.clamp(0.0, beatsPerBar),
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

/// The closest `ChordSymbolKind` to [spec], and what that cost.
///
/// [detail] is null when the mapping is exact. It is prose rather than a code
/// because it goes straight to a musician: "the ♯11 is dropped" is actionable,
/// `EXT_UNREPRESENTABLE` is not.
({ChordSymbolKind kind, String? detail}) chordSymbolFor(ChordSpec spec) {
  final (kind, absorbed) = _bestKind(spec);
  final dropped = <String>[];

  if (spec.extension == 11) dropped.add('the 11th');
  if (spec.extension == 13) dropped.add('the 13th');

  // ⚠️ Only alterations the chosen kind does NOT already express. The kind has
  // to decide this, not a table up front: `Cm7♭5` is parsed as a MINOR triad
  // with a ♭5, not as a diminished one, so a naive "a ♭5 is always lost" reports
  // a loss on a chord the vocabulary spells exactly. Found by the test asserting
  // every exactly-representable quality reports nothing.
  for (final alteration in spec.alterations) {
    if (absorbed.contains(alteration)) continue;
    dropped.add(
      switch (alteration) {
        ChordAlteration.flatNine => 'the ♭9',
        ChordAlteration.sharpNine => 'the ♯9',
        ChordAlteration.sharpEleven => 'the ♯11',
        ChordAlteration.flatThirteen => 'the ♭13',
        ChordAlteration.altered => 'the altered tones',
        ChordAlteration.flatFive => 'the ♭5',
        ChordAlteration.sharpFive => 'the ♯5',
      },
    );
  }
  for (final added in spec.added) {
    dropped.add('the added $added');
  }
  for (final omitted in spec.omitted) {
    dropped.add('the omitted $omitted');
  }
  if (spec.triad == ChordTriad.fifthOnly) {
    dropped.add('the missing third (written as a major triad)');
  }
  if (spec.triad == ChordTriad.augmented && spec.seventh != ChordSeventh.none) {
    dropped.add('the seventh over an augmented triad');
  }

  return (
    kind: kind,
    detail: dropped.isEmpty ? null : '${dropped.join(', ')} cannot be written',
  );
}

/// The closest kind, and which alterations that kind already expresses.
(ChordSymbolKind, Set<ChordAlteration>) _bestKind(ChordSpec spec) {
  const none = <ChordAlteration>{};
  final alts = spec.alterations;
  final flatFive = alts.contains(ChordAlteration.flatFive);
  final sharpFive = alts.contains(ChordAlteration.sharpFive);

  if (spec.triad == ChordTriad.fifthOnly) {
    return (ChordSymbolKind.major, none);
  }
  if (spec.triad == ChordTriad.sus2) {
    return (ChordSymbolKind.suspendedSecond, none);
  }
  if (spec.triad == ChordTriad.sus4) {
    return (ChordSymbolKind.suspendedFourth, none);
  }

  if (spec.triad == ChordTriad.diminished) {
    return switch (spec.seventh) {
      ChordSeventh.diminished => (ChordSymbolKind.diminishedSeventh, none),
      ChordSeventh.minor => (ChordSymbolKind.halfDiminishedSeventh, none),
      _ => (ChordSymbolKind.diminished, none),
    };
  }
  if (spec.triad == ChordTriad.augmented) {
    return (ChordSymbolKind.augmented, none);
  }

  final minor = spec.triad == ChordTriad.minor;

  // A minor triad with a flattened fifth IS a diminished chord, and with a
  // minor seventh on top it is half-diminished — both of which the vocabulary
  // spells exactly, so the ♭5 is absorbed rather than lost.
  if (minor && flatFive) {
    const absorbs = {ChordAlteration.flatFive};
    return switch (spec.seventh) {
      ChordSeventh.minor => (ChordSymbolKind.halfDiminishedSeventh, absorbs),
      ChordSeventh.diminished => (ChordSymbolKind.diminishedSeventh, absorbs),
      ChordSeventh.none => (ChordSymbolKind.diminished, absorbs),
      _ => (ChordSymbolKind.minor, none),
    };
  }
  // Likewise a major triad with a raised fifth is augmented.
  if (!minor && sharpFive && spec.seventh == ChordSeventh.none) {
    return (ChordSymbolKind.augmented, {ChordAlteration.sharpFive});
  }

  return switch (spec.seventh) {
    ChordSeventh.none => (
        minor ? ChordSymbolKind.minor : ChordSymbolKind.major,
        none
      ),
    ChordSeventh.sixth => (
        minor ? ChordSymbolKind.minorSixth : ChordSymbolKind.sixth,
        none
      ),
    ChordSeventh.major => (
        minor
            ? ChordSymbolKind.minorMajorSeventh
            : ChordSymbolKind.majorSeventh,
        none
      ),
    ChordSeventh.diminished => (ChordSymbolKind.diminishedSeventh, none),
    ChordSeventh.minor => (
        minor
            ? ChordSymbolKind.minorSeventh
            : (spec.extension == 9
                ? ChordSymbolKind.dominantNinth
                : ChordSymbolKind.dominantSeventh),
        none
      ),
  };
}

/// A `ChordSymbol` as a `ChordSpec`.
///
/// Lossless in this direction: every `ChordSymbolKind` is expressible in the
/// richer type, which is the whole reason the loss only appears going the other
/// way.
ChordSpec chordSpecFor(ChordSymbol symbol) {
  final (triad, seventh, extension) = switch (symbol.quality) {
    ChordSymbolKind.major => (ChordTriad.major, ChordSeventh.none, 0),
    ChordSymbolKind.minor => (ChordTriad.minor, ChordSeventh.none, 0),
    ChordSymbolKind.diminished => (ChordTriad.diminished, ChordSeventh.none, 0),
    ChordSymbolKind.augmented => (ChordTriad.augmented, ChordSeventh.none, 0),
    ChordSymbolKind.dominantSeventh => (
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
    // the representation the parser produces.
    ChordSymbolKind.halfDiminishedSeventh => (
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
    ChordSymbolKind.suspendedFourth => (ChordTriad.sus4, ChordSeventh.none, 0),
    ChordSymbolKind.suspendedSecond => (ChordTriad.sus2, ChordSeventh.none, 0),
  };
  return ChordSpec(
    root: symbol.root,
    triad: triad,
    seventh: seventh,
    extension: extension,
    alterations: symbol.quality == ChordSymbolKind.halfDiminishedSeventh
        ? const {ChordAlteration.flatFive}
        : const {},
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

String _rootText(Pitch root) {
  final letter = root.step.name.toUpperCase();
  if (root.alter > 0) return letter + '#' * root.alter;
  if (root.alter < 0) return letter + 'b' * -root.alter;
  return letter;
}
