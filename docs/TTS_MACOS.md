# Neural TTS on macOS — bundling `libcrispasr`

> For the overall TTS design (engine framework, per-platform on-device voices,
> the model manager, and licensing) see **[TTS_ARCHITECTURE.md](TTS_ARCHITECTURE.md)**.
> This doc is just the macOS `libcrispasr` bundling detail.


The neural (CrispASR/Kokoro) narration voice needs the native `libcrispasr`
engine at runtime. `libcrispasr` is only ~9.6 MB, but it pulls in **8 more
dylibs** — the ggml runtimes (`libggml*.dylib` ×5) and the Homebrew audio codecs
(`libopusfile`, `libogg`, `libopus`) — several of which reference the maintainer's
Homebrew Cellar and CrispASR build tree by absolute path. So "bundling" means
collecting **9 self-contained dylibs**, not copying one file.

`tool/bundle_macos_tts.sh` does exactly that (a mini `dylibbundler` in
`install_name_tool` + `codesign`): it walks the dependency graph, copies each
non-system dep under the name it is *referenced* by, rewrites every id/dep to
`@rpath/<name>`, strips all foreign `LC_RPATH`s down to `@loader_path`, ad-hoc
signs them, and **statically verifies** the result is self-contained (no external
rpath, every `@rpath` dep present). Verified: synthesis runs through the bundled
set with only `@loader_path` on the rpath — i.e. it loads the bundle's ggml, not
the machine's.

## How the app finds the lib

`KokoroModelStore.libPath()` resolves in order (first hit wins):

1. `COMET_CRISPASR_LIB` env / constructor override — dev & tests;
2. **`<App>.app/Contents/Frameworks/libcrispasr.dylib`** — the release bundle
   (derived from `Platform.resolvedExecutable`);
3. **`~/.cache/crispasr/libcrispasr.dylib`** — a desktop/dev drop next to the
   downloaded models;
4. the `crispasr` package's default candidate (loader search path).

## Dev build (`flutter run macos`) — one command

```bash
# collects the 9 dylibs into ~/.cache/crispasr (default target)
tool/bundle_macos_tts.sh
```

Now `flutter run macos` finds the lib via cascade step 3, the **Settings →
"Natural voice (HD)"** tile appears, and tapping it downloads the ~135 MB Kokoro
model (CrispASR registry) — after which narration uses the neural voice. Nothing
in the Xcode project changes.

## Release `.app` — embed in Frameworks

1. Stage the self-contained set: `tool/bundle_macos_tts.sh <src> build/tts-libs`.
2. Add a **Copy Files** build phase to the `Runner` target (Destination:
   *Frameworks*, "Code Sign On Copy") that copies `build/tts-libs/*.dylib` into
   `Contents/Frameworks/` — or a Podfile `post_install` hook doing the same.
   (Kept out of the shared `macos/` project here so parallel agents' builds aren't
   disturbed — apply it in the release worktree.)
3. Re-sign the app with your Developer ID; the ad-hoc signatures from the script
   are placeholders. `Contents/Frameworks` is already on the app's `@rpath`, so
   `@rpath/libcrispasr.dylib` (cascade step 2) resolves.

## ⚠ App Store considerations

- **Executable code must ship inside the signed bundle** — the model download is
  data (fine), but the dylibs must be embedded + signed, never fetched at runtime.
  The dev `~/.cache` path is for direct-distribution / development only.
- The set includes GPL-clear, Apache-2.0 (ggml, Kokoro) and BSD (opus/ogg)
  components — confirm each license is listed in the About page before shipping.
- Consider a **CPU-only** libcrispasr build to drop `libggml-metal` if the Metal
  path isn't needed, shrinking the payload.

## iOS / Android / Web

- **iOS**: same idea but an `.xcframework` (the `crispasr` package already lists
  `crispasr.framework/crispasr` as a candidate); build libcrispasr for
  `ios-arm64`, wrap + embed. On-device build required.
- **Android**: `.so` per ABI (`arm64-v8a`, `x86_64`) under `jniLibs`; NDK build.
- **Web**: web's on-device voice is the browser **Web Speech API
  (`SpeechSynthesis`)** via `flutter_tts` (verified live in the build) — instant,
  free, no download. HD on web = **pre-baked WAV narration** + the model
  manager's fetch/IndexedDB downloader. Live neural via `crispasr.wasm` was built
  and measured at **~10× real-time (NO-GO)** — details in
  [TTS_ARCHITECTURE.md](TTS_ARCHITECTURE.md) §"Web live-neural".

Until a platform ships its lib, that platform silently falls back to
`flutter_tts` (its on-device voice) and the HD-voice tile stays hidden.
