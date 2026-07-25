import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_export_report.dart';
import 'package:flutter_test/flutter_test.dart';

// A short non-empty PCM buffer so a DocSample counts as "used".
Float64List _pcm() => Float64List.fromList(const [0.0, 0.5, -0.5, 0.0]);

DocSample _sample({
  bool sixteenBit = false,
  bool stereo = false,
  DocEnvelope volumeEnvelope = const DocEnvelope(),
}) =>
    DocSample(
      pcm: _pcm(),
      pcmRight: stereo ? _pcm() : null,
      sixteenBit: sixteenBit,
      volumeEnvelope: volumeEnvelope,
    );

// [rows] rows × [channels] cells, each cell = [fill] (default empty).
DocPattern _pattern(int rows, int channels, {DocCell fill = DocCell.empty}) =>
    DocPattern(
      [for (var r = 0; r < rows; r++) List<DocCell>.filled(channels, fill)],
      channels,
    );

ModuleDoc _doc({
  required ModuleFormat sourceFormat,
  int channelCount = 4,
  List<DocSample> samples = const [],
  List<DocInstrument> itInstruments = const [],
  List<DocPattern>? patterns,
}) =>
    ModuleDoc(
      sourceFormat: sourceFormat,
      channelCount: channelCount,
      order: const [0],
      samples: samples,
      itInstruments: itInstruments,
      patterns: patterns ?? [_pattern(64, channelCount)],
    );

const _enabledEnvelope = DocEnvelope(
  enabled: true,
  points: [(0, 64), (10, 0)],
);

void main() {
  group('moduleExportLossReport', () {
    // The rich source used by the headline cases: 8 channels, a 16-bit stereo
    // sample, and an IT instrument with an envelope + NNA.
    ModuleDoc richItDoc() => _doc(
          sourceFormat: ModuleFormat.it,
          channelCount: 8,
          samples: [_sample(sixteenBit: true, stereo: true)],
          itInstruments: const [
            DocInstrument(nna: 1, volumeEnvelope: _enabledEnvelope),
          ],
          patterns: [_pattern(64, 8)],
        );

    test('8-channel 16-bit-stereo IT doc → MOD lists every MOD limitation', () {
      final report = moduleExportLossReport(richItDoc(), ModuleFormat.mod);
      expect(report, contains(ModuleExportLoss.channelsBeyond4));
      expect(report, contains(ModuleExportLoss.samplesTo8Bit));
      expect(report, contains(ModuleExportLoss.stereoToMono));
      expect(report, contains(ModuleExportLoss.instrumentModel));
      // Cross-format (IT → MOD) provenance note is included too.
      expect(report, contains(ModuleExportLoss.crossFormat(ModuleFormat.it)));
      // No extended effects and a full 64-row pattern → these must be absent.
      expect(report, isNot(contains(ModuleExportLoss.effectsBeyondMod)));
      expect(report, isNot(contains(ModuleExportLoss.rowsForcedTo64)));
    });

    test('same IT doc → IT (same format) lists only the re-encode note', () {
      final report = moduleExportLossReport(richItDoc(), ModuleFormat.it);
      expect(report, equals([ModuleExportLoss.itReencode]));
      expect(report, isNot(contains(ModuleExportLoss.channelsBeyond4)));
      expect(report, isNot(contains(ModuleExportLoss.samplesTo8Bit)));
      expect(report, isNot(contains(ModuleExportLoss.stereoToMono)));
      expect(report, isNot(contains(ModuleExportLoss.instrumentModel)));
    });

    test('plain 4-channel MOD → MOD reports nothing', () {
      final doc = _doc(
        sourceFormat: ModuleFormat.mod,
        samples: [_sample()],
      );
      expect(moduleExportLossReport(doc, ModuleFormat.mod), isEmpty);
    });

    test('MOD target flags extended effects and non-64 row patterns', () {
      final doc = _doc(
        sourceFormat: ModuleFormat.mod,
        // 0x19 (pan slide) is in the internal extended set (> 0x0F).
        patterns: [_pattern(32, 4, fill: const DocCell(effect: 0x19))],
      );
      final report = moduleExportLossReport(doc, ModuleFormat.mod);
      expect(report, contains(ModuleExportLoss.effectsBeyondMod));
      expect(report, contains(ModuleExportLoss.rowsForcedTo64));
      // Same-format MOD → no cross-format note.
      expect(
        report,
        isNot(contains(ModuleExportLoss.crossFormat(ModuleFormat.mod))),
      );
    });

    test('S3M target flags stereo, instrument model, effects, rows, samples',
        () {
      final doc = _doc(
        sourceFormat: ModuleFormat.it,
        samples: [_sample(stereo: true)],
        itInstruments: const [DocInstrument(volumeEnvelope: _enabledEnvelope)],
        // E1x (fine porta up) has no S3M/IT equivalent → dropped.
        patterns: [
          _pattern(48, 4, fill: const DocCell(effect: 0xE, effectParam: 0x10)),
        ],
      );
      final report = moduleExportLossReport(doc, ModuleFormat.s3m);
      expect(report, contains(ModuleExportLoss.stereoToMono));
      expect(report, contains(ModuleExportLoss.instrumentModel));
      expect(report, contains(ModuleExportLoss.s3mEffects));
      expect(report, contains(ModuleExportLoss.rowsForcedTo64));
      expect(report, contains(ModuleExportLoss.s3mSampleReencode));
      expect(report, contains(ModuleExportLoss.crossFormat(ModuleFormat.it)));
    });

    test('same-format S3M export does not flag effect / sample re-encode', () {
      final doc = _doc(
        sourceFormat: ModuleFormat.s3m,
        samples: [_sample()],
        patterns: [
          _pattern(64, 4, fill: const DocCell(effect: 0xE, effectParam: 0x10)),
        ],
      );
      final report = moduleExportLossReport(doc, ModuleFormat.s3m);
      expect(report, isNot(contains(ModuleExportLoss.s3mEffects)));
      expect(report, isNot(contains(ModuleExportLoss.s3mSampleReencode)));
      expect(report, isEmpty);
    });

    test('XM target flags IT-only instrument features and stereo', () {
      final doc = _doc(
        sourceFormat: ModuleFormat.it,
        samples: [_sample(stereo: true)],
        itInstruments: const [
          DocInstrument(nna: 2, pitchEnvelope: _enabledEnvelope),
        ],
      );
      final report = moduleExportLossReport(doc, ModuleFormat.xm);
      expect(report, contains(ModuleExportLoss.xmItFeatures));
      expect(report, contains(ModuleExportLoss.stereoToMono));
      expect(report, contains(ModuleExportLoss.crossFormat(ModuleFormat.it)));
      // XM keeps 16-bit and variable rows → no such warnings.
      expect(report, isNot(contains(ModuleExportLoss.samplesTo8Bit)));
      expect(report, isNot(contains(ModuleExportLoss.rowsForcedTo64)));
    });

    test('same-format XM export of a simple doc is lossless', () {
      final doc = _doc(
        sourceFormat: ModuleFormat.xm,
        samples: [_sample(sixteenBit: true)],
      );
      expect(moduleExportLossReport(doc, ModuleFormat.xm), isEmpty);
    });
  });
}
