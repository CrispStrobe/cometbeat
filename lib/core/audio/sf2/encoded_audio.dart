// The shape of the native ENCODE seam, in a dart:ffi-free file so the export
// layer and web can name these types without pulling in the native encoder.
//
// Mirrors vorbis_pcm.dart on the decode side.

import 'dart:typed_data';

/// Formats the native encoder can produce.
///
/// FLAC is absent on purpose: glint decodes FLAC but ships no FLAC *encoder*,
/// so there is nothing to bind. Adding it means an actual encoder, not a seam.
enum EncodedAudioFormat { mp3, aac, opus }

extension EncodedAudioFormatX on EncodedAudioFormat {
  /// The file extension a stream of this format is normally saved as.
  String get extension => switch (this) {
        EncodedAudioFormat.mp3 => 'mp3',
        EncodedAudioFormat.aac => 'm4a',
        EncodedAudioFormat.opus => 'opus',
      };

  String get label => switch (this) {
        EncodedAudioFormat.mp3 => 'MP3',
        EncodedAudioFormat.aac => 'AAC',
        EncodedAudioFormat.opus => 'Opus',
      };
}

/// Interleaved float PCM decoded back out of an encoded stream.
class DecodedAudio {
  const DecodedAudio({
    required this.pcm,
    required this.channels,
    required this.sampleRate,
  });

  /// Interleaved, ±1.0. Length is [frames] * [channels].
  final Float64List pcm;
  final int channels;
  final int sampleRate;

  int get frames => channels == 0 ? 0 : pcm.length ~/ channels;
}

/// Decode a complete Ogg-Opus stream back to PCM, or null if it isn't one.
///
/// This is the counterpart of encoding to [EncodedAudioFormat.opus] and exists
/// so an export can be verified end to end — encode a tone, decode it, assert
/// the pitch survived. Opus always decodes at 48 kHz.
typedef OpusFileDecode = DecodedAudio? Function(Uint8List ogg);

/// Encode interleaved float PCM (±1.0) to a complete stream, or null on error.
typedef EncodeAudio = Uint8List? Function(
  Float64List interleaved, {
  required int channels,
  required int sampleRate,
  required EncodedAudioFormat format,
  int bitrateKbps,
  int vbrQuality,
  int quality,
});
