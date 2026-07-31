// lib/core/harmony/chart_playback.dart
//
// BB-U1 support — turn a `Chart` into something the app can actually SOUND,
// and into the bar timeline the screen highlights against.
//
// WHY NOT `chart_to_groove.dart`. That projects a chart onto the shipped groove
// engine, whose whole vocabulary is six diatonic triads over four bars. It is a
// deliberate, documented reduction and it stays useful for the styled band. But
// a chart screen has to play what the user typed: `Bb7`, `F#m7b5`, `Ebmaj9/G`,
// thirty-two bars of it. So this path skips the groove engine and renders the
// chords directly through `AudioService.playMixedTimedChords`, which takes
// arbitrary MIDI. Nothing here is limited to a key or a chord vocabulary.
//
// WHAT IT DOES NOT DO. There is no comping RHYTHM here — that is the style model
// (BB-A2) and inventing one would be inventing music the chart does not specify.
// The one rhythmic decision taken is stated below at `_barEvents`, because it is
// a decision and not a law.
library;

import 'package:comet_beat/core/harmony/chart.dart';
import 'package:comet_beat/core/harmony/chord_spec.dart';
import 'package:comet_beat/core/harmony/comp_arranger.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show Pitch, TimeSignature;

/// One sounding chord: absolute MIDI notes and how long they last.
typedef TimedChord = (List<int> midis, int ms);

/// Where one bar sits on the timeline, so the view can follow the transport.
class ChartBarSpan {
  const ChartBarSpan({
    required this.index,
    required this.startMs,
    required this.durationMs,
    required this.sectionIndex,
    required this.pass,
  });

  /// Index into [Chart.barsInPlayOrder].
  final int index;
  final int startMs;
  final int durationMs;

  /// Which section this bar came from, and which repeat pass of it — the two
  /// facts a "you are here" highlight needs that a flat bar index cannot give.
  final int sectionIndex;
  final int pass;

  int get endMs => startMs + durationMs;
}

/// A chart resolved to sound plus a timeline.
class ChartPlayback {
  const ChartPlayback({
    required this.comp,
    required this.bass,
    required this.bars,
    required this.beatMs,
    required this.totalMs,
  });

  /// The chord part, one entry per sounding segment.
  final List<TimedChord> comp;

  /// The bass part, index-aligned in TIME with [comp] (not in length).
  final List<TimedChord> bass;

  /// One span per bar of [Chart.barsInPlayOrder].
  final List<ChartBarSpan> bars;

  /// Milliseconds per quarter-note beat, for a metronome click.
  final int beatMs;

  final int totalMs;

  bool get isEmpty => comp.isEmpty && bass.isEmpty;

  /// The bar sounding at [ms], or null past the end. Linear because a chart is
  /// tens of bars, not thousands.
  ChartBarSpan? barAt(int ms) {
    for (final bar in bars) {
      if (ms >= bar.startMs && ms < bar.endMs) return bar;
    }
    return null;
  }
}

/// Quarter-note beats in one bar of [meter].
///
/// Expressed in QUARTERS rather than in the meter's own beat unit because tempo
/// is quarter-note BPM throughout the app, so 6/8 at 120 has to come out as
/// three quarters, not six eighths at the same clock.
double barBeats(TimeSignature meter) => meter.beats * 4 / meter.beatUnit;

/// Resolves [chart] to sounding parts and a bar timeline.
///
/// [compOctave] places the chord voicings; [bassOctave] the bass note.
ChartPlayback resolveChartPlayback(
  Chart chart, {
  int compOctave = 4,
  int bassOctave = 2,
  VoicingConstraints constraints = VoicingConstraints.piano,
}) {
  final bars = chart.barsInPlayOrder;
  final bpm = chart.tempoBpm < 1 ? 1 : chart.tempoBpm;
  final beatMs = (60000 / bpm).round();

  if (bars.isEmpty) {
    return ChartPlayback(
      comp: const [],
      bass: const [],
      bars: const [],
      beatMs: beatMs,
      totalMs: 0,
    );
  }

  // Which section (and repeat pass) each played bar came from. Rebuilt by the
  // same nesting `barsInPlayOrder` uses, so the two cannot disagree about what
  // bar 17 is — the model's own warning about two separate expansions.
  final origin = <(int section, int pass)>[];
  for (var s = 0; s < chart.sections.length; s++) {
    final section = chart.sections[s];
    for (var pass = 0; pass < section.passes; pass++) {
      for (var b = 0; b < section.bars.length; b++) {
        origin.add((s, pass));
      }
    }
  }

  // Pass 1 — segment the chart into (chord, duration) slots, carrying the last
  // sounding chord across empty bars.
  final slots = <({ChordSpec chord, int ms})>[];
  final spans = <ChartBarSpan>[];
  var cursorMs = 0;
  ChordSpec? held;

  for (var i = 0; i < bars.length; i++) {
    final bar = bars[i];
    final meter = bar.meterChange ?? chart.meter;
    final beats = barBeats(meter);
    final barMs = (beats * beatMs).round();

    spans.add(
      ChartBarSpan(
        index: i,
        startMs: cursorMs,
        durationMs: barMs,
        sectionIndex: origin[i].$1,
        pass: origin[i].$2,
      ),
    );

    slots.addAll(_barEvents(bar, beatMs, barMs, held));
    final last =
        bar.chordsInOrder.isEmpty ? null : bar.chordsInOrder.last.chord;
    if (last != null) held = last;

    cursorMs += barMs;
  }

  // Pass 2 — voice the whole chart at once, so voice leading is chosen across
  // the piece rather than bar by bar. `arrangeComp` is a Viterbi over the chord
  // sequence; feeding it one chord at a time would throw that away entirely.
  final voicings = arrangeComp(
    [for (final slot in slots) slot.chord],
    constraints: constraints,
  );

  final comp = <TimedChord>[];
  final bass = <TimedChord>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    final voicing = i < voicings.length ? voicings[i] : null;
    final midis = voicing == null
        ? _fallbackVoicing(slot.chord, compOctave)
        : _transposeInto(voicing.midis, compOctave);
    comp.add((midis, slot.ms));
    bass.add(([_bassMidi(slot.chord, bassOctave)], slot.ms));
  }

  return ChartPlayback(
    comp: comp,
    bass: bass,
    bars: spans,
    beatMs: beatMs,
    totalMs: cursorMs,
  );
}

