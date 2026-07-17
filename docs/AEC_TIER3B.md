# AEC Tier 3b — native full-duplex echo cancellation (design)

Status: **milestone (a) shipped** (was: design / not started). Tiers 0
(headphones) + 1 (platform `echoCancel`) shipped; Tier 3a (pure-Dart
`echo_canceller.dart`) is a verified linear canceller that starves in-app on
alignment. This doc is the plan for the real fix.

### Progress — 2026-07-13
The standalone plugin package lives at **`native/aec/`** (its own pubspec,
deliberately **NOT** a dependency of the app, so CI never compiles or analyzes
it — see CI safety below). Milestone (a) is done and verified on this Mac:
- **`src/aec_dsp.c`** — the AEC core, a line-for-line **cleanroom C port of
  `lib/core/audio/echo_canceller.dart`** + the FFT from `chroma_analysis.dart`.
- **`src/aec_shim.c` + `src/miniaudio_impl.c`** — the miniaudio full-duplex host
  (aligned mic/reference on one clock) feeding lock-free SPSC rings.
- **`lib/aec_dsp.dart` / `lib/aec_engine.dart`** — hand-written `dart:ffi`
  bindings; `NativeAecEngine` implements the `AecEngine` API below.
- **`test/aec_erle_test.dart`** — offline **ERLE cross-check** over FFI, the C
  twin of `test/echo_canceller_test.dart` (same IR/seeds/thresholds → proves the
  port has no algorithmic drift). Both libs build on macOS; all tests green.

**Licensing decision (MIT-clean):** the original stack below recommended
SpeexDSP (BSD-3). To keep the tree MIT we instead **cleanroom-ported our own
AEC** (already ours, already ERLE-tested) and kept only **miniaudio (MIT-0)** as
the duplex host. SpeexDSP stays an *optional* future component behind a build
flag if residual/nonlinear performance ever demands it — a separate, explicit
licensing call, not baked in.

**Milestone (b) also done — tested on real device audio (2026-07-13):**
- **Headless engine unit test** (`test/aec_engine_test.dart`): drives the
  `aec_engine_*` int16 ring/framing/conversion path via a test pump (no device)
  — ERLE + near-end + raw-tap round-trip all green.
- **Live check** (`tool/live_check.dart`, outside `test/` so CI never opens a
  device): (1) null-backend duplex **lifecycle** — the realtime callback fires,
  frames flow; (2) **BlackHole 2ch loopback** (system default untouched) — plays
  a white-noise reference and cancels its loopback echo at **≈44 dB ERLE** (raw
  RMS ~2079 → cleaned RMS ~13). Real device audio, self-driven, no human/mic.
- Key: a short device **period** (`setPeriod(256)`) decoupled from a longer AEC
  **block** (`frame: 4096`) — the standard short-hop / long-filter arrangement,
  so the acoustic round-trip delay stays inside the filter tail.

**Milestone (c) done — app-side AEC seam:** `lib/core/audio/aec_engine.dart` is
an app-owned abstract `AecEngine`; `MicrophonePitchService` takes an optional
one and, when present, analyses its echo-cancelled `cleaned` stream instead of
the raw `record` mic (recorder is now lazy so AEC mode is headless), with a
`pushReference()` for the backing PCM. The app never imports the native package,
so CI stays green with no native code. Fake-driven test:
`test/microphone_aec_seam_test.dart`.

**Milestone (d) done — Flutter FFI plugin for all 5 platforms:** `native/aec` is
now a real Flutter FFI plugin (`pubspec` `ffiPlugin: true` ×5; `src/CMakeLists.txt`
for Android/Linux/Windows; podspecs + `Classes/` forwarders for macOS/iOS;
android gradle). Portability hardening: the SPSC rings use miniaudio's
`ma_pcm_rb` instead of hand-rolled C11 atomics (MSVC has no `<stdatomic.h>`), and
`CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS` exports the FFI symbols on MSVC. Verified by
the isolated **`aec-native` CI** (paths-filtered, never touches the app):
`lib-and-tests` (build + offline ERLE/engine tests) green on **ubuntu + macOS +
windows**, and `example-build` (a throwaway app depending on the plugin, built
with `flutter build`) green on linux/macOS/windows. The macOS example app was
also built locally.

