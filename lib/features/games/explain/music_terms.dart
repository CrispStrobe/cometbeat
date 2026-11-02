// lib/features/games/explain/music_terms.dart
//
// The term glossary behind the post-answer explanations: every musical TERM a
// lesson compares or names (dynamics, tempo words, articulation) as one enum,
// with the structural facts the visualizations need (loudness rank + playback
// gain, a typical tempo in BPM, the SMuFL dynamic glyph) and its localized
// meaning ("mezzoforte = halblaut") + a one-sentence, child-friendly
// explanation. The wording lives in the ARBs (`term<Name>Meaning` /
// `term<Name>Info`) so it is translated like every other string.
//
// The explanations are written in our own words — never copied from a
// textbook or curriculum (see the repo CLAUDE.md on curriculum text).

import 'package:comet_beat/l10n/app_localizations.dart';

/// What family a [MusicTerm] belongs to — decides which visualization the
/// explanation card draws.
enum TermKind {
  /// A fixed loudness level (pp … ff).
  dynamic,

  /// A gradual change of loudness (crescendo / diminuendo).
  dynamicChange,

  /// A fixed tempo word (Largo … Presto).
  tempo,

  /// A gradual change of tempo (accelerando / ritardando).
  tempoChange,

  /// How a single note is played (staccato, legato, accent …).
  articulation,
}

/// One musical term the lessons use.
///
/// [mark] is what stands in the score (`mf`, `Allegro`, `cresc.`); [italian]
/// is the full Italian word, which is the same in every UI language.
enum MusicTerm {
  // ── Dynamics, softest → loudest. [rank] orders them; [gain] is the
  //    playback level the demos use (matches Charades' scale at pp/p/f/ff).
  pp(TermKind.dynamic, 'pp', 'pianissimo', rank: 1, gain: 0.12, glyph: 0xE52B),
  p(TermKind.dynamic, 'p', 'piano', rank: 2, gain: 0.3, glyph: 0xE520),
  mp(TermKind.dynamic, 'mp', 'mezzopiano', rank: 3, gain: 0.45, glyph: 0xE52C),
  mf(TermKind.dynamic, 'mf', 'mezzoforte', rank: 4, gain: 0.6, glyph: 0xE52D),
  f(TermKind.dynamic, 'f', 'forte', rank: 5, gain: 0.8, glyph: 0xE522),
  ff(TermKind.dynamic, 'ff', 'fortissimo', rank: 6, gain: 1.0, glyph: 0xE52F),

  // ── Gradual loudness changes. rank: +1 louder, -1 softer.
  crescendo(TermKind.dynamicChange, 'cresc.', 'crescendo', rank: 1),
  diminuendo(TermKind.dynamicChange, 'dim.', 'diminuendo', rank: -1),

  // ── Tempo words, slowest → fastest, each with a typical BPM. Tempo words
  //    name a character as much as a speed, so the BPM is a rough middle of
  //    the usual metronome range, shown as "about N beats per minute".
  largo(TermKind.tempo, 'Largo', 'largo', rank: 1, bpm: 50),
  adagio(TermKind.tempo, 'Adagio', 'adagio', rank: 2, bpm: 70),
  andante(TermKind.tempo, 'Andante', 'andante', rank: 3, bpm: 90),
  moderato(TermKind.tempo, 'Moderato', 'moderato', rank: 4, bpm: 110),
  allegro(TermKind.tempo, 'Allegro', 'allegro', rank: 5, bpm: 135),
  vivace(TermKind.tempo, 'Vivace', 'vivace', rank: 6, bpm: 160),
  presto(TermKind.tempo, 'Presto', 'presto', rank: 7, bpm: 185),

  // ── Gradual tempo changes. rank: +1 faster, -1 slower.
  accelerando(TermKind.tempoChange, 'accel.', 'accelerando', rank: 1),
  ritardando(TermKind.tempoChange, 'rit.', 'ritardando', rank: -1),

  // ── Articulation.
  staccato(TermKind.articulation, 'staccato', 'staccato'),
  legato(TermKind.articulation, 'legato', 'legato'),
  tenuto(TermKind.articulation, 'tenuto', 'tenuto'),
  accent(TermKind.articulation, 'accent', 'accento'),
  marcato(TermKind.articulation, 'marcato', 'marcato');

  const MusicTerm(
    this.kind,
    this.mark,
    this.italian, {
    this.rank = 0,
    this.gain = 0,
    this.bpm = 0,
    this.glyph,
  });

  final TermKind kind;

  /// How the term appears in a score / on the game's card.
  final String mark;

  /// The full Italian word (`mezzoforte`), identical in every UI language.
  final String italian;

  /// Order within its family: loudness for dynamics (1 = pp), speed for tempo
  /// words (1 = Largo), direction (+1 / -1) for the gradual changes.
  final int rank;

  /// Playback gain 0..1 for a dynamic level (0 for everything else).
  final double gain;

  /// A typical tempo in beats per minute for a tempo word (0 otherwise).
  final int bpm;

