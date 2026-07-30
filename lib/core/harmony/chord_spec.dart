// lib/core/harmony/chord_spec.dart
//
// BB-D1 — the chord-symbol vocabulary. One type rich enough to hold any chord a
// chart needs, print it in more than one convention, and hand a voicing engine
// the notes.
//
// WHY THIS EXISTS WHEN THE APP ALREADY HAS THREE CHORD VOCABULARIES.
// `songs/import/chord_quality.dart` has 18 flat quality suffixes,
// `composition/chord_db.dart` maps 18 of them onto guitar grips, and
// crisp_notation's `ChordSymbolKind` has 15 MusicXML `<kind>` values. Every one
// of them is a FLAT LIST of whole qualities, so `C7#11`, `Bb7alt` and `C6/9`
// cannot be said at all — you get `C7` and a shrug. A chart needs to say them,
// so this models a chord COMPOSITIONALLY: a triad core, a seventh, a stack
// height, a set of alterations, added and omitted tones, and a slash bass.
//
// ⚠️ Those three stay exactly as they are. Nothing here replaces them and no
// caller of them changes; migrating them is a later card. This is additive.
//
// THE RULE THIS FILE EXISTS TO OBEY (ladder rule 5, decision 1): the MODEL is
// never scoped down — the SURFACE is (BB-U6). Every ⛔ in docs/BACKING_BAND.md
// §2 is a model that was narrowed for a good reason and is now the blocker:
// `Progression` asserts exactly four chords in C, `ChordDegree` has six
// diatonic degrees, `LoopTiming.beatsPerBar` is a compile-time 4. So if a
// quality feels too advanced for a beginner it still belongs here; it gets left
// out of the keypad, not out of the type.
//
// Pure Dart, no Flutter — so the CLI and the tests can use it. Parsing and the
// `ChartCell` sealed type live in `chord_spec_parser.dart`; formatting lives
// here, because how a chord prints is a property of the chord.

import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Interval, Pitch, Step;

/// The triad core — what the symbol says about the third and the fifth.
///
/// [diminished] and [augmented] are cores rather than alterations because that
/// is how the symbols read: `Cdim` names a chord, `Cm(b5)` describes one. Both
/// are representable and they are NOT merged — `Cdim7` (a diminished core with a
/// diminished seventh) and `Cm7b5` (a minor core with a flattened fifth and a
/// minor seventh) print differently, are spelled differently by musicians, and
/// so must survive a round trip separately even though their thirds and fifths
/// agree.
enum ChordTriad {
  major,
  minor,
  diminished,
  augmented,
  sus2,
  sus4,

  /// A power chord — root and fifth, no third at all (`C5`).
  fifthOnly,
}

/// What sits in the seventh slot.
///
/// [sixth] is here, rather than in [ChordSpec.added], because `C6` is a chord
/// name in its own right and prints as one. It happens to sound the same as
/// [diminished] (both 9 semitones) — that is a genuine enharmonic coincidence,
/// not a modelling error, and they are distinguished by name and by spelling.
enum ChordSeventh { none, minor, major, diminished, sixth }

/// A single altered tone. [altered] is the wildcard `alt` of `Bb7alt`.
enum ChordAlteration {
  flatFive,
  sharpFive,
  flatNine,
  sharpNine,
  sharpEleven,
  flatThirteen,

  /// `alt` — the altered dominant. Kept as a MEMBER rather than expanded at
  /// parse time so that `C7alt` prints back as `C7alt` instead of decaying into
  /// `C7b9#9#11b13`. It expands only inside [ChordSpec.intervals], where actual
  /// notes are needed. See [_expandAltered].
  altered,
}

/// How a chord symbol is spelled on screen. A display choice — never stored,
/// never part of equality.
class ChordSymbolStyle {
  const ChordSymbolStyle({
    this.unicodeAccidentals = false,
    this.jazzGlyphs = false,
    this.germanNoteNames = false,
  });

  /// `♭`/`♯` instead of `b`/`#`.
  final bool unicodeAccidentals;

