// The AIFF/AIFF-C reader (O16). AIFF files are built here byte by byte rather
// than checked in as fixtures, so the test pins the FORMAT — big-endian data,
// the 80-bit extended sample rate, signed 8-bit, the 'sowt' little-endian
// variant — instead of one encoder's output.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/aiff_io.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 80-bit IEEE extended encoding of a positive whole-number rate.
Uint8List _extended(int rate) {
  final out = Uint8List(10);
  if (rate <= 0) return out;
  // Normalise: find the exponent so the mantissa's top bit is set.
  var shift = 0;
  var v = rate;
  while (v > 1) {
    v >>= 1;
    shift++;
  }
  final exponent = 16383 + shift;
  // Mantissa is the rate scaled so bit 63 is the leading 1.
  final mantissa = BigInt.from(rate) << (63 - shift);
  out[0] = (exponent >> 8) & 0xFF;
  out[1] = exponent & 0xFF;
  for (var i = 0; i < 8; i++) {
    out[2 + i] = ((mantissa >> (56 - 8 * i)) & BigInt.from(0xFF)).toInt();
  }
  return out;
}

/// Assemble a minimal uncompressed AIFF (or AIFF-C when [compression] is set).
Uint8List _aiff({
  required List<int> samples, // interleaved, at [bits]
  int channels = 1,
  int bits = 16,
  int rate = 44100,
  String? compression,
}) {
  final aifc = compression != null;
  final bytesPer = bits ~/ 8;
  final little = compression == 'sowt';

  final sound = BytesBuilder();
  sound.add(Uint8List(8)); // offset + blockSize, both 0
  for (final s in samples) {
    final b = ByteData(bytesPer);
    switch (bits) {
      case 8:
        b.setInt8(0, s);
      case 16:
        b.setInt16(0, s, little ? Endian.little : Endian.big);
      case 24:
        final v = s & 0xFFFFFF;
        final bytes = little
            ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]
            : [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
        for (var i = 0; i < 3; i++) {
          b.setUint8(i, bytes[i]);
        }
      case 32:
        b.setInt32(0, s, little ? Endian.little : Endian.big);
    }
    sound.add(b.buffer.asUint8List());
  }
  final ssnd = sound.toBytes();

  final comm = BytesBuilder();
  final head = ByteData(8)
    ..setInt16(0, channels)
    ..setUint32(2, samples.length ~/ channels)
    ..setInt16(6, bits);
  comm
    ..add(head.buffer.asUint8List())
    ..add(_extended(rate));
  if (aifc) comm.add(Uint8List.fromList(compression.codeUnits));
  final commBytes = comm.toBytes();

  Uint8List chunk(String id, Uint8List body) {
    final size = ByteData(4)..setUint32(0, body.length);
    return Uint8List.fromList([
      ...id.codeUnits,
      ...size.buffer.asUint8List(),
      ...body,
      if (body.length.isOdd) 0, // chunks pad to even, pad isn't in the size
    ]);
  }

  final payload = Uint8List.fromList([
    ...(aifc ? 'AIFC' : 'AIFF').codeUnits,
    ...chunk('COMM', commBytes),
    ...chunk('SSND', ssnd),
  ]);
  final formSize = ByteData(4)..setUint32(0, payload.length);
  return Uint8List.fromList([
    ...'FORM'.codeUnits,
    ...formSize.buffer.asUint8List(),
    ...payload,
  ]);
}

