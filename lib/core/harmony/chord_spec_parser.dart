// lib/core/harmony/chord_spec_parser.dart
//
// BB-D1 — reading what a musician actually types.
//
// THE ONE RULE: **this never fails.** Getting changes into the app is the
// adoption gate (decision 3 puts a pasted text grid on the critical path), and a
// chart that refuses to load because of one odd symbol is worse than a chart
// with one odd symbol in it. So a token this file cannot read comes back as an
// [UnreadableCell] carrying the text VERBATIM plus a best-guess triad — it
// prints what the user wrote, it plays something sane, and BB-Q3 turns it into a
// test case. Nothing throws.
//
// WHAT "ACTUALLY TYPES" MEANS IN PRACTICE — the awkward set this handles:
//   Cmaj7  CM7  CMaj7  C∆  C∆9  Cma7        a major seventh, five ways
//   Cm7  Cmin7  Cmi7  C-7                   a minor seventh, four ways
//   Cm7b5  Cmin7b5  Cø  Cø7  Cm7-5          half-diminished, five ways
//   Cdim  C°  Cdim7  C°7  Co7               diminished, and its seventh
//   Caug  C+  C7#5  C7+5                    augmented and a raised fifth
//   C6/9  C69   Csus  Csus4  C4  C7sus4      names with internal structure
//   Bb7alt  C7(b9)  F#m7♭5  C7(#11)          alterations, spelled loosely
//   C/G  Cm7/Bb   C5   Cno3   Cadd9          bass, power chord, omission, add
//   N.C.  NC  %  (empty)                     not-a-chord and same-again
//
// Three subtleties worth knowing before editing:
//
// 1. **Matching is longest-token-first, not an ordered if-chain.** That is what
//    keeps `mMaj7` from reading as `m` + `aj7`, `#11` from reading as `#1` + `1`,
//    and `dim7` from reading as `dim` + `7` (which would be a MINOR seventh, not
//    the diminished one `C°7` means). Add tokens freely; the sort keeps them safe.
// 2. **Case matters for exactly two tokens: `M` and `m`.** `CM7` is a major
//    seventh and `Cm7` is a minor one, so those two cannot be case-folded. Every
//    multi-letter word (`maj`, `min`, `dim`, `sus`, `add`, `alt`, `no`, `omit`) IS
//    case-insensitive, because `CMAJ7` and `Cmaj7` are the same chord.
// 3. **A lowercase root letter is NOT an implied minor.** Some Central-European
//    traditions write `c` for C minor. Text charts and ChordPro overwhelmingly
//    write `c` for C major, and silently turning one into the other would change
//    a chord the user can see. `c` reads as C; write `cm` for the minor.
//
// Pure Dart, no Flutter.

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Pitch, Step;

/// One cell of a chart: a chord, an explicit silence, a "same again", or text we
/// could not read and refuse to throw away.
sealed class ChartCell {
  const ChartCell();
}

/// A chord.
final class ChordCell extends ChartCell {
  const ChordCell(this.chord);
  final ChordSpec chord;

  @override
  bool operator ==(Object other) => other is ChordCell && other.chord == chord;
  @override
  int get hashCode => chord.hashCode;
  @override
  String toString() => 'ChordCell(${chord.text})';
}

/// `N.C.` — play nothing here. Distinct from "no chord was written", which is
/// [RepeatCell].
final class NoChordCell extends ChartCell {
  const NoChordCell();
  @override
  bool operator ==(Object other) => other is NoChordCell;
  @override
  int get hashCode => 0x4e43;
  @override
  String toString() => 'NoChordCell()';
}

/// `%`, or an empty cell — the previous chord continues.
///
/// An empty cell and `%` are deliberately the SAME thing: in a text grid
/// `| Cm7 | | F7 |` and `| Cm7 | % | F7 |` are how two people write one idea.
/// Which bar the previous chord actually came from is a chart-level question, so
/// BB-D2 resolves it; this only reports that nothing new was named.
final class RepeatCell extends ChartCell {
  const RepeatCell();
  @override
  bool operator ==(Object other) => other is RepeatCell;
  @override
  int get hashCode => 0x25;
  @override
  String toString() => 'RepeatCell()';
}

