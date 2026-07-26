// lib/core/audio/mod/module_export_report.dart
//
// Export-loss report: given the neutral [ModuleDoc] that is about to be written
// and the TARGET container format, describe — in plain, human-readable lines —
// what that format cannot represent, so the user sees the cost of an export
// BEFORE it happens. Pure and Flutter-free: it only inspects [ModuleDoc] and
// mirrors the concrete lossiness of the writers in module_convert.dart
// (docToMod / docToS3m / docToXm / docToIt).
//
// Each message is grounded in a REAL limitation of the chosen writer and is only
// emitted when the doc actually triggers it (e.g. the >4-channel warning fires
// only for a doc with >4 channels). An empty list means the export is (as far as
// the model can tell) lossless — in particular a same-format export with no
// container-specific caveat returns `[]`.

import 'package:comet_beat/core/audio/mod/module_doc.dart';

/// The human-readable loss messages, exposed as named constants so callers (and
/// tests) can reference an exact string instead of matching substrings.
class ModuleExportLoss {
  ModuleExportLoss._();

  /// MOD is a 4-channel format; docToMod keeps channels 0..3 and drops the rest.
  static const channelsBeyond4 =
      'MOD supports only 4 channels; channels beyond the 4th are dropped.';

  /// MOD samples are 8-bit PCM only; 16-bit precision is quantised down.
  static const samplesTo8Bit =
      '16-bit samples are reduced to 8-bit (MOD stores 8-bit samples only).';

  /// MOD/S3M/XM store mono samples; a stereo sample loses its right channel.
  static const stereoToMono =
      'Stereo samples are mixed to mono; the right channel is dropped.';

  /// MOD/S3M have no instrument layer: envelopes, keymaps and IT new-note
  /// actions are not stored.
  static const instrumentModel =
      'Instrument envelopes, keymaps and NNA/DCT actions are not stored in '
      'this format.';

  /// Effects in the internal extended set (> 0x0F) have no MOD command nibble.
  static const effectsBeyondMod =
      'Effects outside the MOD command set are dropped.';

  /// MOD and S3M patterns are a fixed 64 rows; others are padded or truncated.
  static const rowsForcedTo64 =
      'Patterns are forced to 64 rows (padded or truncated).';

  /// S3M's command set differs; some effects are approximated or dropped.
  static const s3mEffects =
      'Some effects are approximated or dropped (the S3M command set differs).';

  /// The IT resonant low-pass filter (Zxx cutoff/resonance and the raw MIDI
  /// macros it drives) exists only in IT; no other container can store it.
  static const filterEffects =
      'Filter / MIDI effects (IT Zxx cutoff/resonance and MIDI macros) are not '
      'represented in this format.';

  /// Sxy control sub-commands with no faithful cross-format equivalent — they
  /// survive only a same-format export (S3M→S3M / IT→IT via native provenance).
  static const unmappedSpecialEffects =
      'Some Sxy control effects are dropped: S0x set-filter toggle, S7x '
      'NNA/envelope control, S9x surround/reverse, SFx MIDI macro.';

  /// Cross-format samples are re-encoded to S3M PCM; AdLib/packed data is lost.
  static const s3mSampleReencode =
      'Samples are re-encoded as S3M PCM; source AdLib/OPL or packed-sample '
      'data is not reconstructed.';

  /// XM has volume/pan envelopes + fadeout, but no IT-style NNA/DCT/pitch env.
  static const xmItFeatures =
      'IT instrument features (NNA/DCT/DCA, pitch envelopes, sustain points) '
      'are not represented in XM.';

  /// writeIt re-encodes patterns and drops song message / MIDI-macro / packing.
  static const itReencode =
      'IT patterns are re-encoded (not byte-identical); message text and MIDI '
      'macros are not written, and compressed samples are exported '
      'uncompressed.';

  /// Native command provenance survives only a same-format export.
  static String crossFormat(ModuleFormat source) =>
      'Native ${source.name.toUpperCase()} command data beyond the shared '
      'model is dropped; only exporting back to .${source.name} preserves it.';
}

/// MOD-numbered `(effect, param)` values the S3M/IT letter-command mapping
/// (`_fxToLetterEffect` in module_convert.dart) can represent. Anything else
/// with a real command is dropped by those writers.
const _s3mItRepresentableEffects = <int>{
  0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xD, 0xF, //
  0x10, 0x11, 0x12, 0x13, 0x14, 0x19, 0x1B, 0x1D, 0x1E, 0x1F,
};

/// True if [c]'s effect would be dropped when written through the S3M/IT
/// letter-command mapping. `0x0`/param 0 is "no command"; `0x0` with a param is
/// arpeggio (kept); `0xC` set-volume routes to the volume column (not a loss);
/// `0xE` extended survives only for the sub-commands S3M/IT share
/// (3/4/5/6/7/C/D/E ↔ S1/S3/S2/SB/S4/SC/SD/SE).
bool _letterEffectLost(DocCell c) {
  final e = c.effect;
  if (e == 0) return false; // none, or arpeggio (0, param) which maps to J
  if (e == 0xC) return false; // set-volume → volume column
  if (e == 0xE) {
    final sub = (c.effectParam >> 4) & 0xF;
    const roundTrips = {0x3, 0x4, 0x5, 0x6, 0x7, 0xC, 0xD, 0xE};
    return !roundTrips.contains(sub);
  }
  return !_s3mItRepresentableEffects.contains(e);
}

