// The editable tablature model behind the Tab Workshop (B1). A [TabDocument] is
// a tuning + an ordered list of [TabColumn]s (time steps). Each column pins a
// fret to one or more strings (a chord). It converts *to* a crisp_notation
// [Score] for engraving/playback (carrying [TabVoicing]s so the user's explicit
// string choice is honoured, not re-derived) and *from* a Score so an imported
// file (GPIF/MusicXML/…) becomes editable as tab.
//
// Pure Dart (no Flutter) so the whole model is unit-testable.

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:comet_beat/shared/midi_pitch.dart';
import 'package:crisp_notation/crisp_notation.dart';

// B1 — `pitchFromMidi` used to be copy-pasted into five files (two spelled via a
// pitch-class table, two via natural-below-plus-sharp; all four agreed with the
// canonical one). It now lives once in `lib/shared/midi_pitch.dart` and is
// re-exported here, so this file's existing consumers are unaffected.
export 'package:comet_beat/shared/midi_pitch.dart' show pitchFromMidi;

/// A playing technique attached to a tab note. Each maps to the `Score` list
/// the tab engine renders from — and, where the GPIF writer reads the same
/// list, it survives a GPIF export too:
///
/// | technique | Score list | renders | exports to `.gp` |
/// |---|---|---|---|
/// | hammer | `slurs` (to the next note) | ✓ | ✓ |
/// | slide | `glissandos` (to the next note) | ✓ | ✓ |
/// | bend | `bends` | ✓ | ✓ |
/// | vibrato | `vibratos` | ✓ | ✓ |
/// | dead / ghost / harmonic | `tabNoteMarks` | ✓ | ✓ |
enum TabTechnique { hammer, slide, bend, vibrato, dead, ghost, harmonic }

/// Sentinel for [TabColumn.copyWith] so a nullable field can be *cleared*
/// (passing an explicit `null`) as distinct from *left unchanged* (not passed).
const Object _unset = Object();

/// One time-step in a [TabDocument]: a map of string index → fret (a chord when
/// more than one), the played [duration], and any [techniques]. String index
/// 0 = the top tab line (highest-sounding string), matching [Tuning].
///
/// Immutable; every edit goes through [copyWith] (the named `with…` helpers are
/// thin wrappers kept for the existing call sites). Nullable fields use the
/// [_unset] sentinel so they can be explicitly cleared.
class TabColumn {
  final Map<int, int> frets;
  final NoteDuration duration;
  final Set<TabTechnique> techniques;

  /// The selected chord diagram, kept alongside the playable fret voicing.
  final ChordDiagram? chord;

  /// When true, this note sustains INTO the next column (a tie): the next
  /// column doesn't re-attack — it prolongs this one. Notation draws a tie and
  /// playback sums the durations. Set on a noteful column only.
  final bool tieToNext;

  /// The tuplet ratio (actual, normal) this column belongs to, e.g. (3, 2) for
  /// an eighth triplet — 3 notes in the time of 2. Null = not a tuplet. Adjacent
  /// columns with the same ratio form one printed group; each note's written
  /// value is unchanged but its sounding length is scaled by normal/actual.
  final (int, int)? tuplet;

  /// Bar-level repeat barlines, anchored to the FIRST column of a bar: the bar
  /// this column starts opens (`startRepeat`) or closes (`endRepeat`) a repeat.
  final bool startRepeat;
  final bool endRepeat;

  /// The alternate-ending (volta) number bracketed over this column's bar, or
  /// null for none. Bar-level, anchored to the bar's first column.
  final int? volta;

  /// A repeat-structure direction (D.C. / D.S. / Coda / Fine / Segno …) drawn
  /// over this column's bar, or null. Bar-level, anchored to the first column.
  final NavigationMark? navigation;

  /// A section / rehearsal label (e.g. "Verse", "Chorus") shown above this
  /// note, or null. Anchored to this column's own note.
  final String? section;

  /// A tempo change (BPM) that takes effect at this column's bar, or null.
  /// Bar-level, anchored to the bar's first column (A9). `toScore` stamps
  /// `Measure.tempoChange`; playback re-times from here on.
  final double? tempoChange;

  /// A parametric bend curve (B1): control points `(position 0..1, offset in
  /// ¼-steps)`. Null = no bend curve (the flat [TabTechnique.bend] still gives a
  /// plain whole-step bend). Non-null → `Bend.curve` in `toScore`, so a
  /// bend/release, prebend or multi-point shape survives export.
  final List<BendPoint>? bend;

  /// A whammy-bar (tremolo-bar) curve (B2): control points, same shape as
  /// [bend]. Null = none. Non-null → `TremoloBar.curve` in `toScore`.
  final List<BendPoint>? whammy;

  /// A slide-in / slide-out ornament on this note (B3): scoop/fall in or out.
  /// Distinct from [TabTechnique.slide], which is a legato slide TO the next
  /// note. Maps to `TabSlide(id, direction)` in `toScore`.
  final SlideInOut? slide;

  /// Right-hand tapping on this note (B4) → `Tap` in `toScore`. (Hammer-on vs
  /// pull-off stay the [TabTechnique.hammer] slur — the distinction is by pitch
  /// direction, which the notation slur already conveys.)
  final bool tap;

  /// The harmonic KIND on this note (B5): natural / artificial / pinch / tapped
  /// / semi / feedback. Null = no harmonic (the flat [TabTechnique.harmonic]
  /// still gives a plain natural harmonic). Maps to `TabNoteMark(id, style)`.
  final TabNoteStyle? harmonic;

  /// Palm-mute this note (B6) → a self-span `PalmMute(id, id)` in `toScore`.
  final bool palmMute;

  /// Let this note ring (B6) → a self-span `LetRing(id, id)`.
  final bool letRing;

  /// Note articulations (B6): staccato / tenuto / accent / marcato / fermata …
  /// set on the engraved `NoteElement.articulations`.
  final Set<Articulation> articulations;

  /// An ornament on this note (B7): trill / mordent / turn … →
  /// `NoteElement.ornament`. (A trill's auxiliary interval isn't modelled here.)
  final Ornament? ornament;

  /// Tremolo-picking beam count (B7): 1 = 8th, 2 = 16th, 3 = 32nd; null = none.
  /// Maps to `NoteElement.tremolo`.
  final int? tremolo;

  /// Grace-note pitches (B8) played before this note, as MIDI numbers, or null.
  /// Maps to `NoteElement.graceNotes`; [graceStyle] picks acciaccatura vs
  /// appoggiatura.
  final List<int>? graceMidis;

  /// How [graceMidis] are performed/drawn (B8). Ignored when [graceMidis] null.
  final GraceStyle graceStyle;

  /// A strum / rolled-chord direction over this column (B9) →
  /// `NoteElement.arpeggio`. Null = block chord.
  final Arpeggio? arpeggio;

  /// Pick-stroke direction (B9): true = up-stroke, false = down-stroke, null =
  /// unspecified. Maps to `PickStroke(id, up:)`.
  final bool? pickStroke;

  /// Left-hand fingering per note (B10): 0 = open/T (thumb), 1–4 fingers, one
  /// entry per pitch (pitch order). Maps to `NoteElement.fingerings`.
  final List<int>? leftFingers;

  /// A BARRE held for this chord: the fret one finger lies across, or null.
  ///
  /// ⚠ A distinct fact from [leftFingers], not a summary of it. A barre chord's
  /// digits already read 1,1,1 — that says three fingers at one fret, which is
  /// not what a barre is. Guitar Pro states the barre separately and so do we;
  /// maps to `TabBarre` in `toScore`, which engraves as `CIII` over the chord.
  final int? barreFret;

  /// Guitar Pro's `BarreString` value, carried through unchanged so a GP file
  /// round-trips. Not reinterpreted here — see `TabBarre.lowestString`.
  final int? barreString;

  /// Right-hand fingering (B10): p/i/m/a/c → `TabFingering(id, finger)`.
  final RightHandFinger? rightFinger;

  /// A dynamic marking on this note (C1): ppp…fff → `DynamicMarking` + a
  /// mapped `NoteElement.velocity`. Null = inherit.
  final DynamicLevel? dynamic;

  /// A crescendo/diminuendo hairpin STARTING at this column (C1), running to the
  /// next column that sets a [dynamic] (or the next hairpin). Null = none.
  final HairpinType? hairpin;

