// ProTracker's effect memory is per-COMMAND, and differs from every other
// format's.
//
// PLAN.md §6 X3/X4. From `pt2_replayer.c`:
//
//   1xx / 2xx  portaUp/portaDown read `ch->n_cmd` — NO memory, `100` slides 0
//   Axy        volumeSlide reads the row's parameter — NO memory
//   3xx        tonePortamento LATCHES (`if (param > 0) n_toneportspeed = …`)
//   4xy        vibrato LATCHES, each nibble separately
//
// XM, S3M and IT latch all of them. We latched all of them too, which is the
// tracker-general rule applied to MOD as well: a MOD that states `104` once and
// then sends `100` kept sliding where the hardware stops. Measured against
// three engines agreeing at 1.000 spectral, `mem_porta_up` read 0.270 and
// `mem_porta_down` 0.531; both are 1.000 now.
//
// The control mattered more than either: `mem_tone_porta` was ALREADY 1.000,
// because `3xx` genuinely does latch. That is what identified the fault as the
// blanket RULE rather than a broken memory mechanism, and it is why the fix
// leaves `3xx`/`4xy` alone.
//
// These are trajectory assertions through a real import, so they run
// everywhere. The audio measurement needs openmpt123/xmp/mod2wav and lives in
// the opt-in sweep.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kDefaultTicksPerRow;
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

/// A one-channel module: note, then [first] on row 1, then the BARE
/// zero-parameter form of the same command on rows 2..8.
ModuleDoc _statedOnce(int effect, int param) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'memory',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 'sine', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 16; r++)
            [
              if (r == 0)
                const DocCell(note: 60, instrument: 1, volume: 64)
              else if (r == 1)
                DocCell(effect: effect, effectParam: param)
              else if (r <= 8)
                DocCell(effect: effect)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
}

/// The song as each format's reader sees it after a real round trip through
/// our writer — which is what decides whether the ProTracker rule applies.
final _writers = <String, Uint8List Function(ModuleDoc)>{
  'mod': convertToMod,
  'xm': convertToXm,
  's3m': convertToS3m,
  'it': convertToIt,
};

void main() {
  group('the importer marks only MOD', () {
    for (final entry in _writers.entries) {
      test('${entry.key} → protrackerEffectMemory == ${entry.key == "mod"}',
          () {
        final song = songFromModuleBytes(entry.value(_statedOnce(0x1, 0x04)));
        expect(song.protrackerEffectMemory, entry.key == 'mod');
        // And it must reach the channels, which is what the render paths read.
        expect(
          song.channels
              .every((c) => c.protrackerMemory == (entry.key == 'mod')),
          isTrue,
          reason: 'the flag has to be on the CHANNELS, not just the song — '
              'that is the copy every render path actually sees',
        );
      });
    }
  });

  group('1xx / 2xx do not latch under ProTracker rules', () {
    /// The effective pitch at the end of a run where [effect]/[param] appears
    /// on row 1 and rows 2..8 carry either the BARE zero-parameter form
    /// ([bare]) or nothing at all.
    ///
    /// Comparing those two against each other is the exact statement of the
    /// rule, and avoids a magic threshold: under ProTracker a bare `100` is
    /// indistinguishable from no command, so the two must be EQUAL. (My first
    /// attempt asserted `< 61.0` and failed at 61.25 — which was the correct
    /// value, since one row of `104` over five effect ticks bends 1.25
    /// semitones. The code was right and the threshold was invented.)
    double endPitch(
      int effect,
      int param, {
      required bool protracker,
      required bool bare,
    }) {
      final cells = [
        const TrackerCell(midi: 60, instrument: 1),
        TrackerCell(fxCmd: effect, fxParam: param),
        for (var i = 0; i < 7; i++)
          bare ? TrackerCell(fxCmd: effect) : const TrackerCell(),
      ];
      final t = traceChannel(cells, protrackerMemory: protracker);
      return t.pitchAt(cells.length - 1, kDefaultTicksPerRow - 1);
    }

    for (final (name, effect, up) in [
      ('100 after a 104', 0x1, true),
      ('200 after a 204', 0x2, false),
    ]) {
      test('a bare $name is the same as no command at all', () {
        final bare = endPitch(effect, 0x04, protracker: true, bare: true);
        final none = endPitch(effect, 0x04, protracker: true, bare: false);
        expect(
          bare,
          closeTo(none, 1e-9),
          reason: 'ProTracker reads the ROW parameter, so a bare command must '
              'do nothing — bare $bare vs none $none',
        );
        // …and row 1 must STILL have bent. A change that killed the command
        // outright would also satisfy the equality above, and be wrong.
        expect(
          up ? bare > 60.0 : bare < 60.0,
          isTrue,
          reason: 'no bend at all: $bare',
        );
      });

      test('…while the tracker-general rule keeps sliding', () {
        // XM, S3M and IT all latch, and only MOD changed. Without this the fix
        // could have been applied to every format and still looked right on the
        // MOD fixtures.
        final ptBare = endPitch(effect, 0x04, protracker: true, bare: true);
        final gnBare = endPitch(effect, 0x04, protracker: false, bare: true);
        expect(
          up ? gnBare > ptBare : gnBare < ptBare,
          isTrue,
          reason:
              'general rule must latch: ProTracker $ptBare, general $gnBare',
        );
      });
    }
  });

  group('Axy does not latch either', () {
    double endVolume({required bool protracker}) {
      final cells = [
        const TrackerCell(midi: 60, instrument: 1, fxCmd: 0xC, fxParam: 0x30),
        const TrackerCell(fxCmd: 0xA, fxParam: 0x02),
        for (var i = 0; i < 7; i++) const TrackerCell(fxCmd: 0xA),
      ];
      final t = traceChannel(cells, protrackerMemory: protracker);
      return t.volumeAt(cells.length - 1, kDefaultTicksPerRow - 1);
    }

    test('a bare A00 after an A02 stops the fade', () {
      final pt = endVolume(protracker: true);
      final ft = endVolume(protracker: false);
      expect(pt, lessThan(0x30), reason: 'row 1 must still fade');
      expect(
        ft,
        lessThan(pt),
        reason: 'the general rule keeps fading for eight more rows; '
            'ProTracker $pt, general $ft',
      );
    });
  });

  test('3xx DOES latch, under BOTH rules', () {
    // The control, and the reason the fix is per-command. `tonePortamento`
    // stores a non-zero parameter in ProTracker too, so a bare `300` continues
    // toward the target. A blanket "MOD has no memory" would break this — and
    // this fixture measured 1.000 against the references BEFORE the fix.
    final cells = [
      const TrackerCell(midi: 60, instrument: 1),
      const TrackerCell(midi: 67, fxCmd: 0x3, fxParam: 0x08),
      for (var i = 0; i < 10; i++) const TrackerCell(fxCmd: 0x3),
    ];
    for (final protracker in [true, false]) {
      final t = traceChannel(cells, protrackerMemory: protracker);
      expect(
        t.pitchAt(cells.length - 1, kDefaultTicksPerRow - 1),
        greaterThan(61.0),
        reason: 'a bare 300 must CONTINUE toward the target '
            '(protrackerMemory: $protracker)',
      );
    }
  });
}
