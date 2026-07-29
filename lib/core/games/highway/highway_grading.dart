// lib/core/games/highway/highway_grading.dart
//
// DIFFICULTY and GRADING for the note highway.
//
// Two things live here, and they are deliberately the same file because they
// are the same decision seen twice: a difficulty is a *set of tolerances*, and
// the grader is what those tolerances mean in practice.
//
// The grading is polyphonic — a chord is not one target but several, each
// answered separately — which is the difference between a play-along (grade a
// melodic line against a monophonic pitch stream) and a highway (grade a whole
// texture against taps). Every note is judged once and only once: a tap claims
// the nearest un-answered note it matches inside the window, so hammering the
// rail cannot farm points from one note.
//
// Pure Dart, unit-tested in test/highway_grading_test.dart.

import 'package:comet_beat/core/games/highway/highway_chart.dart';
import 'package:comet_beat/core/games/highway/highway_lanes.dart';

/// How forgiving a run is. Independent of tempo — every window is in beats, so
/// slowing a piece down does not secretly make the timing easier.
enum HighwayDifficulty { relaxed, easy, medium, hard, expert }

/// The tolerances and scaffolds a difficulty stands for.
class HighwayRules {
  const HighwayRules({
    required this.difficulty,
    required this.hitWindowBeats,
    required this.perfectWindowBeats,
    required this.leadBeats,
    required this.waitForMe,
    required this.showNoteNames,
    required this.showCaptions,
    required this.showBeatGrid,
  });

  final HighwayDifficulty difficulty;

  /// A tap counts for a note if it lands within ± this many beats of its onset.
  final double hitWindowBeats;

  /// Inside this tighter window the hit is "perfect" and scores more.
  final double perfectWindowBeats;

  /// How much music is visible above the hit line. Less lead = less warning =
  /// harder, and it is what makes the higher tiers feel fast without the
  /// tempo changing.
  final double leadBeats;

  /// Hold the clock at a note until it is played — the beginner's mode, and
  /// the single most effective scaffold there is: it converts a rhythm task
  /// into a "find the right key" task until the hands know the way.
  final bool waitForMe;

  /// Letter names on the blocks.
  final bool showNoteNames;

  /// Instrument captions on the blocks (fret numbers, finger digits).
  final bool showCaptions;

  /// Horizontal beat rules, not just bar rules.
  final bool showBeatGrid;

  static const Map<HighwayDifficulty, HighwayRules> _presets = {
    // Nothing can go wrong: the clock waits, the window is a whole beat wide,
    // and every scaffold is on.
    HighwayDifficulty.relaxed: HighwayRules(
      difficulty: HighwayDifficulty.relaxed,
      hitWindowBeats: 1.0,
      perfectWindowBeats: 0.5,
      leadBeats: 8,
      waitForMe: true,
      showNoteNames: true,
      showCaptions: true,
      showBeatGrid: true,
    ),
    HighwayDifficulty.easy: HighwayRules(
      difficulty: HighwayDifficulty.easy,
      hitWindowBeats: 0.6,
      perfectWindowBeats: 0.28,
      leadBeats: 7,
      waitForMe: false,
      showNoteNames: true,
      showCaptions: true,
      showBeatGrid: true,
    ),
    HighwayDifficulty.medium: HighwayRules(
      difficulty: HighwayDifficulty.medium,
      hitWindowBeats: 0.38,
      perfectWindowBeats: 0.16,
      leadBeats: 6,
      waitForMe: false,
      showNoteNames: false,
      showCaptions: true,
      showBeatGrid: true,
    ),
    HighwayDifficulty.hard: HighwayRules(
      difficulty: HighwayDifficulty.hard,
      hitWindowBeats: 0.24,
      perfectWindowBeats: 0.1,
      leadBeats: 4.5,
      waitForMe: false,
      showNoteNames: false,
      showCaptions: true,
      showBeatGrid: false,
    ),
    // No scaffolds at all: you read the lane, not the label.
    HighwayDifficulty.expert: HighwayRules(
      difficulty: HighwayDifficulty.expert,
      hitWindowBeats: 0.15,
      perfectWindowBeats: 0.06,
      leadBeats: 3.5,
      waitForMe: false,
      showNoteNames: false,
      showCaptions: false,
      showBeatGrid: false,
    ),
  };

  static HighwayRules of(HighwayDifficulty difficulty) => _presets[difficulty]!;

