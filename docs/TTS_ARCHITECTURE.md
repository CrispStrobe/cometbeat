# TTS architecture — the read-aloud / narration voice

CometBeat speaks lesson text through a small **engine framework** that mirrors the
transcription `Backend` framework: several interchangeable TTS paths, resolved to
a sensible default per platform, with the on-device platform voice as the
guaranteed floor so the app *always* speaks.

Two layers:

- **(A) On-device platform speech — the floor, everywhere.** The `flutter_tts`
  plugin wraps each OS's built-in synthesizer: Apple `AVSpeechSynthesizer`,
  Android `TextToSpeech`, and the browser **Web Speech API (`SpeechSynthesis`)**.
  All on-device, offline-capable, free, zero download, instant. On modern
  Apple/Android these are already *neural-quality* voices (Apple "enhanced"/
  "premium"/Siri voices, Google on-device neural) when the user has them
  installed. This layer never needs a network and never blocks.
- **(B) HD neural — an optional, higher-consistency timbre where it can run.**
  Kokoro (CrispASR/GGUF) or Piper (VITS/ONNX), giving the *same* warm voice
  across platforms. Needs a model download and a native runtime; falls back to
  (A) whenever it can't run.

## The engine enum + resolver

`lib/core/audio/tts/tts_engine.dart`:

```
TtsEngine { auto, platform, prebaked, crispasrFfi, onnxFfi, pureDartOnnx, crispasrWasm }
resolveTtsEngines({ required bool isWeb, required Set<TtsEngine> available, TtsEngine preferred = auto })
```

`TtsService._pick` routes through the resolver; `Settings → Voice engine` exposes
`preferred` (Automatic / Natural HD / Device voice). `platform` is always the last
entry — the floor.

- **Native auto order:** `crispasrFfi` → `onnxFfi` → `pureDartOnnx` → `platform`.
- **Web auto order:** `crispasrWasm` → `platform`. `pureDartOnnx` is excluded live
  on web (single-threaded synthesis freezes the main isolate); FFI engines are
  excluded on web entirely.

## Per-platform picture

| Platform | On-device platform voice (floor, layer A) | HD neural (layer B) | Sensible default |
|---|---|---|---|
| **macOS** | `AVSpeechSynthesizer` (enhanced voices downloadable in System Settings) | `crispasrFfi` Kokoro (bundled dylib — see [TTS_MACOS.md](TTS_MACOS.md)); or `onnxFfi` Piper | HD if the lib+model are present, else platform |
| **iOS** | `AVSpeechSynthesizer` | `crispasrFfi` (`.xcframework`) / `onnxFfi` — on-device build required, not wired yet | platform until the lib ships |
| **Android** | `TextToSpeech` (Google/OEM on-device engine) | `crispasrFfi` (`.so` per ABI) / `onnxFfi` — NDK build, not wired yet | platform until the lib ships |
| **Web** | **`SpeechSynthesis`** (Web Speech API — on-device, instant, free) ✅ *verified live in the build* | **pre-baked WAV narration** (fixed strings, RTF ~0) + the model manager's fetch/IndexedDB downloader. Live neural via `crispasr.wasm` = **NO-GO** (measured ~10× real-time, see below) | platform for arbitrary text; pre-baked WAV for the fixed lesson strings |

The on-device platform voice is reached through the resolver's `platform` floor on
**every** platform including web — confirmed: `web_plugin_registrant.dart`
registers `FlutterTtsPlugin` and `build/web/main.dart.js` contains
`SpeechSynthesis`. So web is never voiceless; the HD layer only adds a consistent
neural timbre on top.

## Model / asset management (unified)

`lib/core/audio/tts/tts_model_manager.dart` + `tts_asset_cache.dart` (facade /
`_io` file cache / `_web` IndexedDB) + `tts_asset_catalog.dart`. One API —
`ensure` / `ensureGroup` / `isCached` / `remove` / `report` — over a
cross-platform `http` fetch and a per-platform cache (files native, IndexedDB on
web via `package:web`). Cache keys are `models/`-rooted paths that match
`PiperVoiceStore` exactly, so a download transparently feeds native synthesis.
Surfaced in **Settings → Voice models**.

- Catalog = **CC0 Piper voices only** (kathleen/thorsten). No NC / CC-BY-SA /
  espeak. Kokoro is *not* in the catalog — it downloads through CrispASR's own
  model registry (no hand-rolled URLs).
- Kokoro-82M ≈ 135 MB (GGUF); Piper `low` voices ≈ 63 MB each. The platform
  voices need **no** download.

