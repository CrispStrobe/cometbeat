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

// cometbeat_opus_file_decode — our glue in native/glint/src/opus_file_c_api.cpp,
// NOT a glint symbol (hence the prefix: flac_c_api.cpp once took a glint_ name
// and glint later defined it itself).
typedef _OpusDecNative = Pointer<Float> Function(
  Pointer<Uint8>,
  Int32,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _OpusDec = Pointer<Float> Function(
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);

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

/// Decodes ANY stream glint recognises — MP3, AAC-LC, Ogg-Opus, Ogg-Vorbis or
/// FLAC — through `glint_decode_audio`, which detects the format from the
/// header. Signature is identical to the Opus-only decoder, so it reuses
/// [_OpusDec].
class GlintAudioDecoder {
  GlintAudioDecoder.open(String libraryPath)
      : this._(DynamicLibrary.open(libraryPath));

  GlintAudioDecoder.process() : this._(DynamicLibrary.process());

  GlintAudioDecoder._(this._lib) {
    _decode = _lib.lookupFunction<_OpusDecNative, _OpusDec>(
      'glint_decode_audio',
    );
    _free = _lib.lookupFunction<_FreeNative, _Free>('glint_free');
  }

  final DynamicLibrary _lib;
  late final _OpusDec _decode;
  late final _Free _free;

  AudioFileDecode get decodeAudioFile => decode;

  DecodedAudio? decode(Uint8List bytes) =>
      _decodeInto(_decode, _free, bytes, fallbackRate: 44100);
}

/// Shared body for the two whole-file decoders above: marshal in, copy the PCM
/// out of native memory, free it. Kept in one place so a leak can only be
/// written once.
DecodedAudio? _decodeInto(
  _OpusDec decode,
  _Free free,
  Uint8List bytes, {
  required int fallbackRate,
}) {
  if (bytes.isEmpty) return null;
  final inPtr = calloc<Uint8>(bytes.length);
  final sr = calloc<Int32>();
  final ch = calloc<Int32>();
  final frames = calloc<Int32>();
  try {
    inPtr.asTypedList(bytes.length).setAll(0, bytes);
    final out = decode(inPtr, bytes.length, sr, ch, frames);
    if (out == nullptr || ch.value <= 0 || frames.value <= 0) return null;
    final count = frames.value * ch.value;
    final view = out.asTypedList(count);
    final pcm = Float64List(count);
    for (var i = 0; i < count; i++) {
      pcm[i] = view[i];
    }
    free(out.cast());
    return DecodedAudio(
      pcm: pcm,
      channels: ch.value,
      sampleRate: sr.value > 0 ? sr.value : fallbackRate,
    );
  } finally {
    calloc
      ..free(inPtr)
      ..free(sr)
      ..free(ch)
      ..free(frames);
  }
}

/// Decodes a complete Ogg-Opus stream back to PCM, through the plugin's
/// `cometbeat_opus_file_decode`.
///
/// Lives beside the encoder because that is what it is for: verifying that what
/// we encoded is what comes back out. Opus always decodes at 48 kHz.
class GlintOpusFileDecoder {
  GlintOpusFileDecoder.open(String libraryPath)
      : this._(DynamicLibrary.open(libraryPath));

  GlintOpusFileDecoder.process() : this._(DynamicLibrary.process());

  GlintOpusFileDecoder._(this._lib) {
    _decode = _lib.lookupFunction<_OpusDecNative, _OpusDec>(
      'cometbeat_opus_file_decode',
    );
    _free = _lib.lookupFunction<_FreeNative, _Free>('glint_free');
  }

  final DynamicLibrary _lib;
  late final _OpusDec _decode;
  late final _Free _free;

  OpusFileDecode get decodeOpusFile => decode;

  // Opus always decodes at 48 kHz, so that is the honest fallback if the
  // decoder somehow reports no rate.
  DecodedAudio? decode(Uint8List ogg) =>
      _decodeInto(_decode, _free, ogg, fallbackRate: 48000);
}
