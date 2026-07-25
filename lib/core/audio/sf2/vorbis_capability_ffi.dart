// Native (dart:ffi) `.sf3` Vorbis decoder seam: load the glint shared library
// and expose its decode as a [VorbisDecode]. Selected by vorbis_capability.dart
// only where dart:ffi exists. Degrades gracefully — if the glint library isn't
// present (not yet bundled for this platform), returns null and `.sf3` falls
// back to the clear rejection rather than crashing.

import 'dart:io' show Platform;

import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;
import 'package:comet_beat/core/audio/sf2/vorbis_glint_ffi.dart';

export 'package:comet_beat/core/audio/sf2/vorbis_pcm.dart';

/// Candidate glint library names to try, in order, per platform. When bundled
/// in the app these resolve via the app's native search path; an override path
/// (e.g. a dev build) can be passed to [loadGlintVorbis].
List<String> _candidates() {
  if (Platform.isMacOS) {
    return const ['libglint.dylib', 'glint.framework/glint'];
  }
  if (Platform.isIOS) return const ['glint.framework/glint'];
  if (Platform.isAndroid || Platform.isLinux) return const ['libglint.so'];
  if (Platform.isWindows) return const ['glint.dll'];
  return const [];
}

/// A glint-backed [VorbisDecode] for `.sf3`, or null if the glint decoder can't
/// be loaded on this platform (then `.sf3` stays unsupported, no crash). Pass
/// [libraryPath] to force a specific library (dev/testing).
///
/// Resolution order: an explicit [libraryPath]; then the `glint_vorbis` FFI
/// plugin compiled into the app (symbols in the process); then the
/// platform-conventional bundled library name.
VorbisDecode? loadGlintVorbis({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintVorbis.open(libraryPath).vorbisDecode;
    } catch (_) {
      return null;
    }
  }
  // The FFI plugin links glint's decoder into the app → symbols in-process.
  try {
    return GlintVorbis.process().vorbisDecode;
  } catch (_) {
    // Not compiled in (tests / plugin absent) → try a bundled library file.
  }
  for (final name in _candidates()) {
    try {
      return GlintVorbis.open(name).vorbisDecode;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}

/// Native decode is synchronous + needs no async warm-up: ready iff the glint
/// decoder loads. (Parity with the web seam's async loader.)
Future<bool> ensureGlintVorbisReady() async => loadGlintVorbis() != null;

/// The `.ogg` FILE decoder (keeps rate + both channels), or null if glint isn't
/// available here. Same resolution order as [loadGlintVorbis].
VorbisFileDecode? loadGlintVorbisFile({String? libraryPath}) {
  if (libraryPath != null) {
    try {
      return GlintVorbis.open(libraryPath).vorbisFileDecode;
    } catch (_) {
      return null;
    }
  }
  try {
    return GlintVorbis.process().vorbisFileDecode;
  } catch (_) {
    // Not compiled in → try a bundled library file.
  }
  for (final name in _candidates()) {
    try {
      return GlintVorbis.open(name).vorbisFileDecode;
    } catch (_) {
      // Try the next candidate, else null.
    }
  }
  return null;
}
