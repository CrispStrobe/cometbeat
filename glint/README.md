# glint wasm — the web half of the codec seam

The MIT [glint](https://github.com/CrispStrobe/glint) codec suite, emscripten-built,
so the **web** target runs the same C code the native `native/glint` FFI plugin
compiles. One module serves both halves:

- **Decode** — MP3, AAC-LC, Ogg-Opus, Ogg-Vorbis, FLAC (auto-detected from the
  header), plus the dedicated Vorbis entry point for compressed `.sf3` SoundFonts.
- **Encode** — MP3, AAC-LC, Ogg-Opus.

Full per-platform table: [`../../docs/AUDIO_CODEC_MATRIX.md`](../../docs/AUDIO_CODEC_MATRIX.md).

> The wasm exported `_glint_encode_audio` and `_glint_decode_audio` from the day
> it was built, but only `_glint_vorbis_decode` was wired through to Dart — so
> the bundle shipped a full codec suite and reached about a sixth of it. That is
> what `glint_codec_web.js` fixed, and it added **no** download, because it
> reuses the module the Vorbis shim already loads.

## Files

| File | What |
| --- | --- |
| `glint.wasm` / `glint.mjs` | the emscripten module (built in glint's `bindings/wasm`; re-copy after a glint wasm rebuild) |
| `glint_codec.mjs` | glint's high-level ASYNC API (`decodeVorbis`, `decodeAudio`, `encodeAudio`) + the module cache |
| `glint_vorbis_web.js` | SYNC Vorbis decode shim — fits `Sf2SoundFont.parse`'s sync `VorbisDecode` |
| `glint_codec_web.js` | SYNC encode + whole-file decode shim — fits Dart's sync `EncodeAudio` / decode typedefs |
| `bootstrap.js` | loaded by `web/index.html`; exposes `globalThis.glintVorbis` and `globalThis.glintCodec` |
| `codec_roundtrip_test.mjs` | render → encode → decode → assert, under node |

Dart side: `lib/core/audio/sf2/vorbis_capability_web.dart`,
`encode_capability_web.dart`, `flac_capability_web.dart` — all chosen by
conditional export, so native never falls into the web path.

## The async/sync split, and the rule that follows from it

Loading is async; **calls are synchronous once the module is instantiated**.
That is the whole reason these shims exist — Dart's decode/encode typedefs are
sync, and making the entire export path async to accommodate a one-time fetch
would be the tail wagging the dog.

The consequence is a rule you cannot skip:

> **Await readiness before decoding or encoding.** Until the wasm resolves every
> entry point returns null — so a FLAC/Opus/AAC import fails looking exactly like
> a corrupt file, and a `.sf3` parses into silence.

Use the async wrappers, which do it for you: `importAudioAsync`,
`importAudioMonoAsync`, `loadSoundFontAsync`, `prepareNativeAudioEncoder`.
`ensureAudioDecodersReady()` is there if you genuinely need the sync form.

This is not hypothetical. `ensureGlintVorbisReady()` existed from the `.sf3`
work and was **never called from anywhere**, which quietly broke compressed
SoundFonts on web. Adding a readiness helper is not the same as calling it.

## Memory

Every call frees its wasm-side buffers, and returned typed arrays are `.slice()`
copies — nothing points into `HEAPU8`/`HEAPF32` after a call returns. That
matters because **a wasm heap can be detached and replaced by a grow**, which
turns a retained view into garbage or a throw. `codec_roundtrip_test.mjs` runs
100 encode/decode cycles specifically to shake that out.

## Tests

```bash
node web/glint/codec_roundtrip_test.mjs          # the shim, under node
flutter test test/web --platform chrome          # the Dart seams, in a browser
```

The node suite covers the **working** path (28 assertions: a 440 Hz tone
survives every codec by pitch, hard-panned stereo neither collapses nor swaps,
malformed input is declined rather than crashed on). The Chrome suite covers the
**degradation** path — no `bootstrap.js` on the page, so every seam must hand
back null instead of throwing an interop error.

Both run in CI: `.github/workflows/glint-native.yml` (`web-codec` job) and
`ci.yml`.

Loaded lazily, so there is no startup cost until audio is actually imported or
exported, or a `.sf3` is opened.
