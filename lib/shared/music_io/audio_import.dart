// lib/shared/music_io/audio_import.dart
//
// The read side of the shared audio I/O. Where `audio_export.dart` writes WAV/
// MP3, this reads them back: any screen that loads a user audio file (Voice Lab,
// sample import) can accept **WAV, MP3, or FLAC** from one place instead of a
// WAV-only picker. WAV goes through `readWavPcm16`; MP3 through our pure-Dart
// `mp3Decode`; FLAC uses the platform-safe glint capability seam.
//
// Format is detected by MAGIC BYTES, not the extension, so a mislabelled file
// still decodes (or fails cleanly to null rather than mis-parsing).
//
// This file is deliberately Flutter-free so it works
// in pure/headless code too (e.g. the sample-pack extractor). Screens build
// their own file-picker `XTypeGroup` from [kAudioImportExtensions].

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/sf2/flac_capability.dart';
import 'package:comet_beat/core/audio/wav_io.dart' show readWavPcm16;

/// Mono float PCM (−1..1) plus its sample rate — the common currency the Sound
/// Lab tools work in.
class ImportedAudio {
  const ImportedAudio(this.pcm, this.sampleRate, {this.right});

  final Float64List pcm;
  final int sampleRate;
  final Float64List? right;
}

/// Importable audio file extensions (for a picker `XTypeGroup`). Kept as a plain
/// list so this stays Flutter-free; screens wrap it in an `XTypeGroup`.
const List<String> kAudioImportExtensions = ['wav', 'mp3', 'flac'];

/// True if [bytes] looks like a RIFF/WAVE file.
bool _isWav(Uint8List b) =>
    b.length >= 12 &&
    b[0] == 0x52 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x46 && // "RIFF"
    b[8] == 0x57 &&
    b[9] == 0x41 &&
    b[10] == 0x56 &&
    b[11] == 0x45; // "WAVE"

/// True if [bytes] looks like MP3: an ID3v2 tag, or an MPEG audio frame sync
/// (0xFF followed by 111x xxxx).
bool _isMp3(Uint8List b) {
  if (b.length < 3) return false;
  if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return true; // "ID3"
  // Scan a little for the first frame sync (some files have a byte or two of
  // junk / a stripped tag before it).
  final end = b.length - 1 < 4096 ? b.length - 1 : 4096;
  for (var i = 0; i < end; i++) {
    if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) return true;
  }
  return false;
}

bool _isFlac(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x66 &&
    b[1] == 0x4C &&
    b[2] == 0x61 &&
    b[3] == 0x43; // "fLaC"

/// Decodes [bytes] (WAV, MP3, or FLAC, detected by content) to float PCM.
/// Returns null if the format is unrecognised or decoding fails.
ImportedAudio? importAudio(
  Uint8List bytes, {
  FlacDecode? flacDecode,
}) {
  try {
    if (_isWav(bytes)) {
      final wav = readWavPcm16(bytes);
      final channels = wav.channels < 1 ? 1 : wav.channels;
      final interleaved = Float64List.fromList([
        for (final sample in wav.samples) sample / 32768.0,
      ]);
      final left = _channel(interleaved, channels, 0);
      final right = channels > 1 ? _channel(interleaved, channels, 1) : null;
      if (left.isEmpty) return null;
      return ImportedAudio(
        left,
        wav.sampleRate > 0 ? wav.sampleRate : 44100,
        right: right,
      );
    }
    if (_isMp3(bytes)) {
      final decoded = mp3Decode(bytes);
      final channels = decoded.channels < 1 ? 1 : decoded.channels;
      final left = _channel(decoded.samples, channels, 0);
      final right =
          channels > 1 ? _channel(decoded.samples, channels, 1) : null;
      if (left.isEmpty) return null;
      return ImportedAudio(
        left,
        decoded.sampleRate > 0 ? decoded.sampleRate : 44100,
        right: right,
      );
    }
    if (_isFlac(bytes)) {
      final decoded = (flacDecode ?? loadGlintFlac())?.call(bytes);
      if (decoded == null || decoded.left.isEmpty) return null;
      return ImportedAudio(
        decoded.left,
        decoded.sampleRate > 0 ? decoded.sampleRate : 44100,
        right: decoded.right,
      );
    }
  } catch (_) {
    // fall through to null — callers show a friendly "couldn't read" message
  }
  return null;
}

/// Decodes an audio file and folds stereo to mono for instruments and legacy
/// callers that only accept one channel.
ImportedAudio? importAudioMono(
  Uint8List bytes, {
  FlacDecode? flacDecode,
}) {
  final imported = importAudio(bytes, flacDecode: flacDecode);
  if (imported == null || imported.right == null) return imported;
  final frames = math.min(imported.pcm.length, imported.right!.length);
  final mono = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    mono[i] = (imported.pcm[i] + imported.right![i]) * 0.5;
  }
  return ImportedAudio(mono, imported.sampleRate);
}

Float64List _channel(Float64List interleaved, int channels, int channel) {
  final frames = interleaved.length ~/ channels;
  final out = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    out[i] = interleaved[i * channels + channel];
  }
  return out;
}