## Licensing (clean-room / MIT-shippable)

- CMUdict (public domain) + OLaPh (MIT) for G2P; Kokoro-82M (Apache-2.0); Piper
  VITS code (MIT) with CC0 voices (kathleen, thorsten). **espeak (GPL) is used
  only as a convention target + offline test oracle — never linked/shipped.**
- CC-BY / CC-BY-SA / NC voices are excluded from the shipped catalog.

## Web live-neural (`crispasr.wasm`) — evaluated, NO-GO (measured 2026-07-27)

Built the Kokoro `crispasr.wasm` (single-thread **and** the recommended
multithreaded `--proxy-to-pthread`, SIMD on) and measured RTF in real headless
Chrome (8 cores, `crossOriginIsolated: true`, af_heart, a 5.47 s utterance):

- single-thread SIMD: 53.33 s → **RTF 9.75×**
- multithreaded, 4 threads: 51.51 s → **RTF 9.42×** (pthreads gave no speedup)

~10× real-time is unusable for live narration. Structural blockers on top:
multithread needs COOP/COEP → GitHub Pages needs a `coi-serviceworker` that would
collide with Flutter's own PWA service worker; plus the 135 MB first-run download.
So we did **not** build the JS-interop seam. The web HD path stays **pre-baked WAV
+ the model manager's downloader** — which already serves the real (fixed-string)
narration use case instantly. The `crispasrWasm` engine slot + resolver hook
remain as a latent path if a much smaller/faster model or a non-Pages host ever
changes the math. Full method/evidence: auto-memory `crispasr-wasm-tts-rtf-nogo`.

## Shipped follow-ups

- **✅ OS voice picker.** Settings → *Narration voice* enumerates the on-device
  voices (`flutter_tts.getVoices`) for the current language and lets the user pick
  one — no download, often higher quality than our HD layer on Apple/Android.
  `TtsVoiceOption` + `PlatformVoiceControl` in `tts_service.dart`; the choice is
  persisted per language (SharedPreferences) and applied via `setVoice` before
  each utterance. The tile shows only when the OS offers ≥2 voices. (The gap-1
  engine preference now persists too.)
- **✅ Narration packs on web (pack mode).** `PrebakedNarrationBackend` can serve
  narration WAVs from the asset cache (IndexedDB on web, files native) instead of
  bundling ~40 MB of audio: construct it with a `cache` + `remoteBase`, call
  `prefetch(...)` to warm the cache from a hosted pack, and clips then play from
  IndexedDB. Fully opt-in — with no `cache` it is unchanged BUNDLED MODE.
  *Operational step still pending:* host a narration pack (baked WAVs on a
  CORS-enabled URL) + a manifest, then wire `remoteBase` + a `prefetch` call.

## iOS / Android HD wiring — handover (build + embed, on-device verify)

Native HD (`crispasrFfi` Kokoro) is macOS-only today; iOS/Android need the
`libcrispasr` engine embedded. **No Dart change is required** —
`CrispASR.defaultLibName()` already probes `libcrispasr.so` (Android) and
`crispasr.framework/crispasr` / `libcrispasr.dylib` (iOS), so once the lib is
where the loader searches, `neuralSupported()` returns true and the HD tile
appears automatically. What remains is a native build + embed, kept OUT of the
shared `ios/`/`android/` projects (parallel agents build them — do it in a
release worktree), and verified on a device/emulator (not possible headlessly):

- **iOS** — a prebuilt `crispasr.xcframework` already exists at
  `../CrisperWeaver/ios/Frameworks/crispasr.xcframework` (reference), or rebuild
  with `../CrispASR/build-xcframework.sh` (`BUILD_SHARED_LIBS=OFF`,
  `GGML_METAL=ON`, iOS min 16.4). Add it to the Runner target (Embed & Sign);
  the framework's `crispasr` binary is on the loader path → cascade resolves it.
- **Android** — cross-compile per ABI with `../CrispASR/build-android.sh` (NDK
  present: 26.3 / 28.2; use `-DBUILD_SHARED_LIBS=OFF` to avoid a `libggml.so`
  clash). Drop the result at
  `android/app/src/main/jniLibs/<abi>/libcrispasr.so` (`arm64-v8a`, `x86_64`);
  the system loader finds it by name.
- **Model** — the ~135 MB Kokoro GGUF still downloads via CrispASR's registry
  (the HD-voice tile opt-in), same as macOS. On the App Store, executable code
  must ship signed inside the bundle (data downloads are fine).
