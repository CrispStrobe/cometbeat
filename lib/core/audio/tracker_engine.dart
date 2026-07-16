// lib/core/audio/tracker_engine.dart
//
// Pure-Dart pattern-sequencer engine behind the Tracker (a touch-first take on
// ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker). A tracker is
// the Loop Mixer with an EDITABLE grid: each channel is a column of cells
// (one per row/step); rendering sums the channels through the same
// offline-mix-then-loop path the Loop Mixer uses (mixStems -> one seamless WAV,
// one player, sample-accurate sync). Flutter-free, like synth.dart /
// loop_engine.dart — unit-tested without a device.
//
// Slice 0 ships ADDITIVE instruments only (the built-in synth timbres). The
// [TrackerInstrument] abstraction is the seam where sfxr-generated and
// recorded/effected sample instruments plug in later (see
// docs/TRACKER_HANDOVER.md) without changing the engine.

import 'dart:math';
import 'dart:typed_data';

import 'package:klang_universum/core/audio/crisp_dsp/sfxr.dart';
import 'package:klang_universum/core/audio/synth.dart';

/// The musical clock a pattern renders against. [rows] steps at [stepsPerBeat]
/// steps per beat, [tempoBpm] BPM. Pick values whose step length is an integral
/// number of ms (and of samples at 44.1 kHz) so every channel sums to exactly
/// the same sample count and the loop seam stays click-free — e.g. 120 BPM with
/// 4 steps/beat gives a 125 ms step. (Non-integral choices still play; they just
/// lean on mixStems' shorter-stem padding.)
class TrackerTiming {
  const TrackerTiming({
    this.tempoBpm = 120,
    this.rows = 16,
    this.stepsPerBeat = 4,
  })  : assert(tempoBpm > 0),
        assert(rows > 0),
        assert(stepsPerBeat > 0);

  final int tempoBpm;
  final int rows;
  final int stepsPerBeat;

  int get beatMs => 60000 ~/ tempoBpm;
  int get stepMs => beatMs ~/ stepsPerBeat;
  int get totalMs => stepMs * rows;
  int get totalSamples => (totalMs * kSampleRate) ~/ 1000;
  Duration get loopLength => Duration(milliseconds: totalMs);

  TrackerTiming copyWith({int? tempoBpm, int? rows, int? stepsPerBeat}) =>
      TrackerTiming(
        tempoBpm: tempoBpm ?? this.tempoBpm,
        rows: rows ?? this.rows,
        stepsPerBeat: stepsPerBeat ?? this.stepsPerBeat,
      );
}

/// One step in a channel column. An empty cell means "no trigger here" — it
/// either extends the previous note (let it ring) or is a rest if nothing is
/// sounding. [volume] (0..1) is reserved for the Studio skin; Slice 0 ignores it
/// and uses the channel gain.
class TrackerCell {
  const TrackerCell({this.midi, this.volume});

  final int? midi;
  final double? volume;

  bool get isEmpty => midi == null;

  static const empty = TrackerCell();

  @override
  bool operator ==(Object other) =>
      other is TrackerCell && other.midi == midi && other.volume == volume;

  @override
  int get hashCode => Object.hash(midi, volume);
}

/// Collapses a channel's cells into runs using the classic tracker rule: a
/// non-empty cell triggers a note that rings across itself and every
/// immediately-following empty cell (until the next trigger); leading empties
/// are a rest. Each run is `(midi?, steps)` — `midi == null` is a rest. Runs sum
/// to exactly [TrackerTiming.rows] steps.
List<(int?, int)> cellRuns(List<TrackerCell> cells) {
  final runs = <(int?, int)>[];
  for (final cell in cells) {
    if (cell.isEmpty) {
      if (runs.isEmpty) {
        runs.add((null, 1)); // leading rest
      } else {
        final (m, s) = runs.last;
        runs[runs.length - 1] = (m, s + 1); // extend previous note or rest
      }
    } else {
      runs.add((cell.midi, 1));
    }
  }
  return runs;
}

/// The runs of [cells] as back-to-back [Segment]s (for the additive voices).
List<Segment> cellsToSegments(List<TrackerCell> cells, TrackerTiming timing) =>
    [
      for (final (midi, steps) in cellRuns(cells))
        (
          freqs: midi == null ? const <double>[] : [midiToFrequency(midi)],
          ms: steps * timing.stepMs,
        ),
    ];

/// How a channel's cells become an un-normalized sample buffer. The seam for
/// non-additive instruments (sfxr, recorded samples) added in later slices.
abstract class TrackerInstrument {
  String get id;

  /// Render [cells] onto a buffer sized ~[TrackerTiming.totalSamples] (mixStems
  /// tolerates a shorter stem and pads it). Must not normalize — mixStems sets
  /// levels.
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing);
}

/// The Slice 0 instrument: one of the built-in additive [Instrument] voices.
class AdditiveInstrument implements TrackerInstrument {
  const AdditiveInstrument(this.id, this.instrument);

  @override
  final String id;
  final Instrument instrument;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) =>
      renderSegmentsRaw(
        cellsToSegments(cells, timing),
        timbre: timbreFor(instrument),
      );
}

/// A chiptune instrument: an sfxr preset (a frozen [SfxrParams]) synthesized at
/// each note's pitch (sfxr's `baseFreq` is set to the note frequency ÷ 440).
/// Every note is a one-shot that decays within its run — the classic tracker
/// sampled-voice feel. Deterministic via [seed] so the stem cache is stable.
class SfxrInstrument implements TrackerInstrument {
  const SfxrInstrument(this.id, this.params, {this.seed = 0});

