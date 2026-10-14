// lib/features/workshop/workshop_playhead.dart
//
// The Score Workshop's moving playback cursor, out of the widget.
//
// Playback renders the score to one WAV and, alongside, a SCHEDULE: each
// element id with its start/end in music seconds. A wall-clock timer then asks
// this class "what sounds at elapsed time t?" — the count-in runs before music
// zero (nothing highlights yet), and reaching the end either restarts a loop
// (straight back to the music, no count-in) or finishes.
//
// No audio, timer or widget here: the screen owns those and acts on [step].

/// One scheduled element: its id and when it sounds, in music seconds.
typedef ScheduledElement = ({String id, double start, double end});

/// What the screen should do after a clock tick.
enum PlayheadAction { play, restartLoop, stop }

/// The schedule plus the count-in and loop state of one playback run.
class WorkshopPlayhead {
  List<ScheduledElement> _schedule = const [];
  double _endSeconds = 0;
  double _countInSeconds = 0;
  bool _looping = false;
  Set<String> _sounding = const {};

  /// The element ids sounding at the last [step]. Empty when idle.
  Set<String> get sounding => _sounding;

  /// Whether reaching the end restarts instead of stopping.
  bool get looping => _looping;

  /// Starts a run over [schedule] (music-relative), ending at [endSeconds].
  /// [countInSeconds] of lead-in run before music zero on the first pass only.
  void start(
    List<ScheduledElement> schedule, {
    required double endSeconds,
    double countInSeconds = 0,
    bool loop = false,
  }) {
    _schedule = schedule;
    _endSeconds = endSeconds;
    _countInSeconds = countInSeconds;
    _looping = loop;
    _sounding = const {};
  }

  /// Advances to [elapsedSeconds] of wall clock since the run (or the current
  /// loop cycle) began. Returns whether to keep playing, restart the loop, or
  /// stop; [changed] reports whether [sounding] moved (the screen repaints).
  ({PlayheadAction action, bool changed}) step(double elapsedSeconds) {
    final t = elapsedSeconds - _countInSeconds;
    if (t >= _endSeconds) {
      if (_looping) {
        _countInSeconds = 0; // the count-in leads in the first pass only
        return (action: PlayheadAction.restartLoop, changed: false);
      }
      return (action: PlayheadAction.stop, changed: false);
    }
    final now = <String>{
      if (t >= 0)
        for (final s in _schedule)
          if (t >= s.start && t < s.end) s.id,
    };
    final changed =
        now.length != _sounding.length || !now.every(_sounding.contains);
    if (changed) _sounding = now;
    return (action: PlayheadAction.play, changed: changed);
  }

  /// Ends the run: no loop, nothing sounding.
  void stop() {
    _looping = false;
    _sounding = const {};
  }

  /// One bar of clicks: [beats] of the meter's own unit ([beatUnit]; 6/8
  /// counts eighths) at [quarterBpm], stretched by the practice [speed].
  /// Count-ins are 2–8 beats; a non-positive tempo falls back to 100.
  static double countInLength({
    required double? quarterBpm,
    required int beats,
    required int beatUnit,
    double speed = 1,
  }) {
    final bpm = quarterBpm == null || quarterBpm <= 0 ? 100.0 : quarterBpm;
    final beatSec = 60 / bpm * (4 / beatUnit) / speed;
    return beatSec * beats.clamp(2, 8);
  }
}
