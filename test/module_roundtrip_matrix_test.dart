// Full writer fixed-point matrix.
//
// Every source format is converted to every target format twice:
//   source -> X1 -> parse -> X2 -> parse
// The source-to-target conversion may intentionally be lossy, but once X1 has
// been written, parsing and writing it again must not keep changing the file's
// neutral musical representation.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = <String>[
  'test/fixtures/golden.mod',
  'test/fixtures/golden.s3m',
  'test/fixtures/golden.xm',
  'test/fixtures/golden.it',
];

void main() {
  for (final sourcePath in _fixtures) {
    final sourceBytes = File(sourcePath).readAsBytesSync();
    final source = parseAnyModule(sourceBytes);
    for (final target in ModuleFormat.values) {
      test('${source.sourceFormat.name} -> ${target.name} is fixed-point', () {
        final x1 = parseAnyModule(convertDocTo(source, target));
        final x2 = parseAnyModule(convertDocTo(x1, target));
        _expectEquivalent(x1, x2);
      });
    }
  }
}

void _expectEquivalent(ModuleDoc a, ModuleDoc b) {
  expect(b.title, a.title);
  expect(b.channelCount, a.channelCount);
  expect(b.initialSpeed, a.initialSpeed);
  expect(b.initialTempo, a.initialTempo);
  expect(b.order, a.order);
  expect(b.patterns.length, a.patterns.length);
  expect(b.samples.length, a.samples.length);

  for (var p = 0; p < a.patterns.length; p++) {
    final pa = a.patterns[p], pb = b.patterns[p];
    expect(pb.numRows, pa.numRows, reason: 'pattern $p rows');
    expect(pb.channelCount, pa.channelCount, reason: 'pattern $p channels');
    for (var r = 0; r < pa.rows.length; r++) {
      expect(pb.rows[r], pa.rows[r], reason: 'pattern $p row $r');
    }
  }

  for (var i = 0; i < a.samples.length; i++) {
    final sa = a.samples[i], sb = b.samples[i];
    expect(sb.name, sa.name, reason: 'sample ${i + 1} name');
    expect(sb.volume, sa.volume, reason: 'sample ${i + 1} volume');
    expect(sb.loopStart, sa.loopStart, reason: 'sample ${i + 1} loop start');
    expect(sb.loopLength, sa.loopLength, reason: 'sample ${i + 1} loop length');
    expect(sb.pingPong, sa.pingPong, reason: 'sample ${i + 1} ping-pong');
    expect(sb.c5speed, sa.c5speed, reason: 'sample ${i + 1} C5 speed');
    expect(sb.pcm.length, sa.pcm.length, reason: 'sample ${i + 1} length');
    final tolerance = sa.sixteenBit || sb.sixteenBit ? 1e-4 : 1 / 128;
    for (var k = 0; k < sa.pcm.length; k++) {
      expect(
        sb.pcm[k],
        closeTo(sa.pcm[k], tolerance),
        reason: 'sample ${i + 1} PCM[$k]',
      );
    }
  }
}