/// The sounding slots for one bar.
///
/// ⚠️ **The one rhythmic decision in this file.** An empty bar means "the chord
/// continues" (`| C | % | % | %`), which strictly is a single four-bar sound.
/// It is re-struck on each bar's downbeat instead, because the app's voices
/// decay in about a second, so a literal reading would leave three of those four
/// bars silent — a play-along nobody can play along to. One hit per bar is the
/// most conventional rhythm that exists and it invents no syncopation; anything
/// richer belongs to the style model (BB-A2).
List<({ChordSpec chord, int ms})> _barEvents(
  ChartBar bar,
  int beatMs,
  int barMs,
  ChordSpec? held,
) {
  final chords = bar.chordsInOrder;
  if (chords.isEmpty) {
    return held == null ? const [] : [(chord: held, ms: barMs)];
  }

  final out = <({ChordSpec chord, int ms})>[];

  // A chord that does not start on beat 0 leaves a gap; the previous chord
  // holds through it rather than the bar starting silent.
  final firstBeat = chords.first.beat;
  if (firstBeat > 0 && held != null) {
    out.add((chord: held, ms: (firstBeat * beatMs).round()));
  }

  for (var i = 0; i < chords.length; i++) {
    final chord = chords[i];
    // ⚠️ `ChartBeatChord.beats` is deliberately NOT used as the sounding length.
    // Its default is 1, and the codec omits the field when it equals 1, so an
    // explicit "one beat" is indistinguishable from "unspecified". Honouring it
    // would make the commonest bar in any chart — `| C |`, one chord at beat 0
    // — play for one beat and rest for three.
    //
    // A chord therefore sounds until the NEXT chord, or the end of the bar,
    // which is what chart notation means. The cost is that a deliberate stab
    // followed by silence cannot be expressed; beat OFFSETS still express every
    // split bar (`| C . G . |`), which is what charts actually use.
    final startMs = (chord.beat * beatMs).round();
    final endMs =
        i + 1 < chords.length ? (chords[i + 1].beat * beatMs).round() : barMs;
    // Clamped against the bar's own end so rounding can never let the slots
    // overrun the bar and drift the timeline away from the highlight.
    final ms = (endMs - startMs).clamp(1, barMs);
    out.add((chord: chord.chord, ms: ms));
  }
  return out;
}

/// Moves a voicing so its lowest note sits in [octave], preserving the shape.
///
/// `arrangeComp` chooses register for voice leading, which is right for a comp
/// but can drift; this keeps the chart audible in a fixed range without
/// disturbing the intervals the arranger picked.
List<int> _transposeInto(List<int> midis, int octave) {
  if (midis.isEmpty) return const [];
  final target = (octave + 1) * 12; // MIDI 60 == C4
  final shift = ((target - midis.first) / 12).round() * 12;
  return [for (final m in midis) (m + shift).clamp(0, 127)];
}

/// Root position from the spec itself, for the (unexpected) case where the
/// arranger returns fewer voicings than there are slots. Silence would be a
/// worse answer than a plain stack.
List<int> _fallbackVoicing(ChordSpec chord, int octave) {
  final root = _pitchClass(chord.root) + (octave + 1) * 12;
  return [
    for (final interval in chord.intervals)
      if (root + interval <= 127) root + interval,
  ];
}

int _bassMidi(ChordSpec chord, int octave) {
  final pc = _pitchClass(chord.bass ?? chord.root);
  return (pc + (octave + 1) * 12).clamp(0, 127);
}

int _pitchClass(Pitch pitch) {
  // `midiNumber` already folds step/alter/octave; only the class matters here,
  // since the octave is the caller's choice.
  return ((pitch.midiNumber % 12) + 12) % 12;
}
