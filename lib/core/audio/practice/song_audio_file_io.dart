// Native: decode a picked song file. Order: glint (MP3, ADTS AAC, Ogg-Opus,
// Ogg-Vorbis, FLAC — stereo, the file's own rate, MP3 gapless; compiled into
// the app by the glint_vorbis plugin); then the pure-Dart decoders (WAV, and
// MP3 where glint is absent, e.g. tests); then CrispASR's miniaudio decoder,
// which returns MONO at the rate asked for.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/glint_audio_ffi.dart';
import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart'
    show crispasrLibPath;
import 'package:crispasr/crispasr.dart' show decodeAudioFileAtRate;

/// Decode the song at [path] (with its [bytes] already read), or null.
Future<SongAudio?> decodeSongFile(String path, Uint8List bytes) async {
  // WAV is cheapest read directly; everything else tries glint first.
  if (!isWavBytes(bytes)) {
    final viaGlint = await glintDecodeSong(bytes);
    if (viaGlint != null && viaGlint.frames > 0) return viaGlint;
  }
  final pure = await decodeSongBytes(bytes);
  if (pure != null) return pure;
  final libPath = crispasrLibPath();
  return Isolate.run(() {
    try {
      final d = decodeAudioFileAtRate(path, 44100, libPath: libPath);
      if (d.samples.isEmpty) return null;
      return SongAudio(d.samples, d.samples, d.sampleRate);
    } catch (_) {
      return null;
    }
  });
}
