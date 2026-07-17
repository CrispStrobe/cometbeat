// lib/core/audio/mod/mod_bridge.dart
//
// The Tracker ↔ ProTracker-MOD bridge (lossy by nature). Maps a parsed
// [ModModule] onto the Tracker's pattern snapshots + sampled instruments, and
// back. Pure Dart — reuses TrackerCell/SampleInstrument/TrackerInstrument from
// tracker_engine.dart and the period↔MIDI helpers from mod_module.dart.
//
// TO BE IMPLEMENTED BY A SUB-AGENT against the contract below and the tests in
// test/mod_bridge_test.dart.
//
// ─── Mapping rules (documented approximations) ──────────────────────────────
// IMPORT (modToTracker):
//   • One tracker pattern snapshot per song position (order entry → mod
//     pattern). channelCount = mod.channelCount.
//   • Quantize the 64 mod rows → [rows] tracker steps: tracker step `s` reads mod
//     row `(s * 64) ~/ rows`. A mod cell's period → MIDI via `periodToMidi`
//     (period 0 → empty cell); the tracker cell holds that MIDI.
//   • channelInstruments[c] = a [SampleInstrument] built from the mod sample most
//     often played in mod channel c (fallback: an AdditiveInstrument('piano',…)
//     if the channel plays no sample). PCM: Int8 → Float64 via `v / 128`.
//     baseMidi = [modBridgeBaseMidi].
//   • tempoBpm: default 120 (mod tempo lives in effect commands; approximate).
// EXPORT (trackerToMod):
//   • One mod pattern (64 rows) per tracker pattern snapshot; tracker step `s`
//     writes mod row `(s * 64) ~/ rows`, the rest empty. MIDI → period via
//     `midiToPeriod`; sample number = the channel's instrument index (1-based).
//   • Each SampleInstrument channel → one mod sample (Float64 → Int8 via
//     `(v * 127)`), in channel order (≤ 31). Non-sample channels get an empty
//     sample slot. order = [0,1,2,…] over the patterns.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod_module.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// The MIDI note a raw imported sample is treated as playing at (≈ C-3).
const int modBridgeBaseMidi = modNoteBaseMidi + 24;

/// The result of importing a module into the Tracker.
class ModImport {
  const ModImport({
    required this.patterns,
    required this.channelInstruments,
    required this.channelCount,
    this.tempoBpm = 120,
  });

  /// `patterns[songPosition][channel]` → that channel's cells (length = rows).
  final List<List<List<TrackerCell>>> patterns;

  /// One instrument per channel (a [SampleInstrument] where the mod channel
  /// played a sample, else a fallback additive voice).
  final List<TrackerInstrument> channelInstruments;

  final int channelCount;
  final int tempoBpm;
}

/// Imports [mod] into tracker pattern snapshots + per-channel instruments.
ModImport modToTracker(ModModule mod, {int rows = 8, int stepsPerBeat = 2}) {
  final channelCount = mod.channelCount;

  // ── Pattern snapshots: one per song position, quantized 64 rows → `rows`. ──
  final patterns = <List<List<TrackerCell>>>[];
  // Tally, per channel, how often each mod sample number (1..31) is played, so
  // we can pick each channel's dominant sample for its instrument.
  final sampleTallies = List.generate(channelCount, (_) => <int, int>{});

  for (final patternIndex in mod.order) {
    final pattern = (patternIndex >= 0 && patternIndex < mod.patterns.length)
        ? mod.patterns[patternIndex]
        : null;

    final snapshot = <List<TrackerCell>>[];
    for (var c = 0; c < channelCount; c++) {
      final cells = <TrackerCell>[];
      for (var s = 0; s < rows; s++) {
        final modRow = (s * 64) ~/ rows;
        final cell = _cellAt(pattern, modRow, c);
        if (cell == null || cell.period <= 0) {
          cells.add(TrackerCell.empty);
        } else {
          cells.add(TrackerCell(midi: periodToMidi(cell.period)));
        }
      }
      snapshot.add(cells);
    }
    patterns.add(snapshot);

    // Tally sample usage across the full 64-row pattern (all triggers count).
    if (pattern != null) {
      for (final row in pattern.rows) {
        for (var c = 0; c < channelCount && c < row.length; c++) {
          final s = row[c].sample;
          if (s > 0) {
            sampleTallies[c][s] = (sampleTallies[c][s] ?? 0) + 1;
          }
        }
      }
    }
  }

  // ── Per-channel instruments: dominant mod sample → SampleInstrument. ──
  final channelInstruments = <TrackerInstrument>[];
  for (var c = 0; c < channelCount; c++) {
    final tally = sampleTallies[c];
    var bestSample = 0;
    var bestCount = 0;
    tally.forEach((sample, count) {
      if (count > bestCount) {
        bestCount = count;
        bestSample = sample;
      }
    });

    if (bestSample >= 1 && bestSample <= mod.samples.length) {
      final modSample = mod.samples[bestSample - 1];
      final pcm = modSample.pcm;
      final data = Float64List(pcm.length);
      for (var i = 0; i < pcm.length; i++) {
        data[i] = pcm[i] / 128.0;
      }
      final id =
          modSample.name.isNotEmpty ? modSample.name : 'mod-sample$bestSample';
      channelInstruments.add(
        SampleInstrument(id, data, baseMidi: modBridgeBaseMidi),
      );
    } else {
      channelInstruments.add(
        const AdditiveInstrument('piano', Instrument.piano),
      );
    }
  }

  return ModImport(
    patterns: patterns,
    channelInstruments: channelInstruments,
    channelCount: channelCount,
  );
}