  /// SMuFL code point of the dynamic glyph (dynamics only).
  final int? glyph;

  /// The six dynamic levels, softest → loudest.
  static List<MusicTerm> get dynamicsLadder => [
        for (final t in values)
          if (t.kind == TermKind.dynamic) t,
      ]..sort((a, b) => a.rank.compareTo(b.rank));

  /// The tempo words, slowest → fastest.
  static List<MusicTerm> get tempoLadder => [
        for (final t in values)
          if (t.kind == TermKind.tempo) t,
      ]..sort((a, b) => a.rank.compareTo(b.rank));

  /// The dynamic level written [mark] (`pp` … `ff`), or null.
  static MusicTerm? dynamicFromMark(String mark) =>
      _byMark(TermKind.dynamic, mark);

  /// The tempo word [mark] (`Largo` … `Presto`, any case), or null.
  static MusicTerm? tempoFromMark(String mark) =>
      _byMark(TermKind.tempo, mark.toLowerCase(), lower: true);

  static MusicTerm? _byMark(TermKind kind, String mark, {bool lower = false}) {
    for (final t in values) {
      if (t.kind != kind) continue;
      if ((lower ? t.mark.toLowerCase() : t.mark) == mark) return t;
    }
    return null;
  }
}

/// The name to headline [term] with: the Italian word for dynamics, tempo and
/// most articulations (capitalized, as a child sees it on the game's card),
/// but the localized word for the accent ("Akzent" / "Accent"), which the
/// lessons never call by its Italian name.
String termName(AppLocalizations l10n, MusicTerm term) => switch (term) {
      MusicTerm.accent => l10n.articulationAccent,
      _ when term.kind == TermKind.tempo => term.mark,
      _ when term.kind == TermKind.articulation =>
        term.italian[0].toUpperCase() + term.italian.substring(1),
      _ => term.italian,
    };

/// The short meaning of [term] in the UI language ("halblaut", "walking
/// pace") — what goes after the "=" in "mezzoforte = halblaut".
String termMeaning(AppLocalizations l10n, MusicTerm term) => switch (term) {
      MusicTerm.pp => l10n.termPpMeaning,
      MusicTerm.p => l10n.termPMeaning,
      MusicTerm.mp => l10n.termMpMeaning,
      MusicTerm.mf => l10n.termMfMeaning,
      MusicTerm.f => l10n.termFMeaning,
      MusicTerm.ff => l10n.termFfMeaning,
      MusicTerm.crescendo => l10n.termCrescMeaning,
      MusicTerm.diminuendo => l10n.termDimMeaning,
      MusicTerm.largo => l10n.termLargoMeaning,
      MusicTerm.adagio => l10n.termAdagioMeaning,
      MusicTerm.andante => l10n.termAndanteMeaning,
      MusicTerm.moderato => l10n.termModeratoMeaning,
      MusicTerm.allegro => l10n.termAllegroMeaning,
      MusicTerm.vivace => l10n.termVivaceMeaning,
      MusicTerm.presto => l10n.termPrestoMeaning,
      MusicTerm.accelerando => l10n.termAccelMeaning,
      MusicTerm.ritardando => l10n.termRitMeaning,
      MusicTerm.staccato => l10n.termStaccatoMeaning,
      MusicTerm.legato => l10n.termLegatoMeaning,
      MusicTerm.tenuto => l10n.termTenutoMeaning,
      MusicTerm.accent => l10n.termAccentMeaning,
      MusicTerm.marcato => l10n.termMarcatoMeaning,
    };

/// One child-friendly sentence explaining [term] in the UI language.
String termInfo(AppLocalizations l10n, MusicTerm term) => switch (term) {
      MusicTerm.pp => l10n.termPpInfo,
      MusicTerm.p => l10n.termPInfo,
      MusicTerm.mp => l10n.termMpInfo,
      MusicTerm.mf => l10n.termMfInfo,
      MusicTerm.f => l10n.termFInfo,
      MusicTerm.ff => l10n.termFfInfo,
      MusicTerm.crescendo => l10n.termCrescInfo,
      MusicTerm.diminuendo => l10n.termDimInfo,
      MusicTerm.largo => l10n.termLargoInfo,
      MusicTerm.adagio => l10n.termAdagioInfo,
      MusicTerm.andante => l10n.termAndanteInfo,
      MusicTerm.moderato => l10n.termModeratoInfo,
      MusicTerm.allegro => l10n.termAllegroInfo,
      MusicTerm.vivace => l10n.termVivaceInfo,
      MusicTerm.presto => l10n.termPrestoInfo,
      MusicTerm.accelerando => l10n.termAccelInfo,
      MusicTerm.ritardando => l10n.termRitInfo,
      MusicTerm.staccato => l10n.termStaccatoInfo,
      MusicTerm.legato => l10n.termLegatoInfo,
      MusicTerm.tenuto => l10n.termTenutoInfo,
      MusicTerm.accent => l10n.termAccentInfo,
      MusicTerm.marcato => l10n.termMarcatoInfo,
    };
