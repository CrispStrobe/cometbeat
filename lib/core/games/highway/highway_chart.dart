// lib/core/games/highway/highway_chart.dart
//
// The NOTE HIGHWAY's data model: what falls, when, on which lane.
//
// A [HighwayChart] is deliberately *not* a score and *not* a play-along chart.
// It is the flattened, performance-order, polyphonic thing a falling-note view
// needs: every sounding note as a block with a start, a length, a pitch, a
// voice (hand/part → colour) and an optional caption (the fret number, the
// finger digit, the drum piece). Musical structure — repeats, voltas, tuplets,
// tempo — has already been resolved by `playbackTimeline` before we get here.
//
// Keeping it separate from `PlayAlongChart` is what lets the highway be
// polyphonic: a play-along chart is one melodic line to grade a monophonic
// pitch stream against, while a highway shows a whole piano texture with both
// hands at once. The two coexist — the play-along screen keeps its chart, and
// converts to a highway chart for drawing.
//
// Pure Dart (crisp_notation_core only), so it runs headless and is unit-tested
// in test/highway_chart_test.dart.

import 'package:crisp_notation_core/crisp_notation_core.dart'
    show NoteElement, Score, playbackTimeline;

/// One falling block: a note in musical time on one lane.
class HighwayEvent {
  const HighwayEvent({
    required this.startBeat,
    required this.beats,
    this.midi,
    this.voice = 0,
    this.lane,
    this.caption,
    this.elementId,
  });

  /// Onset in quarter-note beats from the start of the performance.
  final double startBeat;

  /// Sounding length in quarter-note beats. Always > 0 (a very short note is
  /// still drawn as a minimum-height block by the view).
  final double beats;

  /// Sounding pitch, or null for a pure-rhythm event (a drum lane, a pad mode
  /// where only the lane matters).
  final int? midi;

  /// Which hand / part / voice this note belongs to — drives colour, and the
  /// hands-separate filter. 0 = the first (usually right hand / melody).
  final int voice;

  /// Explicit lane index, when the instrument decides the lane rather than the
  /// pitch: the string a fretted note is played on, or the drum piece. Null
  /// means "the lane map works it out from [midi]".
  final int? lane;

  /// Short text drawn on the block — a fret number, a finger digit, a note
  /// name. The view decides whether there is room to draw it.
  final String? caption;

  /// The `crisp_notation` element id this came from, so a staff/tab strip can
  /// highlight the same note the block represents.
  final String? elementId;

  double get endBeat => startBeat + beats;

  HighwayEvent copyWith({
    double? startBeat,
    double? beats,
    int? midi,
    int? voice,
    int? lane,
    String? caption,
    String? elementId,
  }) =>
      HighwayEvent(
        startBeat: startBeat ?? this.startBeat,
        beats: beats ?? this.beats,
        midi: midi ?? this.midi,
        voice: voice ?? this.voice,
        lane: lane ?? this.lane,
        caption: caption ?? this.caption,
        elementId: elementId ?? this.elementId,
      );

  @override
  String toString() => 'HighwayEvent(${midi ?? '-'} @ $startBeat +$beats'
      '${lane == null ? '' : ', lane $lane'}, v$voice)';
}

/// A whole piece as falling blocks, at a fixed tempo.
class HighwayChart {
  const HighwayChart({
    required this.name,
    required this.bpm,
    required this.events,
    this.beatsPerBar = 4,
    this.pickupBeats = 0,
  });

  final String name;

  /// Quarter-note beats per minute.
  final double bpm;

  /// Every block. The score builders emit these in time order, but a chart
  /// authored by hand usually concatenates one voice after another — so
  /// nothing here may ASSUME time order; [columns] sorts defensively.
  final List<HighwayEvent> events;

  /// Quarter-note beats in a bar — the horizontal grid spacing. 4/4 → 4,
  /// 3/4 → 3, 6/8 → 3 (six eighths = three quarters).
  final double beatsPerBar;

  /// Beats of anacrusis before the first full bar, so the bar grid lines up
  /// with the music instead of with the first note.
  final double pickupBeats;

  bool get isEmpty => events.isEmpty;
  bool get isNotEmpty => events.isNotEmpty;

  double get beatMs => 60000.0 / bpm;

