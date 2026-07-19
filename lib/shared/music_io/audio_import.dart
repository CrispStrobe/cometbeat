// lib/shared/music_io/audio_import.dart
//
// The read side of the shared audio I/O. Where `audio_export.dart` writes WAV/
// MP3, this reads them back: any screen that loads a user audio file (Voice Lab,
// sample import) can accept **WAV or MP3** from one place instead of a WAV-only
// picker. WAV goes through `readWavPcm16`; MP3 through our pure-Dart `mp3Decode`
// (all block types), so this is web-safe and needs no native decoder.
//
// Format is detected by MAGIC BYTES, not the extension, so a mislabelled file
// still decodes (or fails cleanly to null rather than mis-parsing).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:file_selector/file_selector.dart';

/// Mono float PCM (−1..1) plus its sample rate — the common currency the Sound
/// Lab tools work in.
class ImportedAudio {
  const ImportedAudio(this.pcm, this.sampleRate);

  final Float64List pcm;
  final int sampleRate;
}

/// The file-picker type group for importable audio (WAV + MP3).
const XTypeGroup kAudioImportGroup = XTypeGroup(
  label: 'Audio (WAV, MP3)',
  extensions: ['wav', 'mp3'],
);

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

/// Decodes [bytes] (WAV or MP3, detected by content) to mono float PCM.
/// Returns null if the format is unrecognised or decoding fails.
ImportedAudio? importAudioMono(Uint8List bytes) {
  try {
    if (_isWav(bytes)) {
      final wav = readWavPcm16(bytes);
      final pcm = wavToMonoFloat(wav);
      if (pcm.isEmpty) return null;
      return ImportedAudio(pcm, wav.sampleRate > 0 ? wav.sampleRate : 44100);
    }
    if (_isMp3(bytes)) {
      final decoded = mp3Decode(bytes);
      final mono = _deinterleaveMono(decoded.samples, decoded.channels);
      if (mono.isEmpty) return null;
      return ImportedAudio(
        mono,
        decoded.sampleRate > 0 ? decoded.sampleRate : 44100,
      );
    }
  } catch (_) {
    // fall through to null — callers show a friendly "couldn't read" message
  }
  return null;
}

/// Downmix interleaved [samples] (`channels` per frame) to mono by averaging.
Float64List _deinterleaveMono(Float64List samples, int channels) {
  if (channels <= 1) return samples;
  final frames = samples.length ~/ channels;
  final out = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += samples[f * channels + c];
    }
    out[f] = sum / channels;
  }
  return out;
}
