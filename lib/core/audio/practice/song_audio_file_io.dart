// Native: decode a picked song file. WAV/MP3 go through the pure-Dart decoders
// (stereo, the file's own rate); anything else through CrispASR's miniaudio
// decoder, which returns MONO at the rate asked for — so a FLAC still plays and
// separates, just without its stereo image.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/song_audio.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart'
    show crispasrLibPath;
import 'package:crispasr/crispasr.dart' show decodeAudioFileAtRate;

/// Decode the song at [path] (with its [bytes] already read), or null.
Future<SongAudio?> decodeSongFile(String path, Uint8List bytes) async {
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