  /// `∆` for a major seventh, `ø` for a half-diminished, `°` for a diminished.
  final bool jazzGlyphs;

  /// The German convention: the natural B prints as `H`, and B♭ prints as `B`.
  ///
  /// ⚠️ Off by default, and it must stay that way: turning it on silently
  /// changes what the extremely common symbol `B` means. It is a per-user
  /// display setting (the app already models the idea in
  /// `core/note_naming.dart`), not a global.
  final bool germanNoteNames;

  /// ASCII, international note names — what a text chart holds.
  static const plain = ChordSymbolStyle();

  /// Engraved lead-sheet spelling.
  static const jazz =
      ChordSymbolStyle(unicodeAccidentals: true, jazzGlyphs: true);

  /// International qualities, German note names.
  static const german = ChordSymbolStyle(germanNoteNames: true);
}

/// A chord symbol: a [root], a [triad] core, a [seventh], an [extension] stack
/// height, [alterations], [added] and [omitted] tones, and an optional slash
/// [bass].
///
/// **Octaves are ignored.** A chord symbol is a pitch class, so equality
/// compares only the step and the alteration of [root] and [bass] — the same
/// decision crisp_notation's `ChordSymbol` makes, and what lets a parsed chord
/// equal a hand-built one.
class ChordSpec {
  const ChordSpec({
    required this.root,
    this.triad = ChordTriad.major,
    this.seventh = ChordSeventh.none,
    this.extension = 0,
    this.alterations = const {},
    this.added = const {},
    this.omitted = const {},
    this.bass,
  });

  /// The chord root (octave ignored).
  final Pitch root;

  final ChordTriad triad;
  final ChordSeventh seventh;

  /// The height of the stack: `0`, `9`, `11` or `13`. Only meaningful together
  /// with a [seventh] — `C9` is a seventh chord that reaches to the ninth, and a
  /// ninth with no seventh under it is written `Cadd9`, which is [added].
  final int extension;

  final Set<ChordAlteration> alterations;

  /// Degrees added WITHOUT implying the stack beneath them (`add9`, `add4`, …).
  /// Members are degree numbers: 2, 4, 6, 9, 11, 13.
  final Set<int> added;

  /// Degrees explicitly left out (`no3`, `omit5`). Members are 3 and 5.
  final Set<int> omitted;

  /// The slash-chord bass (octave ignored), or null.
  final Pitch? bass;

  // ── notes ────────────────────────────────────────────────────────────────

