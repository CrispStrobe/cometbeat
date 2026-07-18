// tracker_replayer — the tick-based replayer for phase-2 PITCH commands.
//
// The state machine is the whole game (see the handover §6), so most of this is
// pure TRAJECTORY testing: author cells, assert the per-tick (pitch, volume)
// sequence via [traceChannel]. A handful of audio-domain smoke tests prove the
// renderer wires the same machine into non-silent PCM of the right length.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument, kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kFxSetVolume, kFxVolumeSlide, kDefaultTicksPerRow;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cell with a command (and optional note) — terse authoring for the tables.
TrackerCell fx(int cmd, int param, {int? midi}) =>
    TrackerCell(midi: midi, fxCmd: cmd, fxParam: param);

/// An Exy extended command: sub-command [sub] (high nibble) + value [val].
TrackerCell ex(int sub, int val, {int? midi}) =>
    fx(kFxExtended, (sub << 4) | val, midi: midi);

void main() {
  group('arpeggio (0xy)', () {
    test('cycles base / base+x / base+y each tick without moving the base', () {
      final cells = [
        fx(kFxArpeggio, 0x47, midi: 60), // 0-4-7 arpeggio on C-4
        const TrackerCell(), // empty → back to the plain base note
      ];
      final t = traceChannel(cells);
      const want = [0, 4, 7, 0, 4, 7];
      for (var k = 0; k < 6; k++) {
        expect(t.pitchAt(0, k), 60 + want[k], reason: 'arp tick $k');
      }
      // The base note is untouched: the empty next row rings at plain 60.
      for (var k = 0; k < 6; k++) {
        expect(t.pitchAt(1, k), 60);
      }
    });
  });

  group('porta up / down (1xx / 2xx)', () {
    test('porta up raises pitch monotonically and persists', () {
      final cells = [
        fx(kFxPortaUp, 0x10, midi: 60), // 1 semitone/tick (16 units)
        const TrackerCell(), // rings — the raised pitch persists
      ];
      final t = traceChannel(cells);
      expect(t.pitchAt(0, 0), 60); // tick 0 holds
      for (var k = 1; k < 6; k++) {
        expect(t.pitchAt(0, k), greaterThan(t.pitchAt(0, k - 1)));
      }
      expect(t.pitchAt(0, 5), closeTo(65, 1e-9)); // +5 over 5 slide-ticks
      expect(t.pitchAt(1, 0), closeTo(65, 1e-9)); // persisted
    });

    test('porta down lowers pitch', () {
      final cells = [fx(kFxPortaDown, 0x10, midi: 60)];
      final t = traceChannel(cells);
      expect(t.pitchAt(0, 5), closeTo(55, 1e-9));
    });
  });

  group('tone porta (3xx)', () {
    test('slides toward the row note and never overshoots', () {
      final cells = [
        const TrackerCell(midi: 60), // C-4
        fx(kFxTonePorta, 0x08, midi: 64), // → E-4: 0.5 st/tick, no retrig
        fx(kFxTonePorta, 0x00), // continue (memory reuses 0x08)
        fx(kFxTonePorta, 0x00),
      ];
      final t = traceChannel(cells);
      // Row 0 sits at C-4.
      expect(t.pitchAt(0, 5), 60);
      // Monotonic non-decreasing toward 64, clamped (never above 64).
      var prev = 60.0;
      for (var r = 1; r < 4; r++) {
        for (var k = 0; k < 6; k++) {
          final p = t.pitchAt(r, k);
          expect(p, greaterThanOrEqualTo(prev - 1e-9));
          expect(p, lessThanOrEqualTo(64 + 1e-9));
          prev = p;
        }
      }
      expect(t.pitchAt(3, 5), closeTo(64, 1e-9)); // reached the target
    });

    test('tone porta with no prior note just starts on the note', () {
      final cells = [fx(kFxTonePorta, 0x08, midi: 64)];
      final t = traceChannel(cells);
      expect(t.pitchAt(0, 0), 64);
      expect(t.pitchAt(0, 5), 64);
    });
  });

  group('vibrato (4xy)', () {
    test('is a zero-mean sine on pitch, bounded by the depth', () {
      // speed 1, depth 8 ⇒ ±1 semitone; a full cycle is 32 ticks.
      final cells = [
        fx(kFxVibrato, 0x18, midi: 60),
        fx(kFxVibrato, 0x00),
        fx(kFxVibrato, 0x00),
        fx(kFxVibrato, 0x00),
      ];
      final t = traceChannel(cells, ticksPerRow: 8); // 4×8 = 32 ticks = 1 cycle
      final all = <double>[];
      for (var r = 0; r < 4; r++) {
        for (var k = 0; k < 8; k++) {
          all.add(t.pitchAt(r, k));
        }
      }
      expect(all.first, closeTo(60, 1e-9)); // starts at the base (sin 0)
      expect(all.reduce(max), greaterThan(60.5)); // swings up
      expect(all.reduce(min), lessThan(59.5)); // and down
      expect(all.reduce(max), lessThan(61.001)); // within ±1 semitone
      expect(all.reduce(min), greaterThan(58.999));
      final mean = all.reduce((a, b) => a + b) / all.length;
      expect(mean, closeTo(60, 1e-6)); // zero-mean over one full cycle
    });
  });

  group('tremolo (7xy)', () {
    test('is a zero-mean sine on volume', () {
      final cells = [
        fx(kFxSetVolume, 0x20, midi: 60), // C-4 at volume 32
        fx(kFxTremolo, 0x18), // speed 1, depth 8
        fx(kFxTremolo, 0x00),
        fx(kFxTremolo, 0x00),
        fx(kFxTremolo, 0x00),
      ];
      final t = traceChannel(cells, ticksPerRow: 8); // rows 1..4 = 32 ticks
      final all = <double>[];
      for (var r = 1; r < 5; r++) {
        for (var k = 0; k < 8; k++) {
          all.add(t.volumeAt(r, k));
        }
      }
      expect(all.reduce(max), greaterThan(32)); // above the base
      expect(all.reduce(min), lessThan(32)); // and below
      final mean = all.reduce((a, b) => a + b) / all.length;
      expect(mean, closeTo(32, 1e-6));
    });
  });

  group('volume slide (Axy) + set volume (Cxx)', () {
    test('Cxx sets the persisting channel volume', () {
      final cells = [
        fx(kFxSetVolume, 0x20, midi: 60),
        const TrackerCell(),
      ];
      final t = traceChannel(cells);
      expect(t.volumeAt(0, 0), 32);
      expect(t.volumeAt(1, 5), 32); // persists across the empty row
    });

    test('Axy slides the volume over the row and persists', () {
      final cells = [
        fx(kFxSetVolume, 0x40, midi: 60), // full
        fx(kFxVolumeSlide, 0x04), // slide down 4/tick
        const TrackerCell(),
      ];
      final t = traceChannel(cells);
      expect(t.volumeAt(1, 0), 64); // tick 0 holds
      expect(t.volumeAt(1, 5), closeTo(44, 1e-9)); // 64 − 4×5
      expect(t.volumeAt(2, 0), closeTo(44, 1e-9)); // persisted
    });
  });

  group('effect memory', () {
    test('a 0 param reuses the last non-zero param (porta)', () {
      final cells = [
        const TrackerCell(midi: 60),
        fx(kFxPortaUp, 0x04), // arm rate 4
        fx(kFxPortaUp, 0x00), // reuse rate 4 → keeps rising
      ];
      final t = traceChannel(cells);
      expect(t.pitchAt(2, 5), greaterThan(t.pitchAt(1, 5)));
    });
  });

  group('audio rendering', () {
    TrackerSong songWith(TrackerCell cell) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      // Channel 0 is an additive 'piano' voice in the default band.
      song.engine.setCell(0, 0, cell);
      return song;
    }

    test('replaySong renders non-silent PCM of the expected length', () {
      final song = songWith(fx(kFxPortaUp, 0x20, midi: 60));
      final res = replaySong(song);
      expect(res.pcm.length, song.timing.totalSamples * song.order.length);
      final peak = res.pcm.fold<int>(0, (m, s) => max(m, s.abs()));
      expect(peak, greaterThan(1000)); // clearly audible
    });

    test('a porta-up note rises in pitch (later half brighter)', () {
      // Zero-crossing rate is a cheap pitch proxy; a rising note crosses more
      // often in its second half than its first.
      final song = songWith(fx(kFxPortaUp, 0x40, midi: 48)); // low note, steep
      final pcm = replaySong(song).pcm;
      final n = song.timing.totalSamples; // one note's run (row 0 rings 8 rows)
      int crossings(int lo, int hi) {
        var c = 0;
        for (var i = lo + 1; i < hi; i++) {
          if ((pcm[i - 1] < 0) != (pcm[i] < 0)) c++;
        }
        return c;
      }

      final firstHalf = crossings(0, n ~/ 2);
      final secondHalf = crossings(n ~/ 2, n);
      expect(secondHalf, greaterThan(firstHalf));
    });

    test('the row-timing map covers every played row in order', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, fx(kFxArpeggio, 0x37, midi: 60));
      song.addToOrder(0); // order = [0, 0] → two passes
      final res = replaySong(song);
      expect(res.timing.length, 8 * 2);
      for (var i = 1; i < res.timing.length; i++) {
        expect(
          res.timing[i].startMs,
          greaterThanOrEqualTo(res.timing[i - 1].startMs),
        );
      }
      expect(res.timing.first.orderIndex, 0);
      expect(res.timing.last.orderIndex, 1);
    });
  });

  group('flow — Bxx position jump / Dxx pattern break', () {
    // A song of [patternCount] patterns × [rows] rows, one channel, authored via
    // [author], with the given [order]. Cells are synced so walkFlow sees them.
    TrackerSong flowSong({
      int patternCount = 3,
      int rows = 8,
      required List<int> order,
      required void Function(TrackerSong) author,
    }) {
      final s = TrackerSong(
        timing: TrackerTiming(rows: rows),
        patternCount: patternCount,
      );
      s.order
        ..clear()
        ..addAll(order);
      author(s);
      s.syncCurrent();
      return s;
    }

    List<String> seq(List<PlayedRow> p) =>
        [for (final r in p) '${r.orderIndex}:${r.patternIndex}:${r.row}'];

    test('no flow → the linear order×rows sequence', () {
      final s = flowSong(
        patternCount: 2,
        order: [0, 1],
        author: (s) => s.engine.setCell(0, 0, const TrackerCell(midi: 60)),
      );
      expect(songUsesFlow(s), isFalse);
      expect(walkFlow(s).length, 8 * 2);
    });

    test('Dxx breaks to the next order entry (D00 → row 0)', () {
      final s = flowSong(
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.engine.setCell(0, 2, fx(kFxPatternBreak, 0x00));
        },
      );
      expect(songUsesFlow(s), isTrue);
      final s2 = seq(walkFlow(s));
      // rows 0,1,2 of order-0 pattern-0, then all of order-1 pattern-1.
      expect(s2.take(4).toList(), ['0:0:0', '0:0:1', '0:0:2', '1:1:0']);
      expect(s2.length, 3 + 8);
    });

    test('Dxx param is decimal and clamps to the pattern length', () {
      final s = flowSong(
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, fx(kFxPatternBreak, 0x03)); // → row 3
        },
      );
      expect(walkFlow(s)[1].row, 3);

      final s2 = flowSong(
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, fx(kFxPatternBreak, 0x13)); // 13 → clamp to 7
        },
      );
      expect(walkFlow(s2)[1].row, 7);
    });

    test('Bxx jumps to another order index (skipping entries)', () {
      final s = flowSong(
        order: [0, 1, 2],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 1, fx(kFxPositionJump, 0x02)); // → order 2
        },
      );
      final s2 = seq(walkFlow(s));
      expect(s2.take(3).toList(), ['0:0:0', '0:0:1', '2:2:0']);
      expect(s2.length, 2 + 8); // order 1 skipped
    });

    test('Bxx + Dxx on one row: jump wins the order, break sets the row', () {
      final s = flowSong(
        order: [0, 1, 2],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, fx(kFxPositionJump, 0x01)); // channel 0
          s.addChannel();
          s.selectPattern(0);
          s.engine.setCell(1, 0, fx(kFxPatternBreak, 0x03)); // channel 1
        },
      );
      final p = walkFlow(s);
      expect(p[1].orderIndex, 1); // Bxx → order 1
      expect(p[1].row, 3); // Dxx → row 3
    });

    test('a backward Bxx loop terminates at the guard cap', () {
      final s = flowSong(
        patternCount: 1,
        order: [0],
        author: (s) {
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.engine.setCell(0, 3, fx(kFxPositionJump, 0x00)); // → order 0 row 0
        },
      );
      expect(walkFlow(s, maxRows: 20).length, 20);
    });

    test('flow render: PCM length + songTotalMs match the played sequence', () {
      final s = flowSong(
        order: [0, 1],
        author: (s) {
          s.selectPattern(0);
          s.engine.setCell(0, 0, const TrackerCell(midi: 60));
          s.engine.setCell(0, 2, fx(kFxPatternBreak, 0x00));
          s.selectPattern(1);
          s.engine.setCell(0, 0, const TrackerCell(midi: 64));
        },
      );
      final played = walkFlow(s);
      final res = replaySong(s);
      expect(res.timing.length, played.length);
      expect(
        res.pcm.length,
        s.timing.copyWith(rows: played.length).totalSamples,
      );
      expect(s.songTotalMs, s.timing.stepMs * played.length);
      final peak = res.pcm.fold<int>(0, (m, v) => max(m, v.abs()));
      expect(peak, greaterThan(1000));
    });
  });

  group('extended (Exy)', () {
    test('E1x/E2x fine porta bump the pitch once', () {
      final up = traceChannel([
        const TrackerCell(midi: 60),
        ex(kExFinePortaUp, 4), // +4/16 = +0.25 st, once
      ]);
      expect(up.pitchAt(1, 0), closeTo(60.25, 1e-9));
      expect(up.pitchAt(1, 5), closeTo(60.25, 1e-9)); // one-time, holds

      final down = traceChannel([
        const TrackerCell(midi: 60),
        ex(kExFinePortaDown, 4),
      ]);
      expect(down.pitchAt(1, 0), closeTo(59.75, 1e-9));
    });

    test('EAx/EBx fine volume bump the volume once', () {
      final t = traceChannel([
        fx(kFxSetVolume, 0x20, midi: 60), // volume 32
        ex(kExFineVolUp, 4), // +4 → 36
        ex(kExFineVolDown, 8), // −8 → 28
      ]);
      expect(t.volumeAt(1, 0), 36);
      expect(t.volumeAt(2, 0), 28);
    });

    test('ECx cuts the note (volume 0) at its tick', () {
      final t = traceChannel([
        fx(kFxSetVolume, 0x40, midi: 60), // full
        ex(kExNoteCut, 3), // cut at tick 3
      ]);
      expect(t.volumeAt(1, 2), 64); // before the cut
      expect(t.volumeAt(1, 3), 0); // cut
      expect(t.volumeAt(1, 5), 0);
    });

    test('EDx delays the note trigger to its tick', () {
      final t = traceChannel([ex(kExNoteDelay, 3, midi: 60)]);
      expect(t.retriggerAt(0, 2), isFalse); // not yet
      expect(t.retriggerAt(0, 3), isTrue); // triggers here
      expect(t.pitchAt(0, 3), 60);
      expect(t.pitchAt(0, 5), 60);
    });

    test('E9x retriggers the note every x ticks', () {
      final t = traceChannel([
        const TrackerCell(midi: 60),
        ex(kExRetrigger, 2), // every 2 ticks
      ]);
      expect(t.retriggerAt(1, 1), isFalse);
      expect(t.retriggerAt(1, 2), isTrue);
      expect(t.retriggerAt(1, 4), isTrue);
    });

    test('E6x pattern loop repeats the marked span (walkFlow)', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(0, 0, ex(kExPatternLoop, 0)); // E60 loop start
      s.engine.setCell(0, 3, ex(kExPatternLoop, 1)); // E61 loop once
      s.syncCurrent();
      expect(songUsesFlow(s), isTrue);
      final rows = [for (final pr in walkFlow(s)) pr.row];
      expect(rows, [0, 1, 2, 3, 0, 1, 2, 3]); // played twice
    });

    test('a note-delay song renders non-silent audio', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, ex(kExNoteDelay, 3, midi: 60));
      final peak = replaySong(song).pcm.fold<int>(0, (m, v) => max(m, v.abs()));
      expect(peak, greaterThan(1000));
    });
  });

  group('Fxx set-speed', () {
    TrackerSong speedSong(int? fParam) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      // A vibrato note so the effect granularity (ticks/row) is audible.
      song.engine.setCell(0, 0, fx(kFxVibrato, 0x88, midi: 60));
      for (var r = 1; r < 8; r++) {
        song.engine.setCell(0, r, fx(kFxVibrato, 0x00));
      }
      if (fParam != null) {
        // Put the Fxx on a fresh channel/row 0 so it is seen first in play order.
        song.engine.setCell(1, 0, fx(kFxSetSpeed, fParam));
      }
      song.syncCurrent(); // persist live edits into the pattern snapshot
      return song;
    }

    test('songInitialSpeed reads the first Fxx speed, ignores tempo/none', () {
      expect(songInitialSpeed(speedSong(0x03)), 3);
      expect(songInitialSpeed(speedSong(0x0C)), 12);
      // A tempo Fxx (>= 0x20) is not a speed → fall back to the default.
      expect(songInitialSpeed(speedSong(0x7D)), kDefaultTicksPerRow);
      // No Fxx → fallback.
      expect(songInitialSpeed(speedSong(null)), kDefaultTicksPerRow);
      // Explicit fallback is honoured.
      expect(songInitialSpeed(speedSong(null), fallback: 4), 4);
    });

    test('the speed changes the render (finer granularity ≠ default)', () {
      final fast = replaySong(speedSong(0x03)).pcm; // 3 ticks/row
      final slow = replaySong(speedSong(0x0C)).pcm; // 12 ticks/row
      expect(fast.length, slow.length); // speed never changes duration
      var diff = false;
      for (var i = 0; i < fast.length; i++) {
        if (fast[i] != slow[i]) {
          diff = true;
          break;
        }
      }
      expect(
        diff,
        isTrue,
        reason: 'ticks/row should affect the vibrato render',
      );
    });
  });

  group('Fxx set-tempo', () {
    TrackerSong tempoSong(int? fParam) {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      if (fParam != null) song.engine.setCell(1, 0, fx(kFxSetSpeed, fParam));
      song.syncCurrent();
      return song;
    }

    test('songInitialTempo reads the first Fxx tempo (≥0x20), else null', () {
      expect(songInitialTempo(tempoSong(0x7D)), 125); // 0x7D = 125 BPM
      expect(songInitialTempo(tempoSong(0x03)), isNull); // that is a speed
      expect(songInitialTempo(tempoSong(null)), isNull);
    });

    test('replaySong + songTotalMs render uniformly at the Fxx tempo', () {
      const at120 = TrackerTiming(rows: 8); // default tempo is 120
      const at80 = TrackerTiming(rows: 8, tempoBpm: 80);
      final base = tempoSong(null); // 120 BPM (no Fxx)
      final slow = tempoSong(0x50); // 0x50 = 80 BPM → longer

      expect(base.songTotalMs, at120.totalMs);
      expect(slow.songTotalMs, at80.totalMs); // Fxx tempo applied

      final pcm = replaySong(slow).pcm;
      expect(pcm.length, at80.totalSamples); // render length matches
      expect(replaySong(base).pcm.length, at120.totalSamples);
      expect(pcm.length, isNot(at120.totalSamples)); // tempo really changed it
      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(1000));
    });
  });

  group('playhead map (resolveTimingMap / rowIndexAtMs)', () {
    test('resolveTimingMap matches replaySong().timing (uniform + flow)', () {
      // Uniform (no flow).
      final plain = TrackerSong(timing: const TrackerTiming(rows: 8));
      plain.engine.setCell(0, 0, const TrackerCell(midi: 60));
      plain.addToOrder(0);
      expect(
        resolveTimingMap(plain).map((r) => r.toString()).toList(),
        replaySong(plain).timing.map((r) => r.toString()).toList(),
      );

      // Flow (Dxx break).
      final flow = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      flow.selectPattern(0);
      flow.engine.setCell(0, 0, const TrackerCell(midi: 60));
      flow.engine.setCell(0, 2, fx(kFxPatternBreak, 0x00));
      flow.order
        ..clear()
        ..addAll([0, 1]);
      flow.syncCurrent();
      expect(
        resolveTimingMap(flow).map((r) => r.toString()).toList(),
        replaySong(flow).timing.map((r) => r.toString()).toList(),
      );
    });

    test('rowIndexAtMs finds the row playing at a given time', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final map = resolveTimingMap(song);
      expect(rowIndexAtMs(map, -5), 0); // before the start → first row
      // A time just past row 3's onset resolves to row 3.
      final r3 = map[3].startMs;
      expect(map[rowIndexAtMs(map, r3 + 1)].row, 3);
      // Exactly on row 5's onset resolves to row 5.
      expect(map[rowIndexAtMs(map, map[5].startMs)].row, 5);
      expect(rowIndexAtMs(const [], 0), -1); // empty map
    });
  });

  group('per-cell instrument column', () {
    test('the default pool has the four additive voices', () {
      expect(TrackerSong().instruments.length, 4);
    });

    test('a cell instrument switches the additive timbre (pool index)', () {
      // Channel 0 is 'piano' (pool[0]); pool[2] is 'flute'.
      TrackerSong twoNotes(int secondInstrument) {
        final s = TrackerSong(timing: const TrackerTiming(rows: 8));
        s.engine.setCell(0, 0, const TrackerCell(midi: 60, instrument: 1));
        s.engine.setCell(
          0,
          4,
          TrackerCell(midi: 60, instrument: secondInstrument),
        );
        s.syncCurrent(); // so usesInstruments sees the live edits
        return s;
      }

      expect(twoNotes(1).usesInstruments, isTrue); // routes via the replayer
      final piano = replaySong(twoNotes(1)).pcm; // note 2 stays piano
      final flute = replaySong(twoNotes(3)).pcm; // note 2 → flute
      expect(piano.length, flute.length);

      final s4 = const TrackerTiming(rows: 8).stepStartSample(4);
      bool sameRange(int lo, int hi) {
        for (var i = lo; i < hi; i++) {
          if (piano[i] != flute[i]) return false;
        }
        return true;
      }

      expect(sameRange(0, s4), isTrue); // note 1 (both piano) is identical
      expect(sameRange(s4, piano.length), isFalse); // note 2 differs (flute)
    });
  });

  group('volume envelope', () {
    test('levelAt interpolates and holds the ends', () {
      const e = VolumeEnvelope([
        (ms: 0, level: 0.0),
        (ms: 100, level: 1.0),
        (ms: 200, level: 0.5),
      ]);
      expect(e.levelAt(-10), 0.0); // before the first point → first level
      expect(e.levelAt(50), closeTo(0.5, 1e-9)); // halfway 0 → 1
      expect(e.levelAt(100), 1.0);
      expect(e.levelAt(150), closeTo(0.75, 1e-9)); // halfway 1 → 0.5
      expect(e.levelAt(999), 0.5); // after the last point → last level
      expect(const VolumeEnvelope([]).levelAt(10), 1.0); // empty = no change
    });

    test('a fade-out envelope makes the note quieter at the end', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine
          .setCell(0, 0, const TrackerCell(midi: 60)); // rings all 8 rows
      // 8 rows at 120 BPM / 4 spb = 1000 ms; fade full → silent across it.
      song.engine.setChannelVolumeEnvelope(
        0,
        const VolumeEnvelope([(ms: 0, level: 1.0), (ms: 1000, level: 0.0)]),
      );
      expect(song.usesEnvelopes, isTrue);
      final pcm = replaySong(song).pcm;
      final n = pcm.length;
      double rms(int a, int b) {
        var s = 0.0;
        for (var i = a; i < b; i++) {
          s += pcm[i] * pcm[i].toDouble();
        }
        return sqrt(s / (b - a));
      }

      expect(rms(0, n ~/ 4), greaterThan(rms(3 * n ~/ 4, n) * 2));
    });

    test('a fade-out envelope shapes a SAMPLE (non-additive) note too', () {
      // A ~500 ms sine sample, a 4-row (500 ms) note, faded full → silent.
      final sample = Float64List.fromList([
        for (var i = 0; i < 22050; i++) sin(2 * pi * 220 * i / kSampleRate),
      ]);
      final ch = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('s', sample),
        gain: 0.9,
        rows: 4,
        volumeEnvelope: const VolumeEnvelope([
          (ms: 0, level: 1.0),
          (ms: 500, level: 0.0),
        ]),
      );
      final cells = List<TrackerCell>.filled(4, TrackerCell.empty)
        ..[0] = const TrackerCell(midi: 60);
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(rows: 4),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );
      expect(song.usesEnvelopes, isTrue);

      final pcm = replaySong(song).pcm;
      final n = pcm.length;
      double rms(int a, int b) {
        var s = 0.0;
        for (var i = a; i < b; i++) {
          s += pcm[i] * pcm[i].toDouble();
        }
        return sqrt(s / (b - a));
      }

      expect(rms(0, n ~/ 4), greaterThan(rms(3 * n ~/ 4, n) * 2));
    });

    test('a flat (always-1.0) envelope leaves the render byte-identical', () {
      TrackerSong mk(VolumeEnvelope? env) {
        final s = TrackerSong(timing: const TrackerTiming(rows: 8));
        s.engine.setCell(0, 0, fx(kFxPortaUp, 0x10, midi: 60)); // → replayer
        if (env != null) s.engine.setChannelVolumeEnvelope(0, env);
        return s;
      }

      final plain = replaySong(mk(null)).pcm;
      final flat = replaySong(
        mk(const VolumeEnvelope([(ms: 0, level: 1.0), (ms: 5000, level: 1.0)])),
      ).pcm;
      expect(flat, plain);
    });
  });

  group('pan envelope', () {
    test('panAt interpolates and holds the ends', () {
      const e = PanEnvelope([(ms: 0, pan: -1.0), (ms: 100, pan: 1.0)]);
      expect(e.panAt(-5), -1.0);
      expect(e.panAt(50), closeTo(0.0, 1e-9)); // centre halfway
      expect(e.panAt(500), 1.0); // held
    });

    test('a pan envelope sweeps a note left → right in the stereo render', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // rings ~1000 ms
      song.engine.setChannelPanEnvelope(
        0,
        const PanEnvelope([(ms: 0, pan: -1.0), (ms: 1000, pan: 1.0)]),
      );
      expect(song.usesPan, isTrue);

      final wav = song.renderSongWav();
      expect(wav[22] | (wav[23] << 8), 2); // stereo
      final data = ByteData.sublistView(wav);
      final frames = (wav.length - 44) ~/ 4;
      ({double l, double r}) energy(int fromFrame, int toFrame) {
        var l = 0.0, r = 0.0;
        for (var f = fromFrame; f < toFrame; f++) {
          final o = 44 + f * 4;
          l += data.getInt16(o, Endian.little).abs();
          r += data.getInt16(o + 2, Endian.little).abs();
        }
        return (l: l, r: r);
      }

      final first = energy(0, frames ~/ 4); // 0..250 ms → panned left
      final last = energy(3 * frames ~/ 4, frames); // 750..1000 ms → right
      expect(first.l, greaterThan(first.r)); // starts left
      expect(last.r, greaterThan(last.l)); // ends right
    });

    test('pan envelope is honoured on the variable-timing stereo path', () {
      // A mid-song tempo change (→ variable timing) + a hard-left pan envelope.
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(0);
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.selectPattern(1);
      s.engine.setCell(
        1,
        0,
        const TrackerCell(fxCmd: kFxSetSpeed, fxParam: 0x3C), // tempo 60
      );
      s.engine.setCell(0, 0, const TrackerCell(midi: 62));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.engine.setChannelPanEnvelope(
        0,
        const PanEnvelope([(ms: 0, pan: -1.0), (ms: 5000, pan: -1.0)]),
      );
      s.syncCurrent();
      expect(s.usesPan && songUsesVariableTiming(s), isTrue);

      final wav = s.renderSongWav();
      expect(wav[22] | (wav[23] << 8), 2); // stereo
      final data = ByteData.sublistView(wav);
      var l = 0.0, r = 0.0;
      for (var o = 44; o + 3 < wav.length; o += 4) {
        l += data.getInt16(o, Endian.little).abs();
        r += data.getInt16(o + 2, Endian.little).abs();
      }
      expect(l, greaterThan(r * 4)); // hard-left throughout the variable render
    });
  });

  group('sample tick voice (per-tick effects on sample channels)', () {
    test('a porta-up on a SAMPLE channel raises the pitch (rising)', () {
      // A long low sine sample so a gentle porta stays within it + is measurable
      // via zero-crossings.
      final sample = Float64List.fromList([
        for (var i = 0; i < 120000; i++) sin(2 * pi * 110 * i / kSampleRate),
      ]);
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 48); // note at base
      for (var r = 1; r < 8; r++) {
        cells[r] = fx(kFxPortaUp, 0x04); // gentle porta up (rings + rises)
      }
      final ch = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('s', sample, baseMidi: 48),
        gain: 0.9,
        rows: 8,
      );
      final song = TrackerSong.fromParts(
        channels: [ch],
        timing: const TrackerTiming(rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells]),
        ],
        order: [0],
      );
      final pcm = replaySong(song).pcm;
      final n = pcm.length;
      int crossings(int lo, int hi) {
        var c = 0;
        for (var i = lo + 1; i < hi; i++) {
          if ((pcm[i - 1] < 0) != (pcm[i] < 0)) c++;
        }
        return c;
      }

      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(1000));
      // A rising pitch crosses zero more often later than earlier.
      expect(crossings(n ~/ 2, n), greaterThan(crossings(0, n ~/ 2)));
    });

    test('per-tick effects apply on a SAMPLE channel with VARIABLE timing', () {
      // Gap fix: a sample channel carrying a per-tick porta AND a mid-song tempo
      // change (→ the variable-timing render path) used to fall back to
      // one-shot-per-note (flat). It must now RISE like the uniform path does.
      final sample = Float64List.fromList([
        for (var i = 0; i < 120000; i++) sin(2 * pi * 110 * i / kSampleRate),
      ]);
      final cells = List<TrackerCell>.filled(8, TrackerCell.empty);
      cells[0] = const TrackerCell(midi: 48);
      for (var r = 1; r < 8; r++) {
        cells[r] = fx(kFxPortaUp, 0x04); // gentle porta up (rings + rises)
      }
      final sampleCh = TrackerChannel(
        id: 's',
        instrument: SampleInstrument('s', sample, baseMidi: 48),
        gain: 0.9,
        rows: 8,
      );
      // A second, silent channel supplies a mid-song set-tempo (120 → 80) so
      // songUsesVariableTiming is true (no note → contributes no audio).
      final tempoCells = List<TrackerCell>.filled(8, TrackerCell.empty);
      tempoCells[4] = fx(kFxSetSpeed, 0x50); // 0x50 = 80 BPM (≥0x20 → tempo)
      final tempoCh = TrackerChannel(
        id: 't',
        instrument: const AdditiveInstrument('p', Instrument.piano),
        rows: 8,
      );
      final song = TrackerSong.fromParts(
        channels: [sampleCh, tempoCh],
        timing: const TrackerTiming(rows: 8),
        patterns: [
          TrackerPattern(name: '00', cells: [cells, tempoCells]),
        ],
        order: [0],
      );
      expect(songUsesVariableTiming(song), isTrue); // the variable path is used

      final pcm = replaySong(song).pcm;
      final n = pcm.length;
      int crossings(int lo, int hi) {
        var c = 0;
        for (var i = lo + 1; i < hi; i++) {
          if ((pcm[i - 1] < 0) != (pcm[i] < 0)) c++;
        }
        return c;
      }

      expect(pcm.fold<int>(0, (m, v) => max(m, v.abs())), greaterThan(1000));
      // Porta applied on the variable path → still rising (more crossings late).
      expect(crossings(n ~/ 2, n), greaterThan(crossings(0, n ~/ 2)));
    });
  });

  group('audit fixes', () {
    test('6xy continues vibrato with its own memory (does not corrupt it)', () {
      // 4-1-8 arms vibrato (speed 1, depth 8 ⇒ ±1 st). 6-0-4 must NOT reparse
      // its param as vib speed/depth — the vibrato keeps swinging ±1 st.
      final cells = [
        fx(kFxVibrato, 0x18, midi: 60),
        fx(kFxVibratoVolSlide, 0x04),
        fx(kFxVibratoVolSlide, 0x04),
        fx(kFxVibratoVolSlide, 0x04),
      ];
      final t = traceChannel(cells, ticksPerRow: 8); // 32 ticks = one cycle
      final all = <double>[];
      for (var r = 0; r < 4; r++) {
        for (var k = 0; k < 8; k++) {
          all.add(t.pitchAt(r, k));
        }
      }
      // Depth still 8 → reaches ~±1 st (a corrupted depth of 4 would only ±0.5).
      expect(all.reduce(max), greaterThan(60.9));
      expect(all.reduce(min), lessThan(59.1));
    });

    test('6xy with no prior vibrato does not invent one', () {
      final t = traceChannel([
        const TrackerCell(midi: 60),
        fx(kFxVibratoVolSlide, 0x84), // 6-8-4: no prior 4xy
      ]);
      // No vibrato memory → the 8 is a slide nibble, not a vib speed → flat.
      for (var k = 0; k < 6; k++) {
        expect(t.pitchAt(1, k), 60);
      }
    });

    test('EDx delayed note does not re-attack a still-ringing prior note', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // rings, decaying
      song.engine
          .setCell(0, 4, ex(kExNoteDelay, 3, midi: 72)); // fires at tick 3
      final pcm = replaySong(song).pcm;
      final s4 = song.timing.stepStartSample(4);
      double rms(int a, int b) {
        var sum = 0.0;
        for (var i = a; i < b; i++) {
          sum += pcm[i] * pcm[i].toDouble();
        }
        return sqrt(sum / (b - a));
      }

      // Just before row 4, and just after its start (still before the delay
      // fires at tick 3) — only the decaying note 60 sounds in both windows.
      final before = rms(s4 - 400, s4 - 100);
      final after = rms(s4 + 50, s4 + 350);
      // A re-attack would spike `after` far above `before`; a clean continued
      // decay keeps it at or below.
      expect(after, lessThanOrEqualTo(before * 1.3));
    });
  });

  group('per-note non-additive render (per-cell instrument on samples)', () {
    Float64List tone(double hz) => Float64List.fromList([
          for (var i = 0; i < 4000; i++) sin(2 * pi * hz * i / kSampleRate),
        ]);

    const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);

    List<TrackerCell> withNotes(Map<int, TrackerCell> at) {
      final c = List<TrackerCell>.filled(timing.rows, TrackerCell.empty);
      at.forEach((row, cell) => c[row] = cell);
      return c;
    }

    test('renderChannelPerNote is byte-identical when the instrument is fixed',
        () {
      final inst = SampleInstrument('s', tone(220));
      final cells = withNotes({
        0: const TrackerCell(midi: 60),
        4: const TrackerCell(midi: 64),
      });
      final whole = inst.renderChannel(cells, timing);
      // Same notes, but naming instrument 1 which points back at `inst`.
      final pc = [
        for (final c in cells)
          c.midi != null ? TrackerCell(midi: c.midi, instrument: 1) : c,
      ];
      final perNote = renderChannelPerNote(inst, pc, timing, [inst]);
      expect(perNote, equals(whole));
    });

    test('a cell instrument plays a different sample from the pool', () {
      final a = SampleInstrument('a', tone(220));
      final b = SampleInstrument('b', tone(880));
      final pool = <TrackerInstrument>[a, b];

      // Note 1 uses the channel default (a); note 2 (row 4) names instrument 2 (b).
      final mixed = renderChannelPerNote(
        a,
        withNotes({
          0: const TrackerCell(midi: 60),
          4: const TrackerCell(midi: 60, instrument: 2),
        }),
        timing,
        pool,
      );
      // Baseline: both notes on `a`.
      final allA = renderChannelPerNote(
        a,
        withNotes({
          0: const TrackerCell(midi: 60),
          4: const TrackerCell(midi: 60),
        }),
        timing,
        pool,
      );
      final s4 = timing.stepStartSample(4);
      var firstHalfSame = true;
      for (var i = 0; i < s4; i++) {
        if (mixed[i] != allA[i]) {
          firstHalfSame = false;
          break;
        }
      }
      var secondHalfDiffers = false;
      for (var i = s4; i < mixed.length; i++) {
        if (mixed[i] != allA[i]) {
          secondHalfDiffers = true;
          break;
        }
      }
      expect(firstHalfSame, isTrue); // note 1 (both `a`) identical
      expect(secondHalfDiffers, isTrue); // note 2 (b vs a) differs
    });
  });
}
