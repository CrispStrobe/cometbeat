// Tests for the two documented-deferred pieces of IT MIDI-macro FILTER control:
//
//   1. Per-channel active parametric-macro selection — the `SFx` effect (IT `S`
//      command value 0xF0..0xFF selects SF0..SFF) picks which of the 16 SFx
//      parametric macros a subsequent `Zxx` (0x00..0x7F) runs on that channel.
//   2. `z`-parameter evaluation beyond direct substitution — a filter macro whose
//      value field combines a fixed high nibble with the `z` low nibble
//      (`F0F0004z` → `0x40 | (param & 0x0F)`).
//
// Also pins the DEFAULT-macro behavior byte-identical to the pre-active-macro
// commit (94c8cca8): with no SFx anywhere every channel stays on SF0 and a Zxx
// resolves exactly as the direct Zxx→filter mapping / the no-MidiCfg path.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two lowercase hex digits for [n] (0..255).
String _hex2(int n) => n.toRadixString(16).padLeft(2, '0');

/// One packed IT pattern row carrying a single channel-0 effect cell:
/// channelvar 0x81 (ch0 + new-mask), mask 0x08 (command), cmd, value, end 0x00.
List<int> _effectRow(int cmd, int value) =>
    [0x81, 0x08, cmd, value & 0xFF, 0x00];

/// Builds a sample-mode IT whose channel 0 plays [rows] (each a `(cmd, value)`
/// IT letter-command cell) in a single pattern, with an embedded MidiCfg
/// (Special 0x08): parametric SF0 = [sf0], SF1 = [sf1], and — when [defaultFixed]
/// — every fixed Zxx[n] = "F0F001nn" (the IT default fixed set). Set
/// [withMacros] false to omit the MidiCfg entirely.
Uint8List buildIt({
  required List<(int, int)> rows,
  bool withMacros = true,
  String sf0 = 'F0F000z',
  String sf1 = 'F0F001z',
  bool defaultFixed = true,
}) {
  final b = Uint8List(0x1600);
  final bd = ByteData.sublistView(b);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b[o + i] = s.codeUnitAt(i) & 0xFF;
    }
  }

  ascii(0x00, 'IMPM');
  ascii(0x04, 'eval');
  bd.setUint16(0x20, 2, Endian.little); // OrdNum (order + end marker)
  bd.setUint16(0x22, 0, Endian.little); // InsNum (sample mode)
  bd.setUint16(0x24, 1, Endian.little); // SmpNum
  bd.setUint16(0x26, 1, Endian.little); // PatNum
  bd.setUint16(0x28, 0x0214, Endian.little); // Cwt/v
  bd.setUint16(0x2A, 0x0200, Endian.little); // Cmwt
  bd.setUint16(0x2C, 0x09, Endian.little); // flags: stereo + sample mode
  bd.setUint16(0x2E, withMacros ? 0x08 : 0x00, Endian.little); // Special
  b[0x30] = 128; // global volume
  b[0x32] = 6; // speed
  b[0x33] = 125; // tempo
  for (var i = 0; i < 64; i++) {
    b[0x40 + i] = 32; // channel pans (centre)
    b[0x80 + i] = 64; // channel volumes
  }
  b[0xC0] = 0; // order: play pattern 0
  b[0xC1] = 0xFF; // end marker

  const smpOff = 0x1400;
  const smpData = smpOff + 80;
  const patOff = 0x1500;
  bd.setUint32(0xC2, smpOff, Endian.little);
  bd.setUint32(0xC6, patOff, Endian.little);

  // ── embedded MidiCfg (after the pattern-offset table @0xCA) ──
  if (withMacros) {
    const cfg = 0xCA;
    const sfxBase = cfg + ItMidiMacros.globalCount * ItMidiMacros.macroLength;
    const zxxBase = sfxBase + ItMidiMacros.sfxCount * ItMidiMacros.macroLength;
    ascii(sfxBase + 0 * 32, sf0);
    ascii(sfxBase + 1 * 32, sf1);
    if (defaultFixed) {
      for (var n = 0; n < ItMidiMacros.zxxCount; n++) {
        ascii(zxxBase + n * 32, 'F0F001${_hex2(n)}');
      }
    }
  }

  // ── sample header (IMPS) ──
  ascii(smpOff, 'IMPS');
  b[smpOff + 0x11] = 64; // global volume
  b[smpOff + 0x12] = 0x01; // Flg: has sample (8-bit, uncompressed)
  b[smpOff + 0x13] = 64; // default volume
  b[smpOff + 0x2E] = 0x01; // Cvt: signed PCM
  bd.setUint32(smpOff + 0x30, 8, Endian.little); // length (samples)
  bd.setUint32(smpOff + 0x3C, 8363, Endian.little); // C5Speed
  bd.setUint32(smpOff + 0x48, smpData, Endian.little); // data pointer
  for (var i = 0; i < 8; i++) {
    b[smpData + i] = (i.isEven ? 60 : -60) & 0xFF;
  }

  // ── pattern: one packed row per entry in [rows], channel 0 ──
  final packed = <int>[
    for (final (cmd, value) in rows) ..._effectRow(cmd, value),
  ];
  bd.setUint16(patOff, packed.length, Endian.little); // packed length
  bd.setUint16(patOff + 2, rows.length, Endian.little); // rows
  for (var i = 0; i < packed.length; i++) {
    b[patOff + 8 + i] = packed[i];
  }
  return b;
}

/// The (effect, param) our converter emits for channel 0's cell on [rowIndex].
(int, int) cellEffect(ItModule module, int rowIndex) {
  final doc = docFromIt(module);
  final cell = doc.patterns.first.rows[rowIndex].first;
  return (cell.effect, cell.effectParam);
}

