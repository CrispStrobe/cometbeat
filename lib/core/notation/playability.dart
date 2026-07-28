// lib/core/notation/playability.dart
//
// "Can this part actually be PLAYED?" — the two questions a player asks of a
// page that a notation editor can answer mechanically:
//
//   1. is the note within the instrument's range at all, and
//   2. can a hand reach it at the level the player is at?
//
// Both answers already existed and neither was reachable. The Score Editor's
// instrument presets have carried `lowMidi`/`highMidi` since the presets were
// added and NOTHING read them; `fingerBowedScore` has always returned exactly
// which notes it could not place, and only the CLI ever printed it. This file
// is the seam that turns both into something the editor can show.
//
// ⚠ These are WARNINGS, never a block, and the distinction is the whole design.
// Composers write out of range deliberately — for an effect, for a transposing
// part, or because the player they have in mind is better than the default. An
// editor that refuses the note is wrong more often than the note is. So nothing
// here mutates a score; it only reports.
//
// Pure Dart (crisp_notation_core only), so the same check runs headless.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:comet_beat/core/notation/bowed_score_fingering.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Why a note was flagged.
enum PlayabilityIssue {
  /// Below the instrument's lowest string — no fingering exists at any level.
  belowRange,

  /// Above the practical top of the instrument.
  aboveRange,

  /// In range, but not playable at the chosen skill level: the note needs a
  /// position, an extension or the thumb that this level does not cover.
  ///
  /// ⚠ This is NOT "the arranger failed". The skill limits are soft costs, so
  /// the arranger always returns *a* fingering — it will put a first-position
  /// student in 7th position rather than refuse the note. The warning is that
  /// the fingering it had to choose left the level, which is the thing a
  /// teacher would notice and the student would not.
  outOfReach,
}

/// One flagged note. [elementId] is the `NoteElement.id`, so a caller can select
/// or highlight exactly the offending notes rather than pointing at a bar.
class PlayabilityWarning {
  final String elementId;
  final int midi;
  final PlayabilityIssue issue;

  const PlayabilityWarning(this.elementId, this.midi, this.issue);

  @override
  String toString() => 'PlayabilityWarning($elementId, $midi, ${issue.name})';

  @override
  bool operator ==(Object other) =>
      other is PlayabilityWarning &&
      other.elementId == elementId &&
      other.midi == midi &&
      other.issue == issue;

  @override
  int get hashCode => Object.hash(elementId, midi, issue);
}

/// A playable compass, in MIDI note numbers, inclusive.
typedef BowedRange = ({int lowMidi, int highMidi});

/// The four bowed strings, keyed by a canonical name.
///
/// Tops are the PRACTICAL ceiling a student or amateur orchestra part stays
/// under, not the theoretical one — a cello harmonic goes far above E6, but a
/// note above it is worth a second look, which is all a warning claims.
const Map<String, BowedRange> kBowedRanges = {
  'violin': (lowMidi: 55, highMidi: 100), // G3 – E7
  'viola': (lowMidi: 48, highMidi: 88), // C3 – E6
  'cello': (lowMidi: 36, highMidi: 81), // C2 – A5
  'doubleBass': (lowMidi: 28, highMidi: 67), // E1 – G4 (sounding)
};

/// Canonical name → the [BowedInstrument] the arranger models, where it models
/// one. Violin and viola have no arranger profile yet, so they get the range
/// check only — a partial answer being better than a wrong one.
// ⚠ NOT const: `BowedInstrument.cello` is a `static final` instance, not an
// enum value, so this map cannot be evaluated at compile time.
final Map<String, BowedInstrument> kBowedArrangerInstruments = {
  'cello': BowedInstrument.cello,
  'doubleBass': BowedInstrument.doubleBass,
};

