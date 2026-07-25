// Native audio ENCODING via glint over dart:ffi — the missing half of the
// codec seam. We already decoded MP3/FLAC/Vorbis; glint's C ABI also exposes a
// one-call encoder, so Ogg-Opus (and AAC) export needs a binding, not a codec.
//
// glint's C ABI (src/glint/glint.h):
//   enum glint_enc_format { GLINT_ENC_MP3=0, GLINT_ENC_AAC=1, GLINT_ENC_OPUS=2 };
//   uint8_t* glint_encode_audio(const float* pcm, int frames, int channels,
//                               int sample_rate, int format, int bitrate_kbps,
//                               int vbr_quality, int quality, int* out_size);
//   void glint_free(void* p);
//
// The encoder resamples internally to a rate the codec allows (Opus → 48 kHz),
// so callers hand over whatever rate they have.
//
// NB: FLAC is deliberately absent — glint decodes FLAC but has no FLAC encoder,
// so there is nothing to bind for it.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/encoded_audio.dart';
import 'package:ffi/ffi.dart';

export 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

typedef _EncodeNative = Pointer<Uint8> Function(
  Pointer<Float>,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Pointer<Int32>,
);
typedef _Encode = Pointer<Uint8> Function(
  Pointer<Float>,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  Pointer<Int32>,
);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// glint's `glint_enc_format` values.
const int _formatMp3 = 0;
const int _formatAac = 1;
const int _formatOpus = 2;

int _formatCode(EncodedAudioFormat format) => switch (format) {
      EncodedAudioFormat.mp3 => _formatMp3,
      EncodedAudioFormat.aac => _formatAac,
      EncodedAudioFormat.opus => _formatOpus,
    };

/// A glint-backed encoder.
class GlintEncoder {
  GlintEncoder.open(String libraryPath)
      : this._(DynamicLibrary.open(libraryPath));

  /// Symbols linked into the host process — the normal in-app path.
  GlintEncoder.process() : this._(DynamicLibrary.process());

  GlintEncoder._(this._lib) {
    _encode = _lib.lookupFunction<_EncodeNative, _Encode>('glint_encode_audio');
    _free = _lib.lookupFunction<_FreeNative, _Free>('glint_free');
  }

  final DynamicLibrary _lib;
  late final _Encode _encode;
  late final _Free _free;

  EncodeAudio get encodeAudio => encode;

  /// Encode interleaved float PCM to a complete stream. Returns null on error.
  Uint8List? encode(
    Float64List interleaved, {
    required int channels,
    required int sampleRate,
    required EncodedAudioFormat format,
    int bitrateKbps = 128,
    int vbrQuality = -1, // -1 = CBR
    int quality = 5,
  }) {
    if (interleaved.isEmpty || channels < 1) return null;
    final frames = interleaved.length ~/ channels;
    if (frames < 1) return null;

    final inPtr = calloc<Float>(interleaved.length);
    final outSize = calloc<Int32>();
    try {
      final view = inPtr.asTypedList(interleaved.length);
      for (var i = 0; i < interleaved.length; i++) {
        view[i] = interleaved[i];
      }
      final out = _encode(
        inPtr,
        frames,
        channels,
        sampleRate,
        _formatCode(format),
        bitrateKbps,
        vbrQuality,
        quality,
        outSize,
      );
      if (out == nullptr || outSize.value <= 0) return null;
      // Copy out of native memory before freeing it.
      final bytes = Uint8List.fromList(out.asTypedList(outSize.value));
      _free(out.cast());
      return bytes;
    } finally {
      calloc
        ..free(inPtr)
        ..free(outSize);
    }
  }
}
