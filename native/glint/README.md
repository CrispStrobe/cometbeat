# glint_vorbis — native glint codecs (Flutter FFI plugin)

Compiles source sets from the MIT [glint](https://github.com/CrispStrobe) codec
suite into the CometBeat app. Two halves:

- **Decode** — Ogg-Vorbis (compressed **`.sf3` SoundFonts**) and FLAC (SFZ
  samples, e.g. VCSL / VSCO2). C ABI: `glint_vorbis_decode`,
  `glint_flac_decode`.
- **Encode** — `glint_encode_audio`: interleaved float PCM at any rate →
  **MP3 / AAC-LC / Ogg-Opus**, auto-resampling to a rate the codec allows
  (Opus → 48 kHz). This is what audio export uses.

Buffers from both halves are released with `glint_free`.

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

Two files are **local, not vendored**: `flac_c_api.cpp` (a minimal wrapper
mirroring glint's `vorbis_c_api.cpp`) and `opus_file_c_api.cpp`
(`cometbeat_opus_file_decode` — Ogg-Opus → PCM glue, so the encode round-trip is
testable end to end). Plus `glint_free_shim.cpp`: glint's real `glint_free`
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

- ✅ Decode set compiles standalone and matches ffmpeg frame-for-frame; the
  `.sf3` oracle decodes FluidR3Mono.sf3 in tune (1.7–2.9¢). See `docs/ORACLE.md`.
- ✅ Encode set links and round-trips (the native test above, 34 assertions).
- ✅ The `Classes/` forwarders compile with the exact podspec flags (c++17,
  libc++).
- ⏳ A full per-platform `flutter build` (iOS/Android/Windows/Linux) is the final
  confirmation — verify on CI before relying on a given platform, as with
  `native/aec`. macOS is verified locally.

Re-vendor: `GLINT_DIR=~/code/glint ./sync_glint.sh`.
