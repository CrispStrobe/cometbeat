// Effect-column round-trip matrix. Converting a module used to DROP every
// effect (portamento / vibrato / slides / arpeggio → 000) on export to any
// format — the readers translated each format's effects into the doc's
// MOD-numbered convention, but no writer emitted them back. This pins that the
// common melodic effects now survive doc → convertTo<Fmt> → parseAnyModule for
// MOD / S3M / XM / IT.
//
// The doc effect column is MOD-numbered (0x0–0xF). MOD/XM carry it 1:1; S3M/IT
// translate to/from their letter commands (A=1…). A MOD `Cxx` set-volume (how
// MOD stores per-note volume) is routed into S3M/IT's volume column. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// The common melodic effects, MOD-numbered `(cmd, param)`, that must survive a
/// round-trip through every format.
const _effects = <String, (int, int)>{
  '1xx portamento up': (0x1, 0x04),
  '2xx portamento down': (0x2, 0x04),
  '3xx tone portamento': (0x3, 0x08),
  '4xy vibrato': (0x4, 0x82),
  '7xy tremolo': (0x7, 0x33),
  'Axy volume slide': (0xA, 0x40),
  '0xy arpeggio': (0x0, 0x37),
  '9xx sample offset': (0x9, 0x10),
  'Bxx position jump': (0xB, 0x02),
  'Dxx pattern break': (0xD, 0x08),
  // Extended (Exy) sub-commands our readers translate ↔ S3M/IT Sxy.
  'E6x pattern loop': (0xE, 0x62),
  'ECx note cut': (0xE, 0xC3),
  'EDx note delay': (0xE, 0xD2),
};

/// Formats whose effect column shares MOD's `Exy` numbering directly — the only
/// ones that carry an Exy sub-command with no S3M/IT letter equivalent.
const _modStyleExtended = {ModuleFormat.mod, ModuleFormat.xm};

ModuleDoc _docWith(int cmd, int param) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.mod,
    order: [0],
    patterns: [
      DocPattern(
        [
          [DocCell(note: 60, instrument: 1, effect: cmd, effectParam: param)],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm)],
  );
}

DocCell _cellAfter(int cmd, int param, ModuleFormat fmt) => parseAnyModule(
      convertDocTo(_docWith(cmd, param), fmt),
    ).patterns.first.rows.first.first;

void main() {
  group('effect-column round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      group(fmt.name, () {
        _effects.forEach((name, e) {
          final (cmd, param) = e;
          test('$name survives', () {
            final c = _cellAfter(cmd, param, fmt);
            expect(c.effect, cmd, reason: '${fmt.name} $name command');
            expect(c.effectParam, param, reason: '${fmt.name} $name param');
          });
        });
      });
    }

    test('an un-mapped Exy (E1x) survives MOD/XM but drops on S3M/IT', () {
      // E1x fine-porta has no S3M/IT letter equivalent our reader maps, so it
      // rides MOD/XM's shared Exy numbering but is dropped by S3M/IT.
      for (final fmt in ModuleFormat.values) {
        final c = _cellAfter(0xE, 0x14, fmt);
        if (_modStyleExtended.contains(fmt)) {
          expect(c.effect, 0xE, reason: '${fmt.name} keeps E1x');
          expect(c.effectParam, 0x14);
        } else {
          expect(c.effect, 0, reason: '${fmt.name} drops un-mapped E1x');
        }
      }
    });

    test('no format drops the effect column any more', () {
      final dropped = <String>[];
      for (final fmt in ModuleFormat.values) {
        _effects.forEach((name, e) {
          final (cmd, param) = e;
          final c = _cellAfter(cmd, param, fmt);
          if (c.effect != cmd || c.effectParam != param) {
            dropped.add('${fmt.name}:$name');
          }
        });
      }
      expect(dropped, isEmpty);
    });
  });
}
