// test/high_sample_offset_test.dart
//
// High sample offset (S3M/IT `SAx`, replayer command kFxSetHighOffset = 0x13).
//
// `SAx` sets the HIGH byte of the sample-start offset that a SUBSEQUENT `9xx`
// (kFxSampleOffset) uses, following the IT/OpenMPT convention:
//     startSample = (highOffset << 16) | (param9xx << 8)
// i.e. the `9xx` param is the MIDDLE byte (param × 256) and `SAx` adds the HIGH
// byte (x × 65536). The high-offset is per-channel effect memory: it persists
// until another `SAx` changes it. With a 0 high-offset a plain `9xx` render is
// byte-identical to the classic behaviour.
//
// This suite pins:
//   1. ReplayVoice.sampleReadStart — the offset-combination convention, the
//      effect memory, and byte-identity of a plain `9xx` (highOffset 0).
//   2. A tick-voice render — a `SAx`+`9xx` note reads DEEPER into the sample
//      than a `9xx` starting at the plain (highOffset 0) position, so it sounds.
//   3. The cross-format map — S3M/IT `SAx` now maps to the neutral 0x13 command
//      (was dropped to (0,0)), and moduleExportLossReport no longer lists SA
//      (but still names S7/SF and the IT Z filter drop).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/high_sample_offset_test.dart

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

