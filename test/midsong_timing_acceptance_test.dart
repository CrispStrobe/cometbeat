// ACCEPTANCE GATE for Feature A — mid-song tempo/speed changes.
// Owned by the orchestrator (opus tracker-replayer). DO NOT EDIT.
// Implement the contract in docs/TRACKER_ENGINE_CONTRACTS.md until this passes.

import 'dart:math';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

// An Fxx cell: param < 0x20 sets speed (ticks/row); >= 0x20 sets tempo (BPM).
TrackerCell fxx(int param) => TrackerCell(fxCmd: kFxSetSpeed, fxParam: param);

void main() {
  group('Feature A — mid-song tempo/speed', () {
    test('regression: a constant-tempo song keeps the uniform length', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 8));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.syncCurrent();
      expect(replaySong(s).pcm.length, s.timing.totalSamples * s.order.length);
    });

    test('walkFlow annotates each played row with the tempo in effect', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8), // song tempo 120
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x3C)); // 0x3C = 60 BPM (>= 0x20) at entry 1
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      final played = walkFlow(s);
      final entry0 = played.where((p) => p.orderIndex == 0);
      final entry1 = played.where((p) => p.orderIndex == 1);
      expect(entry0.isNotEmpty && entry1.isNotEmpty, isTrue);
      expect(entry0.every((p) => p.tempoBpm == 120), isTrue);
      expect(entry1.every((p) => p.tempoBpm == 60), isTrue);
    });

    test('a mid-song tempo drop lengthens the song; length+map+transport agree',
        () {
      // Entry 0 at 120 BPM, entry 1 dropped to 60 BPM (rows twice as long).
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8), // song tempo 120 (the default)
        patternCount: 2,
      );
      s.selectPattern(0);
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.selectPattern(1);
      s.engine.setCell(1, 0, fxx(0x3C)); // Fxx on ch1 …
      s.engine.setCell(0, 0, const TrackerCell(midi: 62)); // … note on ch0
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      // A constant-120 reference (no Fxx): 16 rows × 125 ms = 2000 ms.
      const stepMs120 = 125;
      const stepMs60 = 250;
      const expectedMs = 8 * stepMs120 + 8 * stepMs60; // 1000 + 2000 = 3000
      expect(s.songTotalMs, greaterThan(16 * stepMs120)); // longer than uniform
      expect((s.songTotalMs - expectedMs).abs(), lessThan(20));

      // The rendered WAV length matches songTotalMs (so the transport agrees).
      final pcm = replaySong(s).pcm;
      final renderedMs = pcm.length / kSampleRate * 1000;
      expect((renderedMs - s.songTotalMs).abs(), lessThan(20));

      // The timing map's last row starts near the end (non-uniform cadence).
      final map = resolveTimingMap(s);
      expect(map.length, 16);
      expect(map.last.startMs, greaterThan(2000)); // into the slow half
      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(500));
    });

    test('mid-song SPEED change alters the render but not the length', () {
      // Two speeds in play order → routes through the variable path; speed
      // changes effect granularity, not duration.
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(0);
      s.engine.setCell(0, 0, fxx(0x06)); // speed 6
      s.engine.setCell(1, 0, fx4(0x18)); // a vibrato so granularity is audible
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x02)); // speed 2 (finer)
      s.engine.setCell(1, 0, fx4(0x18));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      final pcm = replaySong(s).pcm;
      // Length is still the uniform 16 rows (speed never changes duration).
      expect((pcm.length - s.timing.totalSamples * 2).abs(), lessThan(50));
      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(200));
    });
  });
}

// A vibrato cell on channel 1 (so a speed change has an audible granularity).
TrackerCell fx4(int param) => TrackerCell(
      midi: 60,
      fxCmd: kFxVibrato,
      fxParam: param,
    );
