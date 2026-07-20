// lib/core/audio/tracker_song_module.dart
//
// Imports a real tracker MODULE (.mod / .s3m / .xm / .it) into an Advanced
// Tracker [TrackerSong]: every pattern, every channel, the order list, and a
// per-channel SAMPLE instrument taken from the module's own samples. Built on
// the existing readers (parseAnyModule -> ModuleDoc) and the sample bridge
// (sampleInstrumentFromDoc), so nothing about the codecs is re-implemented here.
//
// Two lossy adaptations (documented, unavoidable given the Advanced model):
//   * Per-CELL instrument columns collapse to ONE instrument per channel — we
//     pick the sample each channel plays most often. (A channel that swaps
//     samples mid-pattern keeps its notes but plays them with its dominant
//     sample.)
//   * The model uses a uniform row count across patterns, so every pattern is
//     fitted to the module's most common pattern length (MOD/S3M are all 64
//     rows -> lossless; XM/IT with mixed lengths are padded/truncated).
//
// Flutter-free -> unit-tested in test/tracker_song_module_test.dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart'
    show sampleInstrumentFromDoc;
import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// Parses raw module [bytes] and imports them (throws the reader's
/// FormatException on malformed input, so callers can show a friendly error).
TrackerSong songFromModuleBytes(Uint8List bytes) =>
    songFromModuleDoc(parseAnyModule(bytes));

/// Imports an already-parsed [ModuleDoc].
TrackerSong songFromModuleDoc(ModuleDoc doc) {
  final channelCount = doc.channelCount < 1 ? 1 : doc.channelCount;
  final rows = _modalRows(doc.patterns);
  final rep = _repInstrumentPerChannel(doc, channelCount);

  final band = <TrackerChannel>[
    for (var c = 0; c < channelCount; c++)
      TrackerChannel(
        id: 'ch${c + 1}',
        instrument: _instrumentForChannel(doc, rep[c], c),
        rows: rows,
        // The channel's dominant sample carries the module's default pan +
        // envelopes (XM/IT); convert them onto the channel so the imported
        // module plays — and shows in the editor — with its shaping intact.
        pan: _channelPan(doc, rep[c]),
        volumeEnvelope: _channelVolEnv(doc, rep[c]),
        panEnvelope: _channelPanEnv(doc, rep[c]),
      ),
  ];

  final timing = TrackerTiming(
    tempoBpm: doc.initialTempo.clamp(32, 255),
    rows: rows,
  );

  final patterns = <TrackerPattern>[
    for (var pi = 0; pi < doc.patterns.length; pi++)
      _patternFromDoc(doc.patterns[pi], channelCount, rows, pi),
  ];

  final order = [
    for (final o in doc.order)
      if (o >= 0 && o < patterns.length) o,
  ];

  // The shared instrument pool: every module sample (1-based, matching
  // DocCell.instrument), so a note plays its OWN sample via the replayer's
  // per-note render — real per-note sample fidelity, not one voice per channel.
  final pool = <TrackerInstrument>[
    for (var i = 0; i < doc.samples.length; i++)
      sampleInstrumentFromDoc('smp${i + 1}', doc.samples[i]),
  ];

  return TrackerSong.fromParts(
    channels: band,
    timing: timing,
    patterns: patterns,
    order: order,
    instruments: pool,
  );
}