void main() {
  group('isAiff', () {
    test('accepts AIFF and AIFF-C, rejects WAV and junk', () {
      expect(isAiff(_aiff(samples: [0])), isTrue);
      expect(isAiff(_aiff(samples: [0], compression: 'NONE')), isTrue);
      expect(
        isAiff(Uint8List.fromList('RIFF....WAVEfmt '.codeUnits)),
        isFalse,
      );
      expect(isAiff(Uint8List.fromList([1, 2, 3])), isFalse);
    });
  });

  group('readAiff', () {
    test('reads big-endian 16-bit mono with its real sample rate', () {
      final wav = readAiff(
        _aiff(samples: [0, 16384, -16384, 32767, -32768], rate: 48000),
      );
      expect(wav.channels, 1);
      expect(wav.sampleRate, 48000);
      expect(wav.samples, [0, 16384, -16384, 32767, -32768]);
    });

    test('the 80-bit extended rate decodes for the usual rates', () {
      for (final rate in [8000, 22050, 32000, 44100, 48000, 96000]) {
        expect(
          readAiff(_aiff(samples: [1, 2], rate: rate)).sampleRate,
          rate,
          reason: '$rate Hz',
        );
      }
    });

    test('stereo frames stay interleaved', () {
      final wav = readAiff(
        _aiff(samples: [100, -100, 200, -200], channels: 2),
      );
      expect(wav.channels, 2);
      expect(wav.samples, [100, -100, 200, -200]);
    });

    test('8-bit AIFF is SIGNED (unlike 8-bit WAV)', () {
      // -128..127 scales up to the Int16 range; 0 stays centred.
      final wav = readAiff(_aiff(samples: [0, 127, -128], bits: 8));
      expect(wav.samples[0], 0);
      expect(wav.samples[1], 127 * 256);
      expect(wav.samples[2], -128 * 256);
    });

    test('24- and 32-bit are narrowed to PCM16', () {
      final w24 = readAiff(
        _aiff(samples: [0, 0x400000, -0x400000], bits: 24),
      );
      expect(w24.samples[0], 0);
      expect(w24.samples[1], closeTo(16384, 1));
      expect(w24.samples[2], closeTo(-16384, 1));

      final w32 = readAiff(_aiff(samples: [0, 0x40000000], bits: 32));
      expect(w32.samples[0], 0);
      expect(w32.samples[1], closeTo(16384, 1));
    });

    test("'sowt' AIFF-C is little-endian PCM and reads correctly", () {
      final wav = readAiff(
        _aiff(samples: [0, 16384, -16384], compression: 'sowt'),
      );
      expect(wav.samples, [0, 16384, -16384]);
    });

    test('a genuinely compressed AIFF-C is refused with a clear message', () {
      expect(
        () => readAiff(_aiff(samples: [0, 1], compression: 'ima4')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ima4'),
          ),
        ),
      );
    });

    test('a non-AIFF, and one missing its chunks, throw', () {
      expect(
        () => readAiff(Uint8List.fromList('nope'.codeUnits)),
        throwsFormatException,
      );
      expect(
        () => readAiff(
          Uint8List.fromList(
            [...'FORM'.codeUnits, 0, 0, 0, 4, ...'AIFF'.codeUnits],
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('importAudio accepts AIFF', () {
    test('an AIFF decodes to float PCM at its own rate', () {
      final imported = importAudio(
        _aiff(samples: [0, 16384, -16384], rate: 22050),
      );
      expect(imported, isNotNull);
      expect(imported!.sampleRate, 22050);
      expect(imported.pcm[1], closeTo(0.5, 1e-4));
      expect(imported.right, isNull);
    });

    test('a stereo AIFF keeps both channels', () {
      final imported = importAudio(
        _aiff(samples: [16384, -16384, 16384, -16384], channels: 2),
      );
      expect(imported!.right, isNotNull);
      expect(imported.pcm.first, closeTo(0.5, 1e-4));
      expect(imported.right!.first, closeTo(-0.5, 1e-4));
    });

    test('AIFF is offered in the picker extensions', () {
      expect(kAudioImportExtensions, containsAll(['aif', 'aiff', 'aifc']));
    });

    test('a broken AIFF returns null rather than throwing', () {
      expect(
        importAudio(
          Uint8List.fromList(
            [...'FORM'.codeUnits, 0, 0, 0, 4, ...'AIFF'.codeUnits],
          ),
        ),
        isNull,
      );
    });
  });
}
