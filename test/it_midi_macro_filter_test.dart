// Tests for the IT MIDI-macro-driven FILTER control (the embedded MidiCfg block).
//
// Covers: parsing the MidiCfg (16 SFx parametric + 128 Zxx fixed macros) onto the
// model; recognizing the canonical filter macros (F0F000 cutoff / F0F001
// resonance); routing a `Zxx` cell THROUGH the macro table to the kFxSetFilter
// path; the DEFAULT-macro equivalence with the direct Zxx→filter mapping; a
// redefined-macro module applying a custom filter; and byte-identity for a module
// with no MidiCfg.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_module.dart';
import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two lowercase hex digits for [n] (0..255), e.g. 0x0C → "0c".
String _hex2(int n) => n.toRadixString(16).padLeft(2, '0');

/// Builds a minimal sample-mode IT with a single 1-row pattern whose channel 0
/// carries a `Zxx` command (letter 26) with param [zValue]. When [withMacros] is
/// true an embedded MidiCfg is written (Special bit 0x08): parametric SF0 = [sf0],
/// SF1 = [sf1], and — when [defaultFixed] — every fixed Zxx[n] = "F0F001nn"
/// (resonance = n), the IT default fixed set.
Uint8List buildMacroIt({
  required int zValue,
  required bool withMacros,
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
  ascii(0x04, 'macro');
  bd.setUint16(0x20, 2, Endian.little); // OrdNum (order + end marker)
  bd.setUint16(0x22, 0, Endian.little); // InsNum (sample mode)
  bd.setUint16(0x24, 1, Endian.little); // SmpNum
  bd.setUint16(0x26, 1, Endian.little); // PatNum
  bd.setUint16(0x28, 0x0214, Endian.little); // Cwt/v
  bd.setUint16(0x2A, 0x0200, Endian.little); // Cmwt
  bd.setUint16(0x2C, 0x09, Endian.little); // flags: stereo + sample mode
  final special = withMacros ? 0x08 : 0x00; // Special: MidiCfg present?
  bd.setUint16(0x2E, special, Endian.little);
  b[0x30] = 128; // global volume
  b[0x32] = 6; // speed
  b[0x33] = 125; // tempo
  for (var i = 0; i < 64; i++) {
    b[0x40 + i] = 32; // channel pans (centre)
    b[0x80 + i] = 64; // channel volumes
  }
  b[0xC0] = 0; // order: play pattern 0
  b[0xC1] = 0xFF; // end marker

  // Offset tables: no instruments; sample offset @0xC2, pattern offset @0xC6.
  const smpOff = 0x1400;
  const smpData = smpOff + 80;
  const patOff = 0x1500;
  bd.setUint32(0xC2, smpOff, Endian.little);
  bd.setUint32(0xC6, patOff, Endian.little);

  // ── embedded MidiCfg (after the pattern-offset table @0xCA) ──
  if (withMacros) {
    const cfg = 0xCA;
    // 9 global macros (left blank), 16 SFx, 128 Zxx — 32 bytes each.
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

  // ── pattern: 1 row, channel 0 carries Zxx (letter 26) = zValue ──
  // packed: channelvar=0x81 (ch0 + new-mask), mask=0x08 (command), cmd=26 (Z),
  // value=zValue, then 0x00 = end of row.
  final packed = [0x81, 0x08, 26, zValue & 0xFF, 0x00];
  bd.setUint16(patOff, packed.length, Endian.little); // packed length
  bd.setUint16(patOff + 2, 1, Endian.little); // rows
  for (var i = 0; i < packed.length; i++) {
    b[patOff + 8 + i] = packed[i];
  }
  return b;
}

/// The (effect, param) our converter emits for the Zxx cell of [module].
(int, int) zCellEffect(ItModule module) {
  final doc = docFromIt(module);
  final cell = doc.patterns.first.rows.first.first;
  return (cell.effect, cell.effectParam);
}

// The replayer's kFxSetFilter (see tracker_replayer.dart).
const int kFxSetFilter = 0x1C;

void main() {
  group('IT MidiCfg parse', () {
    test('macros land on the model (SF0 cutoff / SF1 resonance)', () {
      final module = parseIt(buildMacroIt(zValue: 0x20, withMacros: true));
      final macros = module.midiMacros;
      expect(macros, isNotNull);
      expect(macros!.sfx.length, ItMidiMacros.sfxCount);
      expect(macros.zxx.length, ItMidiMacros.zxxCount);
      expect(macros.sfx[0], 'F0F000z');
      expect(macros.sfx[1], 'F0F001z');
      expect(macros.zxx[0], 'F0F00100');
      expect(macros.zxx[0x30], 'F0F00130');
    });

    test('no MidiCfg ⇒ midiMacros is null', () {
      final module = parseIt(buildMacroIt(zValue: 0x20, withMacros: false));
      expect(module.midiMacros, isNull);
    });
  });

  group('default-macro equivalence with the direct Zxx→filter mapping', () {
    test('resolveZxxFilterParam reproduces the direct mapping for all values',
        () {
      final module = parseIt(buildMacroIt(zValue: 0, withMacros: true));
      final macros = module.midiMacros!;
      expect(macros.isDefaultFilterSet, isTrue);
      for (var v = 0; v < 256; v++) {
        expect(macros.resolveZxxFilterParam(v), v, reason: 'Z value $v');
      }
    });

    test('a Zxx cutoff cell (Z20) routes to kFxSetFilter identically', () {
      // Default MidiCfg present vs. no MidiCfg → same (0x1C, 0x20).
      final withCfg = parseIt(buildMacroIt(zValue: 0x20, withMacros: true));
      final noCfg = parseIt(buildMacroIt(zValue: 0x20, withMacros: false));
      expect(zCellEffect(withCfg), (kFxSetFilter, 0x20));
      expect(zCellEffect(noCfg), (kFxSetFilter, 0x20));
      expect(zCellEffect(withCfg), zCellEffect(noCfg));
    });

    test('a Zxx resonance cell (Z95) routes to kFxSetFilter identically', () {
      // Z95 (>= 0x80) → fixed macro F0F00115 → resonance 0x15 → 0x80|0x15.
      final withCfg = parseIt(buildMacroIt(zValue: 0x95, withMacros: true));
      final noCfg = parseIt(buildMacroIt(zValue: 0x95, withMacros: false));
      expect(zCellEffect(withCfg), (kFxSetFilter, 0x95));
      expect(zCellEffect(noCfg), (kFxSetFilter, 0x95));
    });
  });

  group('redefined macros apply the custom filter', () {
    test('SF0 redefined to resonance turns Z00..Z7F into resonance sets', () {
      // SF0 = F0F001z ⇒ the parametric (Zxx < 0x80) macro now sets RESONANCE.
      final module = parseIt(
        buildMacroIt(zValue: 0x30, withMacros: true, sf0: 'F0F001z'),
      );
      final macros = module.midiMacros!;
      expect(macros.isDefaultFilterSet, isFalse);
      expect(macros.resolveZxxFilterParam(0x30), 0x80 | 0x30);
      expect(zCellEffect(module), (kFxSetFilter, 0x80 | 0x30));
    });

    test('SF0 with a fixed cutoff value ignores the Zxx parameter', () {
      // SF0 = F0F00040 ⇒ cutoff is always 0x40 regardless of the Zxx value.
      final module = parseIt(
        buildMacroIt(zValue: 0x7F, withMacros: true, sf0: 'F0F00040'),
      );
      expect(module.midiMacros!.resolveZxxFilterParam(0x7F), 0x40);
      expect(zCellEffect(module), (kFxSetFilter, 0x40));
    });

    test('a non-filter macro (MIDI to external gear) is parsed and ignored',
        () {
      // SF0 = "9c n v" (note-on) has no audible filter target → the Zxx is
      // dropped (0, 0) rather than misrouted to the filter.
      final module = parseIt(
        buildMacroIt(zValue: 0x30, withMacros: true, sf0: '9c n v'),
      );
      expect(module.midiMacros!.resolveZxxFilterParam(0x30), isNull);
      expect(zCellEffect(module), (0, 0));
    });
  });

  group('byte-identity for a module with no custom filter macros', () {
    test('no MidiCfg: Zxx maps directly, exactly as before', () {
      for (final v in [0x00, 0x10, 0x40, 0x7F, 0x80, 0x95, 0xFF]) {
        final module = parseIt(buildMacroIt(zValue: v, withMacros: false));
        expect(zCellEffect(module), (kFxSetFilter, v), reason: 'Z value $v');
      }
    });
  });
}