  HighwayRules copyWith({
    bool? waitForMe,
    bool? showNoteNames,
    bool? showCaptions,
    double? leadBeats,
  }) =>
      HighwayRules(
        difficulty: difficulty,
        hitWindowBeats: hitWindowBeats,
        perfectWindowBeats: perfectWindowBeats,
        leadBeats: leadBeats ?? this.leadBeats,
        waitForMe: waitForMe ?? this.waitForMe,
        showNoteNames: showNoteNames ?? this.showNoteNames,
        showCaptions: showCaptions ?? this.showCaptions,
        showBeatGrid: showBeatGrid,
      );
}

/// What happened to one target note.
enum HighwayNoteState { pending, hit, missed }

/// How well a hit was timed — the feedback the player actually reads.
enum HighwayHitQuality { perfect, good, late, early }

/// Mutable per-note state.
class HighwayNote {
  HighwayNote(this.event);

  final HighwayEvent event;
  HighwayNoteState state = HighwayNoteState.pending;

  /// Beats between the tap and the onset (negative = early). Null until hit.
  double? timingError;
  HighwayHitQuality? quality;

  bool get isPending => state == HighwayNoteState.pending;
}

/// The result of one tap.
class HighwayTapResult {
  const HighwayTapResult({required this.note, required this.quality});

  /// Null when the tap matched nothing — a wrong key, or nothing was due.
  final HighwayNote? note;
  final HighwayHitQuality? quality;

  bool get isHit => note != null;
}

/// Grades taps against a chart. Feed it the current beat every frame and a
/// [tap] whenever the player hits the rail.
class HighwayGrader {
  HighwayGrader({
    required this.chart,
    required this.rules,
    required this.laneMap,
    this.gradedVoices,
  }) : notes = [for (final e in chart.events) HighwayNote(e)] {
    // Both working lists are kept in TIME order, and each carries a cursor, so
    // the per-frame work is proportional to what is live rather than to the
    // length of the piece. Without this a four-minute song pays for every note
    // it has already played, on every frame and on every tap. (A chart written
    // one voice after another is not in time order — see HighwayChart.events.)
    _graded = [
      for (final n in notes)
        if (isGraded(n.event)) n,
    ]..sort((a, b) => a.event.startBeat.compareTo(b.event.startBeat));
    _auto = [
      for (final n in notes)
        if (!isGraded(n.event)) n,
    ]..sort((a, b) => a.event.startBeat.compareTo(b.event.startBeat));
  }

  final HighwayChart chart;
  final HighwayRules rules;
  final HighwayLaneMap laneMap;
  final List<HighwayNote> notes;

  /// Which voices the PLAYER is responsible for. Null = all of them. An empty
  /// set = none, which is watch mode: every note plays itself and nothing is
  /// scored. Anything else is hands-separate practice — the other hand's notes
  /// still fall (you need to see them to fit in with them) but they light up on
  /// their own and never count against you.
  final Set<int>? gradedVoices;

  late final List<HighwayNote> _graded;
  late final List<HighwayNote> _auto;

  /// Everything before this index in [_graded] is answered, so no scan needs to
  /// look at it again.
  int _cursor = 0;

  /// Everything before this index in [_auto] has already played itself.
  int _autoCursor = 0;

  bool isGraded(HighwayEvent event) =>
      gradedVoices == null || gradedVoices!.contains(event.voice);

  double _beat = 0;
  int _hits = 0;
  int _misses = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _score = 0;

  double get beat => _beat;
  int get hits => _hits;
  int get misses => _misses;
  int get streak => _streak;
  int get bestStreak => _bestStreak;
  int get score => _score;
  int get total => _graded.length;
  int get answered => _hits + _misses;
  bool get finished => answered >= total;

  /// Fraction of judged notes that were hit (0 when nothing is judged yet).
  double get accuracy => answered == 0 ? 0 : _hits / answered;

  /// The streak multiplier a hit is currently worth (1×…4×) — the thing that
  /// makes a clean run feel different from a scrappy one.
  int get multiplier => 1 + (_streak ~/ 8).clamp(0, 3);