  /// ⚠ O(n) — it walks every event. Fine once per run; never call it from a
  /// per-frame path (hoist it), and the performance test asserts as much.
  double get totalBeats {
    var end = 0.0;
    for (final e in events) {
      if (e.endBeat > end) end = e.endBeat;
    }
    return end;
  }

  double get totalMs => totalBeats * beatMs;

  /// The distinct voices present, ascending — how many hands/parts there are.
  List<int> get voices {
    final set = <int>{};
    for (final e in events) {
      set.add(e.voice);
    }
    final list = set.toList()..sort();
    return list;
  }

  int? get lowMidi {
    int? lo;
    for (final e in events) {
      final m = e.midi;
      if (m != null && (lo == null || m < lo)) lo = m;
    }
    return lo;
  }

  int? get highMidi {
    int? hi;
    for (final e in events) {
      final m = e.midi;
      if (m != null && (hi == null || m > hi)) hi = m;
    }
    return hi;
  }

  /// The same music at a different tempo (the slow-down control). Beats are
  /// tempo-independent, so only [bpm] changes.
  HighwayChart atTempo(double newBpm) => HighwayChart(
        name: name,
        bpm: newBpm <= 0 ? bpm : newBpm,
        events: events,
        beatsPerBar: beatsPerBar,
        pickupBeats: pickupBeats,
      );

  /// Only the given voices — "hands separate" practice. Keeps the original
  /// timing, so a filtered chart still lines up with the full backing track.
  HighwayChart onlyVoices(Set<int> keep) => HighwayChart(
        name: name,
        bpm: bpm,
        events: [
          for (final e in events)
            if (keep.contains(e.voice)) e,
        ],
        beatsPerBar: beatsPerBar,
        pickupBeats: pickupBeats,
      );

  /// The events sounding at [beat] (used for key-lighting).
  ///
  /// ⚠ Also O(n). Measured at ~1–2% of a 60 fps frame budget for a 4,000-note
  /// piece, which is why it is still a linear scan: a cursor here would have to
  /// cope with long notes that started far behind the playhead, and that
  /// complexity is not worth 1% of a frame.
  List<HighwayEvent> eventsAt(double beat) => [
        for (final e in events)
          if (e.startBeat <= beat && beat < e.endBeat) e,
      ];

  /// Groups events that start together (within [tolerance] beats) into chords,
  /// in time order — the columns a fretting arranger or a chord grader needs.
  ///
  /// Sorts first: a two-hand chart written as "melody, then accompaniment"
  /// would otherwise produce one set of columns per hand, which silently
  /// wrecks both the fretting arrangement and the backing track.
  List<List<HighwayEvent>> columns({double tolerance = 1e-6}) {
    final ordered = [...events]
      ..sort((a, b) => a.startBeat.compareTo(b.startBeat));
    final out = <List<HighwayEvent>>[];
    for (final e in ordered) {
      if (out.isNotEmpty &&
          (e.startBeat - out.last.first.startBeat).abs() <= tolerance) {
        out.last.add(e);
      } else {
        out.add([e]);
      }
    }
    return out;
  }

  /// Timed `(pitches, ms)` events for [AudioService.playTimedChords] — the
  /// backing track, gap-accurate, with rests as empty chords. Only the voices
  /// in [keep] sound (null = all), so a hands-separate practice run can play
  /// the *other* hand while the learner plays theirs.
  List<(List<int>, int)> timedChords({Set<int>? keep}) {
    final wanted = [
      for (final e in events)
        if (e.midi != null && (keep == null || keep.contains(e.voice))) e,
    ];
    if (wanted.isEmpty) return const [];
    final out = <(List<int>, int)>[];
    var cursor = 0.0;
    for (final column
        in HighwayChart(name: name, bpm: bpm, events: wanted).columns()) {
      final start = column.first.startBeat;
      if (start > cursor + 1e-6) {
        out.add((const <int>[], ((start - cursor) * beatMs).round()));
      }
      // A column sounds until its shortest note ends — the next column then
      // takes over. Good enough for a practice backing, and gap-accurate.
      var length = column.first.beats;
      for (final e in column) {
        if (e.beats < length) length = e.beats;
      }
      out.add(
        ([for (final e in column) e.midi!], (length * beatMs).round()),
      );
      cursor = start + length;
    }
    return out;
  }
}

