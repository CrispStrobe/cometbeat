// WS-T6 — where the beat and bar lines go.
//
// Two consumers draw a beat grid over the same pattern — the tracker grid and
// the piano roll — and before this they disagreed. The grid read
// `_highlightEvery ?? stepsPerBeat` and then hardcoded FOUR beats to a bar; the
// roll hardcoded 4 and 16 outright and read neither. So a pattern at 3 steps
// per beat, or a piece in 3/4, got its bar lines in different wrong places
// depending on which view you were looking at.
//
// ⚠️ This is a DISPLAY property and lives here rather than in `TrackerTiming`
// for that reason. Beats-per-bar changes nothing about when a note sounds — it
// changes where a line is drawn. Putting it in the engine's timing model would
// imply the replayer cared, and the replayer does not.

/// How a pattern's rows group into beats and bars, for drawing.
///
/// [rowsPerBeat] normally comes from the pattern's own `stepsPerBeat`; the
/// tracker also lets it be overridden, because FT2's row-highlight spacing is a
/// reading aid people set to taste (every 4 rows in a busy pattern, every 8 in
/// a sparse one) and is not always the musical beat.
class TrackerMeter {
  const TrackerMeter({this.rowsPerBeat = 4, this.beatsPerBar = 4})
      : assert(rowsPerBeat > 0),
        assert(beatsPerBar > 0);

  final int rowsPerBeat;
  final int beatsPerBar;

  /// Rows between bar lines.
  int get rowsPerBar => rowsPerBeat * beatsPerBar;

  /// Whether a beat line belongs at [row].
  bool isBeat(int row) => row >= 0 && row % rowsPerBeat == 0;

  /// Whether a BAR line belongs at [row] — the stronger of the two.
  ///
  /// Every bar row is also a beat row; callers that draw both should test this
  /// one first, or the bar is drawn as a beat and the meter reads as 4/4 no
  /// matter what it is.
  bool isBar(int row) => row >= 0 && row % rowsPerBar == 0;

  /// Which bar [row] falls in, counting from 1 as musicians do.
  int barOf(int row) => row < 0 ? 1 : (row ~/ rowsPerBar) + 1;

  /// The beat within its bar, counting from 1.
  int beatInBar(int row) =>
      row < 0 ? 1 : ((row % rowsPerBar) ~/ rowsPerBeat) + 1;

  TrackerMeter copyWith({int? rowsPerBeat, int? beatsPerBar}) => TrackerMeter(
        rowsPerBeat: rowsPerBeat ?? this.rowsPerBeat,
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      );

  /// How it reads on a control: "4/4" at four rows to the beat is the common
  /// case, and the rows only matter when they are not the default.
  String get label => '$beatsPerBar/4 · $rowsPerBeat rows a beat';

  @override
  bool operator ==(Object other) =>
      other is TrackerMeter &&
      other.rowsPerBeat == rowsPerBeat &&
      other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(rowsPerBeat, beatsPerBar);
}

/// The meters worth offering. Deliberately short: this is a reading aid, and a
/// list of every conceivable meter would bury the two people actually want.
const List<TrackerMeter> kCommonMeters = [
  TrackerMeter(),
  TrackerMeter(beatsPerBar: 3),
  TrackerMeter(beatsPerBar: 6),
  TrackerMeter(rowsPerBeat: 3),
  TrackerMeter(rowsPerBeat: 8),
];