  /// Semitones above the root, ascending and deduplicated.
  ///
  /// Extension tones stay ABOVE the octave (a ninth is 14, not 2) because that
  /// is the information a voicing engine needs; [pitchClasses] is the reduced
  /// view. Two conventions are baked in, both of them real practice rather than
  /// simplifications:
  ///
  /// * **A 13th chord does not include the 11th.** `C13` is 1-3-5-♭7-9-13; the
  ///   natural 11 clashes with the major third and players leave it out. It
  ///   comes back if the symbol asks for it (`C13#11`, or an explicit `add11`).
  /// * **An 11th chord keeps its third.** `C11` nominally clashes the same way,
  ///   and players usually drop the third — but that is a VOICING choice, and
  ///   dropping it here would mean the model could not express the chord a
  ///   player who does want both wrote down. Voicing belongs to BB-A1.
  List<int> get intervals {
    final alts = _expandAltered(alterations);
    final out = <int>{0};

    if (!omitted.contains(3)) {
      final third = switch (triad) {
        ChordTriad.major || ChordTriad.augmented => 4,
        ChordTriad.minor || ChordTriad.diminished => 3,
        ChordTriad.sus2 => 2,
        ChordTriad.sus4 => 5,
        ChordTriad.fifthOnly => null,
      };
      if (third != null) out.add(third);
    }

    if (!omitted.contains(5)) {
      var fifth = switch (triad) {
        ChordTriad.diminished => 6,
        ChordTriad.augmented => 8,
        _ => 7,
      };
      if (alts.contains(ChordAlteration.flatFive)) fifth = 6;
      if (alts.contains(ChordAlteration.sharpFive)) fifth = 8;
      out.add(fifth);
    }

    switch (seventh) {
      case ChordSeventh.none:
        break;
      case ChordSeventh.minor:
        out.add(10);
      case ChordSeventh.major:
        out.add(11);
      case ChordSeventh.diminished:
      case ChordSeventh.sixth:
        out.add(9);
    }

    // The ninth, present when the stack reaches it OR when an alteration names
    // it (`C7b9` has no ninth in its stack height and a flat ninth in its sound).
    if (extension >= 9 ||
        alts.contains(ChordAlteration.flatNine) ||
        alts.contains(ChordAlteration.sharpNine)) {
      if (alts.contains(ChordAlteration.flatNine)) out.add(13);
      if (alts.contains(ChordAlteration.sharpNine)) out.add(15);
      if (!alts.contains(ChordAlteration.flatNine) &&
          !alts.contains(ChordAlteration.sharpNine) &&
          extension >= 9) {
        out.add(14);
      }
    }

    // The eleventh — see the 13-omits-11 note above.
    final wantsEleven = extension == 11 ||
        alts.contains(ChordAlteration.sharpEleven) ||
        added.contains(11);
    if (wantsEleven) {
      out.add(alts.contains(ChordAlteration.sharpEleven) ? 18 : 17);
    }

    if (extension >= 13 || alts.contains(ChordAlteration.flatThirteen)) {
      out.add(alts.contains(ChordAlteration.flatThirteen) ? 20 : 21);
    }

    for (final degree in added) {
      final tone = switch (degree) {
        2 => 2,
        4 => 5,
        6 => 9,
        9 => 14,
        11 => 17,
        13 => 21,
        _ => null,
      };
      if (tone != null) out.add(tone);
    }

    return out.toList()..sort();
  }

  /// The sounding pitch classes (0 = C), the chord's own tones only.
  Set<int> get pitchClasses {
    final rootPc = _pitchClassOf(root);
    return {for (final i in intervals) (rootPc + i) % 12};
  }

  /// [pitchClasses] plus the slash bass, when there is one.
  Set<int> get pitchClassesWithBass =>
      {...pitchClasses, if (bass != null) _pitchClassOf(bass!)};

  /// The tones that carry the chord's identity — the third (or whatever stands
  /// in for it in a sus or power chord) and the seventh. What a comping voicing
  /// must not drop, and the input a guide-tone line is built from.
  List<int> get guideTones {
    final all = intervals;
    final out = <int>[];
    for (final third in const [2, 3, 4, 5]) {
      if (all.contains(third)) {
        out.add(third);
        break;
      }
    }
    for (final upper in const [9, 10, 11]) {
      if (all.contains(upper)) {
        out.add(upper);
        break;
      }
    }
    return out;
  }

  /// MIDI notes for preview/testing, the root placed at [rootMidi] (default
  /// C4 = 60). Voicing proper is BB-A1's job — this is deliberately the naive
  /// close stack, so a test can assert on notes without a voicing engine.
  List<int> midis({int rootMidi = 60}) =>
      [for (final i in intervals) rootMidi + i];

  /// The slash bass as a MIDI note in the octave below [rootMidi], or null.
  int? bassMidi({int rootMidi = 60}) {
    if (bass == null) return null;
    final rootPc = _pitchClassOf(root);
    final bassPc = _pitchClassOf(bass!);
    // Below the root, which is what a slash chord means.
    final delta = (bassPc - rootPc + 12) % 12;
    return rootMidi + delta - 12;
  }

  // ── printing ─────────────────────────────────────────────────────────────

  /// The plain ASCII symbol — `Cmaj7`, `F#m7b5`, `Bb7#11/D`.
  String get text => format();

  /// The printed symbol in [style]. Deterministic and canonical: several inputs
  /// map to one spec (`C+`, `Caug`) and this always prints the canonical one, so
  /// `parse(format(x)) == x` holds even where `format(parse(s)) != s`.
  String format({ChordSymbolStyle style = ChordSymbolStyle.plain}) {
    final b = StringBuffer(_noteName(root, style));
    b.write(_groupIfAmbiguous(_qualitySuffix(style)));
    if (bass != null) b.write('/${_noteName(bass!, style)}');
    return b.toString();
  }

