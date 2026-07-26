// test/cross_format_effects_test.dart
//
// Cross-format effect widening: commands that a source format carries but a
// target format used to DROP (mapping to the neutral (0,0)) now survive through
// the neutral ModuleDoc hub. Each case builds a single-cell source module,
// converts it to a target via the doc pipeline (convertToMod/S3m/It, i.e. the
// same path as convertDocTo), re-reads the target bytes, and asserts the mapped
// effect is present. A regression case pins that a genuinely unmappable command
// (Z — MIDI macro) still drops and is surfaced by moduleExportLossReport.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/cross_format_effects_test.dart

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:comet_beat/core/audio/mod/s3m_module.dart';
import 'package:comet_beat/core/audio/mod/s3m_reader.dart';
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

/// A one-channel, one-row neutral doc that reports itself as sourced from
/// [source] and carries a single MOD-numbered effect on channel 0.
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
  group('S3M/IT special sub-commands now survive to MOD Exy', () {
    // sub-command nibble → the MOD extended (high nibble, i.e. E?x) it maps to.
    const cases = {
      0x1: 0x3, // S1x glissando control  → E3x
      0x2: 0x5, // S2x set finetune        → E5x
      0x3: 0x4, // S3x vibrato waveform    → E4x
      0x4: 0x7, // S4x tremolo waveform    → E7x
    };

    cases.forEach((sub, exHigh) {
      final info = (sub << 4) | 0x2; // sub-command with value 2
      test('S3M S${sub.toRadixString(16)}x → MOD E${exHigh}x', () {
        // Import maps it into the neutral extended set (was (0,0) before).
        final cell = _s3mDoc(19, info).patterns.first.rows.first.first;
        expect(cell.effect, 0xE);
        expect(cell.effectParam, (exHigh << 4) | 0x2);
        // And it survives the full convert to MOD bytes.
        final mod = parseMod(convertToMod(_s3mDoc(19, info)));
        final mc = mod.patterns.first.rows.first.first;
        expect(mc.effect, 0xE, reason: 'S${sub.toRadixString(16)}x → Exy');
        expect(mc.effectParam, (exHigh << 4) | 0x2);
      });

      test('IT S${sub.toRadixString(16)}x → MOD E${exHigh}x', () {
        final cell = _itDoc(19, info).patterns.first.rows.first.first;
        expect(cell.effect, 0xE);
        expect(cell.effectParam, (exHigh << 4) | 0x2);
        final mod = parseMod(convertToMod(_itDoc(19, info)));
        final mc = mod.patterns.first.rows.first.first;
        expect(mc.effect, 0xE);
        expect(mc.effectParam, (exHigh << 4) | 0x2);
      });
    });
  });

  group('MOD Exy waveform/finetune/glissando now survive to S3M/IT Sxy', () {
    // MOD extended high-nibble → the S3M/IT Sxy sub-command it maps back to.
    const cases = {
      0x3: 0x1, // E3x glissando        → S1x
      0x4: 0x3, // E4x vibrato waveform → S3x
      0x5: 0x2, // E5x set finetune     → S2x
      0x7: 0x4, // E7x tremolo waveform → S4x
    };

    cases.forEach((exHigh, sub) {
      final param = (exHigh << 4) | 0x2;
      test('MOD E${exHigh}x → S3M S${sub.toRadixString(16)}x', () {
        final s3m = parseS3m(convertToS3m(_modSourcedDoc(0xE, param)));
        final sc = s3m.patterns.first.rows.first.first;
        expect(sc.command, 19, reason: 'E${exHigh}x → Sxy');
        expect(sc.info, (sub << 4) | 0x2);
      });

      test('MOD E${exHigh}x → IT S${sub.toRadixString(16)}x', () {
        final it = parseIt(convertToIt(_modSourcedDoc(0xE, param)));
        final ic = it.patterns.first.rows.first.first;
        expect(ic.command, 19);
        expect(ic.commandValue, (sub << 4) | 0x2);
      });
    });
  });

  test('Z (MIDI macro) still drops and is export-loss-reported', () {
    final doc = _s3mDoc(26, 0x12); // Z12
    final cell = doc.patterns.first.rows.first.first;
    // Dropped on the neutral effect column…
    expect(cell.effect, 0);
    expect(cell.effectParam, 0);
    // …but the native command is retained (same-format S3M export keeps it).
    expect(cell.nativeEffect, 26);
    // Converting S3M→MOD carries no effect for the cell.
    final mod = parseMod(convertToMod(doc));
    final mc = mod.patterns.first.rows.first.first;
    expect(mc.effect, 0);
    expect(mc.effectParam, 0);
    // The loss is surfaced to the user.
    final report = moduleExportLossReport(doc, ModuleFormat.mod);
    expect(report, isNotEmpty);
    expect(report, contains(ModuleExportLoss.crossFormat(ModuleFormat.s3m)));
    // …and specifically named as a filter/MIDI drop.
    expect(report, contains(ModuleExportLoss.filterEffects));
  });

  group('IT Zxx resonant filter', () {
    test('Z40 maps to the neutral kFxSetFilter (0x1C) cutoff', () {
      final cell = _itDoc(26, 0x40).patterns.first.rows.first.first;
      expect(cell.effect, 0x1C, reason: 'IT Zxx → kFxSetFilter');
      expect(cell.effectParam, 0x40);
      expect(cell.nativeEffect, 26);
    });

    test('IT→IT keeps the filter and does NOT flag a filter loss', () {
      final doc = _itDoc(26, 0x40);
      // The filter is representable only in IT, so a same-format export is
      // lossless for it: the report must NOT name a filter drop.
      final report = moduleExportLossReport(doc, ModuleFormat.it);
      expect(report, isNot(contains(ModuleExportLoss.filterEffects)));
    });

    test('IT→MOD drops the filter and names it in the report', () {
      final doc = _itDoc(26, 0x40);
      // kFxSetFilter (0x1C) > 0x0F → no MOD command nibble → dropped.
      final mc = parseMod(convertToMod(doc)).patterns.first.rows.first.first;
      expect(mc.effect, 0);
      expect(mc.effectParam, 0);
      final report = moduleExportLossReport(doc, ModuleFormat.mod);
      expect(report, contains(ModuleExportLoss.filterEffects));
    });
  });

  group('unmapped Sxy sub-commands drop and are export-loss-reported', () {
    // Every remaining special sub-command that GENUINELY has no faithful
    // neutral/replayer equivalent (verified against the IT/ST3 spec):
    //   S0 set-filter toggle · S5 panbrello waveform · S7 NNA/envelope control ·
    //   S9 surround/reverse · SA high sample offset · SF set MIDI macro.
    const droppedSubs = {
      0x0: 'S0 (set filter on/off)',
      0x5: 'S5 (panbrello waveform)',
      0x7: 'S7 (NNA / envelope control)',
      0x9: 'S9 (surround / reverse)',
      0xA: 'SA (high sample offset)',
      0xF: 'SF (set MIDI macro)',
    };

    droppedSubs.forEach((sub, label) {
      final info = (sub << 4) | 0x1; // sub-command with value 1

      test('S3M $label drops to (0,0) but keeps native + is reported', () {
        final doc = _s3mDoc(19, info);
        final cell = doc.patterns.first.rows.first.first;
        // No neutral effect…
        expect(cell.effect, 0);
        expect(cell.effectParam, 0);
        // …native S command retained for a same-format S3M round-trip.
        expect(cell.nativeEffect, 19);
        expect(cell.nativeEffectParam, info);
        // Cross-format to MOD carries no effect.
        final mc = parseMod(convertToMod(doc)).patterns.first.rows.first.first;
        expect(mc.effect, 0);
        // The drop is surfaced to the user.
        final report = moduleExportLossReport(doc, ModuleFormat.mod);
        expect(
          report,
          contains(ModuleExportLoss.unmappedSpecialEffects),
          reason: '$label must be named as an unmapped Sxy drop',
        );
      });

      test('IT $label drops to (0,0) but keeps native + is reported', () {
        final doc = _itDoc(19, info);
        final cell = doc.patterns.first.rows.first.first;
        expect(cell.effect, 0);
        expect(cell.effectParam, 0);
        expect(cell.nativeEffect, 19);
        expect(cell.nativeEffectParam, info);
        // Cross-format IT→S3M also loses it (neutral column is empty).
        final report = moduleExportLossReport(doc, ModuleFormat.s3m);
        expect(report, contains(ModuleExportLoss.unmappedSpecialEffects));
      });
    });

    test('a same-format S3M export does NOT flag the Sxy drop (native kept)',
        () {
      final doc = _s3mDoc(19, 0x91); // S9 surround
      final report = moduleExportLossReport(doc, ModuleFormat.s3m);
      expect(report, isNot(contains(ModuleExportLoss.unmappedSpecialEffects)));
    });
  });
}
