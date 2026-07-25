// Writer-fidelity pins for two independent export details:
//
//   1. XM 16-bit sample export. A neutral DocSample flagged sixteenBit exports
//      as a 16-bit XM sample (type bit4 = 0x10), delta-encoded as 16-bit, so a
//      full-precision waveform is NOT crushed to 8-bit. An unflagged sample
//      stays the classic 8-bit sample (byte-identical export path).
//   2. MOD "M!K!" signature. A 4-channel module with MORE than 64 patterns
//      cannot be addressed by the classic "M.K." tag, so writeMod emits the
//      ProTracker-extended "M!K!" tag there; a module with ≤64 patterns keeps
//      "M.K.". parseMod reads both back as 4 channels.
//
// Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod_module.dart';
import 'package:comet_beat/core/audio/mod/mod_reader.dart';
import 'package:comet_beat/core/audio/mod/mod_writer.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyRow = <DocCell>[DocCell.empty];

/// A smooth waveform with fine detail that 8-bit quantization cannot hold.
Float64List _wave() {
  final pcm = Float64List(512);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.8 * sin(2 * pi * 3 * i / pcm.length) +
        0.15 * sin(2 * pi * 37 * i / pcm.length);
  }
  return pcm;
}

ModuleDoc _xmDoc({required bool sixteenBit}) => ModuleDoc(
      channelCount: 1,
      sourceFormat: ModuleFormat.xm,
      order: const [0],
      patterns: const [
        DocPattern([_emptyRow], 1),
      ],
      samples: [
        DocSample(pcm: _wave(), c5speed: 44100, sixteenBit: sixteenBit),
      ],
    );

double _maxErr(Float64List a, Float64List b) {
  var m = 0.0;
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final e = (a[i] - b[i]).abs();
    if (e > m) m = e;
  }
  return m;
}

/// A 4-channel MOD with [patternCount] patterns (each 64 empty rows). The order
/// references every pattern so parseMod reconstructs the full pattern count.
ModModule _modWith(int patternCount) => ModModule(
      title: 'sig test',
      restart: 0,
      samples: [for (var i = 0; i < 31; i++) ModSample.empty()],
      order: [for (var i = 0; i < patternCount; i++) i],
      patterns: [for (var i = 0; i < patternCount; i++) const ModPattern([])],
    );

/// The 4-byte signature writeMod emitted at offset 0x438 (1080).
String _sigOf(Uint8List bytes) => String.fromCharCodes(
      bytes.sublist(0x438, 0x43C),
    );

void main() {
  group('XM 16-bit sample export', () {
    test('a 16-bit sample round-trips as 16-bit with PCM preserved', () {
      final back = parseAnyModule(convertToXm(_xmDoc(sixteenBit: true)));
      final sample = back.usedSamples.first;

      // The flag survived export → import.
      expect(sample.sixteenBit, isTrue);

      // PCM is preserved to 16-bit precision, NOT quantized to 8-bit. 8-bit
      // steps are ~1/128 (>0.007); 16-bit is near-lossless.
      final err16 = _maxErr(_wave(), sample.pcm);
      expect(
        err16,
        lessThan(0.0005),
        reason: '16-bit export should preserve fine detail',
      );

      // And it is a clear improvement over the 8-bit path on the same wave.
      final err8 = _maxErr(
        _wave(),
        parseAnyModule(convertToXm(_xmDoc(sixteenBit: false)))
            .usedSamples
            .first
            .pcm,
      );
      expect(
        err8,
        greaterThan(0.002),
        reason: '8-bit quantization is coarse',
      );
      expect(err16, lessThan(err8 / 4));
    });

    test('an 8-bit sample stays 8-bit (regression)', () {
      final back = parseAnyModule(convertToXm(_xmDoc(sixteenBit: false)));
      expect(back.usedSamples.first.sixteenBit, isFalse);
    });
  });

  group('MOD M!K! signature for >64 patterns', () {
    test('4 channels with >64 patterns → "M!K!", re-read as 4 channels', () {
      final bytes = writeMod(_modWith(65));
      expect(_sigOf(bytes), 'M!K!');
      expect(parseMod(bytes).channelCount, 4);
    });

    test('4 channels with ≤64 patterns → "M.K.", re-read as 4 channels', () {
      final bytes = writeMod(_modWith(64));
      expect(_sigOf(bytes), 'M.K.');
      expect(parseMod(bytes).channelCount, 4);
    });
  });
}
