// test/panbrello_waveform_test.dart
//
// Panbrello waveform selection (S3M/IT `S5x`). Two halves:
//
//  1. Replayer — a per-voice panbrello waveform (0 sine / 1 saw / 2 square) is
//     honored by the panbrello pan LFO, mirroring the vibrato (E4x) / tremolo
//     (E7x) waveform selects. The set command (kFxSetPanbrelloWaveform) changes
//     the shape of the L/R pan trajectory away from the sine default.
//
//  2. Cross-format — S3M/IT `S5x` now maps to kFxSetPanbrelloWaveform (0x12)
//     instead of the neutral (0,0), survives the round-trip back to Sxy, and
//     moduleExportLossReport no longer lists S5 as an unmapped special (while
//     S7/S9/SA and the IT Zxx filter/MIDI drop are still surfaced).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/panbrello_waveform_test.dart

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The panbrello pan trajectory (per tick) for a voice using panbrello Y84
/// (speed 8, depth 4) after selecting [waveform] (0 sine / 1 saw / 2 square).
List<double> _panTrace(int waveform) {
  final v = ReplayVoice();
  // S5x set-waveform on its own row (no note) — persistent control state.
  if (waveform != 0) {
    v.armRow(TrackerCell(fxCmd: kFxSetPanbrelloWaveform, fxParam: waveform));
  }
  // A note + panbrello Y84 — the note resets the LFO phase (both traces start
  // from phase 0), so the ONLY difference between traces is the waveform.
  v.armRow(const TrackerCell(midi: 60, fxCmd: kFxPanbrello, fxParam: 0x84));
  const ticksPerRow = 16;
  return [for (var k = 0; k < ticksPerRow; k++) v.tick(k, ticksPerRow).pan];
}

/// A one-channel, one-row S3M carrying a single note + `Sxy` command.
ModuleDoc _s3mSpecialDoc(int info) => docFromS3m(
      S3mModule(
        channelCount: 1,
        order: const [0],
        samples: const [],
        patterns: [
          S3mPattern([
            [S3mCell(note: 0x30, instrument: 1, command: 19, info: info)],
          ]),
        ],
      ),
    );

/// A one-channel, one-row MOD-sourced neutral doc carrying [effect]/[param].
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
  group('replayer — panbrello waveform is honored', () {
    // depth 4 → |pan| peak = 4 * kPanbrelloDepthPerUnit.
    const peak = 4 * kPanbrelloDepthPerUnit;

    test('sine is the default and its LFO starts at zero', () {
      final sine = _panTrace(0);
      // A sine panbrello crosses zero at phase 0 and never exceeds the depth.
      expect(sine.first, closeTo(0.0, 1e-12));
      for (final p in sine) {
        expect(p.abs(), lessThanOrEqualTo(peak + 1e-9));
      }
      // It actually pans (not a flat zero).
      expect(sine.any((p) => p.abs() > 1e-6), isTrue);
    });

    test('square (S52) makes the pan LFO a full-swing ±depth square', () {
      final square = _panTrace(2);
      // Every sample sits at ±the depth peak — the defining square property,
      // which the sine default never satisfies.
      for (final p in square) {
        expect(p.abs(), closeTo(peak, 1e-12));
      }
      // …and its trajectory differs from the sine default.
      final sine = _panTrace(0);
      expect(_differs(square, sine), isTrue);
    });

    test('saw (S51) differs from both the sine default and the square', () {
      final saw = _panTrace(1);
      expect(_differs(saw, _panTrace(0)), isTrue);
      expect(_differs(saw, _panTrace(2)), isTrue);
    });
  });

  group('cross-format — S5x set panbrello waveform', () {
    test('S3M/IT S52 imports to kFxSetPanbrelloWaveform (0x12), was (0,0)', () {
      final cell = _s3mSpecialDoc(0x52).patterns.first.rows.first.first;
      expect(cell.effect, kFxSetPanbrelloWaveform); // 0x12
      expect(cell.effectParam, 0x2);
      // Native provenance retained for a same-format export.
      expect(cell.nativeEffect, 19);
      expect(cell.nativeEffectParam, 0x52);
    });

    test('reverse: neutral 0x12 → S3M S5x', () {
      final s3m =
          parseS3m(convertToS3m(_modSourcedDoc(kFxSetPanbrelloWaveform, 0x2)));
      final sc = s3m.patterns.first.rows.first.first;
      expect(sc.command, 19, reason: 'kFxSetPanbrelloWaveform → Sxy');
      expect(sc.info, (0x5 << 4) | 0x2); // S52
    });

    test('S5x is no longer reported as an unmapped special', () {
      final report =
          moduleExportLossReport(_s3mSpecialDoc(0x52), ModuleFormat.mod);
      expect(
        report,
        isNot(contains(ModuleExportLoss.unmappedSpecialEffects)),
        reason: 'S5x now maps to kFxSetPanbrelloWaveform',
      );
      // The named-drop message no longer mentions panbrello / S5.
      expect(ModuleExportLoss.unmappedSpecialEffects, isNot(contains('S5')));
      expect(
        ModuleExportLoss.unmappedSpecialEffects,
        isNot(contains('panbrello')),
      );
    });

    test('S7/S9/SA are still reported as unmapped specials', () {
      // S7x (past-note/NNA) still has no neutral equivalent.
      final report =
          moduleExportLossReport(_s3mSpecialDoc(0x72), ModuleFormat.mod);
      expect(report, contains(ModuleExportLoss.unmappedSpecialEffects));
      for (final s in const ['S7', 'S9', 'SA']) {
        expect(ModuleExportLoss.unmappedSpecialEffects, contains(s));
      }
    });

    test('the IT Zxx filter/MIDI drop (Z) is still surfaced', () {
      // Z (MIDI-macro, command 26) still drops on cross-format export.
      final zDoc = docFromS3m(
        const S3mModule(
          channelCount: 1,
          order: [0],
          samples: [],
          patterns: [
            S3mPattern([
              [S3mCell(note: 0x30, instrument: 1, command: 26, info: 0x12)],
            ]),
          ],
        ),
      );
      expect(
        moduleExportLossReport(zDoc, ModuleFormat.mod),
        contains(ModuleExportLoss.filterEffects),
      );
    });
  });
}

/// True if any per-tick pan value of [a] and [b] differs beyond epsilon.
bool _differs(List<double> a, List<double> b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return true;
  }
  return false;
}
