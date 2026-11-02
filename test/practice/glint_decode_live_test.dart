// Live: song import through glint's whole-file decoder. Needs a glint shared
// library (COMET_GLINT_LIB, e.g. a glint build's libglint.dylib — in the app
// the glint_vorbis plugin provides it) and ffmpeg to make the fixtures; skips
// itself otherwise.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/glint_audio_ffi.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytesStereo;
import 'package:flutter_test/flutter_test.dart';

/// Correlation of [x] with a sine of [hz] — near 1 when that tone is there.
double _tone(Float32List x, int sr, double hz) {
  var s = 0.0, c = 0.0, e = 0.0;
  for (var i = 0; i < x.length; i++) {
    s += x[i] * math.sin(2 * math.pi * hz * i / sr);
    c += x[i] * math.cos(2 * math.pi * hz * i / sr);
    e += x[i] * x[i];
  }
  return e == 0 ? 0 : math.sqrt(s * s + c * c) / math.sqrt(e * x.length / 2);
}

void main() {
  final hasFfmpeg = Process.runSync('which', ['ffmpeg']).exitCode == 0;
  final glint = resolveGlint();
  final skip = glint == null
      ? 'no glint library (set COMET_GLINT_LIB)'
      : (!hasFfmpeg ? 'ffmpeg not found' : null);

  late Directory tmp;
  late File wav;
  const sr = 44100, frames = sr * 2; // 2 s
  setUpAll(() {
    if (skip != null) return;
    tmp = Directory.systemTemp.createTempSync('glint_live');
    // Left 440 Hz, right 660 Hz: a decoder that drops or swaps a channel shows.
    final pcm = Int16List(frames * 2);
    for (var i = 0; i < frames; i++) {
      pcm[2 * i] = (12000 * math.sin(2 * math.pi * 440 * i / sr)).round();
      pcm[2 * i + 1] = (12000 * math.sin(2 * math.pi * 660 * i / sr)).round();
    }
    wav = File('${tmp.path}/in.wav')..writeAsBytesSync(wavBytesStereo(pcm));
  });
  tearDownAll(() {
    if (skip == null) tmp.deleteSync(recursive: true);
  });

  Future<SongAudio?> encodeAndDecode(String ext, List<String> codec) async {
    final out = '${tmp.path}/x.$ext';
    final r = Process.runSync('ffmpeg', [
      '-loglevel', 'error', '-y', '-i', wav.path, ...codec, out, //
    ]);
    if (r.exitCode != 0) return null;
    return glintDecodeSong(File(out).readAsBytesSync());
  }

  test(
    'MP3 decodes gapless: exactly the encoded length, stereo kept',
    () async {
      final song =
          await encodeAndDecode('mp3', ['-c:a', 'libmp3lame', '-b:a', '192k']);
      expect(song, isNotNull);
      expect(song!.sampleRate, sr);
      // Without the Xing/LAME trim this is +2,448 frames (~25 ms late).
      expect(song.frames, frames);
      expect(_tone(song.left, sr, 440), greaterThan(0.9));
      expect(_tone(song.right, sr, 660), greaterThan(0.9));
      expect(_tone(song.left, sr, 660), lessThan(0.1));
    },
    skip: skip,
  );

  for (final (ext, codec) in [
    ('ogg', ['-c:a', 'libvorbis', '-q:a', '5']),
    ('opus', ['-c:a', 'libopus', '-b:a', '128k']),
    ('flac', ['-c:a', 'flac']),
  ]) {
    test(
      '$ext decodes in stereo with both tones in place',
      () async {
        final song = await encodeAndDecode(ext, codec);
        if (song == null) {
          markTestSkipped('this ffmpeg cannot encode $ext');
          return;
        }
        expect(song.frames, greaterThan(frames * 0.95));
        expect(_tone(song.left, song.sampleRate, 440), greaterThan(0.9));
        expect(_tone(song.right, song.sampleRate, 660), greaterThan(0.9));
      },
      skip: skip,
    );
  }

  test(
    'bytes glint does not recognise come back null, not garbage',
    () async {
      expect(
        await glintDecodeSong(Uint8List.fromList(List.filled(4096, 7))),
        isNull,
      );
    },
    skip: skip,
  );
}