/// Text this file could not read. [text] is preserved exactly as written so the
/// chart prints what the user typed; [fallback] is a best-guess chord so it also
/// makes a sound.
final class UnreadableCell extends ChartCell {
  const UnreadableCell(this.text, this.fallback);
  final String text;
  final ChordSpec fallback;

  @override
  bool operator ==(Object other) =>
      other is UnreadableCell && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'UnreadableCell("$text")';
}

/// Reads one chart cell. Never throws — see the file header.
///
/// [style] is consulted only for [ChordSymbolStyle.germanNoteNames]; the other
/// fields are display choices and do not affect reading (`♭` and `b` both read).
ChartCell parseChartCell(
  String text, {
  ChordSymbolStyle style = ChordSymbolStyle.plain,
}) {
  final raw = text.trim();
  if (raw.isEmpty || raw == '%') return const RepeatCell();

  final flat = raw.toUpperCase().replaceAll('.', '').replaceAll(' ', '');
  if (flat == 'NC' || flat == 'NOCHORD') return const NoChordCell();

  final chord = parseChordSpec(raw, style: style);
  if (chord != null) return ChordCell(chord);
  return UnreadableCell(raw, _fallbackFor(raw, style));
}

/// Reads a chord symbol, or null when [text] is not one (including `N.C.` and
/// `%` — use [parseChartCell] to tell those apart from a misspelling).
ChordSpec? parseChordSpec(
  String text, {
  ChordSymbolStyle style = ChordSymbolStyle.plain,
}) {
  var s = _normalize(text);
  if (s.isEmpty) return null;

  // Slash bass first, so `Cm7/Bb` does not try to read `/Bb` as a quality — but
  // only when what follows the LAST slash is a note name, which is what keeps
  // `C6/9` (where the 9 is part of the name) out of this branch.
  Pitch? bass;
  final slash = s.lastIndexOf('/');
  if (slash > 0 && slash < s.length - 1) {
    final tail = s.substring(slash + 1);
    final asNote = _readNote(tail, 0, style);
    if (asNote != null && asNote.end == tail.length) {
      bass = asNote.pitch;
      s = s.substring(0, slash);
    }
  }

  final rootRead = _readNote(s, 0, style);
  if (rootRead == null) return null;

  // Grouping is stripped only AFTER the root is read, and that ordering is
  // load-bearing: `C(b5)` must read as C with a flat five, while the identical
  // ungrouped string `Cb5` reads as a C♭ power chord — which is the convention
  // `Bb5` follows. Strip the brackets any earlier and the two collapse into one
  // ambiguous string. `ChordSpec._groupIfAmbiguous` is the printing half.
  final suffix = _stripGrouping(s.substring(rootRead.end));

  final b = _Builder(root: rootRead.pitch, bass: bass);
  var i = 0;
  while (i < suffix.length) {
    final hit = _matchToken(suffix, i);
    if (hit == null) return null; // caller turns this into an UnreadableCell
    hit.token.apply(b);
    i = hit.end;
  }
  return b.build();
}

// ── normalisation ──────────────────────────────────────────────────────────

/// Folds the many ways a chord symbol is typed into the few this file matches:
/// unicode accidentals and superscripts to ASCII, the several dash characters to
/// `-`, and purely decorative parentheses and separators away entirely.
String _normalize(String input) {
  const map = {
    '♭': 'b', '♮': '', '♯': '#',
    '⁷': '7', '⁹': '9', '¹': '1', '³': '3', '⁵': '5', '⁶': '6', '⁴': '4',
    '²': '2', '⁰': '0', '⁸': '8', '¹¹': '11', '¹³': '13',
    '–': '-', '—': '-', '−': '-', // en dash, em dash, minus sign
    'Δ': '∆', '△': '∆', // fold the delta look-alikes onto one
    'Ø': 'ø', 'º': '°', 'ᵐ': 'm',
  };
  var out = input.trim();
  map.forEach((from, to) => out = out.replaceAll(from, to));
  // Commas and spaces inside a symbol are decoration: `C7(b9, #11)` and
  // `C7b9#11` are one chord written two ways. Parentheses are NOT removed here —
  // they still have work to do at the root boundary, see [_stripGrouping].
  return out.replaceAll(',', '').replaceAll(' ', '');
}

