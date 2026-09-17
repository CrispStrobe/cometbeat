// Same-platform characterization, not a cross-platform audio oracle.
// See fixtures/replayer_parity/README.md for pre-refactor capture/verify.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

const _mode =
    String.fromEnvironment('REPLAYER_PARITY_MODE', defaultValue: 'repeat');
const _directory = String.fromEnvironment('REPLAYER_PARITY_DIR');
final _fixtures = [
  for (final format in ['mod', 'xm', 'it', 's3m']) 'golden.$format',
  for (final format in ['mod', 'xm', 'it', 's3m'])
    'flow/tempo_change_Fxx.$format',
  for (final format in ['mod', 'xm', 'it', 's3m'])
    'flow/pattern_loop_E6x.$format',
  'fx/vibrato.mod',
  'fmt/tremor_Ixy.xm',
  'fmt/fine_porta_up_FFx.it',
  'fmt/panbrello_Yxy.s3m',
];

Uint8List _pcmBytes(Int16List pcm) {
  final bytes = ByteData(pcm.length * 2);
  for (var i = 0; i < pcm.length; i++) {
    bytes.setInt16(i * 2, pcm[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void _expectBytes(List<int> actual, List<int> expected, String label) {
  expect(actual.length, expected.length, reason: '$label byte length');
  var differences = 0;
  var first = -1;
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      differences++;
      if (first < 0) first = i;
    }
  }
  expect(differences, 0, reason: '$label: first differing PCM byte at $first');
}

void main() {
  test('PCM comparison rejects a one-byte change', () {
    expect(
      () => _expectBytes([1, 2], [1, 3], 'negative control'),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => _expectBytes([1], [1, 2], 'length negative control'),
      throwsA(isA<TestFailure>()),
    );
  });

  for (final fixture in _fixtures) {
    for (final stereo in [false, true]) {
      final name =
          '${fixture.replaceAll('/', '_')}.${stereo ? 'stereo' : 'mono'}';
      test(name, () {
        expect(_mode, isIn(['repeat', 'capture', 'verify']));
        if (_mode != 'repeat') {
          expect(_directory, isNotEmpty, reason: 'set REPLAYER_PARITY_DIR');
        }
        final source = File('test/fixtures/$fixture').readAsBytesSync();
        ReplayResult render() {
          final song = songFromModuleBytes(source);
          return stereo ? replaySongStereo(song) : replaySong(song);
        }

        final first = render();
        final actual = _pcmBytes(first.pcm);
        expect(actual, isNotEmpty);
        expect(first.pcm.any((s) => s != 0), isTrue, reason: 'not silent');
        final metadata = <String, Object>{
          'schema': 1,
          'fixture': fixture,
          'sourceBase64': base64Encode(source),
          'platform': Platform.operatingSystem,
          'runtime': Platform.version,
          'channels': stereo ? 2 : 1,
          'pcmEncoding': 'signed PCM16 little-endian, 44100 Hz, no dither',
          'pcmBytes': actual.length,
          'timing': [
            for (final row in first.timing)
              [row.startMs, row.orderIndex, row.patternIndex, row.row],
          ],
        };
        if (_mode == 'verify') {
          final snapshot = File('$_directory/$name.pcm.gz');
          final description = File('$_directory/$name.json');
          expect(
            snapshot.existsSync(),
            isTrue,
            reason: 'missing pre-refactor capture: ${snapshot.path}',
          );
          expect(description.existsSync(), isTrue);
          expect(metadata, jsonDecode(description.readAsStringSync()));
          _expectBytes(actual, gzip.decode(snapshot.readAsBytesSync()), name);
        } else {
          // Always establish determinism before allowing a capture to be saved.
          final second = render();
          _expectBytes(_pcmBytes(second.pcm), actual, '$name repeat');
          expect(
            [
              for (final r in second.timing)
                [r.startMs, r.orderIndex, r.patternIndex, r.row],
            ],
            metadata['timing'],
          );
          if (_mode == 'capture') {
            Directory(_directory).createSync(recursive: true);
            final snapshot = File('$_directory/$name.pcm.gz');
            final description = File('$_directory/$name.json');
            expect(
              snapshot.existsSync() || description.existsSync(),
              isFalse,
              reason: 'capture refuses to overwrite baseline $name',
            );
            snapshot.writeAsBytesSync(gzip.encode(actual));
            description.writeAsStringSync(jsonEncode(metadata));
          }
        }
      });
    }
  }
}