/// The cell in [pattern] at mod [row]/[channel], or null if out of range.
ModCell? _cellAt(ModPattern? pattern, int row, int channel) {
  if (pattern == null) return null;
  if (row < 0 || row >= pattern.rows.length) return null;
  final cells = pattern.rows[row];
  if (channel < 0 || channel >= cells.length) return null;
  return cells[channel];
}

/// Exports tracker [patterns] (each `[channel][cells]`) + their
/// [channelInstruments] to a [ModModule]. `rows` = cells per channel.
ModModule trackerToMod(
  List<List<List<TrackerCell>>> patterns, {
  required List<TrackerInstrument> channelInstruments,
  int rows = 8,
  String title = 'KLANGTRK',
}) {
  final channelCount = channelInstruments.length;

  // ── Patterns: one 64-row mod pattern per tracker snapshot. ──
  final modPatterns = <ModPattern>[];
  for (final snapshot in patterns) {
    final modRows = List.generate(
      64,
      (_) => List<ModCell>.filled(channelCount, ModCell.empty),
    );
    for (var c = 0; c < channelCount; c++) {
      final cells = c < snapshot.length ? snapshot[c] : const <TrackerCell>[];
      for (var s = 0; s < cells.length; s++) {
        final cell = cells[s];
        final midi = cell.midi;
        if (midi == null) continue;
        final modRow = (s * 64) ~/ rows;
        if (modRow < 0 || modRow >= 64) continue;
        // sample number = the channel's 1-based instrument index.
        modRows[modRow][c] = ModCell(
          sample: c + 1,
          period: midiToPeriod(midi),
        );
      }
    }
    modPatterns.add(ModPattern(modRows));
  }

  // ── Samples: each SampleInstrument channel → one mod sample, in order. ──
  final samples = <ModSample>[];
  for (var c = 0; c < channelCount; c++) {
    final inst = channelInstruments[c];
    if (inst is SampleInstrument && inst.sample.isNotEmpty) {
      final src = inst.sample;
      final pcm = Int8List(src.length);
      for (var i = 0; i < src.length; i++) {
        pcm[i] = (src[i] * 127).round().clamp(-128, 127);
      }
      final name = inst.id.length > 22 ? inst.id.substring(0, 22) : inst.id;
      samples.add(ModSample(name: name, pcm: pcm));
    } else {
      samples.add(ModSample.empty());
    }
  }
  // A module always carries exactly 31 sample slots.
  while (samples.length < 31) {
    samples.add(ModSample.empty());
  }

  final order = List<int>.generate(modPatterns.length, (i) => i);

  return ModModule(
    title: title.length > 20 ? title.substring(0, 20) : title,
    channelCount: channelCount,
    samples: samples,
    order: order.isEmpty ? [0] : order,
    patterns: modPatterns.isEmpty ? const [ModPattern([])] : modPatterns,
  );
}