// The replayer's kFxSetFilter (see tracker_replayer.dart).
const int kFxSetFilter = 0x1C;

// IT letter commands used below.
const int cmdS = 19; // S (special/extended; SFx = set active MIDI macro)
const int cmdZ = 26; // Z (MIDI macro / filter)

void main() {
  group('per-channel active parametric-macro selection (SFx)', () {
    test('SFx selects a NON-SF0 macro; Zxx resolves through the SELECTED macro',
        () {
      // SF0 = cutoff, SF1 = resonance. Row 0 issues SF1 (S command, value 0xF1
      // → select active parametric macro = SF1) on channel 0; row 1's Z30
      // (parametric) then runs SF1 → RESONANCE 0x30 (0x80|0x30), NOT SF0 cutoff.
      final module = parseIt(buildIt(rows: [(cmdS, 0xF1), (cmdZ, 0x30)]));
      final macros = module.midiMacros!;

      // Unit level: same value resolves differently per active macro.
      expect(macros.resolveZxxFilterParam(0x30), 0x30); // SF0 cutoff
      expect(macros.resolveZxxFilterParam(0x30, 1), 0x80 | 0x30); // SF1 reso

      // Converter level: the Zxx cell picked up the selected (SF1) macro.
      expect(cellEffect(module, 1), (kFxSetFilter, 0x80 | 0x30));

      // And it genuinely DIFFERS from the SF0-default path (no SFx select).
      final noSelect = parseIt(buildIt(rows: [(cmdZ, 0x30)]));
      expect(cellEffect(noSelect, 0), (kFxSetFilter, 0x30));
      expect(cellEffect(module, 1) != cellEffect(noSelect, 0), isTrue);
    });

    test('SFx selecting SF0 explicitly matches the implicit default', () {
      // SF0 select (S command value 0xF0) is the default macro, so explicit.
      final selectSf0 = parseIt(buildIt(rows: [(cmdS, 0xF0), (cmdZ, 0x30)]));
      final implicit = parseIt(buildIt(rows: [(cmdZ, 0x30)]));
      expect(cellEffect(selectSf0, 1), cellEffect(implicit, 0));
      expect(cellEffect(selectSf0, 1), (kFxSetFilter, 0x30));
    });

    test('the SFx cell itself emits no audible effect', () {
      final module = parseIt(buildIt(rows: [(cmdS, 0xF1), (cmdZ, 0x30)]));
      expect(cellEffect(module, 0), (0, 0)); // SF-select drops to no-op
    });
  });

  group('z-parameter evaluation beyond direct substitution', () {
    test('nibble-combined `F0F0004z`: fixed high nibble + z low nibble', () {
      // Value byte "4z" → 0x40 | (param & 0x0F). For Z35 → param 0x35 → 0x40|0x5.
      final macros =
          parseIt(buildIt(rows: [(cmdZ, 0x35)], sf0: 'F0F0004z')).midiMacros!;
      expect(macros.resolveZxxFilterParam(0x35), 0x40 | 0x05);
      expect(macros.resolveZxxFilterParam(0x2A), 0x40 | 0x0A);

      final module = parseIt(buildIt(rows: [(cmdZ, 0x35)], sf0: 'F0F0004z'));
      expect(cellEffect(module, 0), (kFxSetFilter, 0x40 | 0x05));
    });

    test('resonance nibble form `F0F0017z` sets the resonance selector bit',
        () {
      // "7z" after F0F001 → resonance 0x70 | (param & 0x0F) → 0x80 | value.
      final macros =
          parseIt(buildIt(rows: [(cmdZ, 0x03)], sf0: 'F0F0017z')).midiMacros!;
      expect(macros.resolveZxxFilterParam(0x03), 0x80 | (0x70 | 0x03));
    });

    test('a non-evaluable z form (z in the high nibble) is dropped', () {
      // "z4" is not one of the evaluated forms → null (parse-and-ignore), never
      // misrouted to the filter.
      final macros =
          parseIt(buildIt(rows: [(cmdZ, 0x30)], sf0: 'F0F000z4')).midiMacros!;
      expect(macros.resolveZxxFilterParam(0x30), isNull);
      final module = parseIt(buildIt(rows: [(cmdZ, 0x30)], sf0: 'F0F000z4'));
      expect(cellEffect(module, 0), (0, 0));
    });
  });

  group('DEFAULT-macro behavior is byte-identical to 94c8cca8', () {
    test('default MidiCfg with no SFx == no-MidiCfg == direct mapping', () {
      for (final v in [0x00, 0x10, 0x30, 0x40, 0x7F, 0x80, 0x95, 0xFF]) {
        final withCfg = parseIt(buildIt(rows: [(cmdZ, v)]));
        final noCfg = parseIt(buildIt(rows: [(cmdZ, v)], withMacros: false));
        // Both equal the pre-macro direct kFxSetFilter mapping.
        expect(cellEffect(withCfg, 0), (kFxSetFilter, v), reason: 'withCfg $v');
        expect(cellEffect(noCfg, 0), (kFxSetFilter, v), reason: 'noCfg $v');
        expect(cellEffect(withCfg, 0), cellEffect(noCfg, 0), reason: 'Z=$v');
      }
    });

    test('default filter set: resolveZxxFilterParam(active=0) is the identity',
        () {
      final macros = parseIt(buildIt(rows: [(cmdZ, 0)])).midiMacros!;
      expect(macros.isDefaultFilterSet, isTrue);
      for (var v = 0; v < 256; v++) {
        expect(macros.resolveZxxFilterParam(v), v, reason: 'Z=$v');
      }
    });
  });
}
