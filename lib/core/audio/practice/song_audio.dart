// lib/core/audio/practice/song_audio.dart
//
// A song the learner brings — decoded to float stereo at its own rate, ready to
// be separated into stems and played back. Pure Dart (web-safe): WAV and MP3
// decode here; the native file path (song_audio_file_io.dart) adds CrispASR's
// miniaudio decoder for everything else (FLAC, …).

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

/// Decoded song audio: two channels at [sampleRate] (a mono source carries the
/// same samples in both).
class SongAudio {
  const SongAudio(this.left, this.right, this.sampleRate);

  final Float32List left;
  final Float32List right;
  final int sampleRate;

  int get frames => left.length < right.length ? left.length : right.length;
  double get seconds => sampleRate == 0 ? 0 : frames / sampleRate;

  /// Both channels averaged — what the pitch and beat trackers take.
  Float64List mono() {
    final m = Float64List(frames);
    for (var i = 0; i < m.length; i++) {
      m[i] = (left[i] + right[i]) / 2;
    }
    return m;
  }
}

/// Decode WAV or MP3 [bytes], sniffed from the content rather than a file
/// name. Null for any other format. MP3 decoding is pure Dart and slow (about
/// real time), so it runs off the calling isolate.
Future<SongAudio?> decodeSongBytes(Uint8List bytes) async {
  if (_isWav(bytes)) {
    try {
      return songFromWav(readWavPcm16(bytes));
    } on FormatException {
      return null;
    }
  }
  if (_isMp3(bytes)) {
    return Isolate.run(() {
      try {
        final pcm = mp3Decode(bytes);
        return _deinterleave(pcm.samples, pcm.channels, pcm.sampleRate);
      } catch (_) {
        return null;
      }
    });
  }
  return null;
}

/// A [WavData] as a [SongAudio]: a mono file fills both channels, and a file
/// with more than two keeps its first two.
SongAudio songFromWav(WavData wav) {
  final ch = wav.channels < 1 ? 1 : wav.channels;
  final n = wav.samples.length ~/ ch;
  final l = Float32List(n);
  final r = Float32List(n);
  for (var i = 0; i < n; i++) {
    l[i] = wav.samples[i * ch] / 32768;
    r[i] = wav.samples[i * ch + (ch > 1 ? 1 : 0)] / 32768;
  }
  return SongAudio(l, r, wav.sampleRate);
}

SongAudio _deinterleave(Float64List samples, int channels, int sampleRate) {
  final ch = channels < 1 ? 1 : channels;
  final n = samples.length ~/ ch;
  final l = Float32List(n);
  final r = Float32List(n);
  for (var i = 0; i < n; i++) {
    l[i] = samples[i * ch];
    r[i] = samples[i * ch + (ch > 1 ? 1 : 0)];
  }
  return SongAudio(l, r, sampleRate);
}

bool _isWav(Uint8List b) =>
    b.length >= 12 &&
    b[0] == 0x52 && // R
    b[1] == 0x49 && // I
    b[2] == 0x46 && // F
    b[3] == 0x46 && // F
    b[8] == 0x57 && // W
    b[9] == 0x41; // A

bool _isMp3(Uint8List b) {
  if (b.length < 4) return false;
  // An ID3v2 tag, or an MPEG audio frame sync (11 set bits).
  if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return true;
  return b[0] == 0xFF && (b[1] & 0xE0) == 0xE0;
}
