// Metadata round-trip matrix across the four module formats — the remaining
// small dimensions: the song TITLE, a sample NAME, and a sample's DEFAULT
// VOLUME all survive doc → convertTo<Fmt> → parseAnyModule intact. Every format
// carries these, so no `droppedBy` — each cell is a regression lock. (Names/
// titles have per-format length caps; this uses short values well within all of
// them.) Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyRow = <DocCell>[DocCell.empty];

ModuleDoc _doc() {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    title: 'MyTune',
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: [0],
    patterns: const [
      DocPattern([_emptyRow], 1),
    ],
    samples: [
      DocSample(pcm: pcm, c5speed: 44100, name: 'MySample', volume: 48),
    ],
  );
}

void main() {
  group('metadata round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      test('${fmt.name}: title, sample name and default volume survive', () {
        final back = parseAnyModule(convertDocTo(_doc(), fmt));
        expect(back.title, 'MyTune', reason: '${fmt.name} title');
        final s = back.usedSamples.first;
        expect(s.name, 'MySample', reason: '${fmt.name} sample name');
        expect(s.volume, 48, reason: '${fmt.name} default volume');
      });
    }

    test('no format drops the title/name/volume metadata', () {
      final dropped = <String>[];
      for (final fmt in ModuleFormat.values) {
        final back = parseAnyModule(convertDocTo(_doc(), fmt));
        final s = back.usedSamples.first;
        if (back.title != 'MyTune' || s.name != 'MySample' || s.volume != 48) {
          dropped.add(fmt.name);
        }
      }
      expect(dropped, isEmpty);
    });
  });
}
