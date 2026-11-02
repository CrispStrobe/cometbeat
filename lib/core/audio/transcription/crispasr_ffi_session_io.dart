// Opens a CrispASR ggml session for a given backend (native FFI). Resolves the
// backend's GGUF through CrispASR's OWN registry + cache (no hand-rolled URLs),
// then opens a `CrispasrSession` on libcrispasr. Null on any failure (no lib,
// old lib, backend/model not registered, not cached & no download) so callers
// fall back. dart:io only. Reused by the crepe/piano/separate FFI providers.

import 'dart:ffi';
import 'dart:io';

import 'package:crispasr/crispasr.dart';

/// Whether this device's libcrispasr loads and knows [backend] — the model
/// may still need downloading. Lets a screen offer a feature (and say how big
/// the download is) without fetching anything.
bool crispasrBackendRegistered(String backend) {
  final lib = _openLib();
  return lib != null && registryLookup(backend, lib: lib) != null;
}

/// The local path of [backend]'s GGUF, resolved through CrispASR's registry +
/// cache, or null (no lib, backend not registered, not cached and no
/// [download]). Cheap when the model is cached: it loads nothing but the lib —
/// which is why it, not [openCrispasrSession], is the availability probe for a
/// model that takes seconds to load.
String? crispasrModelPath(String backend, {bool download = false}) {
  final lib = _openLib();
  if (lib == null) return null;
  final entry = registryLookup(backend, lib: lib);
  if (entry == null) return null; // this build has no such backend registered
  final dir = cacheDir(lib: lib);
  final cached = dir == null ? null : File('$dir/${entry.filename}');
  if (cached != null && cached.existsSync() && cached.lengthSync() > 0) {
    return cached.path;
  }
  if (!download) return null;
  try {
    return cacheEnsureFile(entry.filename, entry.url, lib: lib);
  } catch (_) {
    return null;
  }
}

/// Open a session for [backend] (e.g. `crepe`, `piano-transcription`,
/// `htdemucs`), or null. [download] fetches the GGUF if not cached.
CrispasrSession? openCrispasrSession(String backend, {bool download = false}) {
  final modelPath = crispasrModelPath(backend, download: download);
  if (modelPath == null) return null;
  try {
    return CrispasrSession.open(
      modelPath,
      libPath: crispasrLibPath(),
      backend: backend,
    );
  } catch (_) {
    return null;
  }
}

/// Absolute path of libcrispasr — env override, then a built macOS app's
/// Frameworks dir, then a dev drop in the cache dir, then the package default.
String crispasrLibPath() {
  final ov = Platform.environment['COMET_CRISPASR_LIB'];
  if (ov != null && ov.isNotEmpty) return ov;
  if (Platform.isMacOS) {
    try {
      final macos = File(Platform.resolvedExecutable).parent; // Contents/MacOS
      final bundled = '${macos.parent.path}/Frameworks/libcrispasr.dylib';
      if (File(bundled).existsSync()) return bundled;
    } catch (_) {
      // fall through
    }
  }
  final home = Platform.environment['HOME'];
  if (home != null) {
    final drop = '$home/.cache/crispasr/libcrispasr.dylib';
    if (File(drop).existsSync()) return drop;
  }
  return CrispASR.defaultLibName();
}

DynamicLibrary? _openLib() {
  try {
    return DynamicLibrary.open(crispasrLibPath());
  } catch (_) {
    return null;
  }
}