  const TabColumn({
    this.frets = const {},
    this.duration = NoteDuration.quarter,
    this.techniques = const {},
    this.chord,
    this.tieToNext = false,
    this.tuplet,
    this.startRepeat = false,
    this.endRepeat = false,
    this.volta,
    this.navigation,
    this.section,
    this.tempoChange,
    this.bend,
    this.whammy,
    this.slide,
    this.tap = false,
    this.harmonic,
    this.palmMute = false,
    this.letRing = false,
    this.articulations = const {},
    this.ornament,
    this.tremolo,
    this.graceMidis,
    this.graceStyle = GraceStyle.acciaccatura,
    this.arpeggio,
    this.pickStroke,
    this.leftFingers,
    this.barreFret,
    this.barreString,
    this.rightFinger,
    this.dynamic,
    this.hairpin,
  });

  bool get isEmpty => frets.isEmpty;

  /// The one true copy operation. Pass a value to change a field; omit it to
  /// keep the current one. For nullable fields, pass an explicit `null` to
  /// clear (the [_unset] sentinel is what "omitted" looks like internally).
  TabColumn copyWith({
    Map<int, int>? frets,
    NoteDuration? duration,
    Set<TabTechnique>? techniques,
    Object? chord = _unset,
    bool? tieToNext,
    Object? tuplet = _unset,
    bool? startRepeat,
    bool? endRepeat,
    Object? volta = _unset,
    Object? navigation = _unset,
    Object? section = _unset,
    Object? tempoChange = _unset,
    Object? bend = _unset,
    Object? whammy = _unset,
    Object? slide = _unset,
    bool? tap,
    Object? harmonic = _unset,
    bool? palmMute,
    bool? letRing,
    Set<Articulation>? articulations,
    Object? ornament = _unset,
    Object? tremolo = _unset,
    Object? graceMidis = _unset,
    GraceStyle? graceStyle,
    Object? arpeggio = _unset,
    Object? pickStroke = _unset,
    Object? leftFingers = _unset,
    Object? barreFret = _unset,
    Object? barreString = _unset,
    Object? rightFinger = _unset,
    Object? dynamic = _unset,
    Object? hairpin = _unset,
  }) =>
      TabColumn(
        frets: frets ?? this.frets,
        duration: duration ?? this.duration,
        techniques: techniques ?? this.techniques,
        chord: chord == _unset ? this.chord : chord as ChordDiagram?,
        tieToNext: tieToNext ?? this.tieToNext,
        tuplet: tuplet == _unset ? this.tuplet : tuplet as (int, int)?,
        startRepeat: startRepeat ?? this.startRepeat,
        endRepeat: endRepeat ?? this.endRepeat,
        volta: volta == _unset ? this.volta : volta as int?,
        navigation: navigation == _unset
            ? this.navigation
            : navigation as NavigationMark?,
        section: section == _unset ? this.section : section as String?,
        tempoChange:
            tempoChange == _unset ? this.tempoChange : tempoChange as double?,
        bend: bend == _unset ? this.bend : bend as List<BendPoint>?,
        whammy: whammy == _unset ? this.whammy : whammy as List<BendPoint>?,
        slide: slide == _unset ? this.slide : slide as SlideInOut?,
        tap: tap ?? this.tap,
        harmonic:
            harmonic == _unset ? this.harmonic : harmonic as TabNoteStyle?,
        palmMute: palmMute ?? this.palmMute,
        letRing: letRing ?? this.letRing,
        articulations: articulations ?? this.articulations,
        ornament: ornament == _unset ? this.ornament : ornament as Ornament?,
        tremolo: tremolo == _unset ? this.tremolo : tremolo as int?,
        graceMidis:
            graceMidis == _unset ? this.graceMidis : graceMidis as List<int>?,
        graceStyle: graceStyle ?? this.graceStyle,
        arpeggio: arpeggio == _unset ? this.arpeggio : arpeggio as Arpeggio?,
        pickStroke:
            pickStroke == _unset ? this.pickStroke : pickStroke as bool?,
        leftFingers: leftFingers == _unset
            ? this.leftFingers
            : leftFingers as List<int>?,
        barreFret: barreFret == _unset ? this.barreFret : barreFret as int?,
        barreString:
            barreString == _unset ? this.barreString : barreString as int?,
        rightFinger: rightFinger == _unset
            ? this.rightFinger
            : rightFinger as RightHandFinger?,
        dynamic: dynamic == _unset ? this.dynamic : dynamic as DynamicLevel?,
        hairpin: hairpin == _unset ? this.hairpin : hairpin as HairpinType?,
      );

  TabColumn withFret(int string, int fret) =>
      copyWith(frets: {...frets, string: fret});

  TabColumn withoutString(int string) => copyWith(
        frets: {
          for (final e in frets.entries)
            if (e.key != string) e.key: e.value,
        },
      );

  TabColumn withDuration(NoteDuration d) => copyWith(duration: d);

  /// Adds [t] if absent, else removes it.
  TabColumn toggleTechnique(TabTechnique t) => copyWith(
        techniques: techniques.contains(t)
            ? ({...techniques}..remove(t))
            : {...techniques, t},
      );

  /// Sets (or clears, when null) this column's chord diagram.
  TabColumn withChord(ChordDiagram? c) => copyWith(chord: c);

  /// Sets whether this note ties into the next column.
  TabColumn withTie(bool tie) => copyWith(tieToNext: tie);

  /// Sets (or clears, when null) this column's tuplet ratio.
  TabColumn withTuplet((int, int)? ratio) => copyWith(tuplet: ratio);

  /// Sets this column's bar repeat-barline flags.
  TabColumn withRepeat({bool? start, bool? end}) =>
      copyWith(startRepeat: start ?? startRepeat, endRepeat: end ?? endRepeat);

  /// Sets (or clears, when null) this column's bar volta number.
  TabColumn withVolta(int? v) => copyWith(volta: v);

  /// Sets (or clears, when null) this column's bar direction mark.
  TabColumn withNavigation(NavigationMark? n) => copyWith(navigation: n);

  /// Sets (or clears, when null) this column's section/rehearsal label.
  TabColumn withSection(String? label) => copyWith(section: label);

  /// Sets (or clears, when null) this column's bar tempo change (BPM).
  TabColumn withTempo(double? bpm) => copyWith(tempoChange: bpm);

  /// Sets (or clears, when null) this column's parametric bend curve (B1).
  TabColumn withBend(List<BendPoint>? points) => copyWith(bend: points);

  /// Sets (or clears, when null) this column's whammy-bar curve (B2).
  TabColumn withWhammy(List<BendPoint>? points) => copyWith(whammy: points);

  /// Sets (or clears, when null) this column's slide-in/out ornament (B3).
  TabColumn withSlide(SlideInOut? kind) => copyWith(slide: kind);

  /// Sets whether this note is right-hand tapped (B4).
  TabColumn withTap(bool on) => copyWith(tap: on);

  /// Sets (or clears, when null) this column's harmonic kind (B5).
  TabColumn withHarmonic(TabNoteStyle? kind) => copyWith(harmonic: kind);

  /// Sets whether this note is palm-muted (B6).
  TabColumn withPalmMute(bool on) => copyWith(palmMute: on);

  /// Sets whether this note lets ring (B6).
  TabColumn withLetRing(bool on) => copyWith(letRing: on);

  /// Adds [a] if absent, else removes it (B6).
  TabColumn toggleArticulation(Articulation a) => copyWith(
        articulations: articulations.contains(a)
            ? ({...articulations}..remove(a))
            : {...articulations, a},
      );

  /// Sets (or clears, when null) this column's ornament (B7).
  TabColumn withOrnament(Ornament? o) => copyWith(ornament: o);

  /// Sets (or clears, when null) this column's tremolo-picking beams (B7).
  TabColumn withTremolo(int? beams) => copyWith(tremolo: beams);

  /// Sets (or clears, when null) this column's grace notes (B8).
  TabColumn withGrace(
    List<int>? midis, {
    GraceStyle style = GraceStyle.acciaccatura,
  }) =>
      copyWith(graceMidis: midis, graceStyle: style);

  /// Sets (or clears, when null) this column's strum/arpeggio direction (B9).
  TabColumn withArpeggio(Arpeggio? a) => copyWith(arpeggio: a);

  /// Sets (or clears, when null) this column's pick-stroke direction (B9).
  TabColumn withPickStroke(bool? up) => copyWith(pickStroke: up);

  /// Sets (or clears, when null) this column's left-hand fingering (B10).
  TabColumn withLeftFingers(List<int>? fingers) =>
      copyWith(leftFingers: fingers);

  /// Sets (or clears, when null) this column's right-hand fingering (B10).
  TabColumn withRightFinger(RightHandFinger? f) => copyWith(rightFinger: f);

