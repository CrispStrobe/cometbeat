# Handover: vendor glint's ENCODER into the app (Opus / AAC export)

**Status:** unclaimed. The Dart half is done and on `main`; the native half is
not. Sibling of `docs/GLINT_VORBIS_HANDOVER.md` (the decode-side handover), and
that document is the model for how this integration works — read it first.

---

## The one-sentence version

`glint` has a working audio **encoder** (MP3 / AAC-LC / **Ogg-Opus**), and
`glint.h` — which we already vendor — declares it. But `native/glint/sync_glint.sh`
vendors *only the Ogg-Vorbis DECODE sources*, so the compiled plugin does not
contain the encoder symbols. Your job is to vendor the encode closure, wire it
into the plugin build on all five platforms, and turn on the Opus/AAC options in
the export UI.

## Why this is worth doing

WAV is huge and MP3 is the only compressed option the app can currently write.
Opus at ~96 kbps is transparent for music at a fraction of MP3's size and is the
right default for sharing a mix from a phone. The encoder already exists and is
MIT — this is an integration task, not a DSP task.

---

## What is ALREADY DONE (don't redo it)

On `main`, all Dart-side, all safe with no native support present:

| File | What it is |
| --- | --- |
| `lib/core/audio/sf2/encoded_audio.dart` | `EncodedAudioFormat {mp3, aac, opus}`, `EncodeAudio` typedef, extensions for file extension + label. **dart:ffi-free**, so web and the export layer can name the types. |
| `lib/core/audio/sf2/opus_glint_ffi.dart` | `GlintEncoder` — the `dart:ffi` binding to `glint_encode_audio` + `glint_free`. Copies out of native memory before freeing. |
| `lib/core/audio/sf2/encode_capability.dart` | Conditional-export seam: `_stub` unless `dart.library.ffi`. |
| `lib/core/audio/sf2/encode_capability_ffi.dart` | `loadGlintEncoder()` — explicit path → `DynamicLibrary.process()` → per-platform bundled library names. **Returns `null` if the symbol doesn't resolve**, which is exactly today's behaviour. |
| `lib/core/audio/sf2/encode_capability_stub.dart` | Web/no-ffi: returns `null`. |

So today `loadGlintEncoder()` returns `null` on every platform, and the export
UI simply doesn't offer Opus. Nothing crashes and nothing half-writes a file.
**Once the symbol exists, the binding should light up with no Dart changes.**

## What is NOT done — your task

### 1. Vendor the encode sources

`native/glint/sync_glint.sh` says, in its own header comment, that it vendors the
"MINIMAL glint Ogg-Vorbis DECODE source set". Extend it.

