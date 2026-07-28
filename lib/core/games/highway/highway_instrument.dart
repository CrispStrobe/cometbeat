// lib/core/games/highway/highway_instrument.dart
//
// INSTRUMENT PROFILES — what makes a piano highway a piano highway.
//
// One profile bundles the four things that differ per instrument and nothing
// else: which lane map the blocks fall on, what caption each block carries
// (nothing / a fret number / a finger digit), which timbre it sounds with, and
// how a bare chart is *prepared* for it (a guitar chart has to be fretted
// before it has lanes at all).
//
// The preparation step is the interesting one. A chart out of a score is pure
// pitch — it does not know that an E4 is played at the 2nd fret of the D
// string or with the 3rd finger in first position. Fretting and fingering are
// real musical decisions with real solvers behind them, and we already own
// both: `arrangeTab` (Viterbi over hand movement + span) for fretted
// instruments, `arrangeBowed` (positions, extensions, string crossings) for
// bowed ones. The profile calls the right one and writes the answer onto each
// block, so the view stays dumb.
//
// Pure Dart, unit-tested in test/highway_instrument_test.dart.

import 'package:comet_beat/core/audio/synth.dart'
    show Instrument, Timbre, timbreFor;
import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';
import 'package:comet_beat/core/notation/bowed_arranger.dart'
    show BowedFingering, BowedInstrument, BowedSkill, arrangeBowed;
import 'package:comet_beat/core/notation/guitar_score_fingering.dart'
    show fingerFrettings;
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, Tuning;

/// The instruments the highway can be played on.
enum HighwayInstrument { piano, guitar, bass, ukulele, cello, pads }

/// What a block says about how to play it.
enum HighwayCaptionStyle {
  /// Nothing — the position on the keyboard is the whole instruction.
  none,

  /// Fret number (fretted instruments).
  fret,

  /// Left-hand finger, `0` = open string (bowed instruments).
  finger,
}

/// Cello strings, top line (highest) first: A3 D3 G2 C2. `Tuning` ships the
/// fretted instruments; the bowed ones live with the code that needs them.
final Tuning kCelloTuning = Tuning(
  [
    Pitch.parse('a3'),
    Pitch.parse('d3'),
    Pitch.parse('g2'),
    Pitch.parse('c2'),
  ],
  name: 'Cello',
);

// The voices. Piano and cello come from the app's shared timbre table; the
// plucked ones are authored here because `synth.dart`'s instrument enum is a
// user-facing SETTING, and a guitar needs a brighter attack and a much faster
// decay than anything in it. Widening that enum for a game detail would put
// "Ukulele" in the app's instrument picker as a side effect.
final Timbre _kPianoTimbre = timbreFor(Instrument.piano);
final Timbre _kCelloTimbre = timbreFor(Instrument.cello);

const Timbre _kGuitarTimbre = Timbre(
  harmonics: [1.0, 0.5, 0.32, 0.18, 0.1, 0.06],
  attackMs: 4,
  decay: 4.2,
);
const Timbre _kBassTimbre = Timbre(
  harmonics: [1.0, 0.62, 0.2, 0.08],
  attackMs: 10,
  decay: 2.6,
);
const Timbre _kUkuleleTimbre = Timbre(
  harmonics: [1.0, 0.42, 0.4, 0.16, 0.12],
  attackMs: 3,
  decay: 6.5,
);
const Timbre _kPadTimbre = Timbre(
  harmonics: [1.0, 0.25, 0.5, 0.12, 0.3],
  attackMs: 2,
  decay: 5.5,
);

/// Everything the highway needs to know about one instrument.
class HighwayInstrumentProfile {
  const HighwayInstrumentProfile({
    required this.instrument,
    required this.timbre,
    required this.captionStyle,
    this.tuning,
    this.capo = 0,
    this.maxFret = 12,
  });

  final HighwayInstrument instrument;
  final Timbre timbre;
  final HighwayCaptionStyle captionStyle;

  /// Open strings, for the string-lane instruments. Null for piano/pads.
  final Tuning? tuning;

  final int capo;
  final int maxFret;

  bool get isStringed => tuning != null;

