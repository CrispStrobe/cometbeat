# glint_vorbis — native Ogg-Vorbis decoder (Flutter FFI plugin)

Compiles the **minimal glint Ogg-Vorbis decode source set** (from the MIT
[glint](https://github.com/CrispStrobe) codec suite) into the CometBeat app, so
compressed **`.sf3` SoundFonts** can be decoded on native platforms. Exposes
glint's C ABI `glint_vorbis_decode` / `glint_free`.

Reached **only** through `lib/core/audio/sf2/vorbis_capability.dart` (web gets a
`dart:ffi`-free stub); the decoder **degrades gracefully to null** if the plugin
isn't built, so `.sf3` simply stays unsupported rather than crashing.

## What's vendored

`sync_glint.sh` copies the exact minimal set into `src/` (re-run it after glint's
`feature/vorbis-decoder` lands on glint `main`, e.g. floor-0 changes):

- `vorbis_c_api.cpp` · `vorbis_decoder.cpp` · `opus_ogg.cpp` (Ogg framing/CRC) ·
  `resample.cpp` + headers, plus `glint_free_shim.cpp` (glint's real `glint_free`
  is entangled with the AAC/MP3 decoder, so we ship the 2-line `free()` shim).

The full glint suite (MP3/AAC/Opus + the Vorbis **encoder** side) is intentionally
NOT pulled in — only the Vorbis decode path.

## Build wiring

- **Android / Linux / Windows:** `src/CMakeLists.txt` (C++17) builds one
  `glint_vorbis` shared library; the platform folders delegate to it.
- **macOS / iOS:** the podspecs compile the same sources via `Classes/`
  forwarders (C++17 + libc++).

## Verification status

- ✅ The minimal source set **compiles standalone** (clang++ and the CMake) and
  **decodes correctly** (matches ffmpeg frame-for-frame).
- ✅ The `Classes/` forwarders **compile with the exact podspec flags** (c++17,
  libc++).
- ✅ End-to-end: the CometBeat `.sf3` oracle decodes the real FluidR3Mono.sf3 in
  tune (1.7–2.9¢) through glint. See `docs/ORACLE.md`.
- ⏳ A full per-platform `flutter build` (macOS/iOS/Android/Windows/Linux) is the
  final confirmation — verify on CI before relying on `.sf3` on a given platform,
  as with `native/aec`.

Re-vendor: `GLINT_DIR=~/code/glint ./sync_glint.sh`.
