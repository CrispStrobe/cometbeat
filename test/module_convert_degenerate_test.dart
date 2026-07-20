// Robustness lock for the module EXPORT side. convertDocTo is fed ModuleDocs
// from moduleDocFromSong, from a partially-parsed import, and (indirectly) from
// crafted input — so a degenerate doc (empty patterns/order/samples, a zero-row
// pattern, an out-of-range instrument or order index, zero or ragged channels)
// must convert to every format without throwing, and the result must re-parse.
// A probe of these cases found all clean; this pins it. Complements
// module_reader_fuzz_test (which fuzzes the PARSE side). Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

DocSample _sample() {
  final pcm = Float64List(16);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.3;
  }
  return DocSample(pcm: pcm);
}

ModuleDoc _doc({
  int channelCount = 1,
  List<int>? order,
  List<DocPattern>? patterns,
  List<DocSample>? samples,
}) =>
    ModuleDoc(
      channelCount: channelCount,
      sourceFormat: ModuleFormat.mod,
      order: order ?? [0],
      patterns: patterns ??
          const [
            DocPattern(
              [
                [DocCell(note: 60, instrument: 1)],
              ],
              1,
            ),
          ],
      samples: samples ?? [_sample()],
    );

Map<String, ModuleDoc> _cases() => {
      'no patterns': _doc(patterns: []),
      'empty order': _doc(order: []),
      'zero-row pattern': _doc(patterns: const [DocPattern([], 1)]),
      'no samples': _doc(samples: []),
      'instrument index out of range': _doc(
        patterns: const [
          DocPattern(
            [
              [DocCell(note: 60, instrument: 99)],
            ],
            1,
          ),
        ],
      ),
      'order index out of range': _doc(order: [5]),
      'zero channels': _doc(
        channelCount: 0,
        patterns: const [
          DocPattern([[]], 1),
        ],
      ),
      'ragged rows (uneven channel counts)': _doc(
        channelCount: 2,
        patterns: const [
          DocPattern(
            [
              [DocCell(note: 60, instrument: 1)],
              [DocCell(note: 62), DocCell(note: 64)],
            ],
            2,
          ),
        ],
      ),
    };

void main() {
  group('degenerate doc → module conversion never crashes', () {
    _cases().forEach((name, doc) {
      test('$name converts + re-parses in every format', () {
        for (final fmt in ModuleFormat.values) {
          expect(
            () => parseAnyModule(convertDocTo(doc, fmt)),
            returnsNormally,
            reason: '$name → ${fmt.name}',
          );
        }
      });
    });
  });
}