  static HighwayInstrumentProfile of(HighwayInstrument instrument) =>
      switch (instrument) {
        HighwayInstrument.piano => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kPianoTimbre,
            captionStyle: HighwayCaptionStyle.none,
          ),
        HighwayInstrument.guitar => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kGuitarTimbre,
            captionStyle: HighwayCaptionStyle.fret,
            tuning: Tuning.standardGuitar,
          ),
        HighwayInstrument.bass => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kBassTimbre,
            captionStyle: HighwayCaptionStyle.fret,
            tuning: Tuning.standardBass,
          ),
        HighwayInstrument.ukulele => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kUkuleleTimbre,
            captionStyle: HighwayCaptionStyle.fret,
            tuning: Tuning.ukulele,
          ),
        HighwayInstrument.cello => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kCelloTimbre,
            captionStyle: HighwayCaptionStyle.finger,
            tuning: kCelloTuning,
          ),
        HighwayInstrument.pads => HighwayInstrumentProfile(
            instrument: instrument,
            timbre: _kPadTimbre,
            captionStyle: HighwayCaptionStyle.none,
          ),
      };

  /// The lane map for [chart] on this instrument.
  HighwayLaneMap laneMapFor(HighwayChart chart, {int padLanes = 4}) {
    switch (instrument) {
      case HighwayInstrument.piano:
        return KeyboardLaneMap.forRange(
          chart.lowMidi ?? 60,
          chart.highMidi ?? 72,
        );
      case HighwayInstrument.guitar:
      case HighwayInstrument.bass:
      case HighwayInstrument.ukulele:
      case HighwayInstrument.cello:
        return StringLaneMap(tuning!);
      case HighwayInstrument.pads:
        return PadLaneMap.forChart(chart, laneCount: padLanes);
    }
  }

  /// Fills in [HighwayEvent.lane] and [HighwayEvent.caption] for this
  /// instrument. Piano and pads need nothing; the string instruments get a
  /// solved playing position per note.
  ///
  /// Notes the solver cannot place (out of the instrument's range) keep their
  /// pitch but get no lane — the lane map then drops them rather than putting
  /// a block somewhere a player could not reach.
  HighwayChart prepare(HighwayChart chart) {
    if (chart.isEmpty) return chart;
    return switch (instrument) {
      HighwayInstrument.piano || HighwayInstrument.pads => chart,
      HighwayInstrument.cello => _prepareBowed(chart),
      _ => _prepareFretted(chart),
    };
  }

  HighwayChart _prepareFretted(HighwayChart chart) {
    final columns = chart.columns();
    final pitches = [
      for (final col in columns)
        [
          for (final e in col)
            if (e.midi != null) e.midi!,
        ],
    ];
    final shapes = arrangeTab(
      pitches,
      tuning!,
      capo: capo,
      maxFret: maxFret,
    );
    final fingers = fingerFrettings(shapes);

    final out = <HighwayEvent>[];
    for (var c = 0; c < columns.length; c++) {
      final shape = c < shapes.length ? shapes[c] : const <int, int>{};
      // `fingerFrettings` orders its digits by DESCENDING string index (= rising
      // pitch), so rebuild that order to pair a digit with its string.
      final byString = shape.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));
      final digits = c < fingers.length ? fingers[c] : const <int>[];
      final fingerOfString = <int, int>{
        for (var i = 0; i < byString.length && i < digits.length; i++)
          byString[i].key: digits[i],
      };

      for (final event in columns[c]) {
        final midi = event.midi;
        if (midi == null) {
          out.add(event);
          continue;
        }
        int? string;
        int? fret;
        for (final entry in shape.entries) {
          final open = tuning!.strings[entry.key].midiNumber;
          if (open + capo + entry.value == midi) {
            string = entry.key;
            fret = entry.value;
            break;
          }
        }
        if (string == null || fret == null) {
          out.add(event); // unreachable on this instrument — no lane
          continue;
        }
        final finger = fingerOfString[string];
        out.add(
          event.copyWith(
            lane: string,
            caption: captionStyle == HighwayCaptionStyle.finger
                ? '${finger ?? 0}'
                : '$fret',
          ),
        );
      }
    }
    out.sort((a, b) => a.startBeat.compareTo(b.startBeat));
    return HighwayChart(
      name: chart.name,
      bpm: chart.bpm,
      events: out,
      beatsPerBar: chart.beatsPerBar,
      pickupBeats: chart.pickupBeats,
    );
  }

  HighwayChart _prepareBowed(HighwayChart chart) {
    final columns = chart.columns();
    final pitches = [
      for (final col in columns)
        [
          for (final e in col)
            if (e.midi != null) e.midi!,
        ],
    ];
    final arrangement = arrangeBowed(
      pitches,
      skill: BowedSkill.neckPositions,
      instrument: BowedInstrument.cello,
    );

    final out = <HighwayEvent>[];
    for (var c = 0; c < columns.length; c++) {
      final placed = c < arrangement.columns.length
          ? arrangement.columns[c]
          : const <BowedFingering>[];
      for (final event in columns[c]) {
        final midi = event.midi;
        if (midi == null) {
          out.add(event);
          continue;
        }
        // Match by sounding pitch: open string + semitones above the nut.
        var matched = false;
        for (final f in placed) {
          final open = tuning!.strings[f.string].midiNumber;
          if (open + f.semitones == midi) {
            out.add(event.copyWith(lane: f.string, caption: '${f.finger}'));
            matched = true;
            break;
          }
        }
        if (!matched) out.add(event);
      }
    }
    out.sort((a, b) => a.startBeat.compareTo(b.startBeat));
    return HighwayChart(
      name: chart.name,
      bpm: chart.bpm,
      events: out,
      beatsPerBar: chart.beatsPerBar,
      pickupBeats: chart.pickupBeats,
    );
  }
}
