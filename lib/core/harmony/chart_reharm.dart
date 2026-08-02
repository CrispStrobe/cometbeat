// lib/core/harmony/chart_reharm.dart
//
// BB-X6c — reharmonisation: the substitutions a player would reach for.
//
// 🔴 SUGGEST, NEVER REWRITE. Every function here RETURNS options; nothing
// edits a chart. A reharmonisation is a musical opinion, and the chart belongs
// to whoever wrote it — the app's job is to say "you could play this instead",
// not to decide. A caller that wants to apply one builds the new bar itself.
//
// Three substitutions, chosen because they are the ones that come up first and
// each rests on a different mechanism:
//
//   * TRITONE SUB — same guide tones, new root. Works because a dominant's
//     third and seventh are a tritone apart and therefore SWAP roles a tritone
//     away: G7's B/F are D♭7's F/C♭. That shared pair is why it sounds right,
//     and it is why the suggestion is only offered for dominants.
//   * RELATIVE ii–V — approach the dominant from its own ii. Adds a chord
//     rather than replacing one, so it needs somewhere to go: only offered
//     where the dominant has room.
//   * DIMINISHED PASSING — a chromatic step between two chords a tone apart,
//     which is a voice-leading device rather than a functional one.
library;

import 'package:comet_beat/core/harmony/chart_analysis.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;

/// Which substitution a suggestion is.
enum ReharmKind {
  /// Replace a dominant with the one a tritone away.
  tritoneSub,

  /// Put the dominant's own ii in front of it.
  relativeTwoFive,

  /// A diminished chord stepping between two chords a tone apart.
  diminishedPassing,
}

/// Something you could play instead of, or as well as, what is written.
class ReharmSuggestion {
  const ReharmSuggestion({
    required this.kind,
    required this.barNumber,
    required this.original,
    required this.replacement,
    required this.label,
    required this.why,
    this.isInsertion = false,
  });

  final ReharmKind kind;

  /// 1-based bar of the chord this applies to.
  final int barNumber;

  /// The chord as written.
  final String original;

  /// What to play, as a symbol — or the pair, for an insertion.
  final String replacement;

  /// A short name: "tritone sub", "relative ii–V".
  final String label;

  /// One sentence a musician can act on, not a rule number.
  final String why;

  /// True when this ADDS a chord rather than replacing one. The distinction
  /// matters to a caller: an insertion needs a bar with room in it.
  final bool isInsertion;

  @override
  String toString() => '$original → $replacement ($label)';
}

/// Everything worth suggesting for [analysis].
///
/// Ordered by bar, then by how commonly a player would reach for it, so a UI
/// showing only the first suggestion per bar shows the obvious one.
List<ReharmSuggestion> suggestReharmonisations(ChartAnalysis analysis) {
  final out = <ReharmSuggestion>[];

  for (var i = 0; i < analysis.chords.length; i++) {
    final reading = analysis.chords[i];
    final chord = reading.chord;

    if (_isDominant(chord)) {
      out.add(_tritoneSub(reading));
      // A ii in front only makes sense if the dominant is not already preceded
      // by its own ii — suggesting what is already there is noise.
      final previous = i > 0 ? analysis.chords[i - 1].chord : null;
      if (!_isOwnTwo(previous, chord)) {
        out.add(_relativeTwoFive(reading));
      }
    }

    // A passing diminished needs the chord AFTER it, so it is offered on the
    // first of the pair.
    if (i + 1 < analysis.chords.length) {
      final next = analysis.chords[i + 1].chord;
      final step = (_pc(next.root) - _pc(chord.root) + 12) % 12;
      if (step == 2 && !_isDominant(chord)) {
        out.add(_diminishedPassing(reading, next));
      }
    }
  }
  return out;
}

ReharmSuggestion _tritoneSub(ChordReading reading) {
  final chord = reading.chord;
  final sub = _spellFlat((_pc(chord.root) + 6) % 12);
  return ReharmSuggestion(
    kind: ReharmKind.tritoneSub,
    barNumber: reading.barNumber,
    original: chord.text,
    replacement: '${_name(sub)}7',
    label: 'tritone sub',
    // The reason IS the mechanism, and saying it teaches the substitution
    // rather than just naming it.
    why: 'It keeps the same two notes that make the chord want to move — the '
        'third and the seventh just swap places.',
  );
}

ReharmSuggestion _relativeTwoFive(ChordReading reading) {
  final chord = reading.chord;
  // The ii of a dominant is a fifth above it.
  final two = _spellFlat((_pc(chord.root) + 7) % 12);
  return ReharmSuggestion(
    kind: ReharmKind.relativeTwoFive,
    barNumber: reading.barNumber,
    original: chord.text,
    replacement: '${_name(two)}m7 ${chord.text}',
    label: 'relative ii–V',
    why: 'Approach the chord from its own ii, so the bar moves twice instead '
        'of sitting still.',
    isInsertion: true,
  );
}

ReharmSuggestion _diminishedPassing(
  ChordReading reading,
  ChordSpec next,
) {
  final between = _spellSharp((_pc(reading.chord.root) + 1) % 12);
  return ReharmSuggestion(
    kind: ReharmKind.diminishedPassing,
    barNumber: reading.barNumber,
    original: '${reading.chord.text} → ${next.text}',
    replacement: '${_name(between)}dim7',
    label: 'passing diminished',
    why: 'The roots are a whole tone apart, so a diminished chord in between '
        'walks the bass up by half steps.',
    isInsertion: true,
  );
}

bool _isDominant(ChordSpec chord) =>
    chord.triad == ChordTriad.major && chord.seventh == ChordSeventh.minor;

/// True when [previous] is already the ii of [dominant].
bool _isOwnTwo(ChordSpec? previous, ChordSpec dominant) {
  if (previous == null) return false;
  if (previous.triad != ChordTriad.minor) return false;
  return (_pc(previous.root) - _pc(dominant.root) + 12) % 12 == 7;
}

int _pc(Pitch pitch) => (pitch.midiNumber % 12 + 12) % 12;

/// A pitch class spelled with flats — the convention for a tritone sub, which
/// is nearly always written ♭II7.
Pitch _spellFlat(int pc) {
  const table = <int, (Step, int)>{
    0: (Step.c, 0),
    1: (Step.d, -1),
    2: (Step.d, 0),
    3: (Step.e, -1),
    4: (Step.e, 0),
    5: (Step.f, 0),
    6: (Step.g, -1),
    7: (Step.g, 0),
    8: (Step.a, -1),
    9: (Step.a, 0),
    10: (Step.b, -1),
    11: (Step.b, 0),
  };
  final (step, alter) = table[pc]!;
  return Pitch(step, alter: alter);
}

/// A pitch class spelled with sharps — a passing diminished walks UP, so it is
/// written as a raised degree rather than a lowered one.
Pitch _spellSharp(int pc) {
  const table = <int, (Step, int)>{
    0: (Step.c, 0),
    1: (Step.c, 1),
    2: (Step.d, 0),
    3: (Step.d, 1),
    4: (Step.e, 0),
    5: (Step.f, 0),
    6: (Step.f, 1),
    7: (Step.g, 0),
    8: (Step.g, 1),
    9: (Step.a, 0),
    10: (Step.a, 1),
    11: (Step.b, 0),
  };
  final (step, alter) = table[pc]!;
  return Pitch(step, alter: alter);
}

String _name(Pitch pitch) {
  final letter = pitch.step.name.toUpperCase();
  if (pitch.alter > 0) return letter + '#' * pitch.alter;
  if (pitch.alter < 0) return letter + 'b' * -pitch.alter;
  return letter;
}
