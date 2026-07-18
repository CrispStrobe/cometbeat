// glint_vorbis — a Flutter FFI plugin that compiles the glint Ogg-Vorbis decoder
// (MIT) into the app and exports its C ABI (glint_vorbis_decode / glint_free).
//
// This package has no Dart API of its own: the app reaches the bundled symbols
// through lib/core/audio/sf2/vorbis_capability.dart (which resolves the plugin
// library by its conventional name / DynamicLibrary.process()). Re-vendor the
// native sources from the glint repo with sync_glint.sh.
library;
