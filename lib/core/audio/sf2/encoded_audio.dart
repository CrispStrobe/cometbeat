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

/// Decode a complete encoded stream of ANY format glint recognises — MP3,
/// AAC-LC, Ogg-Opus, Ogg-Vorbis or FLAC — auto-detected from its header.
///
/// Null where no such decoder exists on this platform. Today that means: the
/// web (wasm) build has one, native does not, because the native plugin
/// vendors only the encode closure plus the Vorbis/FLAC/Opus decoders. Callers
/// must therefore treat null as "not supported here", not as an error.
typedef AudioFileDecode = DecodedAudio? Function(Uint8List bytes);

/// True if [b] is an Ogg stream carrying Opus (`OggS` + an `OpusHead` header
/// packet).
///
/// Ogg is only a container — the same `.ogg`/`.oga` extension covers Vorbis,
/// Opus, FLAC and Theora — so the codec has to be identified from the first
/// packet, exactly as [isOggVorbis] does for Vorbis. Checking `OggS` alone
/// would hand an Opus file to the Vorbis decoder.
bool isOggOpus(Uint8List b) {
  if (b.length < 36) return false;
  if (b[0] != 0x4F || b[1] != 0x67 || b[2] != 0x67 || b[3] != 0x53) {
    return false; // "OggS"
  }
  return _opusHeadAt(b) >= 0;
}

/// The channel count declared in the OpusHead header, or 0 if unreadable.
/// OpusHead: magic(8) version(1) channels(1) pre_skip(2) input_rate(4) …
int oggOpusChannels(Uint8List b) {
  final at = _opusHeadAt(b);
  if (at < 0 || at + 10 > b.length) return 0;
  return b[at + 9];
}

/// Offset of the `OpusHead` packet in the first page, or -1. The packet follows
/// the Ogg page header + its variable-length segment table, so scan rather than
/// assume a fixed offset (same reasoning as the Vorbis locator).
int _opusHeadAt(Uint8List b) {
  const magic = [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]; // OpusHead
  final limit = b.length < 512 ? b.length - magic.length : 504;
  outer:
  for (var i = 0; i < limit; i++) {
    for (var j = 0; j < magic.length; j++) {
      if (b[i + j] != magic[j]) continue outer;
    }
    return i;
  }
  return -1;
}

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
