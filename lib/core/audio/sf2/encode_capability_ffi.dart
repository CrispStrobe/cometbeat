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
