// test/sound_control_test.dart
//
// IT/S3M `S9x` SOUND-CONTROL playback (replayer command kFxSetSoundControl =
// 0x17) and its cross-format mapping.
//
// The audible sub-commands:
//   • S9E play FORWARD (default) · S9F play BACKWARD (reverse sample playback):
//     the sample read pointer decrements, so a note reads its sample from the
//     END toward index 0.
//   • S90 surround OFF (normal panning) · S91 surround ON: the classic IT
//     pseudo-surround — render the note CENTRE with the RIGHT output channel
//     PHASE-INVERTED (R = −L) in the stereo path; a documented no-op in mono.
//
// This suite pins:
//   1. Reverse — a distinctive rising-ramp sample played with S9F reads its
//      END first and DESCENDS over time, the mirror of S9E which reads its
//      START first and RISES. Forward (S9E) and surround-off (S90) mono renders
//      are byte-identical (mono surround is a no-op), proving the forward /
//      no-surround defaults are unchanged.
//   2. Surround — S91 renders the stereo output with R ≈ −L (anti-correlated);
//      S90 restores normal centre panning (R ≈ +L).
//   3. Cross-format — S3M/IT `S9x` now maps to kFxSetSoundControl (0x17) (it
//      used to drop to (0,0)); the reverse map turns 0x17 back into `S9x`; and
//      moduleExportLossReport no longer lists S9 (nor S7, which now maps too).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/sound_control_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

// --- S9x sub-command params (carried in the low nibble). ---------------------
const int _s90SurroundOff = 0x0;
const int _s91SurroundOn = 0x1;
const int _s9eForward = 0xE;
const int _s9fBackward = 0xF;

/// A one-channel, one-row S3M carrying a single note + effect command.
ModuleDoc _s3mDoc(int command, int info) => docFromS3m(
      S3mModule(
        channelCount: 1,
        order: const [0],
        samples: const [],
        patterns: [
          S3mPattern([
            [S3mCell(note: 0x30, instrument: 1, command: command, info: info)],
          ]),
        ],
      ),
    );

/// A one-channel, one-row IT carrying a single note + effect command.
ModuleDoc _itDoc(int command, int value) => docFromIt(
      ItModule(
        channelCount: 1,
        order: const [0],
        samples: const [],
        patterns: [
          ItPattern(
            [
              [
                ItCell(
                  note: 60,
                  instrument: 1,
                  command: command,
                  commandValue: value,
                ),
              ],
            ],
            1,
          ),
        ],
      ),
    );

/// A one-channel, one-row MOD-sourced doc carrying one MOD-numbered effect (for
/// the reverse cross-format map).
ModuleDoc _modSourcedDoc(int effect, int effectParam) => ModuleDoc(
      sourceFormat: ModuleFormat.mod,
      channelCount: 1,
      order: const [0],
      samples: const [],
      patterns: [
        DocPattern(
          [
            [
              DocCell(
                note: 60,
                instrument: 1,
                effect: effect,
                effectParam: effectParam,
              ),
            ],
          ],
          1,
        ),
      ],
    );