/// Drops the decorative brackets from a quality suffix. Called only on the text
/// AFTER the root, never on the whole symbol — see the note in [parseChordSpec].
String _stripGrouping(String s) => s
    .replaceAll('(', '')
    .replaceAll(')', '')
    .replaceAll('[', '')
    .replaceAll(']', '');

// ── note names ─────────────────────────────────────────────────────────────

class _NoteRead {
  const _NoteRead(this.pitch, this.end);
  final Pitch pitch;
  final int end;
}

/// Reads a note name at [i]: a letter then any run of `#`/`b`.
///
/// German mode (`H` is the natural B, `B` is B♭) is handled with one pragmatic
/// rule: a bare `B` is B♭, but `B` FOLLOWED BY an accidental is read
/// internationally, so `Bb` still means B♭ rather than B♭♭. German charts in the
/// wild mix the two conventions, and this is the reading that never turns a
/// common symbol into a surprising one.
_NoteRead? _readNote(String s, int i, ChordSymbolStyle style) {
  if (i >= s.length) return null;
  final letter = s[i].toUpperCase();
  var j = i + 1;
  var alter = 0;
  while (j < s.length && (s[j] == '#' || s[j] == 'b')) {
    alter += s[j] == '#' ? 1 : -1;
    j++;
  }

  Step? step;
  if (letter == 'H') {
    // `H` is not a note internationally.
    if (!style.germanNoteNames) return null;
    step = Step.b;
  } else if (letter == 'B' && style.germanNoteNames && j == i + 1) {
    step = Step.b;
    alter = -1;
  } else {
    step = Step.values.asNameMap()[letter.toLowerCase()];
  }
  if (step == null) return null;
  return _NoteRead(Pitch(step, alter: alter), j);
}

// ── the token table ────────────────────────────────────────────────────────

class _Token {
  const _Token(this.text, this.apply, {this.caseSensitive = false});
  final String text;
  final void Function(_Builder) apply;
  final bool caseSensitive;
  int get length => text.length;
}

class _TokenHit {
  const _TokenHit(this.token, this.end);
  final _Token token;
  final int end;
}

/// Mutable while parsing; `last writer wins` throughout, so a contradictory
/// symbol still produces a chord rather than an error.
class _Builder {
  _Builder({required this.root, this.bass});
  final Pitch root;
  final Pitch? bass;
  ChordTriad triad = ChordTriad.major;
  ChordSeventh seventh = ChordSeventh.none;
  int extension = 0;
  final Set<ChordAlteration> alterations = {};
  final Set<int> added = {};
  final Set<int> omitted = {};

  /// A bare `7`/`9`/`11`/`13` implies a MINOR seventh (`C9` is a dominant), but
  /// only when nothing has already claimed the slot — `C∆9` and `Cmaj9` set it to
  /// major first, and the number must then raise the stack without overwriting.
  void stack(int height) {
    if (seventh == ChordSeventh.none) seventh = ChordSeventh.minor;
    if (height > 7) extension = height;
  }

  ChordSpec build() => ChordSpec(
        root: root,
        triad: triad,
        seventh: seventh,
        extension: extension,
        alterations: Set.unmodifiable(alterations),
        added: Set.unmodifiable(added),
        omitted: Set.unmodifiable(omitted),
        bass: bass,
      );
}

/// A major seventh reaching to [height] — shared by the `maj9`/`maj11`/`maj13`
/// spellings and their case-sensitive `M9`/`M11`/`M13` twins, so neither needs a
/// block closure sitting in front of a named argument.
void Function(_Builder) _majorTo(int height) => (b) {
      b.seventh = ChordSeventh.major;
      b.extension = height;
    };