- **Source of truth:** the glint repo, MIT. `GLINT_DIR`, default `~/code/glint`
  (present on the maintainer's machine; was at `39f1feb` when this was written).
- **Entry point:** `src/encode_audio_c_api.cpp` defines `glint_encode_audio`.
  Its own includes are trivial (`glint/glint.h`, `resample.hpp` — we already
  vendor `resample.cpp`), **but it dispatches to all three codecs' C APIs**, so
  the link closure is much bigger than its include list suggests.
- **Opus encode closure** (~15–20 files): `opus_c_api.cpp`,
  `opus_celt_encoder.cpp`, `opus_celt_enc_bands.cpp`, `opus_celt_enc_energy.cpp`,
  `opus_celt_enc_vq.cpp`, `opus_celt_bands.cpp`, `opus_celt_energy.cpp`,
  `opus_celt_pitch.cpp`, `opus_celt_rate.cpp`, `opus_ec.cpp`, `opus_mdct.cpp`,
  `opus_cwrs.cpp`, `opus_laplace.cpp`, `opus_analysis.cpp`, `opus_ogg.cpp`
  (already vendored) + their `.hpp`s and `*_tables.hpp`. **Verify this list
  against the actual link errors** — treat it as a starting point, not gospel.

### 2. Decide what to do about MP3 and AAC

`glint_encode_audio` takes a format selector and will reference the MP3 and AAC
encoders whether or not you want them. Two options:

- **(a) Opus only** — add a small local shim (like the existing
  `glint_free_shim.cpp`) providing the MP3/AAC entry points as failures, and
  have `EncodedAudioFormat` expose only `opus` on this platform. Smallest
  binary, least risk. **Recommended for the first pass.**
- **(b) All three** — vendor the AAC and MP3 encoders too. More useful (AAC is
  the better choice for Apple targets) but a much bigger closure and binary.

Either way, keep the Dart `EncodedAudioFormat` enum as-is and just gate which
values the UI offers on what the loaded encoder actually supports.

### 3. `glint_free`

⚠️ We currently ship `glint_free_shim.cpp` — a 2-line stand-in — because, per
`sync_glint.sh`'s comment, "glint_free's real def is entangled with the AAC/MP3
decoder". The encoder returns a **malloc'd buffer that must be freed with
`glint_free`**. Check that the shim's `free()` matches the allocator the encoder
actually used; if the encoder allocates differently, mismatched free is a heap
corruption bug that will not show up in a smoke test. Resolve this deliberately.

### 4. Build wiring

`native/glint/CMakeLists.txt` + the Apple podspec forwarders (macos/ios
`Classes/`), following exactly what was done for the FLAC decoder — see the
auto-memory note on the FLAC/glint work, and mirror `flac_c_api.cpp`'s pattern.
Platforms: **macOS · iOS · Android · Linux · Windows**.

### 5. Turn it on in the UI

`lib/shared/music_io/audio_export.dart` — `AudioExportFormat` is currently
`{wav, mp3}` (both pure Dart). Add the native formats **conditionally**: call
`loadGlintEncoder()` once, and only offer Opus/AAC when it's non-null, so web
and any platform without the library keep today's behaviour. The batch stems
path (`showAudioStemsExportSheet`) shares the same `AudioExportFormat`, so it
gets the new formats for free.

---

## How to verify (don't skip this)

The app's convention is render → decode → assert, not "it compiled".

1. **Symbol resolves:** a test that `loadGlintEncoder()` is non-null on macOS.
   (It must stay null in headless `flutter test` — the plugin isn't linked
   there — so this needs an `integration_test`, like
   `integration_test/gapless_loop_player_test.dart`.)
2. **Round-trip:** encode a known signal (e.g. `dart run bin/dawedit.dart
   --generate sine:440:2 tone.wav`) to Opus, then decode it back and assert the
   pitch survives — `dart run bin/listen.dart --wav <decoded>` should read
   **A4 440.0 Hz**. Opus resamples to 48 kHz internally, so assert the pitch,
   not the sample rate.
3. **Stereo:** encode a hard-panned stereo pair and check the channels didn't
   collapse or swap.
4. **No leak / no corruption:** encode in a loop (a few hundred times) and watch
   RSS. This is where a wrong `glint_free` shows up.
5. `flutter analyze` clean; the DAW suites green (`test/daw_*`).

## Gotchas specific to this repo

- **Apple builds on this machine need the env wrapper**:
  `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter build macos --debug`.
  See `CLAUDE.md`; without it CocoaPods is skipped and you'll debug a phantom.
- **Disk is tight** — never run parallel platform builds.
- **FLAC export is NOT part of this.** glint has `glint_flac_decode` and **no
  FLAC encoder**. Adding FLAC export means writing or sourcing an encoder; it is
  a separate, larger job. Don't let it creep in here.
- **Don't reorder `EncodedAudioFormat`** — nothing persists it today, but the
  export UI and any future project field would both be happier if new values are
  appended.

## Done means

- `loadGlintEncoder()` returns a working encoder on macOS/iOS/Android/Linux/Windows.
- The export sheet offers Opus (and AAC if you took option b) **only where it
  works**, with web unchanged.
- The round-trip test above passes: a 440 Hz tone survives encode → decode.
- `docs/PLAN.md`'s "⚠️ Opus export" section is updated from *scoped* to *shipped*,
  and this file is deleted or marked done.
