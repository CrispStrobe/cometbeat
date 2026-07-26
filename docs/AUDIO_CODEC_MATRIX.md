# Audio codec matrix — what the app can read and write, per platform

One page, because the answer used to require reading four files and a link map.
Last verified 2026-07-26.

## Decode (import)

`importAudio()` in `lib/shared/music_io/audio_import.dart` detects by **magic
bytes, not extension**, so a mislabelled file still decodes.

| Format | Native | Web | Path |
| --- | :-: | :-: | --- |
| WAV | ✅ | ✅ | `readWavPcm16` — pure Dart |
| AIFF / AIFF-C | ✅ | ✅ | `readAiff` — pure Dart |
| MP3 | ✅ | ✅ | `mp3Decode` — pure Dart (our own port) |
| FLAC | ✅ | ✅ | glint (FFI / wasm) |
| Ogg-Vorbis | ✅ | ✅ | glint (FFI / wasm) |
| Ogg-Opus | ✅ | ✅ | glint (FFI / wasm) |
| AAC-LC (ADTS) | ✅ | ✅ | glint (FFI / wasm) |

## Encode (export)

| Format | Native | Web | Path |
| --- | :-: | :-: | --- |
| WAV | ✅ | ✅ | `pcmFloatToWav` — pure Dart |
| MP3 | ✅ | ✅ | `mp3Encode*` — pure Dart, CBR + VBR, mono/stereo/joint |
| AAC-LC | ✅ | ✅ | glint (FFI / wasm) |
| Ogg-Opus | ✅ | ✅ | glint (FFI / wasm) |
| FLAC | ❌ | ❌ | glint decodes FLAC but ships **no FLAC encoder** |

The export sheet only offers a format where its encoder actually resolved
(`availableAudioExportFormats`), so nothing pickable can fail at save time.

## How it hangs together

- **Native** — `native/glint`, a Flutter FFI plugin, vendored verbatim from the
  glint repo by `sync_glint.sh`. Reached through the `*_capability.dart` seams.
- **Web** — `web/glint`, the *same C code* built to wasm, reached through a JS
  shim (`globalThis.glintCodec`) instead of `dart:ffi`. The wasm loads lazily;
  `ensureGlintCodecReady()` must be awaited once before the sync entry points
  return anything, which both export sheets do for you.
- Everything degrades to **null**, never to an exception or a half-written file.

### The readiness rule (web only, but it bites hard)

The wasm is fetched **lazily**. Until it resolves, every glint-backed decoder
returns null on every call — so a FLAC / Ogg-Opus / AAC import fails looking
exactly like a corrupt file, and `.sf3` parses into silence.

So: **await readiness before decoding.** Prefer the async entry points, which do
it for you:

| Instead of | Use |
| --- | --- |
| `importAudio(bytes)` | `await importAudioAsync(bytes)` |
| `importAudioMono(bytes)` | `await importAudioMonoAsync(bytes)` |
| `loadSoundFont(bytes)` | `await loadSoundFontAsync(bytes)` |
| — | `await ensureAudioDecodersReady()` if you need the sync form |

Both export sheets already call `prepareNativeAudioEncoder()` before offering
formats — without it web would list Opus/AAC and then fail at save time.

The sync entry points are still correct where only pure-Dart codecs are
possible: `sample_extractor.dart` admits `.wav`/`.mp3` only, so it stays sync,
with a comment saying what would have to change if that filter widened.

`ensureGlintVorbisReady()` had existed for this exact reason since the `.sf3`
work and was **never called from anywhere** — which is why `.sf3` on web was
quietly broken too. Adding a readiness helper is not enough; something has to
await it.

## History worth keeping

Three asymmetries existed and are now closed. They're recorded because each was
invisible until someone went looking:

1. **`.opus` was write-only.** The export sheet could produce Opus, `ogg`/`oga`
   were in the picker's extension list, but `importAudio` only recognised
   Ogg-*Vorbis*. An Opus file passed the file dialog, missed every branch and
   returned null — indistinguishable from corruption. You could export a mix and
   not reopen it.
2. **AAC was write-only on native.** No AAC decoder was vendored. The wasm build
   had one all along, so the same file opened in the browser and not on desktop.
   Fixed by vendoring glint's `decode_audio_c_api.cpp` + the MP3/AAC decoders
   (+55 KB), which also retired a local `flac_c_api.cpp` fork.
3. **FLAC didn't import on web.** `flac_capability.dart` had an FFI branch and a
   null stub, and web fell into the stub — although the shipped wasm could
   already decode FLAC.

The root cause in all three: the wasm exported the **full** codec surface
(`_glint_encode_audio`, `_glint_decode_audio`) from the start, but only
`_glint_vorbis_decode` was ever wired through to Dart. We shipped the capability
and hid it.

## Tests

| What | Where |
| --- | --- |
| Native round trip, 3 codecs + leak/RSS | `native/glint/test/encode_roundtrip_test.cpp` (ctest) |
| Wasm round trip, same assertions | `web/glint/codec_roundtrip_test.mjs` (node) |
| Import routing + Ogg container detection | `test/audio_import_opus_test.dart` |
| Export format gating | `test/audio_export_format_test.dart` |
| Live, on a real build | `integration_test/glint_encoder_test.dart` |
| Web seams in a real browser | `test/web/audio_codec_web_test.dart` (`--platform chrome`) |

CI: `.github/workflows/glint-native.yml` runs the native tests on Linux/macOS/
Windows, the wasm test on node, and builds an example app on all five platforms.
`ci.yml`'s `android-build` asserts `libglint_vorbis.so` is actually inside the
APK.
