// lib/core/services/transport_service.dart
//
// WS-W2 — one clock.
//
// Today the Tracker, the Audio Editor and Loop Studio each own a private
// Ticker + Stopwatch, so none of them can follow another: pressing play in one
// leaves the others' playheads where they were. This is the single position,
// play state, loop range, count-in and metronome every surface can share.
//
// IT SCHEDULES, IT DOES NOT RENDER. Playback stays offline render-then-play;
// nothing here touches audio, and nothing here presumes the D-RT decision
// (whether to add a real-time preview bus) has been made.
//
// THE ONE DESIGN DECISION WORTH KNOWING: this service does NOT own a clock.
// It is *advanced* — [advance] takes the elapsed milliseconds and the caller
// supplies them. Three reasons, in order of how much they mattered:
//
//   1. It is the only shape that can be tested. `loop_mixer_screen.dart` already
//      documents the opposite case as a problem — "the live grade reads a real
//      Stopwatch, which widget tests can't advance" — and the acceptance test
//      for this task has to drive play → loop wrap → stop headlessly.
//   2. Migration stays additive. Each screen already has a Ticker; during the
//      migration it keeps it and calls `advance` from its existing tick
//      callback. No surface grows a second clock, which is exactly the failure
//      the card warns about.
//   3. The Audio Editor's playhead is deliberately driven by "the Ticker's own
//      elapsed (NOT wall-clock)". A service that read a wall clock would have
//      silently disagreed with it.
//
// Musical position comes from [TempoMap] (`daw_tempo_map.dart`), which already
// does the hard part: beats do not scale linearly with time once the tempo
// changes. Bars do NOT come from there — a TempoMap has no meter — so
// [beatsPerBar] lives here. See the note on it for why that is not a stopgap.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/daw_tempo_map.dart';
import 'package:flutter/foundation.dart';

/// What one call to [TransportService.advance] did, beyond moving the position.
///
/// Returned rather than pushed as a stream because the caller is already inside
/// its own tick: a metronome wants to click *now*, in the same frame, and an
/// async hop would put the click on the wrong one.
@immutable
class TransportAdvance {
  const TransportAdvance({
    this.beatsCrossed = const [],
    this.looped = false,
    this.countInEnded = false,
  });

  /// Absolute beat numbers passed during this advance, in order.
  ///
  /// Absolute (not "3 beats went by") because the metronome accents the
  /// downbeat, and only the number tells you which one that is. During a
  /// count-in these are NEGATIVE — the count-in runs before beat 0.
  final List<double> beatsCrossed;

  /// Whether the loop wrapped. One flag however many times it wrapped: a single
  /// advance longer than the whole loop is a dropped frame, not four laps, and
  /// reporting four would make a listener re-trigger four times.
  final bool looped;

  /// Whether the count-in finished on this advance, i.e. the transport just
  /// started actually moving.
  final bool countInEnded;

  /// Nothing happened worth reacting to.
  static const none = TransportAdvance();
}

/// The shared transport: position, play state, loop, count-in and metronome.
///
/// One instance per project, provided app-wide. Two surfaces listening to the
/// same instance follow each other for free — which is the whole point, and is
/// what the cross-surface test asserts.
class TransportService extends ChangeNotifier {
  TransportService({TempoMap? tempo, int beatsPerBar = 4})
      : _tempo = tempo ?? TempoMap.constant(120),
        _beatsPerBar = math.max(1, beatsPerBar);

  TempoMap _tempo;
  int _beatsPerBar;
  double _positionMs = 0;
  bool _playing = false;
  bool _recordArmed = false;
  bool _recording = false;
  bool _loopEnabled = false;
  double _loopStartMs = 0;
  double _loopEndMs = 0;
  int _countInBars = 0;
  double _countInRemainingMs = 0;
  bool _metronome = false;

  // ---------------------------------------------------------------- position

  /// Where the playhead is, in ms from the project start. Never negative — a
  /// count-in does not rewind the timeline, it delays the start (see
  /// [isCountingIn]).
  double get positionMs => _positionMs;

  /// The musical position in beats, through the tempo map.
  double get beat => _tempo.beatAtMs(_positionMs);

  /// The bar number, counting from 0.
  int get bar => beat ~/ _beatsPerBar;

  /// How far into the current bar, in beats — `0.0` exactly on a downbeat.
  double get beatInBar => beat % _beatsPerBar;

