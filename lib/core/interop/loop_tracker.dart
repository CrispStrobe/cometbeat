// lib/core/interop/loop_tracker.dart
//
// D1 — Tracker <-> Loop Studio, directly and symbolically.
//
// Both routes between these two modes used to detour, and both detours cost
// something real:
//
//   * The Loop Mixer's "Open in Tracker" went Loop -> Score -> Tracker, so the
//     loop had to be engraved (quantized to note values, split at barlines)
//     before it could become a pattern — a round trip through notation that
//     neither side asked for.
//   * C3's tracker -> loop edge went via TAB, which fret-maps every pitch onto
//     six strings. Right for a guitar part; wrong for a piano channel, and
//     nonsense for a drum channel.
//
// Neither detour is necessary, because the two models are already the same
// shape: a monophonic-per-step grid of notes with a length. A [PatternCell] is
// `(midis, steps, velocity)`; a tracker channel is a list of cells where a note
// starts and the empty rows after it are its length. So the conversion is a run
// walk, and the only real work is the GRID RATIO.
//
// The grid ratio is the lossy part and it is worth being precise about: a loop
// step is always an eighth ([LoopTiming.stepsPerBar] = 8 per 4/4 bar), while a
// tracker row is 1/[TrackerTiming.stepsPerBeat] of a beat. At stepsPerBeat 2
// they are the same grid and the trip is exact. At 4 or 8 the tracker is FINER,
// so going to the loop halves or quarters the resolution — a 16th note has
// nowhere to land. That quantization is reported, never silent.
//
// Chords survive: a [PatternCell] holds a list of pitches, and a tracker channel
// is monophonic, so a chord becomes ONE cell per channel and the caller decides
// how many channels to read. Velocity survives natively both ways.
//
// Pure Dart, no Flutter.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';

/// The loop grid: an eighth-note step, i.e. 2 steps per beat.
const int kLoopStepsPerBeatGrid = 2;

/// The result of reading a tracker channel as loop cells.
class TrackerToLoopCellsResult {
  TrackerToLoopCellsResult({
    required this.cells,
    required this.annotations,
    required this.report,
  });

  final List<PatternCell> cells;

  /// What the loop grid could not hold — the original tracker row count, so a
  /// trip back can restore the finer resolution.
  final SymbolicAnnotations annotations;
  final ConversionReport report;
}

/// Reads one tracker [channel] as a run of loop [PatternCell]s.
///
/// The channel's note runs become cells directly: a note plus the empty rows
/// that follow it is one cell whose `steps` is that run's length, rescaled from
/// the tracker grid to the loop's eighth-note grid.
TrackerToLoopCellsResult loopCellsFromTrackerChannel(
  TrackerChannel channel,
  TrackerTiming timing,
) {
  final report = ConversionReport();
  final annotations = SymbolicAnnotations()
    ..docMeta[AnnotationKeys.sourceMode] = 'tracker'
    ..docMeta['stepsPerBeat'] = timing.stepsPerBeat;

  // rows -> loop steps. >1 means the tracker is finer and we lose resolution.
  final ratio = timing.stepsPerBeat / kLoopStepsPerBeatGrid;
  if (timing.stepsPerBeat % kLoopStepsPerBeatGrid != 0 &&
      kLoopStepsPerBeatGrid % timing.stepsPerBeat != 0) {
    report.addApproximated(
      'the pattern grid does not divide evenly into eighth-note loop steps',
    );
  }

  final cells = <PatternCell>[];
  var trackerStep = 0;

  int scale(int rows) {
    final scaled = (rows / ratio).round();
    if (scaled * ratio != rows) {
      report.addApproximated('note lengths snapped to the eighth-note grid');
    }
    return scaled < 1 ? 1 : scaled;
  }

  // noteRuns, NOT cellRuns: a channel distinguishes a note SUSTAINING for four
  // rows from a note sounding for two and then being cut (a `keyOff` cell), and
  // that difference is exactly a loop rest. cellRuns merges the two phases, so
  // using it would let every rest be swallowed by the note before it.
  for (final (midi, sustainRows, releaseRows) in noteRuns(channel.cells)) {
    // Velocity rides the cell's own field, but a tracker cell can also carry an
    // explicit volume column — take it when present so a dynamic pattern does
    // not flatten out.
    final velocity = _velocityAt(channel.cells, trackerStep);

    if (sustainRows > 0) {
      cells.add(
        PatternCell(
          midis: midi == null ? null : [midi],
          steps: scale(sustainRows),
          velocity: velocity,
        ),
      );
    }
    if (releaseRows > 0) {
      cells.add(PatternCell(steps: scale(releaseRows)));
    }
    trackerStep += sustainRows + releaseRows;
  }

  if (channel.fxChain.isNotEmpty || channel.effects.isNotEmpty) {
    report.addLost('the channel\'s insert effects');
  }
  if (channel.volumeEnvelope != null || channel.panEnvelope != null) {
    report.addLost('per-note envelopes');
  }

  final total = cells.fold<int>(0, (sum, c) => sum + c.steps);
  if (total % LoopTiming.stepsPerBar != 0) {
    report.addApproximated(
      'the pattern does not fill whole bars — the loop will not be a clean '
      'length',
    );
  }

  return TrackerToLoopCellsResult(
    cells: cells,
    annotations: annotations,
    report: report,
  );
}