  /// Parenthesises a suffix that would otherwise FUSE WITH THE ROOT.
  ///
  /// `C` + `b5` is the string `Cb5`, and by universal convention that reads as a
  /// C♭ power chord, not as C with a flattened fifth — exactly how `Bb5` is a
  /// B♭ power chord. The reader is right and the printer was wrong, so the
  /// printer disambiguates the way musicians do, with brackets: `C(b5)`.
  /// Caught by the round-trip property test, which is the entire reason it
  /// generates the whole model instead of a hand-picked list.
  static String _groupIfAmbiguous(String suffix) {
    if (suffix.isEmpty) return suffix;
    final first = suffix[0];
    final fuses = first == 'b' || first == '#' || first == '♭' || first == '♯';
    return fuses ? '($suffix)' : suffix;
  }

  String _qualitySuffix(ChordSymbolStyle style) {
    final b = StringBuffer();
    final acc = _Accidentals(style);

    // 1. the core mark
    switch (triad) {
      case ChordTriad.minor:
        b.write('m');
      case ChordTriad.diminished:
        // A half-diminished is a minor core with a flat five, so anything
        // reaching here with a minor seventh is a true diminished spelling.
        b.write(style.jazzGlyphs ? '°' : 'dim');
      case ChordTriad.augmented:
        b.write('aug');
      case ChordTriad.fifthOnly:
        b.write('5');
      case ChordTriad.major:
      case ChordTriad.sus2:
      case ChordTriad.sus4:
        break;
    }

    // 2. the seventh / stack number
    final height = extension > 0 ? extension : 7;
    switch (seventh) {
      case ChordSeventh.none:
        break;
      case ChordSeventh.minor:
        b.write('$height');
      case ChordSeventh.major:
        // `CmMaj7` keeps the app's existing spelling of a minor-major seventh
        // (see chord_quality.dart's `mMaj7`) rather than inventing a second one.
        if (triad == ChordTriad.minor) {
          b.write('Maj$height');
        } else if (style.jazzGlyphs) {
          b.write('∆$height');
        } else {
          b.write('maj$height');
        }
      case ChordSeventh.diminished:
        b.write('7');
      case ChordSeventh.sixth:
        // `C6/9` is one name, not a sixth with an add9 bolted on. Special-cased
        // so it prints the way it is written — and so it round-trips.
        if (added.length == 1 && added.contains(9)) {
          b.write('6/9');
        } else {
          b.write('6');
        }
    }

    // 3. sus, which follows the number (`C7sus4`, not `Csus47`)
    if (triad == ChordTriad.sus2) b.write('sus2');
    if (triad == ChordTriad.sus4) b.write('sus4');

    // 4. alterations, in a fixed order so the output is canonical
    const order = [
      ChordAlteration.flatFive,
      ChordAlteration.sharpFive,
      ChordAlteration.flatNine,
      ChordAlteration.sharpNine,
      ChordAlteration.sharpEleven,
      ChordAlteration.flatThirteen,
      ChordAlteration.altered,
    ];
    for (final a in order) {
      if (!alterations.contains(a)) continue;
      b.write(
        switch (a) {
          ChordAlteration.flatFive => '${acc.flat}5',
          ChordAlteration.sharpFive => '${acc.sharp}5',
          ChordAlteration.flatNine => '${acc.flat}9',
          ChordAlteration.sharpNine => '${acc.sharp}9',
          ChordAlteration.sharpEleven => '${acc.sharp}11',
          ChordAlteration.flatThirteen => '${acc.flat}13',
          ChordAlteration.altered => 'alt',
        },
      );
    }

    // 5. adds — skipping the 9 already spent on a `6/9`
    final printedAdds = added.toList()..sort();
    final sixNine =
        seventh == ChordSeventh.sixth && added.length == 1 && added.contains(9);
    if (!sixNine) {
      for (final d in printedAdds) {
        b.write('add$d');
      }
    }

    // 6. omissions
    final omissions = omitted.toList()..sort();
    for (final d in omissions) {
      b.write('no$d');
    }

    return b.toString();
  }

