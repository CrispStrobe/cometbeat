// lib/core/audio/tracker_native_command.dart
//
// Pure, Flutter-free helpers for the RAW native-command provenance a
// [TrackerCell] preserves for same-format export, plus the small subset of
// native module-header state that survives import onto an editable
// [TrackerSong].
//
// A cell carries, alongside the normalized `fxCmd`/`fxParam`, the ORIGINAL
// format command it was imported from: `nativeFormat` (e.g. "s3m"), the
// `nativeEffect` byte/letter-command, its `nativeEffectParam`, and the
// `nativeVolpan` byte. The normal editor edits the normalized command; these
// helpers surface and edit the raw native bytes directly so a same-format
// (S3M/IT/XM/MOD) export re-emits the exact original command.
//
// Unit-tested in test/native_command_edit_test.dart (no device audio).

import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;

/// Whether [cell] carries any raw native effect/volume provenance.
bool hasNativeProvenance(TrackerCell cell) =>
    cell.nativeEffect >= 0 ||
    cell.nativeVolpan >= 0 ||
    cell.nativeFormat != null;

/// Writes raw native effect provenance onto [cell] for same-format export.
///
/// [format] is the source-format tag (`"mod"`/`"s3m"`/`"xm"`/`"it"`) that
/// must match the export target for the native command to be re-emitted;
/// [effect] is the format's raw effect command (MOD nibble 0..15, S3M/IT
/// letter-command 1..26 = A..Z, XM effect byte), and [param] its 0..255 info
/// byte. The normalized `fxCmd`/`fxParam` are left untouched — this edits the
/// provenance channel only.
TrackerCell setNativeEffect(
  TrackerCell cell, {
  required String format,
  required int effect,
  required int param,
}) =>
    cell.copyWith(
      nativeFormat: format,
      nativeEffect: effect.clamp(0, 0xFF),
      nativeEffectParam: param.clamp(0, 0xFF),
    );

/// Writes the raw native volume/pan-column byte onto [cell] (S3M/IT/XM keep the
/// volume column as a distinct byte); pass [volpan] < 0 to leave it unset.
TrackerCell setNativeVolpan(
  TrackerCell cell, {
  required String format,
  required int volpan,
}) =>
    volpan < 0
        ? cell.copyWith(clearNativeVolpan: true)
        : cell.copyWith(
            nativeFormat: format,
            nativeVolpan: volpan.clamp(0, 0xFF),
          );

/// Removes all native provenance from [cell] (the same clear the normalized
/// editor performs when you retype the generic command).
TrackerCell clearNativeProvenance(TrackerCell cell) =>
    cell.copyWith(clearNativeEffect: true, clearNativeVolpan: true);

/// A short mnemonic for a raw native effect command in [format]: the format's
/// command letter/nibble plus a human label (e.g. `"D — Volume slide"`).
/// Unknown commands fall back to the bare letter/hex.
String nativeEffectMnemonic(String? format, int effect) {
  if (effect < 0) return '—';
  switch (format) {
    case 's3m':
      return _letterMnemonic(effect, _s3mCommands);
    case 'it':
      return _letterMnemonic(effect, _itCommands);
    case 'xm':
      return _xmMnemonic(effect);
    case 'mod':
      return _modCommands[effect] ?? '0x${_hex1(effect)}';
    default:
      return '0x${_hex2(effect)}';
  }
}

/// A one-line decode of [cell]'s raw native command: its format, the command
/// mnemonic, and the hex `command`/`param` (and the volume-column byte when
/// present). Returns an em dash when the cell has no native provenance.
String describeNativeEffect(TrackerCell cell) {
  if (!hasNativeProvenance(cell)) return '—';
  final fmt = (cell.nativeFormat ?? '?').toUpperCase();
  final parts = <String>[];
  if (cell.nativeEffect >= 0) {
    final mnem = nativeEffectMnemonic(cell.nativeFormat, cell.nativeEffect);
    parts.add(
      '$fmt $mnem  '
      '\$${_hex2(cell.nativeEffect)}${_hex2(cell.nativeEffectParam)}',
    );
  }
  if (cell.nativeVolpan >= 0) {
    parts.add('vol \$${_hex2(cell.nativeVolpan)}');
  }
  if (parts.isEmpty) return '$fmt (no command)';
  return parts.join(' · ');
}

String _letterMnemonic(int effect, Map<int, String> table) {
  if (effect < 1 || effect > 26) return '0x${_hex2(effect)}';
  final letter = String.fromCharCode('A'.codeUnitAt(0) + effect - 1);
  final label = table[effect];
  return label == null ? letter : '$letter — $label';
}

String _xmMnemonic(int effect) {
  // XM: 0x00..0x0F are the numeric commands, 0x10.. are the G.. letter effects.
  if (effect >= 0x10 && effect <= 0x22) {
    final letter = String.fromCharCode('G'.codeUnitAt(0) + effect - 0x10);
    final label = _xmLetterCommands[effect];
    return label == null ? letter : '$letter — $label';
  }
  return _xmNumCommands[effect] ?? '0x${_hex2(effect)}';
}