/// The result of writing loop cells into a tracker channel.
class LoopCellsToTrackerResult {
  LoopCellsToTrackerResult({required this.channel, required this.report});

  final TrackerChannel channel;
  final ConversionReport report;
}

/// Writes loop [cells] into a tracker channel on [timing]'s grid.
///
/// A chord cell keeps only its LOWEST pitch — a tracker channel is monophonic
/// by construction, so the caller must spread a chord across channels itself
/// (see [trackerChannelsFromLoopCells]). The report says so rather than letting
/// the upper notes vanish quietly.
LoopCellsToTrackerResult trackerChannelFromLoopCells(
  List<PatternCell> cells,
  TrackerTiming timing, {
  required String id,
  required TrackerInstrument instrument,
  int voiceIndex = 0,
}) {
  final report = ConversionReport();
  final ratio = timing.stepsPerBeat / kLoopStepsPerBeatGrid;

  final rows = <TrackerCell>[];
  var sounding = false;
  for (final cell in cells) {
    final span = (cell.steps * ratio).round();
    final safeSpan = span < 1 ? 1 : span;
    final midis = cell.midis;

    // Only the FIRST voice reports the truncation: when a caller spreads the
    // chord over several channels (trackerChannelsFromLoopCells) nothing is
    // actually lost, and each extra voice repeating the warning would make a
    // successful conversion look damaged.
    if (voiceIndex == 0 && midis != null && midis.length > 1) {
      report.addLost(
        'chord notes above the lowest, unless the chord is spread over several '
        'channels',
      );
    }

    int? note;
    if (midis != null && midis.isNotEmpty) {
      final sorted = [...midis]..sort();
      // voiceIndex picks WHICH note of the chord this channel takes, so a caller
      // spreading a chord over several channels gets one voice each.
      if (voiceIndex < sorted.length) note = sorted[voiceIndex];
    }

    // A REST after a sounding note must be written as an explicit key-off, or
    // the channel reads as that note simply sustaining longer and the rest
    // disappears on the way back (see noteRuns above). The test is whether a
    // note is still SOUNDING — not whether the previous row holds one, since a
    // note's trailing rows are empty by construction.
    final needsKeyOff = note == null && sounding;
    rows.add(
      note != null
          ? TrackerCell(midi: note, volume: cell.velocity)
          : needsKeyOff
              ? const TrackerCell(keyOff: true)
              : TrackerCell.empty,
    );
    sounding = note != null;
    for (var i = 1; i < safeSpan; i++) {
      rows.add(TrackerCell.empty);
    }
  }

  // The channel must be exactly timing.rows long.
  if (rows.length > timing.rows) {
    report.addLost('material past the end of the pattern');
    rows.removeRange(timing.rows, rows.length);
  }
  while (rows.length < timing.rows) {
    rows.add(TrackerCell.empty);
  }

  return LoopCellsToTrackerResult(
    channel: TrackerChannel(
      id: id,
      instrument: instrument,
      rows: timing.rows,
      cells: rows,
    ),
    report: report,
  );
}

/// Spreads loop [cells] across as many channels as the widest chord needs, so a
/// chord survives a conversion that a single monophonic channel would truncate.
///
/// Returns one channel per voice, highest chord note first (matching how the
/// Tracker's own `scoreToChannels` splits chords).
List<TrackerChannel> trackerChannelsFromLoopCells(
  List<PatternCell> cells,
  TrackerTiming timing, {
  required String idPrefix,
  required TrackerInstrument instrument,
}) {
  var voices = 1;
  for (final cell in cells) {
    final n = cell.midis?.length ?? 0;
    if (n > voices) voices = n;
  }
  return [
    for (var v = 0; v < voices; v++)
      trackerChannelFromLoopCells(
        cells,
        timing,
        id: voices == 1 ? idPrefix : '$idPrefix${v + 1}',
        instrument: instrument,
        voiceIndex: v,
      ).channel,
  ];
}

/// A cell's velocity: the explicit volume column when the tracker cell carries
/// one, else full.
double _velocityAt(List<TrackerCell> cells, int step) {
  if (step < 0 || step >= cells.length) return 1;
  return cells[step].volume ?? 1.0;
}