  /// Sets (or clears, when null) this column's dynamic level (C1).
  TabColumn withDynamic(DynamicLevel? d) => copyWith(dynamic: d);

  /// Sets (or clears, when null) a hairpin starting at this column (C1).
  TabColumn withHairpin(HairpinType? h) => copyWith(hairpin: h);

  /// A deep copy (fresh mutable collections) — for duplicating columns.
  TabColumn copy() => copyWith(
        frets: {...frets},
        techniques: {...techniques},
        articulations: {...articulations},
        bend: bend == null ? null : [...bend!],
        whammy: whammy == null ? null : [...whammy!],
        graceMidis: graceMidis == null ? null : [...graceMidis!],
        leftFingers: leftFingers == null ? null : [...leftFingers!],
        barreFret: barreFret,
        barreString: barreString,
      );
}

/// Rhythm is measured on a **32nd-note grid** so every selectable value — down
/// to a 32nd and including dotted forms — tiles a bar integrally. A whole note
/// is 32 steps; a 4/4 bar therefore holds [_kBarSteps] steps.
const int _kBarSteps = 32; // one 4/4 bar = a whole note = 32 thirty-seconds

/// The stock bend shapes (B1), each a list of `(position 0..1, height in whole
/// steps)` control points. A whole-step bend rises 1.0; UI multiplies for ½/1½.
/// These are the four presets industry editors expose; a user can also author
/// an arbitrary point list.
abstract final class TabBends {
  /// Rise from pitch to [height] over the note.
  static List<BendPoint> bend({double height = 1.0}) => [
        const BendPoint(0, 0),
        BendPoint(1, height),
      ];

  /// Rise to [height] then release back to pitch.
  static List<BendPoint> bendRelease({double height = 1.0}) => [
        const BendPoint(0, 0),
        BendPoint(0.5, height),
        const BendPoint(1, 0),
      ];

  /// Struck already bent to [height] (a prebend), then held.
  static List<BendPoint> prebend({double height = 1.0}) => [
        BendPoint(0, height),
        BendPoint(1, height),
      ];

  /// Struck prebent to [height], then released to pitch.
  static List<BendPoint> prebendRelease({double height = 1.0}) => [
        BendPoint(0, height),
        BendPoint(0.5, height),
        const BendPoint(1, 0),
      ];
}

/// The selectable note durations, each with its length in 32nd-note steps.
/// Ordered long→short (whole … 32nd, with the dotted forms interleaved).
const List<(NoteDuration, int)> kTabDurations = [
  (NoteDuration.whole, 32),
  (NoteDuration(DurationBase.half, dots: 1), 24),
  (NoteDuration.half, 16),
  (NoteDuration(DurationBase.quarter, dots: 1), 12),
  (NoteDuration.quarter, 8),
  (NoteDuration(DurationBase.eighth, dots: 1), 6),
  (NoteDuration.eighth, 4),
  (NoteDuration(DurationBase.sixteenth, dots: 1), 3),
  (NoteDuration(DurationBase.sixteenth), 2),
  (NoteDuration(DurationBase.thirtySecond), 1),
];

/// This duration's length in 32nd-note steps. Computed from the actual note
/// fraction (× 32) so it is exact for ANY [NoteDuration] — dotted, tuplet, or an
/// imported value not in [kTabDurations] — instead of a table lookup that fell
/// back to a quarter and mis-tiled 16th/32nd imports.
int _stepsOf(NoteDuration d) {
  final steps = (d.toFraction().toDouble() * _kBarSteps).round();
  return steps < 1 ? 1 : steps;
}

/// A column's SOUNDING length in (fractional) 32nd-note steps: the written value
/// scaled by a tuplet's normal/actual (so an eighth in a 3:2 triplet occupies
/// 4 × 2/3 steps). Bars are tiled by these, so a whole triplet group (integral
/// total) lands on a bar line even though each member is fractional.
double _scaledStepsOf(TabColumn c) {
  final base = _stepsOf(c.duration).toDouble();
  final t = c.tuplet;
  return t == null ? base : base * t.$2 / t.$1;
}

/// The MIDI note-on velocity (0..127) a dynamic level maps to (C1) — a standard
/// ppp→ffff ramp; the sudden/accent marks (sf/sfz/…) read as a firm accent.
int velocityOf(DynamicLevel d) => switch (d) {
      DynamicLevel.pppp => 8,
      DynamicLevel.ppp => 16,
      DynamicLevel.pp => 33,
      DynamicLevel.p => 49,
      DynamicLevel.mp => 64,
      DynamicLevel.mf => 80,
      DynamicLevel.f => 96,
      DynamicLevel.ff => 112,
      DynamicLevel.fff => 120,
      DynamicLevel.ffff => 127,
      _ => 104, // sf/sfz/sffz/fz/fp/rf — a firm accent
    };

/// The ramp levels a raw MIDI velocity quantises to (pppp…ffff), nearest by
/// [velocityOf] — so a MIDI/GP import that carries only note velocities still
/// keeps its loudness as an editable dynamic (C1).
const List<DynamicLevel> _dynamicRamp = [
  DynamicLevel.pppp,
  DynamicLevel.ppp,
  DynamicLevel.pp,
  DynamicLevel.p,
  DynamicLevel.mp,
  DynamicLevel.mf,
  DynamicLevel.f,
  DynamicLevel.ff,
  DynamicLevel.fff,
  DynamicLevel.ffff,
];

/// The [DynamicLevel] whose [velocityOf] is closest to [velocity].
DynamicLevel nearestDynamic(int velocity) {
  var best = _dynamicRamp.first;
  var bestDist = (velocityOf(best) - velocity).abs();
  for (final d in _dynamicRamp.skip(1)) {
    final dist = (velocityOf(d) - velocity).abs();
    if (dist < bestDist) {
      best = d;
      bestDist = dist;
    }
  }
  return best;
}

/// One track in a multi-track tab "band" — a named [TabDocument] (its own
/// tuning, so a bass track can sit next to a guitar track).
class TabTrack {
  String name;
  TabDocument doc;
  bool muted;
  bool soloed;

  /// A6 — this track's insert chain in the shared [FxSpec] model (the same
  /// effects the Audio Editor, Tracker, Loop Studio and Instrument Builder
  /// use). Empty = dry, and an all-empty band renders byte-identically to
  /// before effects existed here.
  ///
  /// Per TRACK, not per band: in a two-guitar tab the rhythm part wants crunch
  /// while the lead wants fuzz. Applied by `renderTabBandWithFx` in
  /// `tab_fx.dart`.
  List<FxSpec> fxChain;

  /// The General-MIDI program (0..127) this track sounds with (D1); null =
  /// the app default. Carried into MIDI/GP export as the track's patch.
  int? instrument;

  /// A per-track capo (D1): raises this track's sounding pitch, fret numbers
  /// unchanged (see [TabDocument.toScore]'s `capo`).
  int capo;

  /// Mixer volume 0..1 (D2), authored gain before the master mix.
  double volume;

  /// Mixer pan −1 (left) … 0 (centre) … +1 (right) (D2).
  double pan;

  /// A percussion / drum-tab track (D3): its lines map to drum voices, and
  /// export marks the track as percussion (GM channel 10).
  bool isDrums;

  TabTrack(
    this.name,
    this.doc, {
    this.muted = false,
    this.soloed = false,
    List<FxSpec>? fxChain,
    this.instrument,
    this.capo = 0,
    this.volume = 1.0,
    this.pan = 0.0,
    this.isDrums = false,
  }) : fxChain = fxChain ?? <FxSpec>[];
}

/// Standard drum-tab lines (D3), top → bottom, each mapped to its General-MIDI
/// percussion note (GM channel-10 key numbers). A drum [TabTrack]'s tuning has
/// one string per line; a mark on line _i_ sounds `kDrumLines[i].$2`.
const List<(String, int)> kDrumLines = [
  ('Crash', 49),
  ('Ride', 51),
  ('Hi-hat', 42),
  ('Open hat', 46),
  ('Tom hi', 48),
  ('Tom mid', 45),
  ('Tom low', 41),
  ('Snare', 38),
  ('Kick', 36),
];

/// The GM percussion note for drum-tab line [line] (0 = top), or null if out of
/// range. Used to voice a drum [TabTrack] and to build its export.
int? drumMidiForLine(int line) =>
    (line >= 0 && line < kDrumLines.length) ? kDrumLines[line].$2 : null;

