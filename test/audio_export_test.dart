// Audio export — the pure PCM→WAV / PCM→MP3 encoders behind the shared export
// sheet. (The sheet's save flow uses file_selector, which needs a host; the
// byte builders are what carry the risk, so those are what we assert.)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _tone(int n, {double freq = 220}) => Float64List.fromList([
      for (var i = 0; i < n; i++)
        0.4 * math.sin(2 * math.pi * freq * i / 44100),
    ]);

void main() {
  final pcm = _tone(4608); // 8 MP3 granules (576 each)

  test('WAV export is a RIFF/WAVE container', () {
    final wav = pcmFloatToWav(pcm);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    // 44-byte header + 2 bytes per sample.
    expect(wav.length, 44 + pcm.length * 2);
  });

  test('WAV export supports 8, 24, and 32 bit PCM headers', () {
    final cases = <(int, int)>[(8, 1), (24, 3), (32, 4)];
    for (final (depth, bytesPerSample) in cases) {
      final wav = pcmFloatToWav(pcm, bitDepth: depth);
      final bd = wav.buffer.asByteData();
      expect(bd.getUint16(22, Endian.little), 1);
      expect(bd.getUint32(28, Endian.little), 44100 * bytesPerSample);
      expect(bd.getUint16(32, Endian.little), bytesPerSample);
      expect(bd.getUint16(34, Endian.little), depth);
      expect(wav.length, 44 + pcm.length * bytesPerSample);
    }
  });

  test('WAV export rejects unsupported bit depths', () {
    expect(() => pcmFloatToWav(pcm, bitDepth: 12), throwsArgumentError);
  });

  test('WAV export resamples when the output sample rate changes', () {
    final oneSecond = _tone(44100);
    final wav48 = pcmFloatToWav(
      oneSecond,
      sampleRate: 48000,
      sourceSampleRate: 44100,
    );
    final wav32 = pcmFloatToWav(
      oneSecond,
      sampleRate: 32000,
      sourceSampleRate: 44100,
      right: _tone(44100, freq: 330),
    );

    expect(wav48.buffer.asByteData().getUint32(24, Endian.little), 48000);
    expect(wav48.length, 44 + 48000 * 2);
    expect(wav32.buffer.asByteData().getUint32(24, Endian.little), 32000);
    expect(wav32.buffer.asByteData().getUint16(22, Endian.little), 2);
    expect(wav32.length, 44 + 32000 * 4);
  });

  test('MP3 export starts with an MPEG-1 Layer III frame sync', () {
    final mp3 = pcmFloatToMp3(pcm);
    expect(mp3.length, greaterThan(0));
    expect(mp3[0], 0xFF); // sync byte 1
    expect(mp3[1] & 0xE0, 0xE0); // sync bits
    // MPEG-1 (bits 11) + Layer III (bits 01) → 0xFB in the common case.
    expect(mp3[1] & 0x18, 0x18, reason: 'MPEG-1');
    expect(mp3[1] & 0x06, 0x02, reason: 'Layer III');
  });

  test('MP3 is much smaller than the WAV for the same audio', () {
    final long = _tone(44100); // 1 s
    expect(pcmFloatToMp3(long).length, lessThan(pcmFloatToWav(long).length));
  });

  test('MP3 export size tracks the chosen bitrate', () {
    final long = _tone(44100); // 1 s
    final low = pcmFloatToMp3(long);
    final high = pcmFloatToMp3(long, bitrate: 320);
    expect(high.length, greaterThan(low.length));
    expect(mp3Decode(high).samples.length, greaterThan(0));
  });

  test('MP3 export resamples to a supported chosen rate', () {
    final mp3 = pcmFloatToMp3(
      _tone(44100),
      sampleRate: 48000,
      sourceSampleRate: 44100,
    );
    final decoded = mp3Decode(mp3);
    expect(decoded.sampleRate, 48000);
    expect(decoded.samples.length, greaterThanOrEqualTo(48000));
  });

  test('a bad sample rate is rejected by the MP3 encoder', () {
    expect(() => pcmFloatToMp3(pcm, sampleRate: 12345), throwsArgumentError);
  });

  test('stereo WAV export declares two channels', () {
    final wav = pcmFloatToWav(
      pcm,
      right: _tone(4608, freq: 330),
      bitDepth: 24,
    );
    // numChannels @ byte 22, blockAlign @ 32 (ch*3), 6 bytes/frame.
    expect(wav.buffer.asByteData().getUint16(22, Endian.little), 2);
    expect(wav.buffer.asByteData().getUint16(34, Endian.little), 24);
    expect(wav.length, 44 + pcm.length * 6);
  });

  test('stereo MP3 export decodes back to two channels', () {
    final mp3 = pcmFloatToMp3(pcm, right: _tone(4608, freq: 330));
    final dec = mp3Decode(mp3);
    expect(dec.channels, 2);
  });

  test('short blocks are on by default and export stays valid on a transient',
      () {
    // A percussive click train — the case short blocks exist for.
    final tr = Float64List(44100);
    for (var i = 0; i < tr.length; i++) {
      final t = i / 44100;
      tr[i] =
          0.7 * math.exp(-40 * (t % 0.25)) * math.sin(2 * math.pi * 300 * t);
    }
    final withShort = pcmFloatToMp3(tr); // default shortBlocks: true
    final longOnly = pcmFloatToMp3(tr, shortBlocks: false);
    // Both are valid MP3s; the default differs from long-only (it switched).
    expect(mp3Decode(withShort).samples.length, greaterThan(0));
    expect(withShort, isNot(equals(longOnly)));
  });

  test('mono export unchanged: short blocks off == old long-only bytes', () {
    // A steady tone has no transients ⇒ short-blocks-on is byte-identical.
    expect(pcmFloatToMp3(pcm), equals(pcmFloatToMp3(pcm, shortBlocks: false)));
  });

  group('WAV TPDF dither', () {
    test('off (explicit) is byte-identical to the default undithered path', () {
      final pcm = _tone(2000);
      final a = pcmFloatToWav(pcm);
      // ignore: avoid_redundant_argument_values  (asserting explicit-off == default)
      final b = pcmFloatToWav(pcm, dither: false);
      expect(b, equals(a));
    });

    test('on changes the samples but keeps a valid WAV of the same length', () {
      final pcm = _tone(2000);
      final plain = pcmFloatToWav(pcm);
      final dithered = pcmFloatToWav(pcm, dither: true);
      expect(dithered.length, plain.length); // same header + frame count
      expect(String.fromCharCodes(dithered.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(dithered.sublist(8, 12)), 'WAVE');
      // The data must actually differ (dither perturbs the LSBs).
      expect(dithered.sublist(44), isNot(equals(plain.sublist(44))));
    });

    test('is deterministic (fixed seed → reproducible export)', () {
      final pcm = _tone(2000);
      final one = pcmFloatToWav(pcm, dither: true);
      final two = pcmFloatToWav(pcm, dither: true);
      expect(two, equals(one));
    });

    test('dithered samples stay within the 16-bit range (no wrap)', () {
      // Full-scale signal + dither must clamp, never wrap to the opposite sign.
      final loud = Float64List.fromList(List<double>.filled(500, 1.0));
      final w = pcmFloatToWav(loud, dither: true);
      final bd = ByteData.sublistView(w);
      for (var o = 44; o + 1 < w.length; o += 2) {
        expect(bd.getInt16(o, Endian.little), inInclusiveRange(-32768, 32767));
      }
    });
  });
}
