// lib/core/audio/play_along.dart
//
// The scoring engine behind play-along and sing-along. Pure Dart, no Flutter —
// it takes a target melody (a [PlayAlongChart]) and a stream of [PitchReading]s
// over time, and decides, per note, whether you played/sang it: the right pitch
// (optionally octave-agnostic, for voices) within a cents window for enough of
// the note's duration. The moving-score UI is just a view over this state.
//
// Unit-tested in test/play_along_test.dart with fabricated readings.

import 'dart:math';

import 'package:klang_universum/core/audio/pitch_analysis.dart';

/// One target note, positioned in musical time (beats from the chart start).
class TargetNote {
  const TargetNote({
    required this.midi,
    required this.startBeat,
    required this.beats,
  });

  final int midi;
  final double startBeat;
  final double beats;

  double get endBeat => startBeat + beats;
}

/// A target melody at a fixed tempo.
class PlayAlongChart {
  const PlayAlongChart({
    required this.name,
    required this.bpm,
    required this.notes,
    this.octaveAgnostic = false,
  });

  final String name;
  final int bpm;
  final List<TargetNote> notes;

  /// When true, a pitch matches if its pitch *class* matches (any octave) — the
  /// right default for singing, where the octave is voice-dependent.
  final bool octaveAgnostic;

  double get beatMs => 60000.0 / bpm;
  double get totalBeats =>
      notes.isEmpty ? 0 : notes.map((n) => n.endBeat).reduce(max);
  double get totalMs => totalBeats * beatMs;

  /// Same chart at a different tempo (used by the slow-down control).
  PlayAlongChart copyWith({int? bpm}) => PlayAlongChart(
        name: name,
        bpm: bpm ?? this.bpm,
        notes: notes,
        octaveAgnostic: octaveAgnostic,
      );
}

/// A star-score to hand `scoreToStars` / `GameResultView.starScore` so stars
/// reflect the **fraction** of a variable-length chart hit, not a raw count:
/// ≥90% → 3★ (`thresholds[2]`), ≥70% → 2★ (`thresholds[1]`), any hit → 1★, none
/// → 0. Lets one game score charts of any length fairly against its fixed
/// `[1★,2★,3★]` [thresholds] (e.g. singing a Song Book song of arbitrary length).
int scaledStarScore(int hits, int total, List<int> thresholds) {
  if (hits <= 0 || total <= 0) return 0;
  final pct = hits / total;
  if (pct >= 0.9) return thresholds[2];
  if (pct >= 0.7) return thresholds[1];
  return 1;
}

enum NoteResult { pending, hit, missed }

/// Mutable per-note scoring state.
class NoteState {
  NoteState(this.note);

  final TargetNote note;
  NoteResult result = NoteResult.pending;

  int _good = 0;
  int _total = 0;
  double _sumCents = 0;
  int _centsCount = 0;

  /// Fraction of sampled frames (while this note was active) that were on pitch.
  double get coverage => _total == 0 ? 0 : _good / _total;

  /// Mean signed cents error over the on-pitch frames (null if never on pitch).
  double? get avgCents => _centsCount == 0 ? null : _sumCents / _centsCount;
}

/// Feed [update] wall-clock elapsed time plus the latest pitch reading each
/// frame; read [notes], [activeNote], [hits], [accuracy], [finished] for the UI.
class PlayAlongEngine {
  PlayAlongEngine(
    this.chart, {
    this.centsTolerance = 45,
    this.hitCoverage = 0.4,
    this.leadInBeats = 4,
  }) : notes = chart.notes.map(NoteState.new).toList();

  final PlayAlongChart chart;

  /// How far off a note may be and still count (in cents).
  final double centsTolerance;

  /// Fraction of a note's active frames that must be on pitch to count as a hit.
  final double hitCoverage;

  /// A count-in before the first note, so the player can get ready.
  final double leadInBeats;

  final List<NoteState> notes;

  double _elapsedMs = 0;