/// A curated set of General-MIDI instruments a tab track can sound with (D1),
/// as `(program 0-based, name)`. Guitar/bass-forward, since that's what a tab
/// editor mostly voices; the names are the standard GM vocabulary. A track's
/// [TabTrack.instrument] holds the chosen program; `TabDocument.toScore`'s
/// `program` carries it into `Score.metadata.midiProgram` → exported MIDI.
const List<(int, String)> kTabInstruments = [
  (24, 'Nylon Guitar'),
  (25, 'Steel Guitar'),
  (26, 'Jazz Guitar'),
  (27, 'Clean Electric'),
  (29, 'Overdrive Guitar'),
  (30, 'Distortion Guitar'),
  (32, 'Acoustic Bass'),
  (33, 'Fingered Bass'),
  (34, 'Picked Bass'),
  (35, 'Fretless Bass'),
  (0, 'Piano'),
  (40, 'Violin'),
  (48, 'Strings'),
  (46, 'Harp'),
  (105, 'Banjo'),
  (56, 'Trumpet'),
];

/// The GM instrument name for [program], or null if it isn't in the curated
/// [kTabInstruments] set.
String? tabInstrumentName(int? program) {
  if (program == null) return null;
  for (final (p, name) in kTabInstruments) {
    if (p == program) return name;
  }
  return null;
}

/// A bar range to loop while practising (D4), inclusive `[startBar, endBar]`.
class LoopRange {
  final int startBar;
  final int endBar;
  const LoopRange(this.startBar, this.endBar);

  bool contains(int bar) => bar >= startBar && bar <= endBar;
  int get barCount => endBar - startBar + 1;
}

/// The speed-trainer tempo ramp (D4): starting at [startPct] of [baseBpm],
/// rising by [stepPct] each loop until [targetPct] (inclusive, always landing
/// exactly on the target). Pure; the UI drives a loop player with these BPMs.
List<int> speedTrainerTempos({
  required int baseBpm,
  double startPct = 60,
  double stepPct = 10,
  double targetPct = 100,
}) {
  final target = (baseBpm * targetPct / 100).round();
  if (stepPct <= 0 || startPct > targetPct) return [target];
  final out = <int>[];
  for (var pct = startPct; pct <= targetPct + 1e-9; pct += stepPct) {
    out.add((baseBpm * pct / 100).round());
  }
  if (out.isEmpty || out.last != target) out.add(target);
  return out;
}

/// The metronome click times in ms (D4) for [bars] bars of [beatsPerBar] at
/// [bpm] — one entry per beat from 0. Pure; the click player reads it.
List<int> metronomeClicksMs({
  required int bpm,
  int beatsPerBar = 4,
  int bars = 1,
}) {
  final beatMs = 60000 / bpm;
  return [for (var b = 0; b < beatsPerBar * bars; b++) (b * beatMs).round()];
}

/// The tracks that should SOUND: if any track is soloed, only the soloed ones;
/// otherwise every non-muted track.
Iterable<TabTrack> audibleTracks(List<TabTrack> tracks) {
  final anySolo = tracks.any((t) => t.soloed);
  return tracks.where((t) => anySolo ? t.soloed : !t.muted);
}

/// Merges several tracks' `(midis, ms)` timelines into one sequential timeline
/// where every slice carries the pitches sounding across ALL tracks at that
/// moment — so `AudioService.playTimedChords` plays the band together. Tracks
/// may differ in length; the merge runs to the longest. Pure + testable.
List<(List<int>, int)> mergePlaybackEvents(
  List<List<(List<int>, int)>> tracks,
) {
  // Expand each track into absolute [start, end) segments.
  final segs = <List<({int start, int end, List<int> midis})>>[];
  for (final t in tracks) {
    var at = 0;
    final s = <({int start, int end, List<int> midis})>[];
    for (final (midis, ms) in t) {
      s.add((start: at, end: at + ms, midis: midis));
      at += ms;
    }
    segs.add(s);
  }
  // Slice at every segment boundary.
  final bounds = <int>{0};
  for (final s in segs) {
    for (final e in s) {
      bounds
        ..add(e.start)
        ..add(e.end);
    }
  }
  final times = bounds.toList()..sort();
  final out = <(List<int>, int)>[];
  for (var i = 0; i + 1 < times.length; i++) {
    final t0 = times[i];
    final t1 = times[i + 1];
    if (t1 <= t0) continue;
    final midis = <int>{};
    for (final s in segs) {
      for (final e in s) {
        if (e.start <= t0 && t0 < e.end) midis.addAll(e.midis);
      }
    }
    out.add((midis.toList()..sort(), t1 - t0));
  }
  return out;
}

/// A mutable tablature document: [tuning] + a list of [columns].
class TabDocument {
  Tuning tuning;
  final List<TabColumn> columns;

  /// The meter columns are tiled into. Default 4/4; set it and a bar holds
  /// [barSteps] thirty-second-note steps (3/4 = 24, 6/8 = 24, 5/4 = 40, …).
  TimeSignature timeSignature;

  /// The key signature (circle-of-fifths count, −7..+7; 0 = C/a). Drives the
  /// accidental spelling on the standard/grand-staff views and exports.
  KeySignature keySignature;

  /// An optional SECOND voice (C2): a parallel column list tiled into the same
  /// bars as [columns] and emitted as `Measure.voice2`. Empty = single voice.
  final List<TabColumn> voice2;

  TabDocument({
    required this.tuning,
    List<TabColumn>? columns,
    this.timeSignature = TimeSignature.fourFour,
    this.keySignature = const KeySignature(0),
    List<TabColumn>? voice2,
  })  : columns = columns ?? <TabColumn>[],
        voice2 = voice2 ?? <TabColumn>[];

  /// A blank document with [initialColumns] empty columns.
  factory TabDocument.blank(Tuning tuning, {int initialColumns = 8}) =>
      TabDocument(
        tuning: tuning,
        columns: List.generate(initialColumns, (_) => const TabColumn()),
      );

  int get stringCount => tuning.stringCount;

  /// How many 32nd-note steps fill one bar at the current [timeSignature]
  /// (4/4 = 32 = a whole note). Columns tile into bars by this capacity.
  int get barCapacity =>
      (timeSignature.toFraction().toDouble() * _kBarSteps).round();

  /// Grows [columns] so index [col] exists (padding with empty columns).
  void _ensure(int col) {
    while (columns.length <= col) {
      columns.add(const TabColumn());
    }
  }

  /// Sets the [fret] on [string] at [col] (creating the column if needed).
  void setFret(int col, int string, int fret) {
    _ensure(col);
    columns[col] = columns[col].withFret(string, fret);
  }

  /// Clears [string] at [col] (leaving other strings in that column).
  void clearCell(int col, int string) {
    if (col < columns.length) {
      columns[col] = columns[col].withoutString(string);
    }
  }

  /// Sets the [duration] of the column at [col].
  void setDuration(int col, NoteDuration duration) {
    _ensure(col);
    columns[col] = columns[col].withDuration(duration);
  }

  /// Toggles technique [t] on the column at [col].
  void toggleTechnique(int col, TabTechnique t) {
    _ensure(col);
    columns[col] = columns[col].toggleTechnique(t);
  }

  /// Sets whether the note at [col] ties into the next column.
  void setTie(int col, bool tie) {
    _ensure(col);
    columns[col] = columns[col].withTie(tie);
  }

  /// Sets (or clears, when null) the tuplet ratio on the column at [col].
  void setTuplet(int col, (int, int)? ratio) {
    _ensure(col);
    columns[col] = columns[col].withTuplet(ratio);
  }

  /// Sets (or clears, when null) the parametric bend curve on the column at
  /// [col] (B1). Use [TabBends] for the stock shapes.
  void setBend(int col, List<BendPoint>? points) {
    _ensure(col);
    columns[col] = columns[col].withBend(points);
  }

  /// Sets (or clears, when null) the whammy-bar curve on the column at [col]
  /// (B2).
  void setWhammy(int col, List<BendPoint>? points) {
    _ensure(col);
    columns[col] = columns[col].withWhammy(points);
  }

  /// Sets (or clears, when null) the slide-in/out ornament on the column at
  /// [col] (B3).
  void setSlide(int col, SlideInOut? kind) {
    _ensure(col);
    columns[col] = columns[col].withSlide(kind);
  }

  /// Sets right-hand tapping on the column at [col] (B4).
  void setTap(int col, bool on) {
    _ensure(col);
    columns[col] = columns[col].withTap(on);
  }

  /// Sets (or clears, when null) the harmonic kind on the column at [col] (B5).
  void setHarmonic(int col, TabNoteStyle? kind) {
    _ensure(col);
    columns[col] = columns[col].withHarmonic(kind);
  }

  /// Sets palm-mute on the column at [col] (B6).
  void setPalmMute(int col, bool on) {
    _ensure(col);
    columns[col] = columns[col].withPalmMute(on);
  }

