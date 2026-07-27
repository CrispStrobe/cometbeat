// lib/core/audio/loop_track_length.dart
//
// Per-track pattern length — the groovebox move where one track loops shorter
// than the rest, so a 3-step hat walks around a 4-step bass and the groove keeps
// changing without anybody editing a note.
//
// Two things make this less obvious than "render it short and repeat it".
//
// SWING. The engine already tiles a 2-bar stem across a longer progression, and
// that is sample-exact "because the swung step grid is periodic per bar". A
// 3-step pattern is NOT bar-periodic: on the next repetition its first cell
// lands on a globally-odd step, which is swung late. Tiling the rendered
// SAMPLES would therefore place the swing wrongly on every other pass. So these
// helpers repeat the CELLS and let the caller render once against the real
// timing, where each cell is placed at its true global step and swing falls
// where it should.
//
// PHASE. The app plays one rendered buffer on a gapless loop. If that buffer is
// 16 steps and a track loops at 3, the track restarts every 16 — you hear a
// clipped tail once per cycle, not polymeter. The buffer has to span a whole
// number of BOTH lengths, i.e. their lcm. [kLoopTrackLengths] is chosen so that
// lcm never exceeds three times the 2-bar grid, which is why the list is a
// curated set rather than "any number from 1 to 16": adding 5 or 7 would let a
// two-track combination demand a 30-bar buffer, and the memory for that is real.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;

/// Pattern lengths a track may loop at, in eighth-steps (16 = the full 2-bar
/// grid, i.e. the current behaviour).
///
/// Every entry divides 48, so the loop buffer never has to exceed 48 steps
/// (6 bars) no matter which combination of tracks is in play, and no pattern is
/// ever cut off mid-repeat. 5, 7, 9… are excluded deliberately: musically they
/// add little that 3 and 6 do not, and lcm(16, 5, 7) is 560 steps of audio.
const List<int> kLoopTrackLengths = [1, 2, 3, 4, 6, 8, 12, 16];

/// Whether [steps] is a length a track may loop at.
bool isLoopTrackLength(int steps) => kLoopTrackLengths.contains(steps);

/// The first [steps] of [cells], splitting a cell that straddles the boundary.
///
/// Shortening a pattern keeps the beginning, which is what a groovebox does and
/// what a player expects: the loop gets shorter, the notes do not move. A cell
/// crossing the new end is kept and clipped rather than dropped, so the result
/// always fills exactly [steps] — anything else would leave a hole that the
/// renderer would voice as silence.
List<PatternCell> takeSteps(List<PatternCell> cells, int steps) {
  if (steps <= 0) return const [];
  final out = <PatternCell>[];
  var used = 0;
  for (final cell in cells) {
    if (used >= steps) break;
    final room = steps - used;
    out.add(
      cell.steps <= room
          ? cell
          : PatternCell(
              midis: cell.midis,
              steps: room,
              velocity: cell.velocity,
            ),
    );
    used += cell.steps <= room ? cell.steps : room;
  }
  // Cells shorter than the requested window: pad with a rest rather than
  // returning a short list, so the contract "fills exactly [steps]" holds for
  // callers that assert it.
  if (used < steps) out.add(PatternCell(steps: steps - used));
  return out;
}

/// [cells] repeated — and clipped — to exactly [total] steps.
///
/// Returns the cells unchanged when they already fill [total], so a track at the
/// default length costs nothing and renders byte-identically to before.
List<PatternCell> tileCellsTo(List<PatternCell> cells, int total) {
  if (total <= 0) return const [];
  final own = cells.fold<int>(0, (sum, c) => sum + c.steps);
  if (own == total) return cells;
  if (own <= 0) return [PatternCell(steps: total)];

  final out = <PatternCell>[];
  var used = 0;
  while (used < total) {
    final remaining = total - used;
    if (own <= remaining) {
      out.addAll(cells);
      used += own;
    } else {
      out.addAll(takeSteps(cells, remaining));
      used = total;
    }
  }
  return out;
}

/// A drum row (one bool per step) repeated and clipped to [total] steps.
List<bool> tileRowTo(List<bool> row, int total) {
  if (total <= 0) return const [];
  if (row.isEmpty) return List<bool>.filled(total, false);
  if (row.length == total) return row;
  return [for (var i = 0; i < total; i++) row[i % row.length]];
}

/// A per-step value row (velocities) repeated and clipped to [total] steps.
List<double> tileValuesTo(List<double> row, int total) {
  if (total <= 0) return const [];
  if (row.isEmpty) return List<double>.filled(total, 1);
  if (row.length == total) return row;
  return [for (var i = 0; i < total; i++) row[i % row.length]];
}

/// How many steps the rendered loop must span for [baseSteps] and every length
/// in [trackLengths] to complete a whole number of repetitions.
///
/// This is what stops a short track from being cut off at the loop seam. With no
/// track shorter than the grid it returns [baseSteps], so an ordinary groove
/// renders exactly as before.
///
/// Lengths outside [kLoopTrackLengths] are ignored rather than honoured: they
/// would be unbounded, and silently rendering a 30-bar buffer is worse than
/// silently ignoring a value no UI can produce.
int loopRenderSteps(int baseSteps, Iterable<int> trackLengths) {
  var steps = baseSteps <= 0 ? 1 : baseSteps;
  for (final length in trackLengths) {
    if (length <= 0 || !isLoopTrackLength(length)) continue;
    steps = _lcm(steps, length);
  }
  return steps;
}

int _lcm(int a, int b) => a ~/ _gcd(a, b) * b;

int _gcd(int a, int b) {
  var x = a, y = b;
  while (y != 0) {
    final t = y;
    y = x % y;
    x = t;
  }
  return x;
}