  /// Advances the clock: notes the player owns are missed once their window
  /// closes, and notes they do not own play themselves as they arrive.
  void advanceTo(double beat) {
    _beat = beat;

    // The other hand simply plays itself, strictly in time order.
    while (_autoCursor < _auto.length &&
        beat >= _auto[_autoCursor].event.startBeat) {
      _auto[_autoCursor]
        ..state = HighwayNoteState.hit
        ..quality = HighwayHitQuality.perfect;
      _autoCursor++;
    }

    // Retire answered notes at the head, then look only as far ahead as the
    // hit window reaches — the list is sorted, so the first note beyond it
    // ends the scan.
    _retire();
    for (var i = _cursor; i < _graded.length; i++) {
      final n = _graded[i];
      if (n.event.startBeat + rules.hitWindowBeats >= beat) break;
      if (!n.isPending) continue;
      n.state = HighwayNoteState.missed;
      _misses++;
      _streak = 0;
    }
    // …and again AFTER, because that scan is what resolved them. Retiring only
    // beforehand leaves the cursor pinned at 0 for the whole run whenever the
    // clock arrives in one jump (a seek, a loop restart, a slow first frame),
    // and then every tap walks the notes already answered. Measured: 1.4 µs vs
    // 81.5 µs per tap late in a four-minute piece.
    _retire();
  }

  /// How many notes the last [tap] looked at. The cursor's whole purpose is to
  /// keep this bounded by the hit window instead of by the length of the piece,
  /// and once the work is this cheap a stopwatch cannot tell the difference —
  /// sub-microsecond timings are noise on a loaded machine. Counting is the
  /// deterministic form of the same question.
  ///
  /// Test-only, and deliberately NOT annotated `@visibleForTesting`: that
  /// annotation lives in `package:flutter/foundation.dart`, and this file is
  /// pure Dart on purpose (it has to run headless). A doc line costs nothing
  /// and does not drag Flutter into the core.
  int lastTapScanned = 0;

  /// Drops the head of the graded list past everything already answered.
  void _retire() {
    while (_cursor < _graded.length && !_graded[_cursor].isPending) {
      _cursor++;
    }
  }

  /// In wait-for-me, the beat the clock must not run past: the onset of the
  /// earliest note the player still owes. Null = nothing is holding us.
  ///
  /// It is a MINIMUM, not "the first pending note in the list" — a chart
  /// written one voice after another is not in time order, and taking the
  /// first entry would let the clock run past the other hand's notes.
  double? get holdBeat {
    if (!rules.waitForMe) return null;
    for (var i = _cursor; i < _graded.length; i++) {
      if (_graded[i].isPending) return _graded[i].event.startBeat;
    }
    return null;
  }

  /// The player hit [key] at [beat]. Claims the closest matching pending note
  /// inside the window; scores it; returns what happened.
  ///
  /// [breaksStreak] is false for MICROPHONE input. A tap is a decision — the
  /// wrong key is a mistake and should cost the run. A microphone is a
  /// measurement: it hears string noise, a neighbour's television and the
  /// player thinking out loud, and zeroing the streak on all of that would
  /// punish someone for the room they are in.
  HighwayTapResult tap(
    HighwayRailKey key,
    double beat, {
    bool breaksStreak = true,
  }) {
    HighwayNote? best;
    var bestDelta = double.infinity;
    var scanned = 0;
    // Same window as the clock: start where the unanswered notes begin and
    // stop at the first note too far in the future to be claimed.
    for (var i = _cursor; i < _graded.length; i++) {
      scanned++;
      final n = _graded[i];
      final delta = beat - n.event.startBeat;
      if (-delta > rules.hitWindowBeats) break;
      if (!n.isPending) continue;
      if (delta.abs() > rules.hitWindowBeats) continue;
      if (!laneMap.matches(n.event, key)) continue;
      if (delta.abs() < bestDelta) {
        bestDelta = delta.abs();
        best = n;
      }
    }
    lastTapScanned = scanned;
    if (best == null) {
      if (breaksStreak) _streak = 0; // a wrong key never costs a NOTE, though
      return const HighwayTapResult(note: null, quality: null);
    }
    if (identical(best, _graded[_cursor])) _retire();

    final delta = beat - best.event.startBeat;
    final quality = delta.abs() <= rules.perfectWindowBeats
        ? HighwayHitQuality.perfect
        : delta < 0
            ? HighwayHitQuality.early
            : HighwayHitQuality.late;
    best
      ..state = HighwayNoteState.hit
      ..timingError = delta
      ..quality = quality;
    _hits++;
    _streak++;
    if (_streak > _bestStreak) _bestStreak = _streak;
    _score += (quality == HighwayHitQuality.perfect ? 100 : 60) * multiplier;
    return HighwayTapResult(note: best, quality: quality);
  }
}
