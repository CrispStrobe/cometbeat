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

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_effects.dart';

export 'package:comet_beat/core/audio/tracker_effects.dart' show TrackerEffect;

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
  const TrackerCell({
    this.midi,
    this.volume,
    this.effect = TrackerEffect.none,
  });

  final int? midi;
  final double? volume;

  /// A per-note effect command (arp/vibrato/slide). Honoured by additive voices
  /// (see [AdditiveInstrument]); other instruments ignore it.
  final TrackerEffect effect;

  bool get isEmpty => midi == null;

  static const empty = TrackerCell();

  @override
  bool operator ==(Object other) =>
      other is TrackerCell &&
      other.midi == midi &&
      other.volume == volume &&
      other.effect == effect;

  @override
  int get hashCode => Object.hash(midi, volume, effect);
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
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final timbre = timbreFor(instrument);
    // Fast path: no per-note effects → the plain whole-channel additive render.
    final hasEffect =
        cells.any((c) => !c.isEmpty && c.effect != TrackerEffect.none);
    if (!hasEffect) {
      return renderSegmentsRaw(cellsToSegments(cells, timing), timbre: timbre);
    }
    // Effect path: render each note's run on its own so its effect can modulate
    // the frequency during synthesis, then place it on the timeline.
    final out = Float64List(timing.totalSamples);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final start = (startStep * timing.stepMs * kSampleRate) ~/ 1000;
        final ms = steps * timing.stepMs;
        final effect = cells[startStep].effect;
        final buf = effect == TrackerEffect.none
            ? renderSegmentsRaw(
                [
                  (freqs: [midiToFrequency(midi)], ms: ms),
                ],
                timbre: timbre,
              )
            : renderNoteWithEffect(midi, ms, effect, timbre: timbre);
        final n = min(buf.length, out.length - start);
        for (var i = 0; i < n; i++) {
          out[start + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
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

/// A sampled instrument: a recorded (optionally voice-effected) buffer played at
/// each note's pitch by classic tracker resampling — `ratio = noteFreq /
/// baseFreq`, so a higher note plays the sample faster (higher, shorter). The
/// note is capped at its run length (a one-shot note-off). [baseMidi] is the
/// pitch the recorded sample represents (default C4). This is the payload behind
/// "record your voice → play a tune with it".
class SampleInstrument implements TrackerInstrument {
  const SampleInstrument(this.id, this.sample, {this.baseMidi = 60});

  /// Records-once: applies [fx] to [raw] and keeps the result as the sample.
  factory SampleInstrument.recorded(
    String id,
    Float64List raw,
    VoiceEffect fx, {
    int baseMidi = 60,
    int sampleRate = kSampleRate,
  }) =>
      SampleInstrument(
        id,
        applyVoiceEffect(raw, fx, sampleRate: sampleRate),
        baseMidi: baseMidi,
      );

  @override
  final String id;
  final Float64List sample;
  final int baseMidi;

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    if (sample.isEmpty) return out;
    final baseFreq = midiToFrequency(baseMidi);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final startSample = (startStep * timing.stepMs * kSampleRate) ~/ 1000;
        final runSamples = (steps * timing.stepMs * kSampleRate) ~/ 1000;
        final buf = resampleCubic(sample, midiToFrequency(midi) / baseFreq);
        final n = min(min(buf.length, runSamples), out.length - startSample);
        for (var i = 0; i < n; i++) {
          out[startSample + i] = buf[i];
        }
      }
      startStep += steps;
    }
    return out;
  }
}

/// A drum instrument: each non-empty cell is a one-shot hit (not held), the
/// cell's [TrackerCell.midi] encoding the [Drum] index (0 kick, 1 snare, 2 hat).
/// Renders via the Loop Mixer's noise percussion. Its rows are drums, not
/// pitches — the screen renders it with a drum row model.
class PercussionInstrument implements TrackerInstrument {
  const PercussionInstrument(this.id);

  @override
  final String id;

  /// The drums, ordered top row → bottom row on the grid.
  static const rows = [Drum.hat, Drum.snare, Drum.kick];

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final hits = <(int, Drum)>[];
    for (var step = 0; step < cells.length; step++) {
      final midi = cells[step].midi;
      if (midi != null) {
        final idx = midi.clamp(0, Drum.values.length - 1);
        hits.add((step * timing.stepMs, Drum.values[idx]));
      }
    }
    return renderDrumPattern(hits, totalMs: timing.totalMs);
  }
}

