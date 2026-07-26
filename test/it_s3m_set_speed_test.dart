// IT/S3M `Axx` set-speed over its FULL 1–255 range.
//
// The bug this pins: IT and S3M keep speed (`Axx`) and tempo (`Txx`) as separate
// commands, so `A99` legitimately means "speed 153". Our internal effect column
// is MOD-numbered, where `Fxx` overloads one parameter — below 0x20 it is a
// speed, at or above it is a TEMPO. So a speed of 153 had no representation at
// all, and both readers silently clamped it to 0x1F (31).
//
// That is not a rounding error, it is a structural truncation: on `buddhia3.it`
// the closing rows are built on a single `A99` at pattern 75, and playing them at
// speed 31 instead of 153 made our render 571.6 s against libopenmpt's 618.4 s —
// 47 s of the outro simply rushed past. With `kFxSetSpeedFull` carrying the value
// unambiguously the same render is 623.5 s (ratio 1.008).
//
// Note what must NOT happen: `kFxSetSpeedFull` must never be read as a tempo.
// Removing the clamp without the new command would have made things worse — a
// param of 153 landing in the `Fxx` branch is `>= 0x20`, so it would have been
// applied as tempo 153 and sped the outro up rather than slowing it down.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-channel, one-row doc carrying `(cmd, param)` in the effect column.
ModuleDoc _docWith(int cmd, int param, {int rows = 1}) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.mod,
    order: [0],
    patterns: [
      DocPattern(
        // Row-major: rows[row][channel]. One channel, `rows` rows.
        [
          [DocCell(note: 60, instrument: 1, effect: cmd, effectParam: param)],
          for (var r = 1; r < rows; r++) const [DocCell.empty],
        ],
        1, // channelCount — NOT the row count; rows.length carries that
      ),
    ],
    samples: [DocSample(pcm: pcm)],
  );
}

DocCell _cellAfter(int cmd, int param, ModuleFormat fmt) => parseAnyModule(
      convertDocTo(_docWith(cmd, param), fmt),
    ).patterns.first.rows.first.first;