String _hex1(int v) => v.toRadixString(16).toUpperCase();
String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

// ── Command tables (mnemonic labels; unknown/unused commands are omitted) ─────

const Map<int, String> _modCommands = {
  0x0: '0 — Arpeggio',
  0x1: '1 — Portamento up',
  0x2: '2 — Portamento down',
  0x3: '3 — Tone portamento',
  0x4: '4 — Vibrato',
  0x5: '5 — Toneporta + vol slide',
  0x6: '6 — Vibrato + vol slide',
  0x7: '7 — Tremolo',
  0x8: '8 — Set panning',
  0x9: '9 — Sample offset',
  0xA: 'A — Volume slide',
  0xB: 'B — Position jump',
  0xC: 'C — Set volume',
  0xD: 'D — Pattern break',
  0xE: 'E — Extended',
  0xF: 'F — Set speed/tempo',
};

// S3M letter commands (1 = A .. 26 = Z).
const Map<int, String> _s3mCommands = {
  1: 'Set speed',
  2: 'Position jump',
  3: 'Pattern break',
  4: 'Volume slide',
  5: 'Portamento down',
  6: 'Portamento up',
  7: 'Tone portamento',
  8: 'Vibrato',
  9: 'Tremor',
  10: 'Arpeggio',
  11: 'Vibrato + vol slide',
  12: 'Toneporta + vol slide',
  15: 'Sample offset',
  17: 'Retrig + vol slide',
  18: 'Tremolo',
  19: 'Special (Sxy)',
  20: 'Set tempo',
  21: 'Fine vibrato',
  22: 'Set global volume',
  24: 'Set panning',
  26: 'MIDI / macro',
};

// IT letter commands (1 = A .. 26 = Z).
const Map<int, String> _itCommands = {
  1: 'Set speed',
  2: 'Jump to order',
  3: 'Break to row',
  4: 'Volume slide',
  5: 'Portamento down',
  6: 'Portamento up',
  7: 'Tone portamento',
  8: 'Vibrato',
  9: 'Tremor',
  10: 'Arpeggio',
  11: 'Vibrato + vol slide',
  12: 'Toneporta + vol slide',
  13: 'Set channel volume',
  14: 'Channel volume slide',
  15: 'Sample offset',
  16: 'Panning slide',
  17: 'Retrigger',
  18: 'Tremolo',
  19: 'Special (Sxy)',
  20: 'Set tempo',
  21: 'Fine vibrato',
  22: 'Set global volume',
  23: 'Global volume slide',
  24: 'Set panning',
  25: 'Panbrello',
  26: 'MIDI macro',
};

const Map<int, String> _xmNumCommands = {
  0x0: '0 — Arpeggio',
  0x1: '1 — Portamento up',
  0x2: '2 — Portamento down',
  0x3: '3 — Tone portamento',
  0x4: '4 — Vibrato',
  0x5: '5 — Toneporta + vol slide',
  0x6: '6 — Vibrato + vol slide',
  0x7: '7 — Tremolo',
  0x8: '8 — Set panning',
  0x9: '9 — Sample offset',
  0xA: 'A — Volume slide',
  0xB: 'B — Position jump',
  0xC: 'C — Set volume',
  0xD: 'D — Pattern break',
  0xE: 'E — Extended (Exy)',
  0xF: 'F — Set speed/tempo',
};

const Map<int, String> _xmLetterCommands = {
  0x10: 'Set global volume',
  0x11: 'Global volume slide',
  0x14: 'Key off',
  0x15: 'Set envelope position',
  0x19: 'Panning slide',
  0x1B: 'Retrig + vol slide',
  0x1D: 'Tremor',
  0x21: 'Extra-fine portamento',
};

// ── Native module-header (S3M) helpers ───────────────────────────────────────
//
// Only a small subset of the S3M header survives import onto the editable
// TrackerSong (see the field map in mod_pending.md): global volume and initial
// speed are carried but were previously read-only; tempo and per-channel pan
// are already editable through existing controls. Master volume, ultraClick,
// flags, createdWith and the raw channel-setting bytes stop at ModuleDoc and
// are NOT retained on TrackerSong (documented import-loss).

/// Clamps a global-volume UI value (0..1) onto the normalized song range.
double normalizeGlobalVolume(double value) => value.clamp(0.0, 1.0);

/// Clamps a ticks-per-row speed onto the S3M-writable 1..31 range.
int normalizeInitialSpeed(int speed) => speed.clamp(1, 31);

/// A one-line summary of the editable native header fields of [song]:
/// global volume (as a percentage), initial speed (ticks/row) and tempo (BPM).
String describeModuleHeader(TrackerSong song) =>
    'Global vol ${(song.globalVolume * 100).round()}% · '
    'Speed ${song.initialSpeed} · '
    'Tempo ${song.timing.tempoBpm} BPM';
