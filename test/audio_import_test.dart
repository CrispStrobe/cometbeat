// Audio import — the shared WAV/MP3 reader behind the Sound Lab pickers. Round-
// trips through our own encoders (pcmFloatToWav / mp3EncodeMono) so a file we
// write, we can read back; also checks format detection is by content and that
// junk fails cleanly to null.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/music_io/audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _tone(int n, {double freq = 220}) => Float64List.fromList([
      for (var i = 0; i < n; i++)
        0.4 * math.sin(2 * math.pi * freq * i / 44100),
    ]);

void main() {
  test('imports a WAV we wrote (mono float + sample rate)', () {
    final pcm = _tone(4608);
    final imported = importAudioMono(pcmFloatToWav(pcm));
    expect(imported, isNotNull);
    expect(imported!.sampleRate, 44100);
    expect(imported.pcm.length, pcm.length);
  });

  test('imports an MP3 we wrote (decoded to mono)', () {
    final pcm = _tone(44100); // 1 s
    final imported = importAudioMono(mp3EncodeMono(pcm));
    expect(imported, isNotNull);
    expect(imported!.sampleRate, 44100);
    // MP3 has codec delay/padding, so length is approximate, not exact.
    expect(imported.pcm.length, greaterThan(40000));
    // The 220 Hz tone survived (non-trivial energy).
    var energy = 0.0;
    for (final s in imported.pcm) {
      energy += s * s;
    }
    expect(energy / imported.pcm.length, greaterThan(0.01));
  });

  test('a stereo MP3 imports as mono (channels averaged)', () {
    final l = _tone(4608);
    final r = _tone(4608, freq: 330);
    final imported = importAudioMono(mp3EncodeJointStereo(l, r));
    expect(imported, isNotNull);
    expect(imported!.pcm.isNotEmpty, isTrue);
  });

  test('detection is by content, not extension: raw junk returns null', () {
    final junk = Uint8List.fromList(List<int>.generate(2048, (i) => i % 256));
    expect(importAudioMono(junk), isNull);
  });

  test('empty bytes return null (no throw)', () {
    expect(importAudioMono(Uint8List(0)), isNull);
  });

  test('the shared type group offers wav + mp3', () {
    expect(kAudioImportGroup.extensions, containsAll(['wav', 'mp3']));
  });
}
