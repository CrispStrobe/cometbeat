// lib/core/harmony/chart_analysis.dart
//
// BB-X6 — the chart explains itself.
//
// Per bar: the roman numeral, the harmonic function, and a scale to solo on.
// Per phrase: ii–V chains, turnarounds and cadences. None of the theory is
// reimplemented here — `romanNumeralFor` and `functionOf` already do it, and
// doing it again would give the app two answers to the same question.
//
// 🔴 A SECONDARY DOMINANT IS A DOMINANT, NOT A KEY CHANGE. `A7` in C is `V7/ii`
// — still a dominant, still explained in C, and a chart that redrew its key
// every time one appeared would be unreadable. The library already gets this
// right; this file's job is to keep it right end to end, which is exactly what
// the card asks to be asserted.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// What one chord means in the key.
class ChordReading {
  const ChordReading({
    required this.barNumber,
    required this.chord,
    required this.numeral,
    required this.function,
    required this.isSecondary,
    required this.scale,
    required this.guideTones,
  });

  /// 1-based bar in play order.
  final int barNumber;
  final ChordSpec chord;

  /// e.g. `ii7`, `V7/V`, `bVII`.
  final RomanNumeral numeral;

  /// Tonic / subdominant / dominant, or null where the chord has no function
  /// in this key.
  final HarmonicFunction? function;

  /// True when this is an applied chord — `V7/ii` and friends.
  final bool isSecondary;

  /// What to solo on, in words a player uses.
  final String scale;

  /// The third and the seventh: the two notes that carry the harmony, as
  /// semitones above the root.
  final List<int> guideTones;

  String get symbol => chord.text;
}

/// Something true of a RUN of chords rather than one.
enum PhraseKind {
  /// A ii–V, the commonest two-chord unit in the repertoire.
  twoFive,

  /// A ii–V–I: the same, resolved.
  twoFiveOne,

  /// A perfect cadence, V→I.
  perfectCadence,

  /// A plagal cadence, IV→I.
  plagalCadence,

  /// A phrase that ends ON the dominant.
  halfCadence,

  /// V→vi: the resolution that is not one.
  deceptiveCadence,

  /// A turnaround: the last bars leading back to the top.
  turnaround,
}

/// One thing worth pointing out, over a span of bars.
class PhraseNote {
  const PhraseNote({
    required this.kind,
    required this.fromBar,
    required this.toBar,
    required this.label,
  });

  final PhraseKind kind;

  /// 1-based, inclusive.
  final int fromBar;
  final int toBar;

  /// What to show, already in words: `ii–V in C`, `perfect cadence`.
  final String label;

  @override
  String toString() => '$label (bars $fromBar–$toBar)';
}

/// A chart, explained.
class ChartAnalysis {
  const ChartAnalysis({
    required this.key,
    required this.chords,
    required this.phrases,
  });

  final Key key;
  final List<ChordReading> chords;
  final List<PhraseNote> phrases;

  bool get isEmpty => chords.isEmpty;

  /// The phrase notes touching [barNumber], for a per-bar UI.
  List<PhraseNote> phrasesAt(int barNumber) => [
        for (final phrase in phrases)
          if (barNumber >= phrase.fromBar && barNumber <= phrase.toBar) phrase,
      ];
}

/// Explains [chart].
ChartAnalysis analyzeChart(Chart chart) {
  final key = _keyOf(chart);
  final readings = <ChordReading>[];

  var barNumber = 0;
  for (final bar in chart.barsInPlayOrder) {
    barNumber++;
    for (final chord in bar.chordsInOrder) {
      final analysis = _asChordAnalysis(chord.chord);
      final numeral = romanNumeralFor(analysis, key);
      readings.add(
        ChordReading(
          barNumber: barNumber,
          chord: chord.chord,
          numeral: numeral,
          function: functionOf(numeral),
          isSecondary: numeral.appliedTo != null,
          scale: scaleFor(chord.chord, numeral),
          guideTones: chord.chord.guideTones,
        ),
      );
    }
  }

  return ChartAnalysis(
    key: key,
    chords: readings,
    phrases: _phrases(readings, key),
  );
}