  /// Sets let-ring on the column at [col] (B6).
  void setLetRing(int col, bool on) {
    _ensure(col);
    columns[col] = columns[col].withLetRing(on);
  }

  /// Toggles articulation [a] on the column at [col] (B6).
  void toggleArticulation(int col, Articulation a) {
    _ensure(col);
    columns[col] = columns[col].toggleArticulation(a);
  }

  /// Sets (or clears, when null) the dynamic on the column at [col] (C1).
  void setDynamic(int col, DynamicLevel? d) {
    _ensure(col);
    columns[col] = columns[col].withDynamic(d);
  }

  /// Starts (or clears, when null) a hairpin at the column at [col] (C1).
  void setHairpin(int col, HairpinType? h) {
    _ensure(col);
    columns[col] = columns[col].withHairpin(h);
  }

  /// Sets the repeat barlines of the BAR containing [col] (anchored to that
  /// bar's first column, which is where [toScore] reads them).
  void setBarRepeat(int col, {bool? start, bool? end}) {
    if (columns.isEmpty) return;
    final (first, _) = barBoundsAt(col);
    _ensure(first);
    columns[first] = columns[first].withRepeat(start: start, end: end);
  }

  /// Sets (or clears, when null) the alternate-ending (volta) number of the BAR
  /// containing [col] (anchored to that bar's first column).
  void setBarVolta(int col, int? volta) {
    if (columns.isEmpty) return;
    final (first, _) = barBoundsAt(col);
    _ensure(first);
    columns[first] = columns[first].withVolta(volta);
  }

  /// Sets (or clears, when null) the direction mark of the BAR containing [col].
  void setBarNavigation(int col, NavigationMark? mark) {
    if (columns.isEmpty) return;
    final (first, _) = barBoundsAt(col);
    _ensure(first);
    columns[first] = columns[first].withNavigation(mark);
  }

  /// Sets (or clears, when null) the tempo change (BPM) of the BAR containing
  /// [col] (anchored to that bar's first column, where [toScore] reads it).
  void setBarTempo(int col, double? bpm) {
    if (columns.isEmpty) return;
    final (first, _) = barBoundsAt(col);
    _ensure(first);
    columns[first] = columns[first].withTempo(bpm);
  }

  /// Sets (or clears, when null) the section/rehearsal label on the column at
  /// [col] (it shows above that note).
  void setSection(int col, String? label) {
    _ensure(col);
    columns[col] = columns[col].withSection(label);
  }

  /// Marks the [count] columns starting at [start] as one tuplet of [ratio]
  /// (default a 3:2 triplet). Grows the document if needed.
  void makeTuplet(int start, int count, {(int, int) ratio = (3, 2)}) {
    for (var i = 0; i < count; i++) {
      setTuplet(start + i, ratio);
    }
  }

  /// Sets (or clears, when null) the chord diagram on the column at [col].
  void setChord(int col, ChordDiagram? chord) {
    _ensure(col);
    columns[col] = columns[col].withChord(chord);
  }

  /// Replaces the selected column's frets with the playable strings in
  /// [chord]. Muted strings are omitted; open strings remain at fret 0.
  void setChordVoicing(int col, ChordDiagram? chord) {
    _ensure(col);
    final current = columns[col];
    final frets = <int, int>{};
    if (chord != null) {
      for (var string = 0; string < chord.frets.length; string++) {
        final fret = chord.frets[string];
        if (fret >= 0 && string < tuning.stringCount) frets[string] = fret;
      }
    }
    columns[col] = TabColumn(
      frets: frets,
      duration: current.duration,
      techniques: current.techniques,
      chord: chord,
    );
  }

  /// Inserts an empty column at [col].
  void insertColumn(int col) =>
      columns.insert(col.clamp(0, columns.length), const TabColumn());

  /// Insert a run of ready-made columns (a strum, arpeggio or scale) at [at].
  void insertColumnsAt(int at, List<TabColumn> cols) {
    if (cols.isEmpty) return;
    columns.insertAll(at.clamp(0, columns.length), cols);
  }

  /// The `[start, end)` column range of the ≤8-step (4/4) bar containing [col] —
  /// the same tiling [toScore] uses to lay columns into bars.
  (int, int) barBoundsAt(int col) {
    if (columns.isEmpty) return (0, 0);
    final target = col.clamp(0, columns.length - 1);
    var start = 0;
    var steps = 0.0;
    for (var c = 0; c < columns.length; c++) {
      final s = _scaledStepsOf(columns[c]);
      if (steps > 0 && steps + s > barCapacity + 1e-6) {
        if (target < c) return (start, c); // the bar [start, c) holds `col`
        start = c;
        steps = 0;
      }
      steps += s;
    }
    return (start, columns.length);
  }

  /// Copies the whole bar containing [col] and inserts the copy right after it.
  /// Returns the number of columns added.
  int duplicateBar(int col) {
    final (s, e) = barBoundsAt(col);
    if (e <= s) return 0;
    final copies = [for (var c = s; c < e; c++) columns[c].copy()];
    columns.insertAll(e, copies);
    return copies.length;
  }