  // Practice loop: while set, musical time wraps back to [_loopStartBeat] each
  // time it reaches [_loopEndBeat]. [_loopRewoundMs] is the total time subtracted
  // so far, keeping the external (ever-growing) clock and musical time in sync.
  double _loopRewoundMs = 0;
  double? _loopStartBeat;
  double? _loopEndBeat;

  /// Musical position now, in beats. Negative during the count-in.
  double get currentBeat =>
      (_elapsedMs - _loopRewoundMs) / chart.beatMs - leadInBeats;

  /// Whether a practice loop is active.
  bool get isLooping => _loopStartBeat != null && _loopEndBeat != null;
  double? get loopStartBeat => _loopStartBeat;
  double? get loopEndBeat => _loopEndBeat;

  /// Set (or clear, with nulls / an empty span) a practice loop over the
  /// half-open beat range [startBeat, endBeat). While active, playback wraps
  /// back to [startBeat] on reaching [endBeat], re-arming the notes inside so
  /// they can be practiced again.
  void setLoop(double? startBeat, double? endBeat) {
    if (startBeat == null || endBeat == null || endBeat <= startBeat) {
      _loopStartBeat = _loopEndBeat = null;
      return;
    }
    _loopStartBeat = startBeat;
    _loopEndBeat = endBeat;
  }

  bool get inCountIn => currentBeat < 0;
  bool get finished => currentBeat >= chart.totalBeats;

  int get hits => notes.where((n) => n.result == NoteResult.hit).length;
  int get judged => notes.where((n) => n.result != NoteResult.pending).length;
  double get accuracy => notes.isEmpty ? 0 : hits / notes.length;

  /// The note whose time window contains [currentBeat], or null (count-in/gap).
  NoteState? get activeNote {
    final i = activeIndex;
    return i < 0 ? null : notes[i];
  }

  /// Index into [notes] of the active note, or -1 (count-in / between notes).
  int get activeIndex {
    final b = currentBeat;
    for (var i = 0; i < notes.length; i++) {
      if (b >= notes[i].note.startBeat && b < notes[i].note.endBeat) return i;
    }
    return -1;
  }

  /// Index of the next upcoming note (the first that starts at/after now), or
  /// -1 when none remain — used by the coach view.
  int get nextIndex {
    final b = currentBeat;
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].note.startBeat >= b) return i;
    }
    return -1;
  }

  /// Advance to [elapsedMs] and sample [reading] against the active note.
  void update({required double elapsedMs, required PitchReading reading}) {
    _elapsedMs = elapsedMs;

    // Practice loop: rewind musical time to the loop start whenever it passes
    // the loop end, re-arming the loop's notes for another pass.
    if (isLooping) {
      final loopLenMs = (_loopEndBeat! - _loopStartBeat!) * chart.beatMs;
      var guard = 0;
      while (loopLenMs > 0 && currentBeat >= _loopEndBeat! && guard++ < 4096) {
        _loopRewoundMs += loopLenMs;
        _rearmLoopNotes();
      }
    }

    final b = currentBeat;

    // Finalize any pending note that has fully elapsed.
    for (final n in notes) {
      if (n.result == NoteResult.pending && b >= n.note.endBeat) {
        n.result =
            n.coverage >= hitCoverage ? NoteResult.hit : NoteResult.missed;
      }
    }

    final active = activeNote;
    if (active != null && active.result == NoteResult.pending) {
      active._total++;
      if (reading.hasPitch && _matches(reading, active.note.midi)) {
        active._good++;
        active._sumCents += reading.cents;
        active._centsCount++;
      }
    }
  }

  bool _matches(PitchReading r, int targetMidi) {
    if (r.cents.abs() > centsTolerance) return false;
    return chart.octaveAgnostic
        ? (r.nearestMidi % 12) == (targetMidi % 12)
        : r.nearestMidi == targetMidi;
  }

  void reset() {
    _elapsedMs = 0;
    _loopRewoundMs = 0;
    _loopStartBeat = _loopEndBeat = null;
    for (final n in notes) {
      n.result = NoteResult.pending;
      n._good = 0;
      n._total = 0;
      n._sumCents = 0;
      n._centsCount = 0;
    }
  }

  /// Re-arm (mark pending, clear scoring) every note that begins inside the loop.
  void _rearmLoopNotes() {
    for (final n in notes) {
      if (n.note.startBeat >= _loopStartBeat! &&
          n.note.startBeat < _loopEndBeat!) {
        n.result = NoteResult.pending;
        n._good = 0;
        n._total = 0;
        n._sumCents = 0;
        n._centsCount = 0;
      }
    }
  }
}