/// Resolve a free-text part name (whatever the score or the user called it) to
/// one of [kBowedRanges]' canonical keys, or null when it does not look bowed.
///
/// ⚠ Matching on a name is fragile in exactly the ways this project has already
/// been bitten by, so it is done deliberately: the app writes LOCALISED labels
/// ("Violoncello", "Kontrabass"), imported corpus files use period orthography
/// ("Baſso." with a long s — that one silently lost 11 of 25 files in
/// `fingerconv`), and abbreviations are everywhere. Hence: normalise the
/// orthography first, then match a list of aliases per instrument.
///
/// ⚠ ORDER MATTERS. "Contrabasso" contains "basso", and "Violoncello" contains
/// "violon" — so the most specific names must be tested first, and the aliases
/// below are ordered accordingly. A shorter list that read naturally would
/// classify every cello as a violin.
String? canonicalBowedName(String? name) {
  if (name == null) return null;
  final n = name
      .toLowerCase()
      .replaceAll('ſ', 's') // ſ long s
      .replaceAll('ß', 'ss') // ß
      .replaceAll('œ', 'oe') // œ
      .replaceAll('æ', 'ae') // æ
      .replaceAll(RegExp(r'[^a-z]'), '');
  if (n.isEmpty) return null;

  // Most specific first — see the warning above.
  const aliases = <(String, List<String>)>[
    (
      'doubleBass',
      ['contrabass', 'contrabasso', 'kontrabass', 'doublebass', 'cb'],
    ),
    ('cello', ['violoncello', 'violoncell', 'cello', 'vlc', 'vc']),
    ('viola', ['viola', 'bratsche', 'altviolin', 'vla']),
    ('violin', ['violin', 'violine', 'violino', 'geige', 'vln', 'vn']),
    // Bare "bass"/"basso" last: it is the least specific of all, and in an old
    // print it usually IS the cello line. Callers that know better should pass
    // an explicit instrument rather than rely on this.
    ('doubleBass', ['bass', 'basso']),
  ];
  for (final (canonical, forms) in aliases) {
    for (final form in forms) {
      if (n.contains(form)) return canonical;
    }
  }
  return null;
}

/// Every playability warning for [score], most useful first: range problems
/// (which no skill level fixes) before reach problems (which a higher one may).
///
/// [range] bounds the pitch check. [instrument] + [skill] enable the reach
/// check; omit either and only the range is checked, which is the honest
/// behaviour for an instrument the arranger does not model.
///
/// Notes without an id are skipped — the caller could not act on them anyway.
List<PlayabilityWarning> checkPlayability(
  Score score, {
  BowedRange? range,
  BowedInstrument? instrument,
  BowedSkill? skill,
}) {
  final notes = <NoteElement>[
    for (final m in score.measures)
      for (final e in m.elements)
        if (e is NoteElement && e.pitches.isNotEmpty && e.id != null) e,
  ];
  if (notes.isEmpty) return const [];

  final out = <PlayabilityWarning>[];
  final flagged = <String>{}; // one warning per note, range taking priority

  if (range != null) {
    for (final n in notes) {
      // A chord is judged by its extremes: it is the lowest and highest pitches
      // that fall off the instrument, not the note as a whole.
      for (final p in n.pitches) {
        final midi = p.midiNumber;
        if (midi < range.lowMidi) {
          out.add(
            PlayabilityWarning(n.id!, midi, PlayabilityIssue.belowRange),
          );
          flagged.add(n.id!);
          break;
        }
        if (midi > range.highMidi) {
          out.add(
            PlayabilityWarning(n.id!, midi, PlayabilityIssue.aboveRange),
          );
          flagged.add(n.id!);
          break;
        }
      }
    }
  }

  if (instrument != null && skill != null) {
    final placed =
        fingerBowedScore(score, skill: skill, instrument: instrument);
    for (final n in notes) {
      // Already out of range: saying "and also unreachable" adds nothing — of
      // course it is. One warning per note, and the more actionable one.
      if (flagged.contains(n.id)) continue;
      final fingering = placed[n.id];
      // Either the arranger could not place it at all (genuinely off the
      // instrument), or it placed it OUTSIDE the level — see [beyondSkill].
      final beyond = fingering == null ||
          fingering.any((f) => beyondSkill(instrument, skill, f));
      if (beyond) {
        out.add(
          PlayabilityWarning(
            n.id!,
            n.pitches.first.midiNumber,
            PlayabilityIssue.outOfReach,
          ),
        );
      }
    }
  }
  return out;
}