/// Longest-first so that `dim7` beats `dim`, `mMaj7` beats `m`, `#11` beats
/// `#1`, and `6/9` beats `6`. Built once.
final List<_Token> _tokens = () {
  final t = <_Token>[
    // minor-major seventh, before anything starting with m
    _Token('mmaj7', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.major;
    }),
    _Token('minmaj7', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.major;
    }),
    _Token('-maj7', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.major;
    }),

    // half-diminished, before `m` and before `dim`
    _Token('m7b5', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.minor;
      b.alterations.add(ChordAlteration.flatFive);
    }),
    _Token('min7b5', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.minor;
      b.alterations.add(ChordAlteration.flatFive);
    }),
    _Token('m7-5', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.minor;
      b.alterations.add(ChordAlteration.flatFive);
    }),
    // `ø` is half-diminished on its own; a following 7 is then redundant.
    _Token('ø', (b) {
      b.triad = ChordTriad.minor;
      b.seventh = ChordSeventh.minor;
      b.alterations.add(ChordAlteration.flatFive);
    }),

    // diminished — the seventh forms must beat the triad forms
    _Token('dim7', (b) {
      b.triad = ChordTriad.diminished;
      b.seventh = ChordSeventh.diminished;
    }),
    _Token('°7', (b) {
      b.triad = ChordTriad.diminished;
      b.seventh = ChordSeventh.diminished;
    }),
    _Token('o7', (b) {
      b.triad = ChordTriad.diminished;
      b.seventh = ChordSeventh.diminished;
    }),
    _Token('dim', (b) => b.triad = ChordTriad.diminished),
    _Token('°', (b) => b.triad = ChordTriad.diminished),

    // major seventh, spelled out
    // ⚠️ `major7` needs its OWN token, unlike `minor7`. `minor` sets the triad
    // and a following `7` then reads as a minor seventh on a minor triad,
    // which is right — but `major` deliberately sets NOTHING (`CMaj` is just
    // C), so `Cmajor7` would fall through to a dominant `C7`. Spelled-out and
    // abbreviated forms must mean the same chord.
    _Token('major7', (b) => b.seventh = ChordSeventh.major),
    _Token('maj7', (b) => b.seventh = ChordSeventh.major),
    _Token('maj9', _majorTo(9)),
    _Token('maj11', _majorTo(11)),
    _Token('maj13', _majorTo(13)),
    _Token('ma7', (b) => b.seventh = ChordSeventh.major),
    // `∆` alone already means a major seventh; `∆9` then raises the stack.
    _Token('∆', (b) => b.seventh = ChordSeventh.major),

    // augmented — `+5`/`+9`/`+11` are alterations and must win over a bare `+`
    _Token('aug', (b) => b.triad = ChordTriad.augmented),
    _Token('+5', (b) => b.alterations.add(ChordAlteration.sharpFive)),
    _Token('+9', (b) => b.alterations.add(ChordAlteration.sharpNine)),
    _Token('+11', (b) => b.alterations.add(ChordAlteration.sharpEleven)),
    _Token('+', (b) => b.triad = ChordTriad.augmented),

    // suspensions
    _Token('sus2', (b) => b.triad = ChordTriad.sus2),
    _Token('sus4', (b) => b.triad = ChordTriad.sus4),
    _Token('sus', (b) => b.triad = ChordTriad.sus4),

    // added tones
    _Token('add2', (b) => b.added.add(2)),
    _Token('add4', (b) => b.added.add(4)),
    _Token('add6', (b) => b.added.add(6)),
    _Token('add9', (b) => b.added.add(9)),
    _Token('add11', (b) => b.added.add(11)),
    _Token('add13', (b) => b.added.add(13)),

    // the sixth family
    _Token('6/9', (b) {
      b.seventh = ChordSeventh.sixth;
      b.added.add(9);
    }),
    _Token('69', (b) {
      b.seventh = ChordSeventh.sixth;
      b.added.add(9);
    }),
    _Token('6', (b) => b.seventh = ChordSeventh.sixth),

    // omissions
    _Token('omit3', (b) => b.omitted.add(3)),
    _Token('omit5', (b) => b.omitted.add(5)),
    _Token('no3', (b) => b.omitted.add(3)),
    _Token('no5', (b) => b.omitted.add(5)),

    // the altered dominant
    _Token('alt', (b) {
      if (b.seventh == ChordSeventh.none) b.seventh = ChordSeventh.minor;
      b.alterations.add(ChordAlteration.altered);
    }),

    // alterations, spelled with either accidental character
    _Token('b5', (b) => b.alterations.add(ChordAlteration.flatFive)),
    _Token('-5', (b) => b.alterations.add(ChordAlteration.flatFive)),
    _Token('#5', (b) => b.alterations.add(ChordAlteration.sharpFive)),
    _Token('b9', (b) => b.alterations.add(ChordAlteration.flatNine)),
    _Token('-9', (b) => b.alterations.add(ChordAlteration.flatNine)),
    _Token('#9', (b) => b.alterations.add(ChordAlteration.sharpNine)),
    _Token('#11', (b) => b.alterations.add(ChordAlteration.sharpEleven)),
    _Token('b13', (b) => b.alterations.add(ChordAlteration.flatThirteen)),
    _Token('-13', (b) => b.alterations.add(ChordAlteration.flatThirteen)),

    // stack heights
    _Token('13', (b) => b.stack(13)),
    _Token('11', (b) => b.stack(11)),
    _Token('9', (b) => b.stack(9)),
    _Token('7', (b) => b.stack(7)),

    // the power chord, and the two numeric suspension spellings charts use
    _Token('5', (b) => b.triad = ChordTriad.fifthOnly),
    _Token('4', (b) => b.triad = ChordTriad.sus4),
    _Token('2', (b) => b.triad = ChordTriad.sus2),

    // plain qualities last: these are prefixes of the tokens above
    // Spelled out in full. Matching is longest-token-first, so these are
    // picked ahead of `maj`/`min` rather than leaving a stranded "or" — which
    // is exactly how `Cminor` used to fail while `Cmin` parsed. Our OWN
    // shipped `assets/chords/ukulele.json` uses the suffix `minor`.
    _Token('major', (b) {}),
    _Token('minor', (b) => b.triad = ChordTriad.minor),
    _Token('maj', (b) {}), // `CMaj` is just C
    _Token('min', (b) => b.triad = ChordTriad.minor),
    _Token('mi', (b) => b.triad = ChordTriad.minor),

    // the two case-sensitive tokens — see header note 2
    _Token('M7', (b) => b.seventh = ChordSeventh.major, caseSensitive: true),
    _Token('M9', _majorTo(9), caseSensitive: true),
    _Token('M11', _majorTo(11), caseSensitive: true),
    _Token('M13', _majorTo(13), caseSensitive: true),
    _Token('M', (b) {}, caseSensitive: true), // `CM` is just C
    _Token('m', (b) => b.triad = ChordTriad.minor, caseSensitive: true),
    _Token('-', (b) => b.triad = ChordTriad.minor),
  ];
  t.sort((a, b) => b.length.compareTo(a.length));
  return List<_Token>.unmodifiable(t);
}();

