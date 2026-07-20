// Note-range round-trip matrix. Each module format plays a different note span,
// so converting an out-of-range note clamps it — a real, audible fidelity limit
// nothing else pinned:
//   * S3M / IT carry the full MIDI range (tested 12..119).
//   * ProTracker MOD's period table covers only ~3 octaves — MIDI 48..83 — so a
//     lower note clamps up to 48 and a higher one down to 83 (a bass-heavy song
//     loses its low notes on .mod export).
//   * XM's 96-note range tops out at MIDI 107.
// In-range notes (48..83, the tightest span, MOD's) survive every format
// exactly. Not a bug — the note range is inherent to each format; this documents
// and locks it. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// MOD's playable range (its Amiga period table): ~3 octaves, C-3..B-5.
const _modLo = 48;
const _modHi = 83;

/// XM's top note (a 96-key range from a low base).
const _xmHi = 107;

ModuleDoc _docWithNote(int note) {
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
          [DocCell(note: note, instrument: 1)],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm)],
  );
}

int _noteAfter(int note, ModuleFormat fmt) =>
    parseAnyModule(convertDocTo(_docWithNote(note), fmt))
        .patterns
        .first
        .rows
        .first
        .first
        .note;

void main() {
  group('note-range round-trip matrix (doc → write → parse)', () {
    for (final note in const [_modLo, 60, 72, _modHi]) {
      test('an in-range note ($note) survives every format exactly', () {
        for (final fmt in ModuleFormat.values) {
          expect(_noteAfter(note, fmt), note, reason: '${fmt.name} @ $note');
        }
      });
    }

    test('a very low note (12): S3M/IT/XM keep it, MOD clamps up to 48', () {
      expect(_noteAfter(12, ModuleFormat.s3m), 12);
      expect(_noteAfter(12, ModuleFormat.it), 12);
      expect(_noteAfter(12, ModuleFormat.xm), 12);
      expect(_noteAfter(12, ModuleFormat.mod), _modLo);
    });

    test('a very high note (119): S3M/IT keep it, XM caps 107, MOD clamps 83',
        () {
      expect(_noteAfter(119, ModuleFormat.s3m), 119);
      expect(_noteAfter(119, ModuleFormat.it), 119);
      expect(_noteAfter(119, ModuleFormat.xm), _xmHi);
      expect(_noteAfter(119, ModuleFormat.mod), _modHi);
    });

    test('MOD clamps every out-of-range note into [48, 83]', () {
      for (final note in const [0, 12, 24, 47, 84, 96, 108, 119]) {
        final got = _noteAfter(note, ModuleFormat.mod);
        expect(got, inInclusiveRange(_modLo, _modHi), reason: 'mod @ $note');
      }
    });
  });
}