  /// The conventional 1-based `bar.beat` readout a transport bar shows.
  String get barBeatLabel => '${bar + 1}.${beatInBar.floor() + 1}';

  /// The tempo in force at the playhead.
  double get bpm => _tempo.bpmAt(_positionMs);

  TempoMap get tempo => _tempo;
  set tempo(TempoMap value) {
    if (identical(_tempo, value)) return;
    _tempo = value;
    notifyListeners();
  }

  /// Beats per bar — the meter.
  ///
  /// This lives on the transport rather than on [TempoMap] because a TempoMap
  /// carries tempo only, and giving it a meter would be a change to a model
  /// other surfaces already persist. A real meter MAP (changing time signature
  /// partway) is its own task; until then one meter per project is honest, and
  /// is what every surface assumes today anyway.
  int get beatsPerBar => _beatsPerBar;
  set beatsPerBar(int value) {
    final next = math.max(1, value);
    if (next == _beatsPerBar) return;
    _beatsPerBar = next;
    notifyListeners();
  }

  // ------------------------------------------------------------- play state

  bool get isPlaying => _playing;

  /// Armed to record on the next [play]. Distinct from [isRecording] so a
  /// surface can light the button before the transport rolls.
  bool get isRecordArmed => _recordArmed;
  bool get isRecording => _recording;

  /// Counting in: [isPlaying] is true but the position is not moving yet.
  bool get isCountingIn => _countInRemainingMs > 0;

  /// How much count-in is left, in ms. `0` when not counting in.
  double get countInRemainingMs => _countInRemainingMs;

  /// Bars of count-in before [play] starts moving the position. `0` disables it.
  int get countInBars => _countInBars;
  set countInBars(int value) {
    final next = math.max(0, value);
    if (next == _countInBars) return;
    _countInBars = next;
    notifyListeners();
  }

  bool get metronomeEnabled => _metronome;
  set metronomeEnabled(bool value) {
    if (value == _metronome) return;
    _metronome = value;
    notifyListeners();
  }

  // ------------------------------------------------------------------- loop

  bool get isLoopEnabled => _loopEnabled;
  double get loopStartMs => _loopStartMs;
  double get loopEndMs => _loopEndMs;

  /// Whether the loop would actually do anything. An empty or inverted range is
  /// not an error — it is a range the user has not finished dragging — so it is
  /// simply inert rather than throwing or being silently repaired.
  bool get hasUsableLoop => _loopEnabled && _loopEndMs > _loopStartMs;

  void setLoop(double startMs, double endMs) {
    final a = math.max(0.0, _finite(startMs));
    final b = math.max(0.0, _finite(endMs));
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    if (lo == _loopStartMs && hi == _loopEndMs) return;
    _loopStartMs = lo;
    _loopEndMs = hi;
    notifyListeners();
  }

  void setLoopEnabled(bool value) {
    if (value == _loopEnabled) return;
    _loopEnabled = value;
    notifyListeners();
  }

  void toggleLoop() => setLoopEnabled(!_loopEnabled);

  // --------------------------------------------------------------- commands

  /// Starts playing from the current position, after any count-in.
  ///
  /// Idempotent: calling it while already playing does nothing, so a shared
  /// transport bar and a keyboard shortcut cannot restart the count-in between
  /// them.
  void play() {
    if (_playing) return;
    _playing = true;
    _recording = _recordArmed;
    _countInRemainingMs = _countInBars > 0 ? _countInLengthMs() : 0;
    notifyListeners();
  }

  /// Stops, leaving the playhead where it is.
  void pause() {
    if (!_playing) return;
    _playing = false;
    _recording = false;
    _countInRemainingMs = 0;
    notifyListeners();
  }

