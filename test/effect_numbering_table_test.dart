// Every effect we can write, checked against the number the FORMAT documents.
//
// PLAN.md §6. This audit turned up FOUR bugs of one shape — IT's hex pattern-
// break row, XM's 16-bit loop units, the fine-porta reverse map, and XM tremor
// written as KEY OFF. Each was found by accident, because some fixture happened
// to exercise it, and each had the same anatomy:
//
//   our reader and our writer agree with each other, so `parse(write(x)) == x`
//   holds perfectly while the FILE means something else to every other player.
//
// A round trip cannot catch that by construction. What catches it is asserting
// the byte on DISK against an outside authority, and doing it for every command
// rather than for the ones somebody happened to trip over. libxmp's
// `src/effects.h` is that authority for XM — its `FX_*` constants ARE the XM
// effect numbers, which is why the loader passes them through untranslated.
//
// The neutral model deliberately reuses XM's numbering from 10h up, so most of
// this table is the identity and the interesting rows are the ones where it is
// NOT: where a neutral command happens to sit on a number XM spends on
// something else. Those are the collisions that have to be spelled out in the
// converter, and each one that is not is a live bug.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:flutter_test/flutter_test.dart';

/// XM's effect numbering, from libxmp `src/effects.h` (the `FX_*` constants the
/// XM loader passes through unchanged). Only the values XM actually defines.
const Map<int, String> kXmEffectNames = {
  0x00: 'arpeggio',
  0x01: 'porta up',
  0x02: 'porta down',
  0x03: 'tone porta',
  0x04: 'vibrato',
  0x05: 'tone porta + vol slide',
  0x06: 'vibrato + vol slide',
  0x07: 'tremolo',
  0x08: 'set pan',
  0x09: 'sample offset',
  0x0A: 'volume slide',
  0x0B: 'position jump',
  0x0C: 'set volume',
  0x0D: 'pattern break',
  0x0E: 'extended',
  0x0F: 'set speed/tempo',
  0x10: 'set global volume',
  0x11: 'global volume slide',
  0x14: 'KEY OFF',
  0x15: 'set envelope position',
  0x19: 'pan slide',
  0x1B: 'multi retrigger',
  0x1D: 'tremor',
  0x21: 'extra fine porta',
};

/// Our neutral commands from 10h up — the range that is supposed to BE XM's.
const Map<int, String> kNeutralAboveMod = {
  0x10: 'kFxSetGlobalVolume',
  0x11: 'kFxGlobalVolSlide',
  0x13: 'kFxSetHighOffset',
  0x14: 'kFxSetSpeedFull',
  0x15: 'kFxSetPanbrelloWaveform',
  0x16: 'kFxSetSoundControl',
  0x17: 'kFxSetPastNote',
  0x19: 'kFxPanSlide',
  0x1B: 'kFxRetrigVolSlide',
  0x1C: 'kFxSetFilter',
  0x1D: 'kFxTremor',
  0x1E: 'kFxPanbrello',
  0x1F: 'kFxTempoSlide',
};

/// Neutral numbers that mean the SAME thing in XM — these must pass through.
const Set<int> kAgreesWithXm = {0x10, 0x11, 0x19, 0x1B, 0x1D};

/// Neutral numbers that XM spends on something ELSE. Writing one of these
/// through unchanged puts a different command in the file, so the converter has
/// to translate or drop it — never pass it through.
const Map<int, String> kCollidesWithXm = {
  0x14: 'XM 14h is KEY OFF; ours is full-range set-speed',
  0x15: 'XM 15h is set-envelope-position (Lxx); ours is set-panbrello-waveform',
};

Float64List _wave() {
  const n = 128;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

ModuleDoc _withEffect(int effect, int param) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'numbering',
    channelCount: 4,
    order: const [0],
    samples: [DocSample(name: 's', pcm: wave, loopLength: wave.length)],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 4; r++)
            [
              if (r == 0)
                const DocCell(note: 60, instrument: 1, volume: 64)
              else if (r == 1)
                DocCell(effect: effect, effectParam: param)
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

/// The effect byte our writer actually put on disk, read back through the
/// format parser — what a foreign player sees, and the only thing that can
/// catch a reader and writer sharing a misunderstanding.
int _xmByteFor(int effect, {int param = 0x11}) {
  final xm = parseXm(convertToXm(_withEffect(effect, param)));
  return xm.patterns.first.rows[1].first.effect;
}

void main() {
  group('the neutral numbering IS XM numbering where it claims to be', () {
    for (final entry in kAgreesWithXm) {
      test(
        '${kNeutralAboveMod[entry]} (${entry.toRadixString(16)}h) '
        'writes as XM ${kXmEffectNames[entry]}',
        () {
          expect(
            _xmByteFor(entry),
            entry,
            reason: 'the neutral model reuses XM numbers above 0Fh so these '
                'pass through; if this fails the two have drifted apart and '
                'every module we export says the wrong thing',
          );
        },
      );
    }
  });

  group('and where it does NOT, the converter must translate', () {
    kCollidesWithXm.forEach((neutral, why) {
      test('${kNeutralAboveMod[neutral]} must not be written verbatim — $why',
          () {
        final written = _xmByteFor(neutral);
        expect(
          written,
          isNot(neutral),
          reason: 'writing ${neutral.toRadixString(16)}h verbatim puts '
              '"${kXmEffectNames[neutral]}" in the file. $why',
        );
        // And whatever it becomes must be a command XM actually defines —
        // translating one wrong number into another is not an improvement.
        expect(
          kXmEffectNames.containsKey(written) || written == 0,
          isTrue,
          reason: '${written.toRadixString(16)}h is not an XM command at all',
        );
      });
    });
  });

  test('no neutral command silently occupies an XM number it does not mean',
      () {
    // The whole class, stated once: for every neutral command above MOD's
    // range, either XM agrees on that number, or the converter translates it.
    // A command that is neither is a bug waiting for a fixture to find it —
    // which is exactly how the previous four were found.
    final unhandled = <String>[];
    kNeutralAboveMod.forEach((neutral, name) {
      final xmMeansSomethingElse = kXmEffectNames.containsKey(neutral) &&
          !kAgreesWithXm.contains(neutral);
      if (!xmMeansSomethingElse) return;
      if (_xmByteFor(neutral) == neutral) {
        unhandled.add('$name (${neutral.toRadixString(16)}h) → XM '
            '"${kXmEffectNames[neutral]}"');
      }
    });
    expect(
      unhandled,
      isEmpty,
      reason: 'these neutral commands are written verbatim onto XM numbers '
          'that mean something else:\n  ${unhandled.join("\n  ")}',
    );
  });

  test('the table itself is honest about XM', () {
    // Guards the guard: if someone adds a neutral command above 0Fh without
    // adding it here, this test says so rather than quietly not checking it.
    final declared = kNeutralAboveMod.keys.toSet();
    const known = {
      kFxSetGlobalVolume,
      kFxGlobalVolSlide,
      kFxSetHighOffset,
      kFxSetSpeedFull,
      kFxSetPanbrelloWaveform,
      kFxSetSoundControl,
      kFxSetPastNote,
      kFxPanSlide,
      kFxRetrigVolSlide,
      kFxSetFilter,
      kFxTremor,
      kFxPanbrello,
      kFxTempoSlide,
    };
    expect(
      declared,
      known,
      reason: 'a neutral command above MOD range is missing from this table, '
          'so nothing checks what it writes into an XM file',
    );
  });
}