/// The scale a player would solo on over [chord].
///
/// Named the way a musician names it rather than by mode number: "D dorian" is
/// what gets said on a bandstand, and the numeral is what decides it — the same
/// chord means different things on different degrees.
String scaleFor(ChordSpec chord, RomanNumeral numeral) {
  final root = _rootName(chord.root);

  // An applied dominant borrows the scale of what it is resolving TO, which is
  // why it is worth knowing that it IS applied.
  if (numeral.appliedTo != null) {
    return chord.alterations.isEmpty ? '$root mixolydian' : '$root altered';
  }

  if (chord.alterations.contains(ChordAlteration.altered)) {
    return '$root altered';
  }
  // ⚠️ A half-diminished chord is parsed as a MINOR triad with a ♭5, not as a
  // diminished one — the canonical spelling `chord_spec.dart` documents. This
  // is the THIRD place in this arc that has had to say so (the score bridge and
  // the scorer projection were the others), so it is worth stating plainly:
  // never test `triad == diminished` alone when you mean "this chord is
  // diminished-ish".
  final flatFive = chord.alterations.contains(ChordAlteration.flatFive);
  if (chord.triad == ChordTriad.diminished ||
      (chord.triad == ChordTriad.minor && flatFive)) {
    return chord.seventh == ChordSeventh.diminished
        ? '$root diminished'
        : '$root locrian';
  }
  if (chord.triad == ChordTriad.sus4 || chord.triad == ChordTriad.sus2) {
    return '$root mixolydian';
  }
  if (chord.triad == ChordTriad.minor) {
    return switch (numeral.degree) {
      2 => '$root dorian',
      3 => '$root phrygian',
      6 => '$root aeolian',
      _ => '$root dorian',
    };
  }
  if (chord.seventh == ChordSeventh.minor) return '$root mixolydian';
  return numeral.degree == 4 ? '$root lydian' : '$root major';
}

/// The ii–Vs, cadences and turnarounds.
List<PhraseNote> _phrases(List<ChordReading> chords, Key key) {
  final out = <PhraseNote>[];
  if (chords.isEmpty) return out;

  for (var i = 0; i < chords.length - 1; i++) {
    final a = chords[i];
    final b = chords[i + 1];

    // ii–V: a minor chord whose root is a step above a dominant's. Detected on
    // the ROOT INTERVAL rather than on the numerals, so an applied ii–V
    // (`Em7 A7` in C, which is ii–V of D) is found too — that is the whole
    // point of looking for chains rather than degrees.
    final aRoot = _pc(a.chord.root);
    final bRoot = _pc(b.chord.root);
    final downFifth = (aRoot - bRoot + 12) % 12 == 7;

    if (downFifth && _isMinorish(a.chord) && _isDominantish(b.chord)) {
      final target = _rootName(
        Pitch.fromMidi(60 + (bRoot + 5) % 12),
      );
      // Resolved?
      if (i + 2 < chords.length &&
          (bRoot - _pc(chords[i + 2].chord.root) + 12) % 12 == 7) {
        out.add(
          PhraseNote(
            kind: PhraseKind.twoFiveOne,
            fromBar: a.barNumber,
            toBar: chords[i + 2].barNumber,
            label: 'ii–V–I in $target',
          ),
        );
      } else {
        out.add(
          PhraseNote(
            kind: PhraseKind.twoFive,
            fromBar: a.barNumber,
            toBar: b.barNumber,
            label: 'ii–V in $target',
          ),
        );
      }
      continue;
    }

    // Cadences, which are about the numerals rather than the interval.
    final from = a.numeral;
    final to = b.numeral;
    if (from.appliedTo == null && to.appliedTo == null) {
      if (from.degree == 5 && to.degree == 1) {
        out.add(_cadence(PhraseKind.perfectCadence, a, b, 'perfect cadence'));
      } else if (from.degree == 4 && to.degree == 1) {
        out.add(_cadence(PhraseKind.plagalCadence, a, b, 'plagal cadence'));
      } else if (from.degree == 5 && to.degree == 6) {
        out.add(
          _cadence(PhraseKind.deceptiveCadence, a, b, 'deceptive cadence'),
        );
      }
    }
  }

  // A phrase ending on the dominant is a half cadence — only worth saying at
  // the very end, where it is a question the next phrase answers.
  final last = chords.last;
  if (last.numeral.degree == 5 && last.numeral.appliedTo == null) {
    out.add(
      PhraseNote(
        kind: PhraseKind.halfCadence,
        fromBar: last.barNumber,
        toBar: last.barNumber,
        label: 'half cadence',
      ),
    );
  }

  // A turnaround is the last four bars when they lead back to the tonic.
  if (chords.length >= 4) {
    final tail = chords.sublist(chords.length - 4);
    final endsOnDominant = tail.last.numeral.degree == 5;
    final startsOnTonic = tail.first.numeral.degree == 1;
    if (startsOnTonic && endsOnDominant) {
      out.add(
        PhraseNote(
          kind: PhraseKind.turnaround,
          fromBar: tail.first.barNumber,
          toBar: tail.last.barNumber,
          label: 'turnaround',
        ),
      );
    }
  }
  return out;
}

