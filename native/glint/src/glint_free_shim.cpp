// glint_free: its real definition lives in glint's src/decoder_c_api.cpp,
// which this plugin does not vendor (it drags in the MP3 and AAC decoders).
// Provide it here so callers can release the buffers glint hands back.
//
// ALLOCATOR CHECK (2026-07-26) — this matters: the ENCODER also returns
// malloc'd buffers through this function, and a mismatched free is heap
// corruption that no smoke test would catch. Verified against glint @ 39f1feb:
//
//   * glint's own definition is exactly `void glint_free(void* p)
//     { std::free(p); }` (decoder_c_api.cpp:111) — this shim is identical,
//     not merely compatible.
//   * every buffer reachable through glint_free on the paths we compile is
//     std::malloc'd: encode_audio_c_api.cpp's dup() (the glint_encode_audio
//     return), glint_opus_encode_file (opus_c_api.cpp), the vorbis/flac
//     wrappers, and cometbeat_opus_file_decode. No new/new[] anywhere.
//   * shim and callers compile into the same shared library, so there is one
//     CRT even on Windows.
//
// Re-check after any sync_glint.sh run that adds sources:
//   grep -n 'malloc\|new \[\|::new' src/*.cpp
#include <cstdlib>
extern "C" void glint_free(void* p) { std::free(p); }