/// S3M/IT `Sxy` sub-command nibbles that `_s3mSpecialToFx` (module_convert.dart)
/// maps to a neutral effect. Any other sub-command drops on cross-format export.
const _mappedSpecialSubs = <int>{
  0x1,
  0x2,
  0x3,
  0x4,
  0x5,
  0x6,
  0x8,
  0xA,
  0xB,
  0xC,
  0xD,
  0xE,
};

/// True if [c] carries an S3M/IT `S` letter-command (19) whose sub-command has
/// no neutral equivalent (S0/S7/S9/SF) — dropped on any cross-format export.
/// (SAx now maps to kFxSetHighOffset, so it is no longer listed here.) Read from
/// the native command, since the neutral effect column is already `(0, 0)` for
/// these.
bool _hasUnmappedSpecial(DocCell c) =>
    c.nativeEffect == 19 &&
    !_mappedSpecialSubs.contains((c.nativeEffectParam >> 4) & 0xF);

/// True if [c] carries a resonant-filter or MIDI-macro effect (IT `Zxx`): the
/// neutral kFxSetFilter (0x1C) for a recognised cutoff/resonance macro, or an
/// IT/S3M `Z` letter-command (26) that dropped to a raw MIDI macro. Only IT can
/// store these, so every other target loses them.
bool _hasFilterEffect(DocCell c) => c.effect == 0x1C || c.nativeEffect == 26;

bool _anyCell(ModuleDoc doc, bool Function(DocCell) test) {
  for (final pattern in doc.patterns) {
    for (final row in pattern.rows) {
      for (final cell in row) {
        if (test(cell)) return true;
      }
    }
  }
  return false;
}

/// Describe what exporting [doc] to [target] cannot represent.
///
/// Returns an empty list when nothing is lost (as far as the neutral model can
/// tell) — notably for a same-format export of a doc with no target-specific
/// caveat. Every message is drawn from [ModuleExportLoss] and gated on the doc
/// actually exhibiting the condition.
List<String> moduleExportLossReport(ModuleDoc doc, ModuleFormat target) {
  final source = doc.sourceFormat;
  final out = <String>[];

  final usedSamples = doc.samples.where((s) => !s.isEmpty).toList();
  final has16Bit = usedSamples.any((s) => s.sixteenBit);
  final hasStereo = usedSamples.any((s) => s.pcmRight != null);
  final hasEnvelopes = usedSamples.any(
        (s) => !s.volumeEnvelope.isEmpty || !s.panEnvelope.isEmpty,
      ) ||
      doc.itInstruments.any(
        (i) =>
            !i.volumeEnvelope.isEmpty ||
            !i.panEnvelope.isEmpty ||
            !i.pitchEnvelope.isEmpty,
      );
  final hasNnaOrDct =
      doc.itInstruments.any((i) => i.nna != 0 || i.dct != 0 || i.dca != 0);
  final hasPitchEnvelope =
      doc.itInstruments.any((i) => !i.pitchEnvelope.isEmpty);
  final hasKeymap = doc.itInstruments.any((i) => i.keymap.toSet().length > 1);
  final hasInstrumentModel =
      hasEnvelopes || hasNnaOrDct || hasPitchEnvelope || hasKeymap;

  final channelsBeyond4 = doc.channelCount > 4;
  final oddRows = doc.patterns.any((p) => p.numRows > 0 && p.numRows != 64);

  switch (target) {
    case ModuleFormat.mod:
      if (channelsBeyond4) out.add(ModuleExportLoss.channelsBeyond4);
      if (has16Bit) out.add(ModuleExportLoss.samplesTo8Bit);
      if (hasStereo) out.add(ModuleExportLoss.stereoToMono);
      if (hasInstrumentModel) out.add(ModuleExportLoss.instrumentModel);
      if (_anyCell(doc, (c) => c.effect > 0xF)) {
        out.add(ModuleExportLoss.effectsBeyondMod);
      }
      if (oddRows) out.add(ModuleExportLoss.rowsForcedTo64);
    case ModuleFormat.s3m:
      if (hasStereo) out.add(ModuleExportLoss.stereoToMono);
      if (hasInstrumentModel) out.add(ModuleExportLoss.instrumentModel);
      if (source != ModuleFormat.s3m && _anyCell(doc, _letterEffectLost)) {
        out.add(ModuleExportLoss.s3mEffects);
      }
      if (oddRows) out.add(ModuleExportLoss.rowsForcedTo64);
      if (source != ModuleFormat.s3m && usedSamples.isNotEmpty) {
        out.add(ModuleExportLoss.s3mSampleReencode);
      }
    case ModuleFormat.xm:
      if (hasStereo) out.add(ModuleExportLoss.stereoToMono);
      if (hasNnaOrDct || hasPitchEnvelope) {
        out.add(ModuleExportLoss.xmItFeatures);
      }
    case ModuleFormat.it:
      out.add(ModuleExportLoss.itReencode);
  }

  // Filter (IT Zxx) exists only in IT: every other target drops it. Gated on
  // the doc actually carrying a filter/MIDI effect so a filter-free song is
  // never falsely flagged.
  if (target != ModuleFormat.it && _anyCell(doc, _hasFilterEffect)) {
    out.add(ModuleExportLoss.filterEffects);
  }
  // Unmapped Sxy control sub-commands survive only a same-format export (native
  // provenance); any cross-format conversion drops them.
  if (source != target && _anyCell(doc, _hasUnmappedSpecial)) {
    out.add(ModuleExportLoss.unmappedSpecialEffects);
  }

  if (source != target) out.add(ModuleExportLoss.crossFormat(source));
  return out;
}