/// A few built-in charts so the modes have real content out of the box.
class PlayAlongCharts {
  /// Cello first-position intonation walk (D major-ish steps), slow.
  static const celloFirstPosition = PlayAlongChart(
    name: 'Cello: first position walk',
    bpm: 60,
    notes: [
      TargetNote(midi: 50, startBeat: 0, beats: 2), // D3
      TargetNote(midi: 52, startBeat: 2, beats: 2), // E3
      TargetNote(midi: 54, startBeat: 4, beats: 2), // F#3
      TargetNote(midi: 55, startBeat: 6, beats: 2), // G3
      TargetNote(midi: 57, startBeat: 8, beats: 4), // A3 (hold)
      TargetNote(midi: 55, startBeat: 12, beats: 2), // G3
      TargetNote(midi: 54, startBeat: 14, beats: 2), // F#3
      TargetNote(midi: 52, startBeat: 16, beats: 2), // E3
      TargetNote(midi: 50, startBeat: 18, beats: 4), // D3 (hold)
    ],
  );

  /// Guitar riff in first position (E-minor pentatonic shape), medium tempo.
  static const guitarRiff = PlayAlongChart(
    name: 'Guitar: pentatonic riff',
    bpm: 80,
    notes: [
      TargetNote(midi: 52, startBeat: 0, beats: 1), // E3
      TargetNote(midi: 55, startBeat: 1, beats: 1), // G3
      TargetNote(midi: 57, startBeat: 2, beats: 1), // A3
      TargetNote(midi: 59, startBeat: 3, beats: 1), // B3
      TargetNote(midi: 62, startBeat: 4, beats: 2), // D4 (hold)
      TargetNote(midi: 59, startBeat: 6, beats: 1), // B3
      TargetNote(midi: 57, startBeat: 7, beats: 1), // A3
      TargetNote(midi: 55, startBeat: 8, beats: 2), // G3
      TargetNote(midi: 52, startBeat: 10, beats: 2), // E3 (hold)
    ],
  );

  /// C-major scale up and down — one note per beat, for keyboard practice.
  static const keyboardScale = PlayAlongChart(
    name: 'Keyboard: C major scale',
    bpm: 100,
    notes: [
      TargetNote(midi: 60, startBeat: 0, beats: 1), // C4
      TargetNote(midi: 62, startBeat: 1, beats: 1), // D4
      TargetNote(midi: 64, startBeat: 2, beats: 1), // E4
      TargetNote(midi: 65, startBeat: 3, beats: 1), // F4
      TargetNote(midi: 67, startBeat: 4, beats: 1), // G4
      TargetNote(midi: 69, startBeat: 5, beats: 1), // A4
      TargetNote(midi: 71, startBeat: 6, beats: 1), // B4
      TargetNote(midi: 72, startBeat: 7, beats: 1), // C5
      TargetNote(midi: 71, startBeat: 8, beats: 1), // B4
      TargetNote(midi: 69, startBeat: 9, beats: 1), // A4
      TargetNote(midi: 67, startBeat: 10, beats: 1), // G4
      TargetNote(midi: 65, startBeat: 11, beats: 1), // F4
      TargetNote(midi: 64, startBeat: 12, beats: 1), // E4
      TargetNote(midi: 62, startBeat: 13, beats: 1), // D4
      TargetNote(midi: 60, startBeat: 14, beats: 2), // C4 (hold)
    ],
  );

