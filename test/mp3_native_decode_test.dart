// MP3 through the native glint decoder (SFZ samples, audio import) must give
// exactly what the pure-Dart decoder gives — glint is only there for speed
// (~25x on a 44-sample bell set). Without a usable glint (>= 0.8.1: gapless)
// every path falls back to pure Dart, which these tests then cover instead.
// Run with COMET_GLINT_LIB=<glint build>/libglint.dylib to exercise native.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart';
import 'package:comet_beat/core/audio/sf2/encode_capability.dart';
import 'package:comet_beat/core/audio/sf2/sfz.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bellMp3() {
  final pcm = Float64List(44100);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] =
        0.5 * math.sin(2 * math.pi * 880 * i / 44100) * math.exp(-i / 9000);
  }
  return mp3EncodeMono(pcm);
}

void main() {
  final mp3 = _bellMp3();
  final native = loadMp3Decoder();

  test('the native MP3 decoder matches pure Dart sample for sample', () {
    if (native == null) {
      markTestSkipped('no gapless glint here (set COMET_GLINT_LIB)');
      return;
    }
    final a = native(mp3)!;
    final p = mp3Decode(mp3);
    expect(a.channels, p.channels);
    expect(a.pcm.length, p.samples.length);
    for (var i = 0; i < a.pcm.length; i++) {
      expect(a.pcm[i], closeTo(p.samples[i], 1e-6));
    }
  });

  test('audio import reads MP3 to the same samples on either decoder', () {
    final imported = importAudio(mp3)!;
    final p = mp3Decode(mp3);
    expect(imported.pcm.length, p.samples.length);
    for (var i = 0; i < p.samples.length; i += 97) {
      expect(imported.pcm[i], closeTo(p.samples[i], 1e-6));
    }
  });

  test('an SFZ with an MP3 sample loads cleanly', () {
    final warnings = <String>[];
    final sf = loadSfz(
      '<region> sample=bell.mp3 pitch_keycenter=81\n',
      readSample: (p) => p == 'bell.mp3' ? mp3 : null,
      onWarn: warnings.add,
    );
    expect(warnings, isEmpty);
    expect(sf.presets, isNotEmpty);
  });
}