**Final wiring done — plugin in the app behind a web-safe capability check:**
the `aec-native` CI now builds an example app on **all five** platforms
(desktop trio + `flutter build ios --no-codesign` + `flutter build apk`); iOS
needed the miniaudio implementation TU compiled as **Objective-C** (`.m`,
AVAudioSession), macOS stays `.c`. With that green, `native/aec` is a path
dependency of the app, reached only through
`lib/core/audio/aec_capability.dart`:

```dart
export 'aec_capability_stub.dart' if (dart.library.ffi) 'aec_capability_ffi.dart';
AecEngine? createNativeAecEngine(); // native adapter, or null on web
```

The conditional export keeps **`dart:ffi` out of the web build** (a stub returns
null there), so `flutter build web` (the deploy path) is unaffected; on native
platforms it returns a `NativeAecEngine`→app-`AecEngine` adapter. Constructing it
does not load the native library (that's lazy, on `start()`), so app startup and
tests never touch it. Tests: `test/aec_capability_test.dart`. The play-along
screen can now opt in via `MicrophonePitchService(aec: createNativeAecEngine())`
when speaker-backing is on.

Remaining: **(e) on-device tuning** — exercise the real duplex path on iOS/Android
hardware (mic permission, session category, latency) and, only if real-room
residual echo proves too strong for the linear core, add a double-talk detector /
residual suppression or swap in SpeexDSP (BSD-3) behind a build flag.
See `native/aec/README.md`.

## Why a native plugin is required

The blocker is **alignment**, not the algorithm. In Flutter, `audioplayers`
(output) and `record` (input) are separate plugins on separate clocks — no
shared timebase, tens of ms of drift. A real AEC needs the reference (what was
played) and the mic aligned to ~a sample. Only a **single native audio engine
that owns both playback and capture** can provide that. So Tier 3b = one plugin
that:
1. Opens a full-duplex stream (mic in + speaker out on one clock).
2. Runs a battle-tested AEC (delay tracking + double-talk detector + residual
   suppression) — the parts Tier 3a lacks.
3. Emits the cleaned near-end PCM to Dart, where the existing
   `StreamingAudioAnalyzer` / `PitchDetector` consume it unchanged.

## Recommended stack (all BSD/MIT/Apache)

- **Full-duplex host: [miniaudio](https://miniaud.io)** (single-header, MIT-0 /
  public-domain). One `ma_device` in **duplex** mode gives synchronized
  `(input, output)` callbacks on all five targets — the shared clock we need.
  Alternative: Oboe (Android, Apache) + AVAudioEngine (Apple) natively, but
  miniaudio is one codebase for all platforms.
- **AEC: [SpeexDSP](https://github.com/xiph/speexdsp) `speex_echo`** (BSD-3).
  ~1k lines of portable C (MDF frequency-domain adaptive filter + DTD),
  self-contained (bundles its own FFT). Smaller and simpler to vendor than
  WebRTC AEC3 (also BSD, but large C++). Start with Speex; swap to WebRTC AEC3
  only if residual/nonlinear performance demands it.

## Architecture

```
                       ┌──────────────── native plugin (C, via FFI) ───────────────┐
 speaker  ◀── ma_device(duplex) ──▶  mic
   ▲            │  output cb: pull the app's reference frame (ring buffer)         │
   │            │  input  cb: mic frame                                            │
 backing        │  → speex_echo_cancellation(mic, reference) → cleaned near-end    │
 (synth) ───────┼──────────────────────────────────────────────────┐             │
                └───────────────────────────────────────────────────┼─────────────┘
                                                                     ▼
 Dart:  AecEngine.reference(pcm)  →  ring buffer          AecEngine.cleaned : Stream<Uint8List>
                                                                     ▼
                                            StreamingAudioAnalyzer → PitchReading (unchanged)
```

Key contract: the app **hands the plugin the reference it is about to play**
(the same synth PCM the backing uses), the plugin plays it AND uses it as the
AEC reference, and returns the cleaned mic. That closes the loop with perfect
digital reference + a shared hardware clock.

## Dart API (the plugin's surface)

```dart
abstract class AecEngine {
  Future<void> start({int sampleRate = 44100, int frame = 256});
  /// Queue reference PCM16 to be played AND cancelled.
  void reference(Uint8List pcm16);
  /// Cleaned near-end (mic minus echo), frame by frame.
  Stream<Uint8List> get cleaned;
  Future<void> stop();
}
```
`MicrophonePitchService` would gain an optional `AecEngine`: when present and
backing is on, feed the backing PCM to `reference()` and analyze `cleaned`
instead of the raw `record` stream. Everything above stays identical.

## Build (per platform, the fiddly part)

- **FFI bindings** via `ffigen` over a tiny C shim (`aec_open/reference/read/
  close`) that wraps miniaudio + speex. Vendor `miniaudio.h` + the ~15 speexdsp
  echo files under `native/`.
- macOS/iOS: CocoaPods `.podspec` compiling the C (respect the GEM-env wrapper,
  see CLAUDE.md). Android: `CMakeLists.txt` + Gradle externalNativeBuild.
  Linux/Windows: CMake. This is the bulk of the work and the CI risk.

## CI safety (mandatory — multi-agent, Linux CI)

Native compilation must not red the shared CI. Do the whole build **in an
isolated branch/worktree**, keep the plugin **out of the app's `pubspec.yaml`**
until it compiles green on every CI platform, and only then wire it in behind a
runtime capability check (fall back to Tier 0/1 when absent). Never land
half-built native code on `origin/main`.

## Verification plan

1. **Unit (host, offline):** feed the C AEC a digitally-aligned mic+reference
   mix; assert ERLE, mirroring `test/echo_canceller_test.dart` (the C output
   should match the Dart core within tolerance — a nice cross-check).
2. **Loopback (this Mac):** the BlackHole rig — play a reference through the
   plugin while it captures, confirm cancellation on real device audio.
3. **On-device (human):** speaker backing during play-along without headphones;
   confirm pitch scoring still tracks the user, not the speaker.

### `bin/aec.dart` — the streaming/pipe AEC harness (headless, no device/FFI)

Test the cancellation algorithm itself (the pure-Dart `EchoCanceller` the native
core is a cleanroom port of) over files or live pipes, via
`lib/core/audio/aec_offline.dart`. No plugin build required.

```bash
# Self-test: synth a "band" + "instrument" + room echo, cancel, prove the
# instrument survives (reads A4, not the band) and the echo-only ERLE is high.
dart run bin/aec.dart --selftest --detect        # → PASS (tail ERLE ≈ 48 dB)

# Files: a captured mic recording + the reference that was played.
dart run bin/aec.dart --mic captured.wav --ref played.wav --out clean.wav --detect

# Live pipe — interleaved STEREO PCM16 in (ch0 = mic, ch1 = reference),
# cleaned MONO PCM16 out; chain into the detector to see what survived:
<stereo-pcm16-source> | dart run bin/aec.dart --stdin | dart run bin/listen.dart --stdin
<stereo-pcm16-source> | dart run bin/aec.dart --stdin --detect     # notes to stdout
```

Build the stereo `(mic|ref)` stream with `sox -M` (or `ffmpeg`), e.g. mic =
default device, ref = the groove WAV — the offline analogue of the BlackHole
rig, and the one you can run in CI. `estimateEchoDelay` aligns files by
cross-correlation; the streaming path takes a fixed `--delay` (default 0, for a
pre-aligned full-duplex/loopback capture). `bin/listen.dart --aec` shares the
same core (whole-file only). Tested: `test/aec_offline_test.dart`.

### Quality metrics (patent-free by design)

`aec_offline.dart` reports objective metrics that are all **freely usable / not
patent-encumbered** — a deliberate choice for this MIT-clean tree:

- **ERLE** and **segmental ERLE** (mean of per-frame ERLE) — standard echo-
  suppression measures. Valid only for **far-end single-talk** (echo only).
- **Convergence time** — first offset the segmental ERLE crosses a target (the
  adaptive filter settling; a good linear AEC is tens of ms on a broadband ref).
- **SI-SDR** (scale-invariant signal-to-distortion, Le Roux et al. 2019) — the
  gain-invariant fidelity metric from source separation. Under **double-talk**
  ERLE is misleading (preserving the near-end keeps residual energy up), so we
  report SI-SDR of the cleaned output vs the *true* near-end instead.

**Deliberately NOT used:** **PESQ** (ITU-T P.862) and **POLQA** — both are
license/patent-encumbered for commercial use.

**AECMOS** (Microsoft AEC Challenge) — MIT-licensed, a Conv+MaxPool+GRU model —
**is now available** (headless eval only). It was previously skipped because our
pure-Dart `onnx_runtime_dart` lacked conv/pooling/recurrent ops; the runtime has
since gained them (mel front-end matched to librosa at 2.4e-7, MOS to ~1e-6 vs
the Python reference), so AECMOS runs in **pure Dart on every target — no FFI**.
Wired as a dev-only harness so it never reaches the app / web bundle:
- `bin/aecmos.dart <model|run-id> <lpb.raw> <mic.raw> <enh.raw> <st|nst|dt>`
  prints the echo-MOS + degradation-MOS pair.
- `onnx_runtime_dart` is a **`dev_dependency`** (path `../onnx_runtime_dart`,
  public `CrispStrobe/onnx_runtime_dart`; CI/deploy check it out as a sibling like
  crisp_notation). Its `_io` model loader uses `dart:io`, so keeping it dev-only +
  confined to `bin/` is what guarantees web-safety.
- The scorer + mel front-end (`bin/aecmos/`) are copied from the runtime's
  `example/aecmos/`; a model-free smoke test (`test/aecmos_smoke_test.dart`) guards
  the mus-side wiring (the DSP is exhaustively tested upstream).
- The **model is not bundled** — a Microsoft AEC-Challenge artifact (run id
  `1663915512` / `1663829550` @ 16 kHz, `1668423760` @ 48 kHz) dropped into
  `~/.cache/onnx_runtime_dart_models/aecmos_<run-id>.onnx`. The 16 kHz + 48 kHz
  models are mirrored (MIT) at <https://huggingface.co/cstr/aecmos-onnx>:
  `hf download cstr/aecmos-onnx aecmos_1663915512.onnx --local-dir
  ~/.cache/onnx_runtime_dart_models`. Full scoring can't run in CI (same skip
  convention as upstream); it's a local/dev tool.

The objective metrics (ERLE / convergence / SI-SDR) still need nothing.

### Algorithm upgrades — safe (patent-free)

Both are classic, expired-patent techniques; neither copies an encumbered
implementation.

1. ✅ **Double-talk detector (DTD) — DONE.** The linear core kept adapting on
   near-end speech (double-talk SI-SDR gain only a few dB); a DTD freezes the
   filter while the near-end is present. Shipped in `aec_offline.dart` as
   `DoubleTalkDetector` + an additive `EchoCanceller.process(..., {bool adapt})`
   gate (default true — the C port and existing callers are untouched). Uses a
   **normalized cross-correlation** statistic — `corr(mic, echoEst)` where
   `echoEst = mic − cleaned = W·x` — which needs no echo-path-gain threshold
   (unlike Geigel); a warmup guard lets the filter converge first, a hangover
   stops flapping. On the `--selftest` scenario (converge → double-talk) it lifts
   the double-talk SI-SDR from ~9 dB (linear) to ~16 dB (**+7 dB**), while
   leaving far-end-single-talk cancellation untouched. Opt in via
   `cancelEcho(..., doubleTalkDetect: true)` / `StreamingEchoCanceller(...,
   doubleTalkDetect: true)` / `bin/aec.dart --dtd`.
2. ✅ **Residual echo suppression (RES) — DONE.** A Wiener-style spectral
   post-filter on what the linear filter leaves (misadjustment, the tail beyond
   the filter). Shipped as `ResidualEchoSuppressor` in `aec_offline.dart`; opt in
   via `cancelEcho(..., residualSuppress: true)` / `StreamingEchoCanceller(...,
   residualSuppress: true)` / `bin/aec.dart --res`. It reuses the canceller's own
   **overlap-save framing** (a 2·blockSize `[prev ; cur]` frame, spectrally
   gained, keep the last block) so there's no window/COLA bookkeeping. Per bin
   the residual echo is `λ(k)·|Ŷ(k)|²`, with the **echo leakage λ learned only on
   far-end single-talk** — gated by the DTD, because during double-talk the
   near-end inflates the residual and would drive λ (and the suppression) far too
   high. A `gainFloor` bounds the attenuation. Result on `--selftest`: echo-only
   segmental ERLE **39 → 55 dB (+15)**, while the double-talk SI-SDR is
   **unchanged (−0.1 dB)** — it deepens the echo suppression without chewing the
   voice. The short-time spectral-gain approach is decades old and patent-free;
   this copies no encumbered implementation (notably not AEC3's statistical
   model).

**The patent-free algorithm roadmap is complete** (DTD + RES). Recommended
combination: `--dtd --res` (they compose — RES's leakage estimate is DTD-gated).

3. ✅ **Closed-loop learning rate (self-tuning) — DONE.** Instead of a
   hand-picked `mu`, the filter derives its own step per bin per block from its
   live leakage estimate: Valin, "On Adjusting the Learning Rate in Frequency
   Domain Echo Cancellation With Double-Talk" (IEEE TASLP 2007;
   arXiv:1602.08044), written from the paper (SpeexDSP MDF uses the same law;
   we did not vendor it). `mu_opt(k) = min(η·|Ŷ(k)|²/|E(k)|², μ_max)` with η
   (=1/ERLE) regressed from DC-rejected error/echo power spectra. Shipped as
   `AdaptiveLearningRate` in `echo_canceller.dart`; opt in via
   `EchoCanceller(rate:)` / `cancelEcho(..., AecTuning(adaptiveRate:true))` /
   `bin/aec.dart --adaptive-rate`. On `--selftest` it lifts the **linear**
   double-talk SI-SDR from ~9 dB to **~33 dB** — beating fixed-`mu`+DTD (~16 dB)
   with no DTD, and it **subsumes double-talk detection** (adding a DTD on top
   hurts, since the rate already collapses on near-end). Trade-off: slower
   convergence (~0.9 s vs a hot fixed `mu`'s ~0.1 s), so it's opt-in. **Ported to
   C** (`aec_rate_*` in `src/aec_dsp.c`, `aec_dsp_set_rate`; NULL = fixed-`mu`
   path, byte-identical — the ERLE cross-check still pins it). NOT yet wired into
   `aec_shim`/`aec_engine` — that's the on-device milestone (e).

### Automatic tuning (`bin/aec_tune.dart`)

The adaptive rate removes the hand-tuning of `mu`, but its own control law
introduces a few constants that are still hand-picked (`rateGamma`, `rateBeta0`,
`rateMuMax` — the paper leaves γ/β₀ unspecified). `bin/aec_tune.dart` tunes those
**automatically**: it builds a ground-truth corpus (`bin/aec_tune/corpus.dart` —
parametric rooms today; the interface accepts measured RIRs / real captures as a
drop-in), scores a config on a **domain objective** (`objective.dart` —
note-survival + double-talk SI-SDR, deliberately NOT speech-MOS, per this doc's
"judge by the decoded outcome"), and runs **separable CMA-ES** (`cmaes.dart`,
correctness-tested against sphere + ill-conditioned ellipsoid) to maximize it.
On the synthetic corpus it takes the untuned adaptive rate (8.9 dB SI-SDR / 83%
note-survival) to **20.4 dB / 100%** (+11.5 dB). CLI-only (out of the app);
tests in `test/aec_tune_test.dart`. This is the industry-standard black-box
recipe (a non-intrusive metric + a corpus + CMA-ES), with a music-appropriate
objective in place of AECMOS (which `bin/aecmos` provides as a cross-check).

**Tier-2 real-acoustics corpus (shipped).** `buildCorpusFromAssets` builds the
same ground-truth scenarios from **real measured room IRs** ([MIT IR Survey](https://mcdermottlab.mit.edu/Reverb/IR_Survey.html),
CC-BY) × **real cello** ([University of Iowa MIS](https://theremin.music.uiowa.edu/MIS.html),
free/unrestricted) instead of synthesized rooms/tones. Point the tuner at asset
dirs:

```bash
dart run bin/aec_tune.dart --rir-dir <dir-of-RIR-wavs> --cello-dir <dir-of-cello-wavs>
```

The RIR is truncated to its early field (~90 ms) — the high-energy, cancellable
part a single-block filter models; the long reverb tail exceeds a 1024-tap
filter (an MDF filter would capture more — a known upgrade). The echo is
level-calibrated to a realistic echo-to-near ratio (measured RIRs aren't
energy-normalized). The near-end note is DETECTED on the clean cello (not
assumed), so note-survival honestly asks "same note before and after". On the
real corpus (6 MIT rooms × 3 Iowa cello runs, 54 notes) the tuner lifts the
untuned adaptive rate **3.4 dB SI-SDR / 74% notes → 9.0 dB / 94%** (+5.6 dB). The
lower absolute SI-SDR vs the synthetic corpus (20 dB) is the honest point — real
rooms are harder, and `rateGamma` settles to an *interior* optimum (0.36) the
synthetic corpus never revealed (it pinned to the bound). Assets live on
`/Volumes/backups/ai/aec_corpus/` (never checked in; research/eval-use licences,
local tuning only).

**Modelled loudspeaker nonlinearity.** An RIR is linear, so to approximate the
one thing it misses — a driven speaker's harmonic distortion — the corpus can
pass the reference through a memoryless nonlinearity BEFORE the echo path (a
Hammerstein model, exactly how the AEC Challenge synthesizes its nonlinear set;
in ~80% of its cases the far-end is hard-clipped or sigmoidally distorted). The
AEC still sees the CLEAN reference, so the added harmonics aren't in it and a
linear filter can't cancel them. `--nonlin clip|tanh --drive N`; the model holds
RMS (shape changes, level constant) so the cost is distortion, not gain. It
first reports the cost and whether a residual stage recovers it. On the real
corpus with a hard clip (drive 4): the nonlinear echo drops note-survival
**74% → 30%** (SI-SDR 3.4 → 0.2 dB), and the residual suppressor (`--res`)
recovers it to **87% / 4.7 dB** — a concrete case for enabling RES once the
speaker is driven hard. It's a MODEL, not measured; the only source of measured
nonlinearity remains the AEC-Challenge real set (blind/AECMOS) or a real device
capture. **Remaining realism gap:** measured speaker/mic nonlinearity — a real
device capture (the on-device milestone).

Reference algorithms in the same patent-free family: **SpeexDSP MDF** (Valin,
BSD-3, designed to avoid patents) and **WebRTC AEC3** (BSD-3) — read for
technique, don't vendor unless the licence + tree stay clean.

### Native port status

- ✅ **DTD ported to C.** `src/aec_dsp.c`/`.h` gained an additive
  `aec_dsp_set_adapt()` gate (default adapt=1, so the existing default-`adapt`
  ERLE cross-check is unchanged) and an `AecDtd` struct/functions
  (`aec_dtd_create_default` / `_freeze` / `_update` / `_reset` / `_destroy`) — a
  line-for-line port of the Dart `DoubleTalkDetector` (normalized correlation,
  warmup + hangover). FFI-bound in `lib/aec_dsp.dart` (`AecDsp.setAdapt`,
  `AecDtd`). Verified by an FFI cross-check in `test/aec_erle_test.dart` (the C
  DTD preserves the near-end better than linear-only, mirroring the Dart test)
  — green via `build.sh` on macOS.
- ✅ **DTD wired into the engine block loop.** `aec_shim.c`'s `engine_run`
  (the shared core the realtime duplex callback AND the headless test pump both
  run) now, when the DTD is enabled, reads `aec_dtd_freeze` → `aec_dsp_set_adapt`
  → process → `aec_dtd_update` each block. It's **opt-in** via a new
  `aec_engine_set_dtd()` (default off — the existing continuous-double-talk
  engine test stays green; a DTD can hurt when there's no clean convergence
  window). FFI-bound as `AecEngineFfi.setDtd(bool)`. Verified headlessly by a new
  double-talk test in `test/aec_engine_test.dart` (pump: converge→double-talk,
  DTD-on near-end error <0.7× DTD-off) — the whole native suite is green (8/8).
  NB the divergence the DTD fixes shows at the 1024-sample AEC block; a
  256-sample filter is already robust, so enable the DTD only with a matching
  block size.
- ✅ **RES ported to C + wired into the engine.** `src/aec_dsp.{c,h}` gained an
  `AecRes` (create_default / process / reset / destroy) — a port of the Dart
  `ResidualEchoSuppressor`, reusing the DSP's own `aec_fft`/`ifft`. FFI-bound as
  `AecRes` in `lib/aec_dsp.dart`; verified by an offline cross-check
  (`test/aec_erle_test.dart`: RES deepens echo-only ERLE >3 dB past the linear
  filter). Also wired **opt-in** into the engine block loop
  (`aec_engine_set_res()` / `AecEngineFfi.setRes(bool)`), with its leakage
  estimate gated on the DTD's single-talk decision; headless engine test
  (`test/aec_engine_test.dart`: RES deepens echo-only ERLE through the pump). RES
  needs a distinct output buffer — it reads the cleaned/echo frame after writing
  its output, so it can't run in place. Whole native suite green (10/10).
- **`build.sh` fixed:** it now runs the cross-check with `flutter test` +
  `AEC_LIBRARY_PATH` (→ the full `libaec`, which carries the DSP + DTD + RES +
  engine symbols) OUTSIDE the GEM-env wrapper (the wrapper hangs the flutter test
  runner; the old `dart test` couldn't resolve the flutter_test suite).
- **Remaining (all need on-device hardware — milestone (e)):** app opt-in —
  have `NativeAecEngine`/the jam screen call `setDtd(true)` + `setRes(true)` (with
  a 1024-block engine) once speaker-backing is on; then tune the real duplex path
  on iOS/Android (latency, ring, session). The whole DTD+RES stack is now **in the
  native engine and headlessly verified** — what's left is exercising it on real
  hardware.

## Effort

Days–weeks: most of it is the 5-platform native build + on-device tuning, not
the algorithm (SpeexDSP is done). Sequence: (a) C shim + FFI + macOS build +
offline ERLE test → (b) BlackHole loopback → (c) wire into
`MicrophonePitchService` behind a flag → (d) Android/iOS/Windows/Linux builds →
(e) on-device tuning.
