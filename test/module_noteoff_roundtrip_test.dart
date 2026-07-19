// Note-off round-trip matrix across the four module formats. A DocCell.off()
// stops a ringing note (a rest) — the Score→ModuleDoc bridge emits these so a
// rest survives export instead of being absorbed into the held note. This pins
// how each format carries that:
//   * S3M / XM / IT have a real note-off event → it round-trips as noteOff.
//   * ProTracker MOD has no note-off, so doc→mod emulates it as a C00
//     (set-volume-0) that silences the note; it reads back as that effect (an
//     audible rest), not as a noteOff flag.
//
// Note-off support is declared per-format (_noteOffFormats) in the crisp_notation
// round-trip matrix's `droppedBy` spirit. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats with a native note-off event (round-trips as a noteOff cell). MOD has
/// none — it emulates the note-off as a C00 volume-cut effect.
const _noteOffFormats = {ModuleFormat.s3m, ModuleFormat.xm, ModuleFormat.it};

ModuleDoc _docWithNoteOff() {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: [0],
    patterns: const [
      DocPattern(
        [
          [DocCell(note: 60, instrument: 1)], // trigger
          [DocCell()], // ring
          [DocCell.off()], // note-off (a rest starts here)
          [DocCell()],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm, c5speed: 44100)],
  );
}

DocCell _row2After(ModuleFormat fmt) => parseAnyModule(
      convertDocTo(_docWithNoteOff(), fmt),
    ).patterns.first.rows[2].first;

void main() {
  group('note-off round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      test('${fmt.name}: the note-off is not lost', () {
        final c = _row2After(fmt);
        if (_noteOffFormats.contains(fmt)) {
          // A real note-off event survives as a noteOff cell.
          expect(c.noteOff, isTrue, reason: '${fmt.name} should keep note-off');
        } else {
          // MOD emulates it as C00 (set volume 0) — an audible rest, carried in
          // the effect column rather than a noteOff flag.
          expect(c.noteOff, isFalse); // MOD has no note-off event
          expect(c.effect, 0xC, reason: 'MOD note-off → C00');
          expect(c.effectParam, 0);
        }
      });
    }

    test('every format silences the note at the rest (native or C00)', () {
      final unsilenced = <String>[];
      for (final fmt in ModuleFormat.values) {
        final c = _row2After(fmt);
        final silenced = c.noteOff || (c.effect == 0xC && c.effectParam == 0);
        if (!silenced) unsilenced.add(fmt.name);
      }
      expect(unsilenced, isEmpty);
    });
  });
}
