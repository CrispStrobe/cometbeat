// Audio export — the pure PCM→WAV / PCM→MP3 encoders behind the shared export
// sheet. (The sheet's save flow uses file_selector, which needs a host; the
// byte builders are what carry the risk, so those are what we assert.)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) 0.4 * math.sin(2 * math.pi * 220 * i / 44100),
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

  test('a bad sample rate is rejected by the MP3 encoder', () {
    expect(() => pcmFloatToMp3(pcm, sampleRate: 12345), throwsArgumentError);
  });
}
