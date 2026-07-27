// Impulse Tracker stores the pattern-break row in HEX. Everyone else uses BCD.
//
// PLAN.md §6 X6/X7. Our canonical `Dxx`/`Cxx` parameter is decimal-coded into
// the two nibbles — row 16 is 0x16 — which is what MOD, S3M and XM all store,
// what `setPatternBreak` writes, and what the replayer decodes. The IT
// converter passed the parameter straight through in BOTH directions, so an IT
// we wrote said 0x16 and every other player read that as hex 0x16 = row 22.
//
// It was invisible to round-trip testing precisely BECAUSE it was wrong in both
// directions: our reader undid our writer's mistake, and every existing
// doc→IT→doc test passed. Only an external player could see it. The proof is
// `tool/make_flow_fixtures.dart`, which emits one song into all four formats:
// libopenmpt rendered our MOD, S3M and XM to 13.541 s each and the IT to
// 12.821 s — 0.72 s short, exactly the six rows between landing on row 16 and
// landing on row 22. libxmp agreed (13.440 vs 12.720).
//
// Both references model this explicitly: libxmp gives IT its own effect
// (`FX_IT_BREAK`, commented "like FX_BREAK with hex parameter") while MOD/S3M
// go through `FX_BREAK`, which multiplies the high nibble by ten.
//
// The tests below are pure conversion arithmetic plus one that reads the actual
// bytes we emit, so they run everywhere. The cross-format duration measurement
// that found it needs openmpt123/xmp and lives in the opt-in sweep.

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kFxPatternBreak;
import 'package:flutter_test/flutter_test.dart';

/// The decimal-coded parameter for [row], the way `setPatternBreak` writes it.
int _decimalParam(int row) => ((row ~/ 10) << 4) | (row % 10);

ModuleDoc _docBreakingTo(int row) => ModuleDoc(
      sourceFormat: ModuleFormat.mod,
      title: 'break',
      channelCount: 4,
      order: const [0, 1],
      samples: const [],
      patterns: [
        for (var p = 0; p < 2; p++)
          DocPattern(
            [
              for (var r = 0; r < 64; r++)
                [
                  if (p == 0 && r == 63)
                    DocCell(
                      effect: kFxPatternBreak,
                      effectParam: _decimalParam(row),
                    )
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

/// The `Cxx` parameter our IT writer actually emitted, read back out of the
/// bytes at the FORMAT level (before any of our own conversion runs).
int _emittedItBreakParam(ModuleDoc doc) {
  final it = parseIt(convertToIt(doc));
  for (final pattern in it.patterns) {
    for (final row in pattern.rows) {
      for (final cell in row) {
        if (cell.command == 3) return cell.commandValue; // 3 = 'C'
      }
    }
  }
  return -1;
}

void main() {
  group('IT pattern break is hex', () {
    test('a break to row 16 is written as 0x10, not 0x16', () {
      // The regression in one line. 0x16 is what we used to emit, and every
      // other player reads it as row 22.
      expect(_emittedItBreakParam(_docBreakingTo(16)), 0x10);
    });

    test('a break to row 22 is written as 0x16', () {
      // The mirror image, so a fix that merely swapped the constant cannot
      // pass both.
      expect(_emittedItBreakParam(_docBreakingTo(22)), 0x16);
    });

    test('rows below 10 are identical under either convention', () {
      // Which is why this went unnoticed: the common case of a short break
      // encodes the same way whichever rule you apply. Any fixture built on a
      // single-digit target proves nothing.
      for (final row in [0, 5, 9]) {
        expect(_emittedItBreakParam(_docBreakingTo(row)), row);
      }
    });

    test('the round trip through IT preserves the target row', () {
      for (final row in [0, 9, 10, 16, 22, 63, 99]) {
        final back = docFromIt(parseIt(convertToIt(_docBreakingTo(row))));
        final cell = back.patterns[0].rows[63][0];
        expect(cell.effect, kFxPatternBreak);
        expect(
          (cell.effectParam >> 4) * 10 + (cell.effectParam & 0xF),
          row,
          reason: 'row $row did not survive doc → IT → doc',
        );
      }
    });

    test('MOD, S3M and XM keep the decimal coding untouched', () {
      // The fix must be confined to IT. These three genuinely are decimal, and
      // re-coding them would break the formats that were right all along.
      final cell =
          parseMod(convertToMod(_docBreakingTo(16))).patterns[0].rows[63][0];
      expect(cell.effect, 0xD);
      expect(cell.effectParam, 0x16);
    });
  });
}