  /// "Ode to Joy" (Beethoven, public domain) in C — a keyboard/cello tune.
  static const odeToJoy = PlayAlongChart(
    name: 'Ode to Joy',
    bpm: 100,
    notes: [
      TargetNote(midi: 64, startBeat: 0, beats: 1), // E
      TargetNote(midi: 64, startBeat: 1, beats: 1),
      TargetNote(midi: 65, startBeat: 2, beats: 1), // F
      TargetNote(midi: 67, startBeat: 3, beats: 1), // G
      TargetNote(midi: 67, startBeat: 4, beats: 1),
      TargetNote(midi: 65, startBeat: 5, beats: 1),
      TargetNote(midi: 64, startBeat: 6, beats: 1),
      TargetNote(midi: 62, startBeat: 7, beats: 1), // D
      TargetNote(midi: 60, startBeat: 8, beats: 1), // C
      TargetNote(midi: 60, startBeat: 9, beats: 1),
      TargetNote(midi: 62, startBeat: 10, beats: 1),
      TargetNote(midi: 64, startBeat: 11, beats: 1),
      TargetNote(midi: 64, startBeat: 12, beats: 1.5),
      TargetNote(midi: 62, startBeat: 13.5, beats: 0.5),
      TargetNote(midi: 62, startBeat: 14, beats: 2), // D (hold)
    ],
  );

  /// "Mary Had a Little Lamb" for singing — octave-agnostic, easy range.
  static const marySing = PlayAlongChart(
    name: 'Sing: Mary Had a Little Lamb',
    bpm: 100,
    octaveAgnostic: true,
    notes: [
      TargetNote(midi: 64, startBeat: 0, beats: 1), // E
      TargetNote(midi: 62, startBeat: 1, beats: 1), // D
      TargetNote(midi: 60, startBeat: 2, beats: 1), // C
      TargetNote(midi: 62, startBeat: 3, beats: 1), // D
      TargetNote(midi: 64, startBeat: 4, beats: 1), // E
      TargetNote(midi: 64, startBeat: 5, beats: 1),
      TargetNote(midi: 64, startBeat: 6, beats: 2),
      TargetNote(midi: 62, startBeat: 8, beats: 1), // D
      TargetNote(midi: 62, startBeat: 9, beats: 1),
      TargetNote(midi: 62, startBeat: 10, beats: 2),
      TargetNote(midi: 64, startBeat: 12, beats: 1), // E
      TargetNote(midi: 67, startBeat: 13, beats: 1), // G
      TargetNote(midi: 67, startBeat: 14, beats: 2),
    ],
  );

  /// "Twinkle, Twinkle" for singing — octave-agnostic, comfortable range.
  static const twinkleSing = PlayAlongChart(
    name: 'Sing: Twinkle, Twinkle',
    bpm: 96,
    octaveAgnostic: true,
    notes: [
      TargetNote(midi: 60, startBeat: 0, beats: 1), // C
      TargetNote(midi: 60, startBeat: 1, beats: 1),
      TargetNote(midi: 67, startBeat: 2, beats: 1), // G
      TargetNote(midi: 67, startBeat: 3, beats: 1),
      TargetNote(midi: 69, startBeat: 4, beats: 1), // A
      TargetNote(midi: 69, startBeat: 5, beats: 1),
      TargetNote(midi: 67, startBeat: 6, beats: 2), // G
      TargetNote(midi: 65, startBeat: 8, beats: 1), // F
      TargetNote(midi: 65, startBeat: 9, beats: 1),
      TargetNote(midi: 64, startBeat: 10, beats: 1), // E
      TargetNote(midi: 64, startBeat: 11, beats: 1),
      TargetNote(midi: 62, startBeat: 12, beats: 1), // D
      TargetNote(midi: 62, startBeat: 13, beats: 1),
      TargetNote(midi: 60, startBeat: 14, beats: 2), // C
    ],
  );
}