PhraseNote _cadence(
  PhraseKind kind,
  ChordReading a,
  ChordReading b,
  String label,
) =>
    PhraseNote(
      kind: kind,
      fromBar: a.barNumber,
      toBar: b.barNumber,
      label: label,
    );

bool _isMinorish(ChordSpec chord) =>
    chord.triad == ChordTriad.minor || chord.triad == ChordTriad.diminished;

bool _isDominantish(ChordSpec chord) =>
    chord.triad == ChordTriad.major && chord.seventh == ChordSeventh.minor;

/// The chart's key as the analyser's `Key`.
Key _keyOf(Chart chart) {
  final pc = chart.tonicPitchClass;
  final tonic = Pitch.fromMidi(60 + pc);
  return chart.minor ? Key.minor(tonic) : Key.major(tonic);
}

/// A `ChordSpec` as the analyser's `ChordAnalysis`.
///
/// The quality narrows onto `ChordType`, which is a closed list — the same
/// narrowing the score bridge makes, and for the same reason. An extension the
/// type cannot hold does not change what the chord MEANS in the key, so it is
/// dropped here silently rather than reported: `C13` is a dominant on I however
/// tall it is stacked.
ChordAnalysis _asChordAnalysis(ChordSpec spec) {
  final type = switch (spec.triad) {
    ChordTriad.sus2 => ChordType.sus2,
    ChordTriad.sus4 => ChordType.sus4,
    ChordTriad.augmented => ChordType.augmented,
    ChordTriad.fifthOnly => ChordType.major,
    ChordTriad.diminished => switch (spec.seventh) {
        ChordSeventh.diminished => ChordType.diminishedSeventh,
        ChordSeventh.minor => ChordType.halfDiminishedSeventh,
        _ => ChordType.diminished,
      },
    ChordTriad.minor => spec.alterations.contains(ChordAlteration.flatFive)
        ? (spec.seventh == ChordSeventh.minor
            ? ChordType.halfDiminishedSeventh
            : ChordType.diminished)
        : switch (spec.seventh) {
            ChordSeventh.none => ChordType.minor,
            ChordSeventh.minor => ChordType.minorSeventh,
            ChordSeventh.major => ChordType.minorMajorSeventh,
            ChordSeventh.sixth => ChordType.minorSixth,
            ChordSeventh.diminished => ChordType.diminished,
          },
    ChordTriad.major => switch (spec.seventh) {
        ChordSeventh.none => ChordType.major,
        ChordSeventh.minor => ChordType.dominantSeventh,
        ChordSeventh.major => ChordType.majorSeventh,
        ChordSeventh.sixth => ChordType.majorSixth,
        ChordSeventh.diminished => ChordType.dominantSeventh,
      },
  };
  final root = spec.root;
  return ChordAnalysis(root, type, 0, spec.bass ?? root);
}

int _pc(Pitch pitch) => (pitch.midiNumber % 12 + 12) % 12;

String _rootName(Pitch root) {
  final letter = root.step.name.toUpperCase();
  if (root.alter > 0) return letter + '#' * root.alter;
  if (root.alter < 0) return letter + 'b' * -root.alter;
  return letter;
}
