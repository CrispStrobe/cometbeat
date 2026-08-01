// lib/core/harmony/form_realizer.dart
//
// BB-A5 — chart + repeats + form → the flat bar timeline everything renders
// from.
//
// THE ONE ANSWER TO "WHAT SOUNDS AT BAR 17". `Chart.barsInPlayOrder` already
// warns that two separate expansions are two answers; this is the same rule one
// level up, now that intro bars, chorus counts and an ending can shift every
// index. Bass, drums, comp and the playhead all read this list, so they cannot
// disagree about where they are.
//
// It also carries the facts a generator cannot work out for itself: whether a
// bar ends a phrase (a fill goes there), whether it ends a section, which
// chorus it belongs to, and what intensity is in force.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show TimeSignature;

/// What a realised bar is FOR, which decides what plays over it.
enum BarRole {
  /// Counted in, not played over.
  countIn,

  /// The chart proper.
  tune,

  /// The final bar: a hold, not a groove that stops.
  ending,
}

/// One bar of the piece as it will actually be played.
class RealizedBar {
  const RealizedBar({
    required this.index,
    required this.chords,
    required this.meter,
    required this.intensity,
    required this.sectionLabel,
    required this.chorusIndex,
    this.role = BarRole.tune,
    this.isPhraseEnd = false,
    this.isSectionEnd = false,
    this.isLastBar = false,
    this.sourceBar,
  });

  /// Position in the realised timeline, count-in included.
  final int index;

  final List<ChartBeatChord> chords;
  final TimeSignature meter;

  /// 0..3, already resolved from the section and the chorus.
  final int intensity;

  final String sectionLabel;

  /// Which pass through the whole form this is, from 0.
  final int chorusIndex;

  final BarRole role;
  final bool isPhraseEnd;
  final bool isSectionEnd;
  final bool isLastBar;

  /// The document bar this came from, or null for a generated bar (count-in,
  /// ending). What lets the UI highlight the bar the user is looking at.
  final ({int section, int bar})? sourceBar;

  bool get isEmpty => chords.isEmpty;
}

/// How a chart should be played out.
class FormOptions {
  const FormOptions({
    this.choruses = 1,
    this.countIn = true,
    this.ending = true,
    this.baseIntensity = 2,
    this.liftLastChorus = true,
    this.phraseLength = 4,
    this.seed = 0,
  });

  /// How many times through the whole form.
  final int choruses;

  final bool countIn;

  /// Append a final held bar. A backing track that simply stops mid-phrase
  /// sounds like a dropped connection.
  final bool ending;

  /// Intensity when nothing else says otherwise.
  final int baseIntensity;

  /// The last chorus lifts one level. This is what the intensity axis exists
  /// for — see `style_spec.dart`.
  final bool liftLastChorus;

  /// Bars per phrase, for fill placement. Four is the near-universal default;
  /// a 12-bar blues still phrases in fours.
  final int phraseLength;

  final int seed;
}

/// Expands [chart] into the timeline the band plays.
List<RealizedBar> realizeForm(
  Chart chart, {
  FormOptions options = const FormOptions(),
}) {
  final out = <RealizedBar>[];
  final choruses = options.choruses < 1 ? 1 : options.choruses;

  if (chart.isEmpty) return out;

  var index = 0;

  if (options.countIn) {
    out.add(
      RealizedBar(
        index: index++,
        chords: const [],
        meter: chart.meter,
        intensity: 0,
        sectionLabel: '',
        chorusIndex: 0,
        role: BarRole.countIn,
      ),
    );
  }

  for (var chorus = 0; chorus < choruses; chorus++) {
    // The lift applies only when there is more than one chorus — otherwise a
    // single pass would always play at the raised level, which is not "the last
    // chorus lifts", it is just louder.
    final isLast = chorus == choruses - 1;
    final lift = options.liftLastChorus && isLast && choruses > 1 ? 1 : 0;

    // Bar position WITHIN this chorus, so phrases restart each time through
    // rather than drifting against the form.
    var barInChorus = 0;

    for (var s = 0; s < chart.sections.length; s++) {
      final section = chart.sections[s];
      final sectionIntensity = section.intensity == null
          ? options.baseIntensity
          : (section.intensity! * 3).round();

      for (var pass = 0; pass < section.passes; pass++) {
        for (var b = 0; b < section.bars.length; b++) {
          final bar = section.bars[b];
          final isSectionEnd =
              b == section.bars.length - 1 && pass == section.passes - 1;

          out.add(
            RealizedBar(
              index: index++,
              chords: bar.chordsInOrder,
              meter: bar.meterChange ?? chart.meter,
              intensity: (sectionIntensity + lift).clamp(0, 3),
              sectionLabel: section.label,
              chorusIndex: chorus,
              // A phrase end is counted from the start of the CHORUS. A fill
              // every four bars regardless of where the form began would land
              // mid-phrase on any chart whose sections are not multiples of
              // four — a 12-bar blues over 3 choruses being the obvious case.
              isPhraseEnd:
                  (barInChorus + 1) % options.phraseLength == 0 || isSectionEnd,
              isSectionEnd: isSectionEnd,
              sourceBar: (section: s, bar: b),
            ),
          );
          barInChorus++;
        }
      }
    }
  }

  if (options.ending && out.isNotEmpty) {
    final lastTune =
        out.lastWhere((b) => b.role == BarRole.tune, orElse: () => out.last);
    out.add(
      RealizedBar(
        index: index++,
        // The ending holds the LAST chord of the tune rather than inventing
        // one, so it resolves where the chart said it would.
        chords: lastTune.chords.isEmpty ? const [] : [lastTune.chords.last],
        meter: lastTune.meter,
        intensity: options.baseIntensity.clamp(0, 3),
        sectionLabel: lastTune.sectionLabel,
        chorusIndex: choruses - 1,
        role: BarRole.ending,
      ),
    );
  }

  // `isLastBar` is a property of the finished timeline, not of any one bar, so
  // it is stamped once at the end rather than guessed while building.
  if (out.isNotEmpty) {
    final last = out.last;
    out[out.length - 1] = RealizedBar(
      index: last.index,
      chords: last.chords,
      meter: last.meter,
      intensity: last.intensity,
      sectionLabel: last.sectionLabel,
      chorusIndex: last.chorusIndex,
      role: last.role,
      isPhraseEnd: last.isPhraseEnd,
      isSectionEnd: last.isSectionEnd,
      isLastBar: true,
      sourceBar: last.sourceBar,
    );
  }
  return out;
}

/// The chord sounding at the START of [bar], for a generator that needs to know
/// what it is approaching. Null when the bar is empty and nothing precedes it.
ChordSpec? chordAt(List<RealizedBar> bars, int index) {
  for (var i = index; i >= 0; i--) {
    if (i < bars.length && bars[i].chords.isNotEmpty) {
      return bars[i].chords.first.chord;
    }
  }
  return null;
}

/// The chord the bar at [index] is walking INTO — the first chord of the next
/// bar that has one. Null at the end of the piece.
ChordSpec? nextChordAfter(List<RealizedBar> bars, int index) {
  for (var i = index + 1; i < bars.length; i++) {
    if (bars[i].chords.isNotEmpty) return bars[i].chords.first.chord;
  }
  return null;
}
