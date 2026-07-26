// The score view must honour a Note Cut.
//
// `trackerChannelToScore` read `cellRuns`, which folds a note's RELEASE phase
// back into its sustain — the right sum for "how many rows until the next
// trigger", but wrong for notation, because it drew the note as still sounding
// through rows the module plays silent. A phrase that ends with a cut came out
// as one long held note, and a Score → Tracker → Score trip grew notes nobody
// wrote (the trailing padding rows fused onto the final note).
//
// It now reads `noteRuns`, which keeps sustain and release apart — the same
// distinction `loop_tracker.dart` depends on for rests.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tracker_notation.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show NoteElement, RestElement, Score;
import 'package:flutter_test/flutter_test.dart';

// The default grid: 16 rows at 4 steps per beat = one 4/4 bar.
const _timing = TrackerTiming();

TrackerChannel _channel(List<TrackerCell> cells) => TrackerChannel(
      id: 'melody',
      instrument: kTrackerInstruments.first.build(),
      rows: cells.length,
      cells: cells,
    );

/// Every element in reading order as `('n', midi)` or `('r', 0)`.
List<(String, int)> _events(Score score) => [
      for (final measure in score.measures)
        for (final element in measure.elements)
          if (element is NoteElement)
            ('n', element.pitches.first.midiNumber)
          else if (element is RestElement)
            ('r', 0),
    ];

/// One bar: a note at row 0, and a Note Cut at [cutAt] if given.
List<TrackerCell> _cells({int? cutAt}) => [
      for (var r = 0; r < _timing.rows; r++)
        if (r == 0)
          const TrackerCell(midi: 60)
        else if (r == cutAt)
          const TrackerCell(keyOff: true)
        else
          TrackerCell.empty,
    ];

void main() {
  test('rows after a Note Cut are rests, not more note', () {
    // Cut halfway: half a bar of C, then silence.
    final score = trackerChannelToScore(_channel(_cells(cutAt: 8)), _timing);
    final events = _events(score);

    expect(events.first, ('n', 60));
    expect(
      events.any((e) => e.$1 == 'r'),
      isTrue,
      reason: 'the cut produced no silence at all',
    );
    // Nothing may sound after the cut.
    final lastNote = events.lastIndexWhere((e) => e.$1 == 'n');
    final firstRest = events.indexWhere((e) => e.$1 == 'r');
    expect(
      firstRest,
      greaterThan(lastNote),
      reason: 'a note is still sounding after the Note Cut',
    );
  });

  test('without a cut the note rings on, as the tracker rule says', () {
    // The behaviour that must NOT change: an empty cell is "let it ring".
    final score = trackerChannelToScore(_channel(_cells()), _timing);
    final events = _events(score);

    expect(
      events.every((e) => e.$1 == 'n'),
      isTrue,
      reason: 'an uncut held note should have no rests',
    );
    expect(events.map((e) => e.$2).toSet(), {60});
  });

  test('a cut immediately after the note leaves almost all silence', () {
    final score = trackerChannelToScore(_channel(_cells(cutAt: 1)), _timing);
    final events = _events(score);

    expect(
      events.where((e) => e.$1 == 'n').length,
      1,
      reason: 'one row of C4 is one note',
    );
    expect(events.where((e) => e.$1 == 'r'), isNotEmpty);
  });

  test('the total written duration still covers every row', () {
    // Whatever the split between note and rest, the bar must stay full — a cut
    // that dropped its rows would shorten the piece instead of silencing it.
    for (final cutAt in [1, 4, 8, 12]) {
      final score =
          trackerChannelToScore(_channel(_cells(cutAt: cutAt)), _timing);
      var quarters = 0.0;
      for (final measure in score.measures) {
        for (final element in measure.elements) {
          if (element is NoteElement) {
            final (n, d) = element.duration.fraction;
            quarters += 4 * n / d;
          } else if (element is RestElement) {
            final (n, d) = element.duration.fraction;
            quarters += 4 * n / d;
          }
        }
      }
      // The whole bar must still be accounted for.
      expect(
        quarters,
        closeTo(_timing.rows / _timing.stepsPerBeat, 0.001),
        reason: 'cut at $cutAt lost or invented time',
      );
    }
  });
}
