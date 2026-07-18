// lib/features/games/widgets/playing_staff.dart
//
// A reusable "the notes light up as they play" staff. Audio in the app is
// fire-and-forget (a rendered WAV), but the *schedule* is always known — each
// note/chord has a duration in ms — so we can drive crisp_notation's
// `StaffView.highlightedIds` on a Ticker started at the same instant as the
// sound, with no audio callback needed. This is the same primitive the
// play-along note-highway uses, packaged so any example or minigame can show
// progress with a few lines:
//
//   final _pb = ScorePlayback();                       // in State
//   PlayingStaffView(score: _score, controller: _pb)   // in build
//   audio.playSequence(seq); _pb.play(steps);          // fire together
//
// Provide a matching `List<PlayStep>` (which ids sound, for how long) built
// from the very same data you pass to AudioService, so sound and highlight stay
// in lockstep.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';

/// One step of a playback: the element ids that sound now, and for how long.
typedef PlayStep = ({Set<String> ids, int ms});

/// Turns a monophonic (midi, ms) sequence + the score element ids it plays into
/// a highlight schedule — one step per note. `ids[i]` is the id of the note
/// that the i-th sequence entry engraves.
List<PlayStep> stepsForSequence(List<(int, int)> seq, List<String> ids) => [
      for (var i = 0; i < seq.length && i < ids.length; i++)
        (ids: {ids[i]}, ms: seq[i].$2),
    ];

/// Drives a [PlayingStaffView]'s highlight along a timed schedule. Create it in
/// `initState`, dispose it in `dispose`, and call [play] at the same moment you
/// start the audio.
class ScorePlayback extends ChangeNotifier {
  List<PlayStep> _schedule = const [];
  int _epoch = 0;

  List<PlayStep> get schedule => _schedule;
  int get epoch => _epoch;

  /// Start (or restart) the highlight running through [schedule].
  void play(List<PlayStep> schedule) {
    _schedule = schedule;
    _epoch++;
    notifyListeners();
  }

  /// Stop and clear any highlight.
  void clear() {
    _schedule = const [];
    _epoch++;
    notifyListeners();
  }
}

/// A [StaffView] that lights its elements in time with a [ScorePlayback].
class PlayingStaffView extends StatefulWidget {
  const PlayingStaffView({
    super.key,
    required this.score,
    required this.controller,
    this.staffSpace = 11,
    this.theme = CrispNotationTheme.kids,
    this.showNoteNames = false,
    this.noteNameStyle = NoteNameStyle.letter,
  });

  final Score score;
  final ScorePlayback controller;
  final double staffSpace;
  final CrispNotationTheme theme;

  /// Print letter names under the noteheads (the reading scaffold). Off by
  /// default; set by [ReadingStaffView] so name-safe games keep the scaffold
  /// while their notes light up.
  final bool showNoteNames;
  final NoteNameStyle noteNameStyle;

  @override
  State<PlayingStaffView> createState() => _PlayingStaffViewState();
}

class _PlayingStaffViewState extends State<PlayingStaffView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Set<String> _highlight = const {};
  int _seenEpoch = 0;

  // Cumulative end time (ms) of each step, so a tick maps to a step in O(log n).
  List<int> _ends = const [];
  int _totalMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick); // Ticker in initState (never lazy/late).
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(PlayingStaffView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (widget.controller.epoch == _seenEpoch) return;
    _seenEpoch = widget.controller.epoch;
    final sched = widget.controller.schedule;
    var acc = 0;
    _ends = [
      for (final s in sched) acc += s.ms,
    ];
    _totalMs = acc;
    _ticker.stop();
    if (_totalMs == 0) {
      _setHighlight(const {});
      return;
    }
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMicroseconds / 1000.0;
    if (ms >= _totalMs) {
      _ticker.stop();
      _setHighlight(const {});
      return;
    }
    final sched = widget.controller.schedule;
    var i = 0;
    while (i < _ends.length && ms >= _ends[i]) {
      i++;
    }
    _setHighlight(i < sched.length ? sched[i].ids : const {});
  }

  void _setHighlight(Set<String> ids) {
    if (setEquals(ids, _highlight)) return;
    setState(() => _highlight = ids);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StaffView(
      score: widget.score,
      staffSpace: widget.staffSpace,
      theme: widget.theme,
      highlightedIds: _highlight,
      showNoteNames: widget.showNoteNames,
      noteNameStyle: widget.noteNameStyle,
    );
  }
}