/// A one-channel, one-row neutral MOD-sourced doc carrying one MOD-numbered
/// effect on channel 0 (for the reverse cross-format map).
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
  group('ReplayVoice.sampleReadStart — the SAx/9xx offset convention', () {
    test('a plain 9xx (highOffset 0) is byte-identical to classic param×256',
        () {
      final voice = ReplayVoice();
      // With the default (0) high-offset memory, sampleReadStart must equal the
      // old inline formula `param × 256 × offsetScale` EXACTLY — the byte-
      // identity guarantee for a SAx-free render.
      for (final p in const [0x00, 0x01, 0x08, 0x40, 0x80, 0xFF]) {
        final cell = TrackerCell(midi: 60, fxCmd: kFxSampleOffset, fxParam: p);
        expect(voice.sampleReadStart(cell, 1.0), (p * 256).toDouble());
        expect(voice.sampleReadStart(cell, 0.5), p * 256 * 0.5);
      }
      // A cell not carrying 9xx contributes no offset.
      expect(voice.sampleReadStart(const TrackerCell(midi: 60), 1.0), 0.0);
      expect(voice.highOffset, 0);
    });

    test('SAx sets the HIGH byte a subsequent 9xx combines in', () {
      final voice = ReplayVoice();
      // SA1 → high-offset memory 1 (× 65536).
      voice.armRow(const TrackerCell(fxCmd: kFxSetHighOffset, fxParam: 1));
      expect(voice.highOffset, 1);
      const cell = TrackerCell(midi: 60, fxCmd: kFxSampleOffset, fxParam: 0x80);
      // start = (1 << 16) | (0x80 << 8) = 65536 + 32768 = 98304.
      expect(voice.sampleReadStart(cell, 1.0), 98304.0);
      // ...and it rides the instrument's offsetScale.
      expect(voice.sampleReadStart(cell, 0.5), 49152.0);
    });

    test('the high offset persists per channel (effect memory)', () {
      final voice = ReplayVoice();
      voice.armRow(const TrackerCell(fxCmd: kFxSetHighOffset, fxParam: 2));
      // A later row with no SAx keeps the memory.
      voice.armRow(const TrackerCell(midi: 60));
      expect(voice.highOffset, 2);
      // A 9x00 (param 0) with the high offset set → the read start is purely
      // the high byte.
      const cell = TrackerCell(midi: 60, fxCmd: kFxSampleOffset);
      // start = (2 << 16) | 0 = 131072.
      expect(voice.sampleReadStart(cell, 1.0), 131072.0);
      // A new SAx REPLACES it — a direct SET, so SA0 clears it back to 0.
      voice.armRow(const TrackerCell(fxCmd: kFxSetHighOffset));
      expect(voice.highOffset, 0);
      expect(voice.sampleReadStart(cell, 1.0), 0.0);
    });
  });

  group('render — a SAx+9xx note reads deeper into the sample', () {
    test('a higher SAx starts the note higher up a ramp (so it sounds)', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      // A long, monotonically RISING ramp so the read START position is directly
      // observable: a deeper start reads a higher value. normalize:false keeps
      // the amplitude a plain `gain` scalar (no per-channel peak normalisation),
      // so the two renders are directly comparable.
      final ramp = Float64List(260000);
      for (var i = 0; i < ramp.length; i++) {
        ramp[i] = i / ramp.length;
      }
      final inst = SampleInstrument('ramp', ramp, normalize: false);

      // Row 0 seeds the high-offset memory; row 1 triggers the note with 9x80.
      // Both channels carry a SAx, so both run the SAME tick-voice path — the
      // ONLY difference is the high offset, isolating the read-start shift.
      List<TrackerCell> col(int highOffset) => [
            TrackerCell(fxCmd: kFxSetHighOffset, fxParam: highOffset),
            const TrackerCell(midi: 60, fxCmd: kFxSampleOffset, fxParam: 0x80),
            TrackerCell.empty,
            TrackerCell.empty,
          ];

      TrackerChannel chan(List<TrackerCell> cells) => TrackerChannel(
            id: 'c',
            instrument: inst,
            rows: timing.rows,
            cells: cells,
          );

      // deep: SA1 → 9x80 starts at (1<<16)|(0x80<<8) = 98304.
      // shallow: SA0 → 9x80 starts at 0x80×256 = 32768 (the plain-9xx position).
      final deepCells = col(1);
      final shallowCells = col(0);
      final deep = replayPatternStereo([chan(deepCells)], [deepCells], timing);
      final shallow =
          replayPatternStereo([chan(shallowCells)], [shallowCells], timing);

      // Probe well past the note onset (and its declick attack) on row 1.
      final probe = timing.stepStartSample(1) + 4000;
      final deepL = deep.pcm[2 * probe];
      final shallowL = shallow.pcm[2 * probe];

      // Both sound (non-silent) …
      expect(shallowL, greaterThan(0));
      expect(deepL, greaterThan(0));
      // … and the SAx-deepened note sits clearly higher up the ramp.
      expect(deepL, greaterThan(shallowL + 500));
    });
  });

  group('cross-format — S3M/IT SAx maps to kFxSetHighOffset (0x13)', () {
    test('S3M SAx → neutral (0x13, x); native kept for round-trip', () {
      // SA1 → high offset 1.
      final cell = _s3mDoc(19, 0xA1).patterns.first.rows.first.first;
      expect(cell.effect, kFxSetHighOffset, reason: 'was (0,0) before');
      expect(cell.effectParam, 0x1);
      expect(cell.nativeEffect, 19);
      expect(cell.nativeEffectParam, 0xA1);
    });

    test('IT SAx → neutral (0x13, x)', () {
      final cell = _itDoc(19, 0xA5).patterns.first.rows.first.first;
      expect(cell.effect, kFxSetHighOffset);
      expect(cell.effectParam, 0x5);
      expect(cell.nativeEffect, 19);
    });

    test('reverse: MOD-numbered 0x13 → S3M/IT SAx', () {
      final s3m = parseS3m(convertToS3m(_modSourcedDoc(kFxSetHighOffset, 0x3)));
      final sc = s3m.patterns.first.rows.first.first;
      expect(sc.command, 19, reason: '0x13 → S letter-command');
      expect(sc.info, (0xA << 4) | 0x3, reason: 'SA3');
    });

    test('moduleExportLossReport no longer lists SA, but still S7/SF/Z', () {
      // A SAx doc: the export loss no longer names it as an unmapped special.
      final saDoc = _s3mDoc(19, 0xA1);
      final saReport = moduleExportLossReport(saDoc, ModuleFormat.mod);
      expect(
        saReport,
        isNot(contains(ModuleExportLoss.unmappedSpecialEffects)),
        reason: 'SAx now maps, so it is no longer an unmapped-special drop',
      );
      // The message text itself no longer mentions the high sample offset.
      expect(
        ModuleExportLoss.unmappedSpecialEffects,
        isNot(contains('high sample offset')),
      );
      expect(ModuleExportLoss.unmappedSpecialEffects, isNot(contains('SA')));

      // S7x (NNA/envelope control) still has no neutral equivalent → reported.
      final s7Report =
          moduleExportLossReport(_s3mDoc(19, 0x71), ModuleFormat.mod);
      expect(s7Report, contains(ModuleExportLoss.unmappedSpecialEffects));
      // SFx (set MIDI macro) likewise.
      final sfReport =
          moduleExportLossReport(_s3mDoc(19, 0xF1), ModuleFormat.mod);
      expect(sfReport, contains(ModuleExportLoss.unmappedSpecialEffects));
      // The IT Zxx resonant filter / MIDI macro still drops cross-format.
      final zReport =
          moduleExportLossReport(_itDoc(26, 0x40), ModuleFormat.mod);
      expect(zReport, contains(ModuleExportLoss.filterEffects));
    });
  });
}
