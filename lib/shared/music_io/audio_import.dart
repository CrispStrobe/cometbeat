// lib/shared/music_io/audio_import.dart
//
// The read side of the shared audio I/O. Where `audio_export.dart` writes WAV/
// MP3/Opus/AAC, this reads them back: any screen that loads a user audio file
// (Voice Lab, sample import) can accept **WAV, AIFF, MP3, AAC, FLAC,
// Ogg-Vorbis or Ogg-Opus** from one place instead of a WAV-only picker.
//
// WAV goes through `readWavPcm16`, AIFF/AIFF-C through `readAiff`, MP3 through
// our own `mp3Decode` — all pure Dart, so all three work on web. FLAC, Vorbis
// and Opus need glint, reached through the platform-safe capability seams
// (dart:ffi natively, the wasm shim on web).
//
// Format is detected by MAGIC BYTES, not the extension, so a mislabelled file
// still decodes (or fails cleanly to null rather than mis-parsing).
//
// This file is deliberately Flutter-free so it works
// in pure/headless code too (e.g. the sample-pack extractor). Screens build
// their own file-picker `XTypeGroup` from [kAudioImportExtensions].

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aiff_io.dart' show isAiff, readAiff;
import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';
import 'package:comet_beat/core/audio/sf2/encode_capability.dart'
    show
        AudioFileDecode,
        OpusFileDecode,
        isOggOpus,
        loadAudioDecoder,
        loadOpusFileDecoder;
import 'package:comet_beat/core/audio/sf2/flac_capability.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_capability.dart';
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
const List<String> kAudioImportExtensions = [
  'wav',
  'mp3',
  'flac',
  'aif',
  'aiff',
  'aifc',
  'ogg',
  'oga',
  'opus',
  'aac',
  'm4a',
];

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

/// True if [b] starts with an ADTS AAC frame: a 12-bit sync word (0xFFF) whose
/// layer bits are 00. That last part is what separates it from an MP3 frame
/// sync, which shares the leading 0xFF and sets the layer bits.
bool _isAdtsAac(Uint8List b) {
  if (b.length < 7) return false;
  var off = 0;
  if (b.length > 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    // Skip an ID3v2 tag (syncsafe size) before looking at the first frame.
    off = 10 +
        ((b[6] & 0x7F) << 21 |
            (b[7] & 0x7F) << 14 |
            (b[8] & 0x7F) << 7 |
            (b[9] & 0x7F));
  }
  if (off + 2 > b.length) return false;
  return b[off] == 0xFF && (b[off + 1] & 0xF6) == 0xF0;
}

bool _isFlac(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x66 &&
    b[1] == 0x4C &&
    b[2] == 0x61 &&
    b[3] == 0x43; // "fLaC"

/// Decodes [bytes] (WAV, AIFF, MP3, FLAC, Ogg-Vorbis or Ogg-Opus, detected by
/// CONTENT not extension) to float PCM. Returns null if the format is
/// unrecognised or its decoder isn't available on this platform.
ImportedAudio? importAudio(
  Uint8List bytes, {
  FlacDecode? flacDecode,
  VorbisFileDecode? vorbisDecode,
  OpusFileDecode? opusDecode,
  AudioFileDecode? audioDecode,
}) {
  try {
    // WAV and AIFF are the same shape once parsed (interleaved PCM16 + rate),
    // so they share one path.
    if (_isWav(bytes) || isAiff(bytes)) {
      final wav = _isWav(bytes) ? readWavPcm16(bytes) : readAiff(bytes);
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
    // ADTS AAC BEFORE MP3: both start 0xFF, and _isMp3's loose sync scan
    // (0xFF followed by 111x xxxx) also matches an ADTS header, so testing MP3
    // first would send every .aac to the MP3 decoder. ADTS is the stricter
    // pattern — 12 sync bits with the layer field 00 — so it decides first.
    if (_isAdtsAac(bytes)) {
      final decoded = (audioDecode ?? loadAudioDecoder())?.call(bytes);
      if (decoded == null || decoded.frames <= 0) return null;
      final ch = decoded.channels < 1 ? 1 : decoded.channels;
      final left = _channel(decoded.pcm, ch, 0);
      final right = ch > 1 ? _channel(decoded.pcm, ch, 1) : null;
      if (left.isEmpty) return null;
      return ImportedAudio(
        left,
        decoded.sampleRate > 0 ? decoded.sampleRate : 44100,
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
    // Ogg-Opus BEFORE Ogg-Vorbis: both are `.ogg`/`.oga`, and an Opus stream
    // handed to the Vorbis decoder just fails. We can WRITE Opus (the export
    // sheet offers it), so not being able to read our own output back was a
    // hole — and a silent one, since the file passed the picker's extension
    // filter and then returned null like a corrupt file.
    if (isOggOpus(bytes)) {
      final decoded = (opusDecode ?? loadOpusFileDecoder())?.call(bytes);
      if (decoded == null || decoded.frames <= 0) return null;
      final ch = decoded.channels < 1 ? 1 : decoded.channels;
      final left = _channel(decoded.pcm, ch, 0);
      final right = ch > 1 ? _channel(decoded.pcm, ch, 1) : null;
      if (left.isEmpty) return null;
      return ImportedAudio(
        left,
        decoded.sampleRate > 0 ? decoded.sampleRate : 48000,
        right: right,
      );
    }
    if (isOggVorbis(bytes)) {
      // Like FLAC, this needs the native/wasm glint decoder; without it we
      // decline the file rather than pretending.
      final decoded = (vorbisDecode ?? loadGlintVorbisFile())?.call(bytes);
      if (decoded == null || decoded.left.isEmpty) return null;
      // The Ogg header is the backstop if a decoder didn't report a rate.
      final headerRate = oggVorbisSampleRate(bytes);
      return ImportedAudio(
        decoded.left,
        decoded.sampleRate > 0
            ? decoded.sampleRate
            : (headerRate > 0 ? headerRate : 44100),
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
  VorbisFileDecode? vorbisDecode,
  OpusFileDecode? opusDecode,
  AudioFileDecode? audioDecode,
}) {
  final imported = importAudio(
    bytes,
    flacDecode: flacDecode,
    vorbisDecode: vorbisDecode,
    opusDecode: opusDecode,
    audioDecode: audioDecode,
  );
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