  /// Transposes every note by [semitones] by shifting its fret on the SAME
  /// string (so the pitch moves correctly and the fingering shape is kept).
  /// All-or-nothing: returns false and changes nothing if any note would leave
  /// the 0..24 fret range, so nothing is ever silently dropped. Chord labels
  /// (which describe the old shape) are cleared on a successful transpose.
  bool transposeBy(int semitones) {
    if (semitones == 0) return true;
    for (final col in columns) {
      for (final f in col.frets.values) {
        final nf = f + semitones;
        if (nf < 0 || nf > 24) return false;
      }
    }
    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      if (col.frets.isEmpty) continue;
      columns[c] = TabColumn(
        frets: {for (final e in col.frets.entries) e.key: e.value + semitones},
        duration: col.duration,
        techniques: col.techniques,
      );
    }
    return true;
  }

  /// Removes the column at [col] (no-op if out of range or it's the last one).
  void removeColumn(int col) {
    if (columns.length > 1 && col >= 0 && col < columns.length) {
      columns.removeAt(col);
    }
  }

  /// Engraves the document as a [Score] with [TabVoicing]s pinning each note to
  /// its authored strings. Columns tile into ≤8-step (4/4) bars without ever
  /// splitting a note across a barline (so voicing ids stay 1:1 with columns).
  ///
  /// [capo] raises every sounding pitch by that many semitones (a capo clamps
  /// the nut up). Fret numbers stay capo-relative, so the tab staff — which
  /// re-derives frets against the capo-shifted tuning — keeps showing the
  /// authored numbers, while the standard staff and playback sound transposed.
  ///
  /// [program] tags the score with a General-MIDI instrument (D1, a track's
  /// [TabTrack.instrument]) → `Score.metadata.midiProgram`, so an exported MIDI
  /// plays with that voice instead of the default piano.
  Score toScore({int capo = 0, int? program}) {
    final measures = <Measure>[];
    final voicings = <TabVoicing>[];
    // A chord diagram belongs to the note it sits above, exactly as a voicing
    // does — the Score model has a slot for it, and not filling it meant every
    // diagram was dropped the moment a tab became a score.
    final chordDiagrams = <PlacedChordDiagram>[];
    final bends = <Bend>[];
    final tremoloBars = <TremoloBar>[];
    final slideInOuts = <TabSlide>[];
    final taps = <Tap>[];
    final palmMutes = <PalmMute>[];
    final barres = <TabBarre>[];
    final letRings = <LetRing>[];
    final pickStrokes = <PickStroke>[];
    final tabFingerings = <TabFingering>[];
    final dynamics = <DynamicMarking>[];
    final hairpins = <Hairpin>[];
    final marks = <TabNoteMark>[];
    final slurs = <Slur>[];
    final glissandos = <Glissando>[];
    final vibratos = <Vibrato>[];
    final annotations = <Annotation>[];
    var bar = <MusicElement>[];
    var barSteps = 0.0;
    var barFirstCol =
        0; // column index this bar began at (for its repeat flags)
    var barTuplets = <TupletSpan>[];
    // The open tuplet group within the current bar: its bar-relative start index
    // and (actual, normal) ratio.
    int? tupStart;
    (int, int)? tupRatio;

    void closeTuplet(int endExclusive) {
      final s = tupStart;
      final r = tupRatio;
      if (s != null && r != null && endExclusive - 1 >= s) {
        barTuplets.add(
          TupletSpan(s, endExclusive - 1, actual: r.$1, normal: r.$2),
        );
      }
      tupStart = null;
      tupRatio = null;
    }

    // C2 — tile the optional second voice into per-bar element lists (notes /
    // rests / ties / voicings only; techniques on voice 2 are a follow-up) so
    // each measure can carry its `voice2`.
    final v2Bars = <List<MusicElement>>[];
    final v2Voicings = <TabVoicing>[];
    {
      var vb = <MusicElement>[];
      var vSteps = 0.0;
      for (var c = 0; c < voice2.length; c++) {
        final col = voice2[c];
        final s = _scaledStepsOf(col);
        if (vSteps > 0 && vSteps + s > barCapacity + 1e-6) {
          v2Bars.add(vb);
          vb = <MusicElement>[];
          vSteps = 0;
        }
        if (col.isEmpty) {
          vb.add(RestElement(col.duration));
        } else {
          final entries = col.frets.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          final id = 'v$c';
          vb.add(
            NoteElement(
              pitches: [
                for (final e in entries)
                  pitchFromMidi(
                    tuning.strings[e.key].midiNumber + e.value + capo,
                  ),
              ],
              duration: col.duration,
              id: id,
              tieToNext: col.tieToNext,
            ),
          );
          v2Voicings.add(TabVoicing(id, [for (final e in entries) e.key]));
        }
        vSteps += s;
      }
      if (vb.isNotEmpty) v2Bars.add(vb);
    }
    var measIdx = 0;

    void flushBar() {
      closeTuplet(bar.length);
      if (bar.isNotEmpty) {
        final first =
            barFirstCol < columns.length ? columns[barFirstCol] : null;
        measures.add(
          Measure(
            bar,
            voice2: measIdx < v2Bars.length ? v2Bars[measIdx] : const [],
            tuplets: barTuplets,
            startRepeat: first?.startRepeat ?? false,
            endRepeat: first?.endRepeat ?? false,
            volta: first?.volta,
            navigation: first?.navigation,
            tempoChange:
                first?.tempoChange == null ? null : Tempo(first!.tempoChange!),
          ),
        );
        measIdx++;
      }
      bar = <MusicElement>[];
      barSteps = 0;
      barTuplets = <TupletSpan>[];
    }

    // Next noteful column after each index — the legato slur target for hammer.
    int? nextNoteful(int from) {
      for (var i = from + 1; i < columns.length; i++) {
        if (!columns[i].isEmpty) return i;
      }
      return null;
    }

    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      final steps = _scaledStepsOf(col);
      if (barSteps > 0 && barSteps + steps > barCapacity + 1e-6) {
        flushBar();
        barFirstCol = c; // this column opens the new bar
      }
      // Tuplet grouping: adjacent columns of the same ratio form one printed
      // span (bar-relative indices). A change (or a plain note) closes the group.
      final barIdx = bar.length;
      if (col.tuplet != tupRatio) {
        closeTuplet(barIdx);
        if (col.tuplet != null) {
          tupStart = barIdx;
          tupRatio = col.tuplet;
        }
      }
      if (col.isEmpty) {
        bar.add(RestElement(col.duration));
      } else {
        final entries = col.frets.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final pitches = [
          for (final e in entries)
            pitchFromMidi(tuning.strings[e.key].midiNumber + e.value + capo),
        ];
        final id = 't$c';
        bar.add(
          NoteElement(
            pitches: pitches,
            duration: col.duration,
            id: id,
            tieToNext: col.tieToNext,
            articulations: col.articulations,
            ornament: col.ornament, // B7 trill/mordent/turn
            tremolo: col.tremolo, // B7 tremolo picking
            graceNotes: col.graceMidis == null
                ? const []
                : [for (final m in col.graceMidis!) pitchFromMidi(m)],
            graceStyle: col.graceStyle, // B8
            arpeggio: col.arpeggio, // B9 strum roll
            fingerings: col.leftFingers ?? const [], // B10 left hand
            velocity:
                col.dynamic == null ? null : velocityOf(col.dynamic!), // C1
          ),
        );
        voicings.add(TabVoicing(id, [for (final e in entries) e.key]));
        if (col.chord != null) {
          chordDiagrams.add(PlacedChordDiagram(id, col.chord!));
        }
        if (col.section != null) annotations.add(Annotation(id, col.section!));
        // Parametric expressions (B1–B3) — a point list wins over the flat flag.
        if (col.bend != null) bends.add(Bend.curve(id, col.bend!));
        if (col.whammy != null) {
          tremoloBars.add(TremoloBar.curve(id, col.whammy!));
        }
        if (col.slide != null) slideInOuts.add(TabSlide(id, col.slide!));
        // B4/B5/B6/B9/B10 note-scoped marks.
        if (col.tap) taps.add(Tap(id));
        if (col.harmonic != null) marks.add(TabNoteMark(id, col.harmonic!));
        if (col.palmMute) palmMutes.add(PalmMute(id, id)); // self-span
        if (col.barreFret != null) {
          barres.add(
            TabBarre(id, col.barreFret!, lowestString: col.barreString),
          );
        }
        if (col.letRing) letRings.add(LetRing(id, id));
        if (col.pickStroke != null) {
          pickStrokes.add(PickStroke(id, up: col.pickStroke!));
        }
        if (col.rightFinger != null) {
          tabFingerings.add(TabFingering(id, col.rightFinger!));
        }
        if (col.dynamic != null) dynamics.add(DynamicMarking(id, col.dynamic!));
        for (final t in col.techniques) {
          switch (t) {
            case TabTechnique.bend:
              if (col.bend == null) bends.add(Bend(id)); // flat whole-step bend
            case TabTechnique.slide:
              // A slide goes TO the next sounding note — `glissandos` is both
              // what the tab engine draws and what the GPIF writer exports.
              final n = nextNoteful(c);
              if (n != null) glissandos.add(Glissando(id, 't$n'));
            case TabTechnique.vibrato:
              vibratos.add(Vibrato(id));
            case TabTechnique.dead:
              marks.add(TabNoteMark(id, TabNoteStyle.dead));
            case TabTechnique.ghost:
              marks.add(TabNoteMark(id, TabNoteStyle.ghost));
            case TabTechnique.harmonic:
              // A specific harmonic kind (B5) supersedes the flat flag.
              if (col.harmonic == null) {
                marks.add(TabNoteMark(id, TabNoteStyle.harmonic));
              }
            case TabTechnique.hammer:
              final n = nextNoteful(c);
              if (n != null) slurs.add(Slur(id, 't$n'));
          }
        }
      }
      barSteps += steps;
    }
    flushBar();
    // C1 hairpins: a start marker runs to the next noteful column that sets a
    // dynamic (or another hairpin), else to the last noteful column.
    for (var c = 0; c < columns.length; c++) {
      if (columns[c].isEmpty || columns[c].hairpin == null) continue;
      int? end;
      var lastNoteful = -1;
      for (var j = c + 1; j < columns.length; j++) {
        if (columns[j].isEmpty) continue;
        lastNoteful = j;
        if (columns[j].dynamic != null || columns[j].hairpin != null) {
          end = j;
          break;
        }
      }
      end ??= lastNoteful >= 0 ? lastNoteful : null;
      if (end != null) {
        hairpins.add(Hairpin('t$c', 't$end', columns[c].hairpin!));
      }
    }
    if (measures.isEmpty) {
      measures.add(const Measure([RestElement(NoteDuration.whole)]));
    }
    voicings.addAll(v2Voicings); // C2 — voice-2 string pins
    return Score(
      clef: Clef.treble,
      timeSignature: timeSignature,
      keySignature: keySignature,
      measures: measures,
      tabVoicings: voicings,
      chordDiagrams: chordDiagrams,
      bends: bends,
      tremoloBars: tremoloBars,
      slideInOuts: slideInOuts,
      taps: taps,
      palmMutes: palmMutes,
      tabBarres: barres,
      letRings: letRings,
      pickStrokes: pickStrokes,
      tabFingerings: tabFingerings,
      dynamics: dynamics,
      hairpins: hairpins,
      tabNoteMarks: marks,
      slurs: slurs,
      glissandos: glissandos,
      vibratos: vibratos,
      annotations: annotations,
      metadata: program == null
          ? const ScoreMetadata()
          : ScoreMetadata(midiProgram: program),
    );
  }

  /// A percussion [Score] (D3): each fretted string is read as a drum-tab LINE
  /// (via [drumMidiForLine]) rather than a pitched fret, engraved on the neutral
  /// percussion clef and flagged `isPercussion` so export routes it to GM
  /// channel 10. Tiling + rests match [toScore]; the fret value is ignored (a
  /// mark on a line is just a hit).
  Score toDrumScore() {
    final measures = <Measure>[];
    var bar = <MusicElement>[];
    var steps = 0.0;
    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      final s = _scaledStepsOf(col);
      if (steps > 0 && steps + s > barCapacity + 1e-6) {
        measures.add(Measure(bar));
        bar = <MusicElement>[];
        steps = 0;
      }
      if (col.isEmpty) {
        bar.add(RestElement(col.duration));
      } else {
        final lines = col.frets.keys.toList()..sort();
        final notes = [
          for (final line in lines)
            if (drumMidiForLine(line) case final int m) m,
        ];
        if (notes.isEmpty) {
          bar.add(RestElement(col.duration));
        } else {
          bar.add(
            NoteElement(
              pitches: [for (final m in notes) pitchFromMidi(m)],
              duration: col.duration,
              id: 'd$c',
            ),
          );
        }
      }
      steps += s;
    }
    if (bar.isNotEmpty) measures.add(Measure(bar));
    if (measures.isEmpty) {
      measures.add(const Measure([RestElement(NoteDuration.whole)]));
    }
    return Score(
      clef: Clef.percussion,
      timeSignature: timeSignature,
      measures: measures,
      metadata: const ScoreMetadata(instrument: 'Drums', isPercussion: true),
    );
  }

  /// A `(midi pitches, ms)` timeline for `AudioService.playTimedChords`, at
  /// [bpm] (a quarter note = 60000/bpm ms). [capo] raises every pitch by that
  /// many semitones so playback matches a clamped nut (see [toScore]).
  ///
  /// [from]/[to] optionally restrict the timeline to the half-open column range
  /// `[from, to)` (a bar-range practice loop). The tempo in effect at [from] is
  /// pre-rolled from any earlier `tempoChange`, and a tie is clamped to the
  /// range, so a mid-song slice still plays at the right speed and length.
  List<(List<int>, int)> toPlaybackEvents({
    int bpm = 120,
    int capo = 0,
    int from = 0,
    int? to,
  }) {
    // Duration → ms straight from the note fraction (a whole note = 4 beats), so
    // it is exact for every value — a quarter is exactly 60000/bpm, no rounding
    // drift from the 32nd-step grid. A column carrying a `tempoChange` (A9) sets
    // the BPM from that point on, so the ms/step re-times mid-song.
    var curBpm = bpm.toDouble();
    // Written value × wholeMs (at the CURRENT tempo), scaled by a tuplet's
    // normal/actual.
    int ms(TabColumn c) {
      if (c.tempoChange != null) curBpm = c.tempoChange!;
      final wholeMs = 60000 / curBpm * 4;
      final scale = c.tuplet == null ? 1.0 : c.tuplet!.$2 / c.tuplet!.$1;
      return (c.duration.toFraction().toDouble() * wholeMs * scale).round();
    }

    List<int> midis(TabColumn c) => [
          for (final e
              in (c.frets.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            tuning.strings[e.key].midiNumber + e.value + capo,
        ];
    final start0 = from.clamp(0, columns.length);
    final end0 = (to ?? columns.length).clamp(start0, columns.length);
    // Pre-roll the tempo state so a range starting mid-song plays at the tempo
    // that was already in effect there.
    for (var i = 0; i < start0; i++) {
      if (columns[i].tempoChange != null) curBpm = columns[i].tempoChange!;
    }
    final out = <(List<int>, int)>[];
    var c = start0;
    while (c < end0) {
      // A tie sustains one note across columns: emit ONE sound (the attacking
      // column's pitches) whose length is the whole tied chain — the following
      // columns don't re-attack. A tie is clamped to [end0].
      final start = c;
      var dur = ms(columns[c]);
      while (columns[c].tieToNext && c + 1 < end0) {
        c++;
        dur += ms(columns[c]);
      }
      out.add((midis(columns[start]), dur));
      c++;
    }
    return out;
  }

  /// Builds an editable document from an arbitrary [score]. Notes the score
  /// pins to explicit strings (a GP/MusicXML import's [Score.tabVoicings]) keep
  /// that fingering; every other note is placed by the [arrangeTab] Viterbi —
  /// minimising hand movement + chord span, not just lowest-fret-per-note — so
  /// a scale stays in position and chords take a playable voicing. Unreachable
  /// pitches (within the arranger's fret window) are dropped; best effort for
  /// dense polyphony. Behind a [capo] the open pitch rises, so frets shrink.
  static TabDocument fromScore(Score score, Tuning tuning, {int capo = 0}) {
    final voiced = {for (final v in score.tabVoicings) v.noteId: v.strings};
    final diagrams = {
      for (final d in score.chordDiagrams) d.elementId: d.diagram,
    };

    // Read the techniques the notation already carries back onto their source
    // notes, so an imported .gp/MusicXML keeps its bends / slides / vibrato /
    // dead / ghost / harmonic / hammer through the editor. Without this, every
    // technique is silently dropped on the first import→edit→export round-trip
    // (toScore writes them, fromScore never read them back).
    final tech = <String, Set<TabTechnique>>{};
    void mark(String id, TabTechnique t) =>
        (tech[id] ??= <TabTechnique>{}).add(t);
    // Parametric expressions (B1–B3) keyed by note id, read back so an imported
    // bend curve / whammy dive / slide-in-out survives the editor round-trip.
    final bendCurve = <String, List<BendPoint>>{};
    final whammyCurve = <String, List<BendPoint>>{};
    final slideKind = <String, SlideInOut>{};
    for (final b in score.bends) {
      if (b.points.isNotEmpty) {
        bendCurve[b.noteId] = b.points;
      } else {
        mark(b.noteId, TabTechnique.bend); // flat whole-step bend
      }
    }
    for (final t in score.tremoloBars) {
      whammyCurve[t.noteId] = t.points.isNotEmpty
          ? t.points
          : [const BendPoint(0, 0), BendPoint(1, t.steps)];
    }
    for (final s in score.slideInOuts) {
      slideKind[s.noteId] = s.direction;
    }
    for (final g in score.glissandos) {
      mark(g.startId, TabTechnique.slide);
    }
    for (final v in score.vibratos) {
      mark(v.noteId, TabTechnique.vibrato);
    }
    for (final s in score.slurs) {
      mark(s.startId, TabTechnique.hammer);
    }
    // B5 — a harmonic mark keeps its specific kind; dead/ghost stay flat flags.
    final harmonicById = <String, TabNoteStyle>{};
    for (final m in score.tabNoteMarks) {
      switch (m.style) {
        case TabNoteStyle.dead:
          mark(m.noteId, TabTechnique.dead);
        case TabNoteStyle.ghost:
          mark(m.noteId, TabTechnique.ghost);
        default:
          harmonicById[m.noteId] = m.style; // natural/artificial/pinch/…
      }
    }
    // B4 — right-hand taps.
    final tapIds = {for (final t in score.taps) t.noteId};
    // The barre held for a chord (a GP import carries these).
    final barreById = {for (final b in score.tabBarres) b.noteId: b};
    // B9/B10 — pick-stroke + right-hand fingering (score-level, by note id).
    final pickStrokeById = {for (final p in score.pickStrokes) p.noteId: p.up};
    final rightFingerById = {
      for (final f in score.tabFingerings) f.noteId: f.finger,
    };
    // C1 — dynamics by note id + hairpin starts by their start note id.
    final dynamicById = {for (final d in score.dynamics) d.elementId: d.level};
    final hairpinById = {for (final h in score.hairpins) h.startId: h.type};
    // Per-note attributes captured during the element walk below.
    final artById = <String, Set<Articulation>>{}; // B6
    final ornById = <String, Ornament>{}; // B7
    final tremById = <String, int>{}; // B7
    final graceById = <String, (List<int>, GraceStyle)>{}; // B8
    final arpById = <String, Arpeggio>{}; // B9
    final leftFingersById = <String, List<int>>{}; // B10
    final velById = <String, int>{}; // C1 raw note velocity (fallback dynamic)

    final annById = <String, String>{};
    for (final a in score.annotations) {
      annById.putIfAbsent(a.elementId, () => a.text);
    }
    final midiCols = <List<int>>[];
    final durations = <NoteDuration>[];
    final ids = <String?>[]; // per-column source note id (null for a rest)
    final ties = <bool>[]; // per-column: does this note tie into the next?
    final tuplets = <(int, int)?>[]; // per-column tuplet ratio (null = none)
    final startReps = <bool>[]; // per-column: bar opens a repeat
    final endReps = <bool>[]; // per-column: bar closes a repeat
    final voltas = <int?>[]; // per-column: bar volta number
    final navs = <NavigationMark?>[]; // per-column: bar direction mark
    final tempos = <double?>[]; // per-column: bar tempo change (BPM)
    final sections = <String?>[]; // per-column: section/rehearsal label
    final pinned = <int, Fretting>{}; // column index → explicit fingering
    // C2 — second-voice parallel arrays.
    final v2Midis = <List<int>>[];
    final v2Durs = <NoteDuration>[];
    final v2Ties = <bool>[];
    final v2Pinned = <int, Fretting>{};
    var v2idx = 0;
    var idx = 0;
    for (final measure in score.measures) {
      final measureStart =
          idx; // column index of this bar's first voice-1 element
      for (final el in measure.elements) {
        if (el is NoteElement) {
          final midis = [for (final p in el.pitches) p.midiNumber];
          final strings = voiced[el.id];
          if (strings != null && strings.length == midis.length) {
            final frets = <int, int>{};
            for (var i = 0; i < midis.length; i++) {
              final s = strings[i];
              if (s < 0 || s >= tuning.strings.length) continue;
              final fret = midis[i] - tuning.strings[s].midiNumber - capo;
              if (fret >= 0) frets[s] = fret;
            }
            if (frets.isNotEmpty) pinned[idx] = frets;
          }
          final eid = el.id;
          if (eid != null) {
            if (el.articulations.isNotEmpty) artById[eid] = el.articulations;
            if (el.ornament != null) ornById[eid] = el.ornament!;
            if (el.tremolo != null) tremById[eid] = el.tremolo!;
            if (el.graceNotes.isNotEmpty) {
              graceById[eid] = (
                [for (final p in el.graceNotes) p.midiNumber],
                el.graceStyle,
              );
            }
            if (el.arpeggio != null) arpById[eid] = el.arpeggio!;
            if (el.fingerings.isNotEmpty) leftFingersById[eid] = el.fingerings;
            if (el.velocity != null) velById[eid] = el.velocity!;
          }
          midiCols.add(midis);
          durations.add(el.duration);
          ids.add(el.id);
          ties.add(el.tieToNext);
          sections.add(annById[el.id]);
          navs.add(null);
          tempos.add(null);
          tuplets.add(null);
          startReps.add(false);
          endReps.add(false);
          voltas.add(null);
          idx++;
        } else if (el is RestElement) {
          midiCols.add(const []);
          durations.add(el.duration);
          ids.add(null);
          ties.add(false);
          sections.add(null);
          navs.add(null);
          tempos.add(null);
          tuplets.add(null);
          startReps.add(false);
          endReps.add(false);
          voltas.add(null);
          idx++;
        }
      }
      // C2 — collect the second voice (notes / rests / ties + string pins).
      for (final el in measure.voice2) {
        if (el is NoteElement) {
          final midis = [for (final p in el.pitches) p.midiNumber];
          final strings = voiced[el.id];
          if (strings != null && strings.length == midis.length) {
            final frets = <int, int>{};
            for (var i = 0; i < midis.length; i++) {
              final s = strings[i];
              if (s < 0 || s >= tuning.strings.length) continue;
              final fret = midis[i] - tuning.strings[s].midiNumber - capo;
              if (fret >= 0) frets[s] = fret;
            }
            if (frets.isNotEmpty) v2Pinned[v2idx] = frets;
          }
          v2Midis.add(midis);
          v2Durs.add(el.duration);
          v2Ties.add(el.tieToNext);
          v2idx++;
        } else if (el is RestElement) {
          v2Midis.add(const []);
          v2Durs.add(el.duration);
          v2Ties.add(false);
          v2idx++;
        }
      }
      // Stamp this bar's tuplet spans (voice 1) onto their columns.
      for (final t in measure.tuplets) {
        if (t.voice != 0) continue; // voice 0 = elements (voice 1)
        for (var e = t.startIndex; e <= t.endIndex; e++) {
          final gi = measureStart + e;
          if (gi >= 0 && gi < tuplets.length) {
            tuplets[gi] = (t.actual, t.normal);
          }
        }
      }
      if (measure.startRepeat && measureStart < startReps.length) {
        startReps[measureStart] = true;
      }
      if (measure.endRepeat && measureStart < endReps.length) {
        endReps[measureStart] = true;
      }
      if (measure.volta != null && measureStart < voltas.length) {
        voltas[measureStart] = measure.volta;
      }
      if (measure.navigation != null && measureStart < navs.length) {
        navs[measureStart] = measure.navigation;
      }
      if (measure.tempoChange != null && measureStart < tempos.length) {
        tempos[measureStart] = measure.tempoChange!.bpm;
      }
    }
    // C2 — reconstruct the second voice via the same arranger.
    final v2Cols = <TabColumn>[];
    if (v2Midis.isNotEmpty) {
      final v2Arr = arrangeTab(v2Midis, tuning, capo: capo);
      for (var i = 0; i < v2Arr.length; i++) {
        v2Cols.add(
          TabColumn(
            frets: v2Pinned[i] ?? v2Arr[i],
            duration: v2Durs[i],
            tieToNext: v2Ties[i],
          ),
        );
      }
    }
    if (midiCols.isEmpty) {
      return TabDocument(
        tuning: tuning,
        timeSignature: score.timeSignature ?? TimeSignature.fourFour,
        keySignature: score.keySignature,
        columns: [const TabColumn()],
        voice2: v2Cols,
      );
    }
    // B6 — palm-mute / let-ring are id spans; flag every column in each range.
    final idIndex = <String, int>{
      for (var i = 0; i < ids.length; i++)
        if (ids[i] != null) ids[i]!: i,
    };
    Set<int> spanRows(Iterable<(String, String)> spans) {
      final out = <int>{};
      for (final (startId, endId) in spans) {
        final s = idIndex[startId];
        final e = idIndex[endId];
        if (s == null || e == null) continue;
        for (var i = s; i <= e; i++) {
          out.add(i);
        }
      }
      return out;
    }

    final palmMuteRows = spanRows(
      score.palmMutes.map((p) => (p.startId, p.endId)),
    );
    final letRingRows = spanRows(
      score.letRings.map((l) => (l.startId, l.endId)),
    );
    final arranged = arrangeTab(midiCols, tuning, capo: capo);
    return TabDocument(
      tuning: tuning,
      timeSignature: score.timeSignature ?? TimeSignature.fourFour,
      keySignature: score.keySignature,
      voice2: v2Cols,
      columns: [
        for (var i = 0; i < arranged.length; i++)
          TabColumn(
            frets: pinned[i] ?? arranged[i],
            duration: durations[i],
            techniques: {...?tech[ids[i]]},
            tieToNext: ties[i],
            tuplet: tuplets[i],
            startRepeat: startReps[i],
            endRepeat: endReps[i],
            volta: voltas[i],
            navigation: navs[i],
            section: sections[i],
            tempoChange: tempos[i],
            chord: ids[i] == null ? null : diagrams[ids[i]],
            bend: ids[i] == null ? null : bendCurve[ids[i]],
            whammy: ids[i] == null ? null : whammyCurve[ids[i]],
            slide: ids[i] == null ? null : slideKind[ids[i]],
            tap: ids[i] != null && tapIds.contains(ids[i]),
            harmonic: ids[i] == null ? null : harmonicById[ids[i]],
            palmMute: palmMuteRows.contains(i),
            letRing: letRingRows.contains(i),
            articulations:
                ids[i] == null ? const {} : (artById[ids[i]] ?? const {}),
            ornament: ids[i] == null ? null : ornById[ids[i]],
            tremolo: ids[i] == null ? null : tremById[ids[i]],
            graceMidis: ids[i] == null ? null : graceById[ids[i]]?.$1,
            graceStyle: (ids[i] == null ? null : graceById[ids[i]]?.$2) ??
                GraceStyle.acciaccatura,
            arpeggio: ids[i] == null ? null : arpById[ids[i]],
            pickStroke: ids[i] == null ? null : pickStrokeById[ids[i]],
            leftFingers: ids[i] == null ? null : leftFingersById[ids[i]],
            barreFret: ids[i] == null ? null : barreById[ids[i]]?.fret,
            barreString:
                ids[i] == null ? null : barreById[ids[i]]?.lowestString,
            rightFinger: ids[i] == null ? null : rightFingerById[ids[i]],
            dynamic: ids[i] == null
                ? null
                : (dynamicById[ids[i]] ??
                    (velById[ids[i]] != null
                        ? nearestDynamic(velById[ids[i]]!)
                        : null)),
            hairpin: ids[i] == null ? null : hairpinById[ids[i]],
          ),
      ],
    );
  }
}