void main() {
  group('a full-range speed survives IT and S3M round-trips', () {
    // 153 = 0x99, the value buddhia3.it actually uses. Well above the 0x1F the
    // readers used to clamp to, and above the 0x20 that means "tempo" in Fxx.
    for (final fmt in [ModuleFormat.it, ModuleFormat.s3m]) {
      test('${fmt.name}: speed 153 comes back as 153, not 31', () {
        final c = _cellAfter(kFxSetSpeedFull, 153, fmt);
        expect(
          c.effect,
          kFxSetSpeedFull,
          reason: 'must stay a full-range set-speed',
        );
        expect(c.effectParam, 153, reason: 'clamped again?');
      });

      test('${fmt.name}: a low speed still round-trips', () {
        final c = _cellAfter(kFxSetSpeedFull, 6, fmt);
        expect(c.effect, kFxSetSpeedFull);
        expect(c.effectParam, 6);
      });

      test('${fmt.name}: the whole 1..255 range survives', () {
        for (final speed in [1, 31, 32, 100, 200, 255]) {
          final c = _cellAfter(kFxSetSpeedFull, speed, fmt);
          expect(c.effectParam, speed, reason: 'speed $speed on ${fmt.name}');
        }
      });
    }

    test('MOD and XM are untouched — they really do use Fxx semantics', () {
      // Fxx below 0x20 is a speed there; that encoding is correct for these two
      // formats and must keep working exactly as before.
      for (final fmt in [ModuleFormat.mod, ModuleFormat.xm]) {
        final c = _cellAfter(kFxSetSpeed, 6, fmt);
        expect(c.effect, kFxSetSpeed, reason: '${fmt.name} keeps Fxx');
        expect(c.effectParam, 6);
      }
    });
  });

  group('the replayer applies it as a SPEED, never a tempo', () {
    /// The command on ROW 0 — a song-wide speed, applied uniformly by
    /// [songInitialSpeed] rather than by the per-row walk.
    TrackerSong songWithSpeedAtStart(int cmd, int param) =>
        songFromModuleDoc(_docWith(cmd, param, rows: 2));

    /// The command MID-SONG (row 1 of 4), which is what buddhia3.it actually
    /// does and what forces the variable-timing walk: row 0 plays at the
    /// module's initial speed, the rest at the new one. This is the shape whose
    /// length the walk has to get right, so it is the shape worth asserting on.
    TrackerSong songWithSpeedMidway(int cmd, int param) {
      final pcm = Float64List(32);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
      }
      return songFromModuleDoc(
        ModuleDoc(
          channelCount: 1,
          sourceFormat: ModuleFormat.mod,
          order: [0],
          patterns: [
            DocPattern(
              // Row-major: rows[row][channel]. Four rows of ONE channel, with
              // the speed command on row 1 — so row 0 keeps the module's
              // initial speed and this is a genuine MID-SONG change.
              [
                const [DocCell(note: 60, instrument: 1)],
                [
                  DocCell(
                    note: 62,
                    instrument: 1,
                    effect: cmd,
                    effectParam: param,
                  ),
                ],
                const [DocCell(note: 64, instrument: 1)],
                const [DocCell(note: 65, instrument: 1)],
              ],
              1, // channelCount — rows.length carries the row count
            ),
          ],
          samples: [DocSample(pcm: pcm)],
        ),
      );
    }

    test('walkFlow reports the full-range speed from that row onward', () {
      // This is the code path the fix changed, so assert on it directly rather
      // than on songTotalMs (which folds speed in only on some paths).
      final rows = walkFlow(songWithSpeedMidway(kFxSetSpeedFull, 153));
      expect(rows.length, greaterThanOrEqualTo(4));
      expect(
        rows.first.ticksPerRow,
        isNot(153),
        reason: 'row 0 is before the command — it must keep the old speed',
      );
      for (final r in rows.skip(1).take(3)) {
        expect(
          r.ticksPerRow,
          153,
          reason: 'row ${r.row} should play at the new speed',
        );
      }
    });

    test('the tempo is left alone — 153 is a speed, not a BPM', () {
      // The trap in "just remove the clamp": 153 in the Fxx branch is >= 0x20,
      // so it would land on the tempo and make rows SHORTER instead of longer.
      final rows = walkFlow(songWithSpeedMidway(kFxSetSpeedFull, 153));
      final tempos = rows.map((r) => r.tempoBpm).toSet();
      expect(
        tempos.length,
        1,
        reason: 'the speed command must not have changed the tempo: $tempos',
      );
      expect(tempos.single, isNot(153));
    });

    test('the whole 1..255 range reaches the walk intact', () {
      for (final speed in [1, 31, 32, 100, 200, 255]) {
        final rows = walkFlow(songWithSpeedMidway(kFxSetSpeedFull, speed));
        expect(rows[1].ticksPerRow, speed, reason: 'speed $speed');
      }
    });

    test('songInitialSpeed reports the full-range value', () {
      expect(songInitialSpeed(songWithSpeedAtStart(kFxSetSpeedFull, 153)), 153);
      // And the Fxx path still answers for MOD-style speeds.
      expect(songInitialSpeed(songWithSpeedAtStart(kFxSetSpeed, 6)), 6);
    });

    test('it never reports as a tempo', () {
      // songInitialTempo asks _firstFxx with wantTempo: true; the full-range
      // command must not answer that question at any value.
      expect(
        songInitialTempo(songWithSpeedAtStart(kFxSetSpeedFull, 153)),
        isNull,
      );
      expect(
        songInitialTempo(songWithSpeedAtStart(kFxSetSpeedFull, 200)),
        isNull,
      );
      // Fxx >= 0x20 still is a tempo, as MOD intends.
      expect(songInitialTempo(songWithSpeedAtStart(kFxSetSpeed, 140)), 140);
    });

    test('a mid-song change arms the variable-timing render path', () {
      // _songHasFxx is the cheap pre-filter. If the new command were missing
      // from it, a song whose only timing command is an Axx would take the
      // fixed-size fast path and ignore the speed change entirely.
      expect(
        songUsesVariableTiming(songWithSpeedMidway(kFxSetSpeedFull, 153)),
        isTrue,
      );
    });
  });

  group('the command value itself', () {
    test('does not collide with any other internal effect command', () {
      // 0x12 was tried first and collided with S5x (set panbrello waveform),
      // which lives as a RAW hex literal in module_convert's internal->IT/S3M
      // switch rather than as a kFx* constant — so enumerating the constants was
      // not enough. `flutter analyze` caught it as an unreachable switch case;
      // this pins the constants side so a rename cannot quietly re-collide.
      const taken = <int>[
        kFxArpeggio,
        kFxPortaUp,
        kFxPortaDown,
        kFxTonePorta,
        kFxVibrato,
        kFxTonePortaVolSlide,
        kFxVibratoVolSlide,
        kFxTremolo,
        kFxSetPan,
        kFxSampleOffset,
        kFxPositionJump,
        kFxPatternBreak,
        kFxExtended,
        kFxSetSpeed,
        kFxSetGlobalVolume,
        kFxGlobalVolSlide,
        kFxPanSlide,
        kFxRetrigVolSlide,
        kFxSetFilter,
        kFxTremor,
        kFxPanbrello,
        kFxTempoSlide,
      ];
      expect(
        taken,
        isNot(contains(kFxSetSpeedFull)),
        reason: 'kFxSetSpeedFull = 0x${kFxSetSpeedFull.toRadixString(16)} '
            'collides with an existing command',
      );
    });
  });

  group('the real module', () {
    test('buddhia3.it renders close to libopenmpt, not 47s short', () {
      // The fixture is licence-restricted and .gitignored, so skip when absent.
      const path = 'test/fixtures/buddhia3.it';
      if (!File(path).existsSync()) return;
      final song = songFromModuleBytes(File(path).readAsBytesSync());
      final seconds = song.songTotalMs / 1000;
      // libopenmpt reports 618.38s; a straight walk honouring the A99 gives
      // 619.00s. Before the fix this was 567s.
      expect(seconds, greaterThan(600), reason: 'the A99 was ignored again');
      expect(seconds, lessThan(640));
    });
  });
}