/// Builds a highway chart from an engraved [score] — every sounding pitch of
/// every chord, in performance order (repeats and navigation expanded by
/// `playbackTimeline`).
///
/// [voice] on each event comes from the score's voice (voice 1 → 0, voice 2 →
/// 1), offset by [voiceOffset] so several parts can be merged into one chart
/// with distinct colours. Grace notes carry no time and are skipped, as they
/// are in playback.
HighwayChart highwayChartFromScore(
  Score score, {
  required String name,
  double? bpmOverride,
  int voiceOffset = 0,
}) {
  final pitchesOf = <String, List<int>>{};
  for (final measure in score.measures) {
    for (final voice in [
      measure.elements,
      measure.voice2,
      measure.voice3,
      measure.voice4,
    ]) {
      for (final element in voice) {
        if (element is NoteElement &&
            element.id != null &&
            element.pitches.isNotEmpty) {
          pitchesOf[element.id!] = [
            for (final p in element.pitches) p.midiNumber,
          ];
        }
      }
    }
  }

  final events = <HighwayEvent>[];
  for (final n in playbackTimeline(score)) {
    if (n.isRest) continue;
    final pitches = pitchesOf[n.elementId];
    if (pitches == null) continue; // grace note / unknown → no block
    final start = n.start.numerator / n.start.denominator * 4;
    final beats = n.duration.numerator / n.duration.denominator * 4;
    if (beats <= 0) continue;
    for (final midi in pitches) {
      events.add(
        HighwayEvent(
          startBeat: start,
          beats: beats,
          midi: midi,
          voice: n.voice + voiceOffset,
          elementId: n.elementId,
        ),
      );
    }
  }
  events.sort((a, b) => a.startBeat.compareTo(b.startBeat));

  final scoreBpm = score.tempo?.quarterBpm ?? 100;
  final bpm = bpmOverride ?? scoreBpm;
  final sig = score.timeSignature;
  return HighwayChart(
    name: name,
    bpm: bpm > 0 ? bpm : 100,
    events: events,
    // A score with no explicit meter is drawn on a 4/4 grid — the grid is a
    // reading aid, so a sensible default beats no bar lines at all.
    beatsPerBar: sig == null ? 4 : sig.beats / sig.beatUnit * 4,
  );
}

/// Merges several [parts] into one chart, one voice per part — a grand staff
/// (right hand = part 0, left hand = part 1) or a small ensemble. Each part
/// keeps its own timing; the tempo and meter come from the first part.
HighwayChart highwayChartFromParts(
  List<Score> parts, {
  required String name,
  double? bpmOverride,
}) {
  if (parts.isEmpty) {
    return HighwayChart(name: name, bpm: bpmOverride ?? 100, events: const []);
  }
  final events = <HighwayEvent>[];
  var voice = 0;
  HighwayChart? first;
  for (final part in parts) {
    final chart = highwayChartFromScore(
      part,
      name: name,
      bpmOverride: bpmOverride,
      voiceOffset: voice,
    );
    first ??= chart;
    events.addAll(chart.events);
    // A part with two written voices consumes two colour slots, so the next
    // part still reads as a separate hand.
    voice += chart.events.isEmpty ? 1 : (chart.voices.last - voice + 1);
  }
  events.sort((a, b) => a.startBeat.compareTo(b.startBeat));
  return HighwayChart(
    name: name,
    bpm: first!.bpm,
    events: events,
    beatsPerBar: first.beatsPerBar,
  );
}

/// A play-along chart as highway blocks — the bridge that lets the play-along
/// screen draw its falling view with the shared [HighwayView] instead of a
/// painter of its own.
///
/// A [PlayAlongChart] is one melodic line (it grades a monophonic pitch
/// stream), so every event lands on voice 0 and carries no lane: the pitch axis
/// IS the position, which is what a singer or a fretless player needs to see.
HighwayChart highwayChartFromTargets(
  List<({double startBeat, double beats, int midi})> notes, {
  required String name,
  required double bpm,
  double beatsPerBar = 4,
}) =>
    HighwayChart(
      name: name,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      events: [
        for (final n in notes)
          HighwayEvent(
            startBeat: n.startBeat,
            beats: n.beats,
            midi: n.midi,
          ),
      ]..sort((a, b) => a.startBeat.compareTo(b.startBeat)),
    );