  /// Builds an instrument from a named [SfxrPreset], freezing it with [seed].
  factory SfxrInstrument.preset(String id, SfxrPreset preset, {int seed = 0}) =>
      SfxrInstrument(id, preset(Random(seed)), seed: seed);

  @override
  final String id;
  final SfxrParams params;
  final int seed;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    final rng = Random(seed);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final startSample = (startStep * timing.stepMs * kSampleRate) ~/ 1000;
        final buf = sfxrGenerate(
          params.copyWith(baseFreq: midiToFrequency(midi) / 440),
          durationSec: steps * timing.stepMs / 1000,
          rng: rng,
        );
        final n = min(buf.length, out.length - startSample);
        for (var i = 0; i < n; i++) {
          out[startSample + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// One editable column: an [instrument], an authored mix [gain], and [rows]
/// cells. Levels are combo-independent (each channel carries its gain into
/// mixStems' unit-peak-per-stem + soft-limiter mixdown), so editing one channel
/// never changes how loud the others are.
class TrackerChannel {
  TrackerChannel({
    required this.id,
    required this.instrument,
    required int rows,
    this.gain = 0.6,
    List<TrackerCell>? cells,
  }) : cells = cells != null
            ? List<TrackerCell>.of(cells)
            : List<TrackerCell>.filled(
                rows,
                TrackerCell.empty,
                growable: true,
              ) {
    assert(this.cells.length == rows, 'cells must be exactly $rows long');
  }

  final String id;
  final TrackerInstrument instrument;
  final double gain;
  final List<TrackerCell> cells;

  bool get hasAnyNote => cells.any((c) => !c.isEmpty);
}

/// Default Sandbox band: melodic additive voices plus one sfxr chiptune lead
/// (all pentatonic-friendly so the scale-locked kid grid always grooves). Drums
/// arrive with the percussion instrument in a later slice.
List<TrackerChannel> defaultTrackerChannels({int rows = 16}) => [
      TrackerChannel(
        id: 'melody',
        instrument: const AdditiveInstrument('piano', Instrument.piano),
        gain: 0.55,
        rows: rows,
      ),
      TrackerChannel(
        id: 'sparkle',
        instrument: const AdditiveInstrument('musicBox', Instrument.musicBox),
        gain: 0.40,
        rows: rows,
      ),
      TrackerChannel(
        id: 'zap',
        instrument: SfxrInstrument.preset('zap', sfxrZap, seed: 7),
        gain: 0.45,
        rows: rows,
      ),
      TrackerChannel(
        id: 'bass',
        instrument: const AdditiveInstrument('cello', Instrument.cello),
        gain: 0.55,
        rows: rows,
      ),
    ];

/// Holds the pattern (channels × rows) + timing, edits cells, and renders the
/// current pattern to a loop-ready WAV. Caches per-channel stems and the mixed
/// WAV so an edit only re-synthesizes the channel that changed.
class TrackerEngine {
  TrackerEngine({List<TrackerChannel>? channels, TrackerTiming? timing})
      : _timing = timing ?? const TrackerTiming(),
        channels = channels ??
            defaultTrackerChannels(
              rows: (timing ?? const TrackerTiming()).rows,
            ) {
    for (final c in this.channels) {
      assert(
        c.cells.length == _timing.rows,
        'channel "${c.id}" has ${c.cells.length} cells, expected '
        '${_timing.rows}',
      );
    }
  }

  final List<TrackerChannel> channels;

  TrackerTiming _timing;
  TrackerTiming get timing => _timing;
  set timing(TrackerTiming value) {
    _timing = value;
    _stemCache.clear();
    _wav = null;
  }

  // Rendered stem per channel index (at the current timing) and the mixed WAV.
  final Map<int, Float64List> _stemCache = {};
  Uint8List? _wav;

  int get rows => _timing.rows;

  TrackerCell cellAt(int channel, int row) => channels[channel].cells[row];

  /// Sets [row] of [channel] to [cell] and invalidates the affected caches.
  void setCell(int channel, int row, TrackerCell cell) {
    final cells = channels[channel].cells;
    if (cells[row] == cell) return;
    cells[row] = cell;
    _stemCache.remove(channel);
    _wav = null;
  }

  void clearCell(int channel, int row) =>
      setCell(channel, row, TrackerCell.empty);

  /// Tap-to-place/remove for the grid: placing [midi] where the same note
  /// already sits clears it; otherwise sets it. Returns the note now at the cell
  /// (null if cleared).
  int? toggleNote(int channel, int row, int midi) {
    final current = channels[channel].cells[row];
    if (current.midi == midi) {
      clearCell(channel, row);
      return null;
    }
    setCell(channel, row, TrackerCell(midi: midi));
    return midi;
  }

  /// Clears every cell in every channel.
  void clearAll() {
    for (final c in channels) {
      for (var i = 0; i < c.cells.length; i++) {
        c.cells[i] = TrackerCell.empty;
      }
    }
    _stemCache.clear();
    _wav = null;
  }

  bool get isEmpty => channels.every((c) => !c.hasAnyNote);

  Float64List _stem(int channel) => _stemCache[channel] ??= channels[channel]
      .instrument
      .renderChannel(channels[channel].cells, _timing);

  /// The current pattern as one loop-ready WAV. An empty pattern renders silence
  /// of the full loop length.
  Uint8List renderLoop() {
    return _wav ??= wavBytes(
      mixStems(
        [
          for (var i = 0; i < channels.length; i++)
            if (channels[i].hasAnyNote)
              (samples: _stem(i), gain: channels[i].gain),
        ],
        totalSamples: _timing.totalSamples,
      ),
    );
  }
}