/// The most common pattern row count (falls back to 64 — the MOD/S3M default).
int _modalRows(List<DocPattern> patterns) {
  if (patterns.isEmpty) return 64;
  final counts = <int, int>{};
  for (final p in patterns) {
    final n = p.numRows;
    if (n > 0) counts[n] = (counts[n] ?? 0) + 1;
  }
  if (counts.isEmpty) return 64;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// For each channel, the 1-based sample index it triggers most often (0 = none).
List<int> _repInstrumentPerChannel(ModuleDoc doc, int channelCount) {
  final counts = List.generate(channelCount, (_) => <int, int>{});
  for (final p in doc.patterns) {
    for (var r = 0; r < p.numRows; r++) {
      final row = p.rows[r];
      for (var c = 0; c < channelCount && c < row.length; c++) {
        final ins = row[c].instrument;
        if (ins > 0) counts[c][ins] = (counts[c][ins] ?? 0) + 1;
      }
    }
  }
  return [
    for (var c = 0; c < channelCount; c++)
      counts[c].isEmpty
          ? 0
          : counts[c].entries.reduce((a, b) => a.value >= b.value ? a : b).key,
  ];
}

/// XM/IT envelope x-units are ticks; at [tempo] BPM one tick is 2500/tempo ms.
double _tickMs(int tempo) => 2500.0 / (tempo < 1 ? 1 : tempo);

DocSample? _sampleFor(ModuleDoc doc, int ins) =>
    (ins >= 1 && ins - 1 <= doc.samples.length - 1)
        ? doc.samples[ins - 1]
        : null;

/// The dominant sample's default pan (0..255, 128 centre) as a channel pan
/// (−1 left … +1 right). Centre when there's no sample.
double _channelPan(ModuleDoc doc, int ins) {
  final s = _sampleFor(doc, ins);
  if (s == null) return 0.0;
  return ((s.pan - 128) / 128).clamp(-1.0, 1.0);
}

/// The dominant sample's volume envelope as a tracker [VolumeEnvelope] (ticks →
/// ms at the module tempo, value 0..64 → level 0..1). Null when there's none.
VolumeEnvelope? _channelVolEnv(ModuleDoc doc, int ins) {
  final e = _sampleFor(doc, ins)?.volumeEnvelope;
  if (e == null || e.isEmpty) return null;
  final ms = _tickMs(doc.initialTempo);
  return VolumeEnvelope([
    for (final (t, v) in e.points)
      (ms: (t * ms).round(), level: (v / 64).clamp(0.0, 1.0)),
  ]);
}

/// The dominant sample's pan envelope as a tracker [PanEnvelope] (value 0..64,
/// centred at 32, → pan −1..1). Null when there's none.
PanEnvelope? _channelPanEnv(ModuleDoc doc, int ins) {
  final e = _sampleFor(doc, ins)?.panEnvelope;
  if (e == null || e.isEmpty) return null;
  final ms = _tickMs(doc.initialTempo);
  return PanEnvelope([
    for (final (t, v) in e.points)
      (ms: (t * ms).round(), pan: ((v - 32) / 32).clamp(-1.0, 1.0)),
  ]);
}

/// A channel's instrument: its dominant module sample, else a rotating additive
/// voice so empty channels still sound distinct.
TrackerInstrument _instrumentForChannel(ModuleDoc doc, int ins, int c) {
  if (ins >= 1 && ins - 1 < doc.samples.length) {
    final sample = doc.samples[ins - 1];
    if (!sample.isEmpty) {
      return sampleInstrumentFromDoc('smp$ins', sample);
    }
  }
  const voices = [
    Instrument.piano,
    Instrument.cello,
    Instrument.flute,
    Instrument.musicBox,
  ];
  return AdditiveInstrument('ch${c + 1}', voices[c % voices.length]);
}

/// Transposes a row-major [DocPattern] into a channel-major [TrackerPattern],
/// fitting it to [rows] (extra rows dropped; short patterns padded with empties).
TrackerPattern _patternFromDoc(
  DocPattern dp,
  int channelCount,
  int rows,
  int index,
) {
  final cells = <List<TrackerCell>>[
    for (var c = 0; c < channelCount; c++)
      List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
  ];
  for (var r = 0; r < dp.numRows && r < rows; r++) {
    final row = dp.rows[r];
    for (var c = 0; c < channelCount && c < row.length; c++) {
      final dc = row[c];
      final hasFx = dc.effect != 0 || dc.effectParam != 0;
      // A volume COLUMN reduction (0..63) — carried even without a note, so a
      // mid-note volume change isn't dropped at import.
      final hasVol = dc.volume >= 0 && dc.volume < 64;
      if (dc.note >= 0 || hasFx || dc.instrument != 0 || hasVol) {
        cells[c][r] = TrackerCell(
          midi: dc.note >= 0 ? dc.note : null,
          volume: hasVol ? (dc.volume / 64).clamp(0.0, 1.0) : null,
          // MOD effect column → the replayer's classic effect column. An
          // effect-only cell (no note) is how porta/vibrato continue on a
          // ringing note.
          fxCmd: dc.effect,
          fxParam: dc.effectParam,
          // The per-cell instrument (module sample number) → the pool built in
          // songFromModuleDoc, so the note plays its own sample.
          instrument: dc.instrument,
        );
      }
      // noteOff cells stop a ring in real trackers; our model rings until the
      // next trigger, so a key-off simply leaves the cell empty.
    }
  }
  return TrackerPattern(name: index.toString().padLeft(2, '0'), cells: cells);
}

// ── Export: TrackerSong → neutral ModuleDoc (PCM-preserving) ─────────────────
//
// The Advanced Tracker's other export path routes through a Score, which has no
// PCM and no effect column — so a recorded/loaded sample becomes a re-synthesized
// timbre and authored effects drop. [moduleDocFromSong] converts DIRECTLY:
//   * each SampleInstrument keeps its ACTUAL waveform (its `.sample` PCM), with
//     the tuning baked into `c5speed` so it re-imports at the right pitch;
//   * procedural voices (additive/sfxr/FM/…), which have no PCM, are rendered to
//     a short base-note (C-5 / MIDI 60) one-shot sample;
//   * the effect column (`fxCmd`/`fxParam`) rides through 1:1 (MOD numbering).
// Pair with the writers to get bytes: `convertToMod/Xm/S3m/It(moduleDocFromSong(
// song))`. XM/S3M/IT keep 16-bit samples; `.mod` is 8-bit (its waveform is still
// the real one, just quantised).

/// Convert [song] to a [ModuleDoc], preserving sample PCM + the effect column.
/// [sixteenBit] stores the samples at 16-bit depth where the container supports
/// it (XM/IT/S3M — MOD is always 8-bit); default true keeps app-recorded audio
/// at full precision. Pass false for a smaller, classic 8-bit export.
ModuleDoc moduleDocFromSong(
  TrackerSong song, {
  int engineRate = kSampleRate,
  bool sixteenBit = true,
}) {
  song.syncCurrent();
  final channelCount = song.channels.length;

  // Distinct instruments → 1-based module samples (channel defaults first, then
  // the per-cell pool). identical() so a shared voice isn't duplicated.
  final insts = <TrackerInstrument>[];
  int slotOf(TrackerInstrument i) {
    final at = insts.indexWhere((e) => identical(e, i));
    if (at >= 0) return at;
    insts.add(i);
    return insts.length - 1;
  }

  for (final ch in song.channels) {
    slotOf(ch.instrument);
  }
  for (final p in song.instruments) {
    slotOf(p);
  }

  // Carry each channel's envelope onto its instrument's sample (export). XM/IT
  // hold envelopes per instrument, so when several channels share one voice the
  // first with an envelope wins.
  final volEnvBySlot = <int, VolumeEnvelope>{};
  final panEnvBySlot = <int, PanEnvelope>{};
  final panBySlot = <int, double>{};
  for (final ch in song.channels) {
    final slot = slotOf(ch.instrument);
    panBySlot.putIfAbsent(slot, () => ch.pan);
    final ve = ch.volumeEnvelope;
    if (ve != null && !ve.isEmpty) volEnvBySlot.putIfAbsent(slot, () => ve);
    final pe = ch.panEnvelope;
    if (pe != null && !pe.isEmpty) panEnvBySlot.putIfAbsent(slot, () => pe);
  }
  final tempo = song.timing.tempoBpm.clamp(32, 255);

  TrackerInstrument effectiveInst(int channel, TrackerCell cell) =>
      (cell.instrument > 0 && cell.instrument - 1 < song.instruments.length)
          ? song.instruments[cell.instrument - 1]
          : song.channels[channel].instrument;

  final patterns = <DocPattern>[];
  for (final pat in song.patterns) {
    final numRows = pat.cells.isEmpty ? 0 : pat.cells.first.length;
    final rows = <List<DocCell>>[];
    for (var r = 0; r < numRows; r++) {
      final row = <DocCell>[];
      for (var c = 0; c < channelCount; c++) {
        final cell = pat.cells[c][r];
        if (cell.midi == null && cell.fxCmd == 0 && cell.volume == null) {
          row.add(DocCell.empty);
          continue;
        }
        final vol =
            cell.volume == null ? -1 : (cell.volume! * 64).round().clamp(0, 64);
        row.add(
          DocCell(
            note: cell.midi ?? -1,
            // Instrument attaches to a note; an effect-only cell carries none.
            instrument:
                cell.midi == null ? 0 : slotOf(effectiveInst(c, cell)) + 1,
            volume: vol,
            effect: cell.fxCmd,
            effectParam: cell.fxParam,
          ),
        );
      }
      rows.add(row);
    }
    patterns.add(DocPattern(rows, channelCount));
  }

  return ModuleDoc(
    channelCount: channelCount,
    sourceFormat: ModuleFormat.mod,
    initialTempo: song.timing.tempoBpm.clamp(32, 255),
    order: List<int>.of(song.order),
    patterns: patterns,
    samples: [
      for (var k = 0; k < insts.length; k++)
        _docSampleForInstrument(
          insts[k],
          engineRate,
          sixteenBit,
          pan: _docPan(panBySlot[k]),
          volumeEnvelope: _docVolEnv(volEnvBySlot[k], tempo),
          panEnvelope: _docPanEnv(panEnvBySlot[k], tempo),
        ),
    ],
  );
}

/// A tracker [VolumeEnvelope] as a doc [DocEnvelope] (ms → ticks at [tempo] BPM,
/// level 0..1 → value 0..64). Empty when there's none.
DocEnvelope _docVolEnv(VolumeEnvelope? e, int tempo) {
  if (e == null || e.isEmpty) return const DocEnvelope();
  final perTick = _tickMs(tempo);
  return DocEnvelope(
    enabled: true,
    points: [
      for (final p in e.points)
        ((p.ms / perTick).round(), (p.level * 64).round().clamp(0, 64)),
    ],
  );
}

/// A tracker [PanEnvelope] as a doc [DocEnvelope] (pan −1..1 → value 0..64,
/// centred at 32). Empty when there's none.
DocEnvelope _docPanEnv(PanEnvelope? e, int tempo) {
  if (e == null || e.isEmpty) return const DocEnvelope();
  final perTick = _tickMs(tempo);
  return DocEnvelope(
    enabled: true,
    points: [
      for (final p in e.points)
        ((p.ms / perTick).round(), (p.pan * 32 + 32).round().clamp(0, 64)),
    ],
  );
}

/// One module [DocSample] for [inst]: a [SampleInstrument] keeps its real PCM
/// (tuning baked into c5speed); any other voice is rendered to a base-note
/// (MIDI 60) one-shot.
/// A channel pan (−1..1) as a doc default pan (0..255, 128 centre). Centre when
/// null (no channel used the instrument).
int _docPan(double? p) =>
    p == null ? 128 : (p * 128 + 128).round().clamp(0, 255);

DocSample _docSampleForInstrument(
  TrackerInstrument inst,
  int engineRate,
  bool sixteenBit, {
  int pan = 128,
  DocEnvelope volumeEnvelope = const DocEnvelope(),
  DocEnvelope panEnvelope = const DocEnvelope(),
}) {
  if (inst is SampleInstrument && inst.sample.isNotEmpty) {
    // Import plays a sample unshifted at MIDI 60 with ratio = c5speed/engineRate,
    // so to preserve the instrument's own baseMidi we set the rate that shifts
    // it onto the 60 reference: ratio = 2^((60 - baseMidi)/12).
    final ratio = pow(2, (60 - inst.baseMidi) / 12).toDouble();
    return DocSample(
      pcm: Float64List.fromList(inst.sample),
      c5speed: (engineRate * ratio).round(),
      loopStart: (inst.loopStart * ratio).round(),
      loopLength: (inst.loopLength * ratio).round(),
      pingPong: inst.pingPong,
      // Full precision where the format allows (XM/IT/S3M); MOD stays 8-bit.
      sixteenBit: sixteenBit,
      pan: pan,
      volumeEnvelope: volumeEnvelope,
      panEnvelope: panEnvelope,
    );
  }
  // A procedural voice has no PCM → render ~1s of MIDI 60 as a one-shot sample.
  const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
  final cells = [
    const TrackerCell(midi: 60),
    ...List<TrackerCell>.filled(3, TrackerCell.empty),
  ];
  final pcm = inst.renderChannel(cells, timing);
  return DocSample(
    pcm: _trimTrailingSilence(pcm),
    c5speed: engineRate,
    sixteenBit: sixteenBit,
    pan: pan,
    volumeEnvelope: volumeEnvelope,
    panEnvelope: panEnvelope,
  );
}

/// Drop a trailing run of near-silence (keeps rendered one-shots compact).
Float64List _trimTrailingSilence(Float64List pcm, {double threshold = 1e-4}) {
  var end = pcm.length;
  while (end > 1 && pcm[end - 1].abs() < threshold) {
    end--;
  }
  return end == pcm.length ? pcm : Float64List.sublistView(pcm, 0, end);
}