  // ── transformation ───────────────────────────────────────────────────────

  ChordSpec copyWith({
    Pitch? root,
    ChordTriad? triad,
    ChordSeventh? seventh,
    int? extension,
    Set<ChordAlteration>? alterations,
    Set<int>? added,
    Set<int>? omitted,
    Pitch? bass,
    bool clearBass = false,
  }) =>
      ChordSpec(
        root: root ?? this.root,
        triad: triad ?? this.triad,
        seventh: seventh ?? this.seventh,
        extension: extension ?? this.extension,
        alterations: alterations ?? this.alterations,
        added: added ?? this.added,
        omitted: omitted ?? this.omitted,
        bass: clearBass ? null : (bass ?? this.bass),
      );

  /// The same chord [interval] higher (or lower when [descending]), with the
  /// root and bass RE-SPELLED rather than reduced to a pitch class — so a chart
  /// transposed into D♭ reads in flats. This is the mechanism BB-T4's display
  /// and sounding transpositions both sit on.
  ChordSpec transposedBy(Interval interval, {bool descending = false}) =>
      copyWith(
        root: root.transposeBy(interval, descending: descending),
        bass: bass?.transposeBy(interval, descending: descending),
      );

  @override
  bool operator ==(Object other) =>
      other is ChordSpec &&
      other.root.step == root.step &&
      other.root.alter == root.alter &&
      other.triad == triad &&
      other.seventh == seventh &&
      other.extension == extension &&
      _setEq(other.alterations, alterations) &&
      _setEq(other.added, added) &&
      _setEq(other.omitted, omitted) &&
      other.bass?.step == bass?.step &&
      other.bass?.alter == bass?.alter;

  @override
  int get hashCode => Object.hash(
        root.step,
        root.alter,
        triad,
        seventh,
        extension,
        Object.hashAllUnordered(alterations),
        Object.hashAllUnordered(added),
        Object.hashAllUnordered(omitted),
        bass?.step,
        bass?.alter,
      );

  @override
  String toString() => 'ChordSpec($text)';
}

/// `alt` means "the altered dominant" — ♭9, ♯9, ♯11 and ♭13 all available. It
/// deliberately does NOT touch the fifth: an altered voicing usually omits it,
/// and omitting is a voicing decision (BB-A1), not something a symbol asserts.
Set<ChordAlteration> _expandAltered(Set<ChordAlteration> alterations) {
  if (!alterations.contains(ChordAlteration.altered)) return alterations;
  return {
    ...alterations,
    ChordAlteration.flatNine,
    ChordAlteration.sharpNine,
    ChordAlteration.sharpEleven,
    ChordAlteration.flatThirteen,
  };
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

int _pitchClassOf(Pitch p) => (p.step.semitonesFromC + p.alter) % 12;

class _Accidentals {
  _Accidentals(ChordSymbolStyle style)
      : flat = style.unicodeAccidentals ? '♭' : 'b',
        sharp = style.unicodeAccidentals ? '♯' : '#';
  final String flat;
  final String sharp;
}

/// The printed name of [p] — letter plus accidentals, octave ignored.
String _noteName(Pitch p, ChordSymbolStyle style) {
  final letter = p.step.name.toUpperCase();
  final acc = _Accidentals(style);

  if (style.germanNoteNames && p.step == Step.b) {
    // German: the natural B is H, and B♭ is B. Anything further out keeps the
    // H spelling with accidentals rather than reaching for `Heses`/`His` — this
    // is a chord-symbol renderer, not a note-name renderer.
    if (p.alter == 0) return 'H';
    if (p.alter == -1) return 'B';
    return 'H${_accidentalRun(p.alter, acc)}';
  }
  return '$letter${_accidentalRun(p.alter, acc)}';
}

String _accidentalRun(int alter, _Accidentals acc) =>
    alter >= 0 ? acc.sharp * alter : acc.flat * -alter;