  /// Stops and returns to the start of the loop, or to 0 if there is no loop.
  ///
  /// Returning to the loop start rather than always to 0 is what makes stop
  /// usable while working on one section; without a loop the two are the same.
  void stop() {
    final home = hasUsableLoop ? _loopStartMs : 0.0;
    final changed = _playing || _recording || _positionMs != home;
    _playing = false;
    _recording = false;
    _countInRemainingMs = 0;
    _positionMs = home;
    if (changed) notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  void setRecordArmed(bool value) {
    if (value == _recordArmed) return;
    _recordArmed = value;
    if (_playing) _recording = value;
    notifyListeners();
  }

  /// Moves the playhead. Legal while playing — that is a scrub.
  void seekMs(double ms) {
    final next = math.max(0.0, _finite(ms));
    if (next == _positionMs) return;
    _positionMs = next;
    notifyListeners();
  }

  /// Moves the playhead to a musical position.
  void seekBeat(double beat) => seekMs(_tempo.msAtBeat(math.max(0, beat)));

  /// Moves the playhead to the nearest beat — what a snapped drag lands on.
  void snapToBeat() => seekMs(_tempo.snapToBeat(_positionMs));

  // ---------------------------------------------------------------- advance

  /// Advances the transport by [deltaMs] and reports what that crossed.
  ///
  /// The caller owns the clock; see the header for why. A non-positive or
  /// non-finite delta is a no-op rather than an error, because a Ticker's first
  /// callback legitimately reports zero elapsed.
  TransportAdvance advance(double deltaMs) {
    if (!_playing) return TransportAdvance.none;
    final delta = _finite(deltaMs);
    if (delta <= 0) return TransportAdvance.none;

    var remaining = delta;
    var countInEnded = false;
    final crossed = <double>[];

    // The count-in consumes time before the position moves. It still crosses
    // beats — that is the entire point of a count-in — so they are reported,
    // numbered NEGATIVELY so a listener can tell "three, four" from "one, two".
    if (_countInRemainingMs > 0) {
      final consumed = math.min(remaining, _countInRemainingMs);
      final beatMs = 60000 / _tempo.bpmAt(_positionMs);
      final before = -_countInRemainingMs / beatMs;
      _countInRemainingMs -= consumed;
      remaining -= consumed;
      final after = -_countInRemainingMs / beatMs;
      _collectBeats(crossed, before, after);
      if (_countInRemainingMs <= 0) {
        _countInRemainingMs = 0;
        countInEnded = true;
      }
      if (remaining <= 0) {
        notifyListeners();
        return TransportAdvance(
          beatsCrossed: crossed,
          countInEnded: countInEnded,
        );
      }
    }

    final startBeat = _tempo.beatAtMs(_positionMs);
    var looped = false;
    var target = _positionMs + remaining;

    if (hasUsableLoop && target >= _loopEndMs) {
      // Wrap by modulo, not by subtracting the loop length once: a dropped
      // frame can be longer than the loop, and subtracting once would leave the
      // playhead past the end — a bug that only shows up on a slow device.
      final span = _loopEndMs - _loopStartMs;
      final over = (target - _loopStartMs) % span;
      // Beats up to the loop end belong to this pass; beats after the wrap
      // belong to the next one. Reporting them as one run would put the
      // metronome on beats the playhead never visited.
      _collectBeats(crossed, startBeat, _tempo.beatAtMs(_loopEndMs));
      target = _loopStartMs + over;
      _collectBeats(
        crossed,
        _tempo.beatAtMs(_loopStartMs),
        _tempo.beatAtMs(target),
      );
      looped = true;
    } else {
      _collectBeats(crossed, startBeat, _tempo.beatAtMs(target));
    }

    _positionMs = target;
    notifyListeners();
    return TransportAdvance(
      beatsCrossed: crossed,
      looped: looped,
      countInEnded: countInEnded,
    );
  }

  // ----------------------------------------------------------------- detail

  /// Whole beats strictly after [from] and at or before [to].
  ///
  /// Half-open at the start so a beat is never reported twice across two
  /// advances, and inclusive at the end so landing exactly on a downbeat clicks
  /// on that frame rather than the next.
  static void _collectBeats(List<double> out, double from, double to) {
    if (!(to > from)) return;
    // Guard the pathological case (a multi-minute delta at 300 BPM) so a stalled
    // app resuming cannot allocate an unbounded list inside a frame.
    const maxBeats = 4096;
    var beat = (from.floorToDouble()) + 1;
    while (beat <= to && out.length < maxBeats) {
      out.add(beat);
      beat += 1;
    }
  }

  double _countInLengthMs() {
    final beats = _countInBars * _beatsPerBar;
    // Measured at the CURRENT tempo rather than through the map: a count-in
    // happens before the music, so it is not at a timeline position that a
    // tempo change could apply to.
    return beats * (60000 / _tempo.bpmAt(_positionMs));
  }

  static double _finite(double value) => value.isFinite ? value : 0;
}
