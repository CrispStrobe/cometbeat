# glint_vorbis — native glint codecs (Flutter FFI plugin)

Compiles source sets from the MIT [glint](https://github.com/CrispStrobe) codec
suite into the CometBeat app. Two halves:

- **Decode** — `glint_decode_audio` takes a whole stream and detects the format
  from its header: **MP3, AAC-LC, Ogg-Opus, Ogg-Vorbis, FLAC**. Plus the
  narrower entry points the app already used: `glint_vorbis_decode` (compressed
  `.sf3` SoundFonts) and `glint_flac_decode` (SFZ samples, e.g. VCSL / VSCO2).
- **Encode** — `glint_encode_audio`: interleaved float PCM at any rate →
  **MP3 / AAC-LC / Ogg-Opus**, auto-resampling to a rate the codec allows
  (Opus → 48 kHz). This is what audio export uses.

Buffers from both halves are released with `glint_free`.

**Web runs the same C code** compiled to wasm — see `web/glint/`. Keeping the
two in step is the point: for a while native could WRITE AAC but not read it
back, while the wasm build could do both, so an export was unopenable on the
platform that made it.

> The package name is historical — it predates the FLAC and encode sets.
> Renaming it would churn five platform manifests for no functional gain.

Reached **only** through the capability seams under `lib/core/audio/sf2/` —
`vorbis_capability.dart`, `flac_capability.dart`, `encode_capability.dart` (web
gets `dart:ffi`-free stubs). Every seam **degrades gracefully to null** if the
plugin isn't built, so the affected feature simply isn't offered rather than
crashing: `.sf3` stays unsupported, and the export sheet falls back to WAV plus
the pure-Dart MP3 writer.

## What's vendored

`sync_glint.sh` copies the source sets into `src/` **verbatim** — this plugin
forks none of glint's codec logic, so re-running it is always safe:

- **decode:** `vorbis_c_api.cpp` · `vorbis_decoder.cpp` · `flac_decoder.cpp` ·
  `opus_ogg.cpp` (Ogg framing/CRC) · `resample.cpp`
- **encode:** `encode_audio_c_api.cpp` (the entry point) + the MP3 encoder
  (8 files), the AAC-LC encoder (5), and the CELT/Opus encoder (13)
- `opus_c_api.cpp`, which defines `glint_opus_encode_file`. It also names
  `OpusDecoder` / `OpusMsDecoder`, so taking it verbatim brings the Opus + SILK
  **decoder** along (+97 KB, measured). We pay that rather than hand-copy
  glint's muxing logic into a local shim that would silently drift.

One file is **local, not vendored**: `opus_file_c_api.cpp`
(`cometbeat_opus_file_decode` — Ogg-Opus → PCM glue, so the encode round-trip is
testable end to end). There used to be a local `flac_c_api.cpp` too; vendoring
`decode_audio_c_api.cpp` retired it, because glint defines `glint_flac_decode`
itself and the two collided. One less fork. Plus `glint_free_shim.cpp`: glint's real `glint_free`
lives in `decoder_c_api.cpp`, which we don't vendor. Read that file's header
before touching it — the encoder returns malloc'd buffers, so a mismatched free
would be heap corruption that no smoke test catches.

`sync_glint.sh` also **generates** `src/glint_sources.cmake` and the
`macos/ios Classes/` forwarders from whatever `.cpp` ended up in `src/`, so a
vendored-but-unlisted source cannot become a link error that only one platform
discovers.

## Build wiring

- **Android / Linux / Windows:** `src/CMakeLists.txt` (C++17) builds one
  `glint_vorbis` shared library; the platform folders delegate to it.
- **macOS / iOS:** the podspecs compile the same sources via `Classes/`
  forwarders (C++17 + libc++).

## Tests

Native round-trip (render → encode → decode → assert), no Flutter needed:

```bash
cmake -B build -DGLINT_BUILD_TESTS=ON native/glint/src
cmake --build build -j8 && ctest --test-dir build --output-on-failure
```

It links the real `glint_vorbis` library and checks that a 440 Hz tone survives
Opus encode+decode with its **pitch** intact (never its sample rate — Opus
always decodes at 48 kHz), that hard-panned stereo neither collapses nor swaps,
that MP3/AAC streams carry valid MPEG/ADTS sync, that malformed input is
rejected rather than crashed on, and that 250 encode/free cycles don't grow RSS.

The Dart side: `test/audio_export_format_test.dart` (gating logic, headless) and
`integration_test/glint_encoder_test.dart` (the live symbol + round-trip against
a real app build).

## Verification status

CI does the per-platform work: **`.github/workflows/glint-native.yml`** builds
the library and runs the round-trip tests on Linux / macOS / Windows, then
builds a throwaway example app on all five platforms. That job is the authority
— it is the only place this code meets **MSVC** and **libstdc++**.

- ✅ Decode set compiles standalone and matches ffmpeg frame-for-frame; the
  `.sf3` oracle decodes FluidR3Mono.sf3 in tune (1.7–2.9¢). See `docs/ORACLE.md`.
- ✅ Encode set links and round-trips — 34 assertions, verified locally on
  **macOS** (full app build + live integration test) and on **Linux** (GCC 13 /
  libstdc++, whole suite green).
- ✅ **Android**: compiles for arm64-v8a / armeabi-v7a / x86_64 via the NDK,
  symbols exported, LOAD segments 16 KB-aligned.
- ✅ **iOS**: full `flutter build ios` succeeds; the bundled
  `glint_vorbis.framework` (arm64) exports `glint_encode_audio`, `glint_free`
  and `cometbeat_opus_file_decode`.
- ⚠️ **Windows**: the M_PI hazard below was found and fixed, and the fix was
  proven by reproducing MSVC's exact failure under a strict-ANSI cross-compile.
  A genuine MSVC build happens on CI — trust that run, not this line.

### Windows gotcha, if you touch the build

MSVC's `<cmath>` does **not** define `M_PI` unless `_USE_MATH_DEFINES` is set
before it is included, and five vendored files use `M_PI`. `src/CMakeLists.txt`
defines it for `WIN32`. It is fixed **there, not in the sources**, because
everything under `src/` except our three local files is a verbatim copy and
`sync_glint.sh` would overwrite any edit on the next re-vendor.

Re-vendor: `GLINT_DIR=~/code/glint ./sync_glint.sh`.
