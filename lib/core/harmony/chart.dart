// lib/core/harmony/chart.dart
//
// BB-D2 — the chart document. The thing every other backing-band card reads.
//
// A chord chart is not a score and not a progression: it is bars, the chords
// inside them, and a FORM that says which bars play when. BB-D1 gave us a chord
// symbol that can say what a real chart says; this says where those chords sit.
//
// WHY NOT REUSE `ChordChart` (`core/audio/chord_progression.dart`). Its card
// says not to, and the reason is worth restating where someone will read it: it
// is a flat beat-list built for SCORING A PLAYER — "what should be sounding at
// beat 37" — which is the right shape for that job and the wrong one for a
// document. It has no bars, no sections, no repeats, so it cannot answer "play
// the A section twice" without being flattened first. Flattening is a
// projection, and projections belong downstream of a document, not in it.
//
// CHORDS CARRY BEAT OFFSET AND DURATION, NOT AN INDEX. `| Dm7 G7 |` and a bar
// holding a 3-beat chord then a 1-beat chord are then the same mechanism rather
// than two, and a chart in 7/8 needs no special case. It also means a bar is
// never implicitly "however many chords, evenly spaced", which is a rule that
// looks fine until the first `| C . . G |`.
//
// UNKNOWN CONTENT IS PRESERVED, NOT DROPPED. Every object here carries an
// [extra] map holding json keys this build did not recognise, written back
// unchanged on encode. That is `ProjectTrack.unreadable`'s rule one level down,
// and it exists because the alternative is silent destruction: a newer build
// writes a chart with a construct we lack, an older build opens it, saves, and
// the construct is gone — with nothing on screen ever having looked wrong.
//
// PURE DART. No Flutter, so the whole document is testable headlessly, which is
// what lets BB-A0 render one in a test without a widget in sight.

import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;

/// What is drawn at the end of a bar.
///
/// Only the barline itself — repeat STRUCTURE (how many times, which ending) is
/// [ChartBar.endingNumber] and [ChartSection.repeatCount], because a barline is
/// a glyph and a repeat is a behaviour, and conflating them is how "play it
/// twice" ends up depending on how the bar was drawn.
enum ChartBarline { plain, doubleBar, repeatStart, repeatEnd, repeatBoth, end }

/// Navigation marks, which say where to go rather than what to play.
enum ChartNavigation { segno, coda, fine, dc, ds, dcAlFine, dsAlCoda, dsAlFine }

/// One chord, and where it sits in its bar.
class ChartBeatChord {
  const ChartBeatChord({
    required this.chord,
    this.beat = 0,
    this.beats = 1,
    this.extra,
  });

  final ChordSpec chord;

  /// Beats from the start of the bar, 0-based. Fractional on purpose: a chord
  /// landing on the second half of beat 2 is `1.5`, not a special case.
  final double beat;

  /// How long it sounds, in beats. The chart's own unit, so a change of meter
  /// does not rewrite every chord.
  final double beats;

  /// Json keys this build did not recognise. See the header.
  final Map<String, dynamic>? extra;

  double get endBeat => beat + beats;
}

/// One bar.
class ChartBar {
  const ChartBar({
    this.chords = const [],
    this.meterChange,
    this.barline = ChartBarline.plain,
    this.endingNumber,
    this.navigation,
    this.extra,
  });

  /// In beat order. Not enforced by the constructor — a decoder must be able to
  /// hold a file that is out of order without refusing to open it — but
  /// [chordsInOrder] is what consumers should read.
  final List<ChartBeatChord> chords;

  /// A meter change AT this bar, or null to inherit. Per-bar rather than
  /// per-section: a single 2/4 bar in a 4/4 tune is ordinary, and putting the
  /// change on the section would force a section break to express it.
  final TimeSignature? meterChange;

  final ChartBarline barline;

  /// `1.` / `2.` volta number, or null. Kept as a NUMBER rather than a flag so
  /// a third ending needs no new field.
  final int? endingNumber;

  final ChartNavigation? navigation;

  final Map<String, dynamic>? extra;

  /// A bar with nothing in it is legal and common — `| C | % | % | % |` in a
  /// chart, or a bar of held sound.
  bool get isEmpty => chords.isEmpty;

  List<ChartBeatChord> get chordsInOrder =>
      [...chords]..sort((a, b) => a.beat.compareTo(b.beat));
}

/// A named run of bars — the unit a form refers to and a player rehearses.
class ChartSection {
  const ChartSection({
    this.label = '',
    this.bars = const [],
    this.repeatCount = 1,
    this.feel,
    this.tempoScale,
    this.intensity,
    this.extra,
  });

  /// "A", "Intro", "Chorus". Free text: chart conventions are not an enum, and
  /// a section called "Head (2nd x only)" must survive being typed.
  final String label;

  final List<ChartBar> bars;

  /// How many times this section plays. 1 = once. Clamped by [passes] rather
  /// than asserted, so a hand-edited 0 opens as 1 instead of vanishing.
  final int repeatCount;

  /// A style hint for the arranger (BB-A2) — "swing", "bossa". Null inherits.
  final String? feel;

  /// A tempo multiplier for this section (0.5 = half time). Null inherits.
  final double? tempoScale;

  /// 0..1 dynamic intensity for the arranger. Null inherits.
  final double? intensity;

  final Map<String, dynamic>? extra;

  int get passes => repeatCount < 1 ? 1 : repeatCount;

  /// Bars counted with repeats — what a timeline is long.
  int get totalBars => bars.length * passes;
}

/// A chord chart.
class Chart {
  const Chart({
    this.title = '',
    this.composer,
    this.keyFifths = 0,
    this.minor = false,
    this.meter = const TimeSignature(4, 4),
    this.tempoBpm = 120,
    this.styleId,
    this.sections = const [],
    this.pickupBeats = 0,
    this.extra,
  });

  final String title;
  final String? composer;

  /// Key as MusicXML-style fifths (−7…+7): 0 = C/a, +1 = G/e, −1 = F/d. Chosen
  /// over a bare pitch class because it distinguishes F♯ from G♭, which a chart
  /// spells and a pitch class cannot.
  final int keyFifths;

  /// Whether [keyFifths] names the minor key rather than its relative major.
  final bool minor;

  /// The prevailing meter; individual bars may override it.
  final TimeSignature meter;

  final int tempoBpm;

  /// The arranger style this chart asks for, or null for the default.
  final String? styleId;

  final List<ChartSection> sections;

  /// Beats of pickup before the first full bar. 0 for none.
  final double pickupBeats;

  final Map<String, dynamic>? extra;

  /// The tonic's pitch class (0 = C). Derived from [keyFifths] so the two can
  /// never disagree.
  int get tonicPitchClass {
    // Each fifth up is +7 semitones; minor keys are three semitones below their
    // relative major's tonic.
    final major = (keyFifths * 7) % 12;
    final pc = minor ? major + 9 : major;
    return ((pc % 12) + 12) % 12;
  }

  /// Every bar in play order, sections expanded by their repeat counts.
  ///
  /// The one definition of "the chart as played". Anything answering "what
  /// sounds at bar N" must come through here — two separate expansions is two
  /// answers, which is the bug WS-L2 hit in Loop Studio when the screen and the
  /// export each walked the section list themselves.
  List<ChartBar> get barsInPlayOrder => [
        for (final section in sections)
          for (var pass = 0; pass < section.passes; pass++) ...section.bars,
      ];

  int get totalBars => barsInPlayOrder.length;

  bool get isEmpty => sections.every((s) => s.bars.isEmpty);
}
