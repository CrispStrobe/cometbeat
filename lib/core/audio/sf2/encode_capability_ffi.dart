// Native (dart:ffi) encoder seam: load glint and expose its one-call encoder.
// Same resolution order as the decoders — an explicit path, then symbols linked
// into the process by the FFI plugin, then a bundled library file.

import 'dart:io' show Platform;

import 'package:comet_beat/core/audio/sf2/opus_glint_ffi.dart';

export 'package:comet_beat/core/audio/sf2/encoded_audio.dart';

List<String> _candidates() {
  if (Platform.isMacOS) {
    return const ['libglint.dylib', 'glint.framework/glint'];
  }
  if (Platform.isIOS) return const ['glint.framework/glint'];
  if (Platform.isAndroid || Platform.isLinux) return const ['libglint.so'];
  if (Platform.isWindows) return const ['glint.dll'];
  return const [];
}

/// A glint-backed encoder, or null if glint isn't available here (then the
/// export sheet just doesn't offer Opus/AAC — no crash, no half-written file).
EncodeAudio? loadGlintEncoder({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintEncoder.open(libraryPath).encodeAudio;
    } catch (_) {
      return null;
    }
  }
  try {
    return GlintEncoder.process().encodeAudio;
  } catch (_) {
    // Not compiled in (tests / plugin absent) → try a bundled library.
  }
  for (final name in _candidates()) {
    try {
      return GlintEncoder.open(name).encodeAudio;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}

/// The Ogg-Opus decoder that verifies the encoder's output, or null if the
/// plugin isn't here. Same resolution order as [loadGlintEncoder].
///
/// NB: unlike the encoder, this symbol (`cometbeat_opus_file_decode`) is OURS —
/// it exists only in native/glint, not in an upstream libglint. So a machine
/// with glint `make install`ed will resolve the encoder from
/// /usr/local/lib/libglint.dylib but NOT this, which is a useful tell that the
/// plugin proper isn't linked.
OpusFileDecode? loadOpusFileDecoder({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintOpusFileDecoder.open(libraryPath).decodeOpusFile;
    } catch (_) {
      return null;
    }
  }
  try {
    return GlintOpusFileDecoder.process().decodeOpusFile;
  } catch (_) {
    // Not compiled in → try a bundled library.
  }
  for (final name in _candidates()) {
    try {
      return GlintOpusFileDecoder.open(name).decodeOpusFile;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}

/// Whole-file decode of any format glint recognises (MP3, AAC-LC, Ogg-Opus,
/// Ogg-Vorbis, FLAC), auto-detected from the header. Same resolution order as
/// [loadGlintEncoder].
///
/// This is `glint_decode_audio`, vendored alongside the MP3 + AAC decoders so
/// native matches what the web/wasm build could always do. Before that, the app
/// could WRITE AAC and never read it back.
AudioFileDecode? loadAudioDecoder({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintAudioDecoder.open(libraryPath).decodeAudioFile;
    } catch (_) {
      return null;
    }
  }
  try {
    return GlintAudioDecoder.process().decodeAudioFile;
  } catch (_) {
    // Not compiled in -> try a bundled library.
  }
  for (final name in _candidates()) {
    try {
      return GlintAudioDecoder.open(name).decodeAudioFile;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}

/// Native needs no async load — the symbols are either linked in or they are
/// not — so readiness is just "did the encoder resolve".
Future<bool> ensureGlintCodecReady() async => loadGlintEncoder() != null;