_TokenHit? _matchToken(String s, int i) {
  for (final token in _tokens) {
    final end = i + token.length;
    if (end > s.length) continue;
    final slice = s.substring(i, end);
    final ok = token.caseSensitive
        ? slice == token.text
        : slice.toLowerCase() == token.text.toLowerCase();
    if (ok) return _TokenHit(token, end);
  }
  return null;
}

/// The best guess for a symbol we could not read: the right root if we can find
/// one, minor when the quality starts the way a minor quality starts, major
/// otherwise. Mirrors the fallback `intervalsForSuffix` has always used in
/// `songs/import/chord_quality.dart`, so an unreadable chord sounds the same
/// here as it does on the existing chord-sheet screen.
ChordSpec _fallbackFor(String raw, ChordSymbolStyle style) {
  final s = _normalize(raw);
  final read = _readNote(s, 0, style);
  final root = read?.pitch ?? const Pitch(Step.c);
  final suffix = read == null ? '' : _stripGrouping(s.substring(read.end));
  final minor = (suffix.startsWith('m') || suffix.startsWith('-')) &&
      !suffix.toLowerCase().startsWith('maj') &&
      !suffix.startsWith('M');
  return ChordSpec(
    root: root,
    triad: minor ? ChordTriad.minor : ChordTriad.major,
  );
}