void main() {
  // A long, monotonically RISING ramp so the read DIRECTION is directly
  // observable: reading forward gives rising values, reading backward gives
  // falling ones. normalize:false keeps the amplitude a plain gain scalar so
  // renders are directly comparable.
  final ramp = Float64List(200000);
  for (var i = 0; i < ramp.length; i++) {
    ramp[i] = i / ramp.length;
  }
  final inst = SampleInstrument('ramp', ramp, normalize: false);

  const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);

  // Row 0 triggers the note carrying the S9x sub-command; the rest ring.
  List<TrackerCell> col(int s9sub) => [
        TrackerCell(midi: 60, fxCmd: kFxSetSoundControl, fxParam: s9sub),
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
        TrackerCell.empty,
      ];

  TrackerChannel chan(List<TrackerCell> cells) => TrackerChannel(
        id: 'c',
        instrument: inst,
        rows: timing.rows,
        cells: cells,
      );

  group('reverse playback (S9F / S9E)', () {
    test('S9F reads the sample END first and DESCENDS; S9E is the mirror', () {
      final fwdCells = col(_s9eForward);
      final revCells = col(_s9fBackward);
      final fwd = replayPattern([chan(fwdCells)], [fwdCells], timing);
      final rev = replayPattern([chan(revCells)], [revCells], timing);

      // Two probes well past the note onset + its declick attack.
      const p1 = 3000, p2 = 12000;
      final fwd1 = fwd.pcm[p1], fwd2 = fwd.pcm[p2];
      final rev1 = rev.pcm[p1], rev2 = rev.pcm[p2];

      // Forward reads UP the ramp: near-zero at onset, rising over time.
      expect(fwd1, greaterThan(0));
      expect(
        fwd2,
        greaterThan(fwd1),
        reason: 'forward playback climbs the ramp',
      );

      // Backward reads DOWN from the ramp END: high at onset, falling over time.
      expect(rev1, greaterThan(0));
      expect(
        rev2,
        lessThan(rev1),
        reason: 'reverse playback descends the ramp',
      );

      // The reverse onset sits near the ramp END (high); the forward onset near
      // the START (low) — so reverse ≫ forward at the same instant.
      expect(
        rev1,
        greaterThan(fwd1 + 1000),
        reason: 'reverse onset reads the sample END, forward the START',
      );
    });

    test(
      'forward (S9E) and surround-off (S90) mono renders are byte-identical',
      () {
        // In MONO, surround is a documented no-op and S9E is the forward
        // default, so S9E, S90 and S91 all render the SAME forward samples.
        List<int> mono(int s9sub) =>
            replayPattern([chan(col(s9sub))], [col(s9sub)], timing).pcm;
        final e = mono(_s9eForward);
        expect(
          mono(_s90SurroundOff),
          orderedEquals(e),
          reason: 'S90 == S9E in mono',
        );
        expect(
          mono(_s91SurroundOn),
          orderedEquals(e),
          reason: 'surround is a no-op in mono',
        );
      },
    );
  });

  group('surround (S91 / S90)', () {
    test('S91 renders R ≈ −L (anti-correlated); S90 restores normal centre',
        () {
      final onCells = col(_s91SurroundOn);
      final offCells = col(_s90SurroundOff);
      final on = replayPatternStereo([chan(onCells)], [onCells], timing);
      final off = replayPatternStereo([chan(offCells)], [offCells], timing);

      // Probe several instants across the ringing note.
      for (final i in const [3000, 6000, 12000, 24000]) {
        final onL = on.pcm[2 * i], onR = on.pcm[2 * i + 1];
        final offL = off.pcm[2 * i], offR = off.pcm[2 * i + 1];

        // Surround ON: the right channel is the phase-inverted left (R = −L).
        expect(onL.abs(), greaterThan(100), reason: 'surround note sounds @$i');
        expect(
          onR.toDouble(),
          closeTo(-onL, 2),
          reason: 'S91: R ≈ −L (phase-inverted) @$i',
        );

        // Surround OFF: a centred note pans equally — R ≈ +L, not inverted.
        expect(offL, greaterThan(100), reason: 'centre note sounds @$i');
        expect(
          offR.toDouble(),
          closeTo(offL, 2),
          reason: 'S90: normal centre panning, R ≈ +L @$i',
        );
      }
    });
  });

  group('cross-format — S3M/IT S9x maps to kFxSetSoundControl (0x17)', () {
    test('S3M S91 → (0x17, 1); native kept for round-trip', () {
      final cell = _s3mDoc(19, 0x91).patterns.first.rows.first.first;
      expect(cell.effect, kFxSetSoundControl, reason: 'was (0,0) before');
      expect(cell.effectParam, 0x1);
      expect(cell.nativeEffect, 19);
      expect(cell.nativeEffectParam, 0x91);
    });

    test('IT S9F → (0x17, 0xF)', () {
      final cell = _itDoc(19, 0x9F).patterns.first.rows.first.first;
      expect(cell.effect, kFxSetSoundControl);
      expect(cell.effectParam, 0xF);
      expect(cell.nativeEffect, 19);
    });

    test('reverse: MOD-numbered 0x17 → S3M/IT S9x', () {
      final s3m =
          parseS3m(convertToS3m(_modSourcedDoc(kFxSetSoundControl, 0xE)));
      final sc = s3m.patterns.first.rows.first.first;
      expect(sc.command, 19, reason: '0x17 → S letter-command');
      expect(sc.info, (0x9 << 4) | 0xE, reason: 'S9E');
    });

    test('moduleExportLossReport no longer lists S9 (nor S7)', () {
      // An S9x doc: the export loss no longer names it as an unmapped special.
      final s9Report =
          moduleExportLossReport(_s3mDoc(19, 0x91), ModuleFormat.mod);
      expect(
        s9Report,
        isNot(contains(ModuleExportLoss.unmappedSpecialEffects)),
        reason: 'S9x now maps, so it is no longer an unmapped-special drop',
      );
      expect(ModuleExportLoss.unmappedSpecialEffects, isNot(contains('S9')));
      expect(
        ModuleExportLoss.unmappedSpecialEffects,
        isNot(contains('surround')),
      );

      // S7x (past-note / NNA control) now maps to kFxSetPastNote too, so it is
      // likewise no longer named as an unmapped-special drop.
      final s7Report =
          moduleExportLossReport(_s3mDoc(19, 0x71), ModuleFormat.mod);
      expect(
        s7Report,
        isNot(contains(ModuleExportLoss.unmappedSpecialEffects)),
        reason: 'S7x now maps via kFxSetPastNote',
      );
    });
  });
}