/// An optional insert effect applied to a channel's stem (before mixStems).
enum TrackerChannelEffect { none, delay, chorus, flanger, reverb }

/// Applies [fx] to a channel [stem] with kid-friendly default params, returning a
/// SAME-LENGTH buffer (so stems still line up for mixStems). [TrackerChannelEffect.none]
/// returns the stem unchanged.
Float64List applyChannelEffect(
  Float64List stem,
  TrackerChannelEffect fx, {
  int sampleRate = kSampleRate,
}) =>
    // The DSP functions' own defaults are the tuned kid-friendly params; only the
    // few overrides that differ from those defaults are passed here.
    switch (fx) {
      TrackerChannelEffect.none => stem,
      TrackerChannelEffect.delay => delayFx(
          stem,
          delayMs: 200,
          feedback: 0.3,
          mix: 0.3,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.chorus => chorusFx(
          stem,
          rateHz: 1.2,
          mix: 0.4,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.flanger => flangerFx(
          stem,
          mix: 0.4,
          sampleRate: sampleRate,
        ),
      TrackerChannelEffect.reverb => reverbFx(stem, sampleRate: sampleRate),
    };

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
    this.effect = TrackerChannelEffect.none,
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

  /// Mutable so a channel can be re-voiced at runtime (e.g. assigning a freshly
  /// recorded [SampleInstrument] to the voice channel). Go through
  /// [TrackerEngine.setChannelInstrument] so caches are invalidated.
  TrackerInstrument instrument;
  final double gain;

  /// Mutable insert effect on this channel's stem. Go through
  /// [TrackerEngine.setChannelEffect] so caches are invalidated.
  TrackerChannelEffect effect;
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
      TrackerChannel(
        id: 'drums',
        instrument: const PercussionInstrument('drums'),
        gain: 0.50,
        rows: rows,
      ),
      // Empty until the child records into it (renders silence meanwhile).
      TrackerChannel(
        id: 'voice',
        instrument: SampleInstrument('voice', Float64List(0)),
        rows: rows,
      ),
    ];

/// A selectable voice for the instrument picker: a stable [id] (matches the
/// built instrument's `id`, for highlighting the current choice + tests) and a
/// factory. Additive timbres + a curated sfxr palette; the recorded `voice`
/// instrument stays off the picker (it's set by recording).
class InstrumentOption {
  const InstrumentOption(this.id, this.build);

  final String id;
  final TrackerInstrument Function() build;
}

/// The picker palette: four additive voices + five chiptune presets.
final List<InstrumentOption> kTrackerInstruments = [
  InstrumentOption(
    'piano',
    () => const AdditiveInstrument('piano', Instrument.piano),
  ),
  InstrumentOption(
    'cello',
    () => const AdditiveInstrument('cello', Instrument.cello),
  ),
  InstrumentOption(
    'flute',
    () => const AdditiveInstrument('flute', Instrument.flute),
  ),
  InstrumentOption(
    'musicBox',
    () => const AdditiveInstrument('musicBox', Instrument.musicBox),
  ),
  InstrumentOption('zap', () => SfxrInstrument.preset('zap', sfxrZap, seed: 7)),
  InstrumentOption(
    'blip',
    () => SfxrInstrument.preset('blip', sfxrBlip, seed: 3),
  ),
  InstrumentOption(
    'laser',
    () => SfxrInstrument.preset('laser', sfxrLaser, seed: 5),
  ),
  InstrumentOption(
    'coin',
    () => SfxrInstrument.preset('coin', sfxrCoin, seed: 11),
  ),
  InstrumentOption(
    'explosion',
    () => SfxrInstrument.preset('explosion', sfxrExplosion, seed: 13),
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

  /// Re-voices [channel] (e.g. assigning a freshly recorded [SampleInstrument])
  /// and invalidates that channel's cached stem + the mixed WAV.
  void setChannelInstrument(int channel, TrackerInstrument instrument) {
    channels[channel].instrument = instrument;
    _stemCache.remove(channel);
    _wav = null;
  }

  /// Sets a channel's insert [effect] (applied to its stem before mixStems) and
  /// invalidates that channel's cached stem + the mixed WAV.
  void setChannelEffect(int channel, TrackerChannelEffect effect) {
    channels[channel].effect = effect;
    _stemCache.remove(channel);
    _wav = null;
  }

  /// Replaces every cell of [channel] with [cells] (same length as the row
  /// count) — used to import a whole pattern (e.g. a Score). Invalidates caches.
  void setChannelCells(int channel, List<TrackerCell> cells) {
    final target = channels[channel].cells;
    assert(cells.length == target.length, 'cells length must match rows');
    for (var i = 0; i < target.length; i++) {
      target[i] = cells[i];
    }
    _stemCache.remove(channel);
    _wav = null;
  }

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

  /// Sets the [volume] (a soft/ghost note, 0..1; null = normal) of the note at
  /// [row]. No-op on an empty cell — only notes carry dynamics.
  void setCellVolume(int channel, int row, double? volume) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      TrackerCell(midi: cur.midi, volume: volume, effect: cur.effect),
    );
  }

  /// Sets the per-note [effect] of the note at [row]. No-op on an empty cell.
  void setCellEffect(int channel, int row, TrackerEffect effect) {
    final cur = channels[channel].cells[row];
    if (cur.isEmpty) return;
    setCell(
      channel,
      row,
      TrackerCell(midi: cur.midi, volume: cur.volume, effect: effect),
    );
  }

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

  Float64List _stem(int channel) =>
      _stemCache[channel] ??= _renderWithDynamics(channel);

  /// Renders a channel, then scales each note's sample range by that note's
  /// [TrackerCell.volume] (a soft/ghost note) — a renderer-agnostic volume
  /// column: additive, sfxr, sampled and percussion voices all honour it.
  Float64List _renderWithDynamics(int channel) {
    final ch = channels[channel];
    final buf = ch.instrument.renderChannel(ch.cells, _timing);
    var startStep = 0;
    for (final (midi, steps) in cellRuns(ch.cells)) {
      final vol = midi != null ? ch.cells[startStep].volume : null;
      if (vol != null && vol != 1.0) {
        final start = (startStep * _timing.stepMs * kSampleRate) ~/ 1000;
        final end =
            ((startStep + steps) * _timing.stepMs * kSampleRate) ~/ 1000;
        for (var i = start; i < end && i < buf.length; i++) {
          buf[i] *= vol;
        }
      }
      startStep += steps;
    }
    return applyChannelEffect(buf, ch.effect);
  }

  /// The current pattern mixed to PCM16 (one loop's worth). Used by [renderLoop]
  /// and by [renderSong] (which concatenates one per order-list entry).
  Int16List renderLoopPcm() => mixStems(
        [
          for (var i = 0; i < channels.length; i++)
            if (channels[i].hasAnyNote)
              (samples: _stem(i), gain: channels[i].gain),
        ],
        totalSamples: _timing.totalSamples,
      );

  /// The current pattern as one loop-ready WAV. An empty pattern renders silence
  /// of the full loop length.
  Uint8List renderLoop() => _wav ??= wavBytes(renderLoopPcm());

  /// A deep copy of every channel's cells — a pattern snapshot for arrangement.
  List<List<TrackerCell>> exportCells() =>
      [for (final c in channels) List<TrackerCell>.of(c.cells)];

  /// Loads a snapshot from [exportCells] back into the channels.
  void importCells(List<List<TrackerCell>> data) {
    for (var i = 0; i < channels.length && i < data.length; i++) {
      setChannelCells(i, data[i]);
    }
  }
}

/// Renders a song: the [patterns] (each a snapshot from [TrackerEngine.
/// exportCells]) played back-to-back into one long loop-ready WAV — the
/// arrangement / order-list. Uses [engine]'s band + timing; the engine's live
/// pattern is saved and restored, so this is side-effect-free to the caller.
Uint8List renderSong(
  TrackerEngine engine,
  List<List<List<TrackerCell>>> patterns,
) {
  if (patterns.isEmpty) return wavBytes(Int16List(0));
  final saved = engine.exportCells();
  final chunks = <Int16List>[];
  for (final pattern in patterns) {
    engine.importCells(pattern);
    chunks.add(engine.renderLoopPcm());
  }
  engine.importCells(saved);

  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Int16List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return wavBytes(out);
}
