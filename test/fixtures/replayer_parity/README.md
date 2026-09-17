# Replayer extraction parity

`test/tracker_replayer_pcm_parity_test.dart` characterizes the public
`replaySong` / `replaySongStereo` PCM and timing results. Its 16 existing,
project-authored module inputs cover MOD/XM/IT/S3M, uniform timing, tempo
changes, pattern loops, MOD vibrato, XM tremor, IT fine portamento and S3M
panbrello. Both mono and stereo are checked: **32 PCM cases**, plus one
negative-control test that rejects changed bytes and lengths. Missing module
inputs fail rather than skip. No external player or downloaded corpus is needed.

## Local pre-/post-refactor gate

Do not commit rendered goldens. As documented in `../README.md`, platform libm
rounding prevents a portable byte-exact reference. Capture on the unmodified
baseline, then verify on the **same runtime and platform** after changing code.
The directory must be outside the repository and new for each baseline.

From the repository root, with the characterization test already present:

```sh
# Run this BEFORE changing production code. Capture renders each input twice
# and requires identical bytes and timing before writing anything.
PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter test --no-pub \
  --dart-define=REPLAYER_PARITY_MODE=capture \
  --dart-define=REPLAYER_PARITY_DIR=/tmp/replayer-parity-BASELINE \
  test/tracker_replayer_pcm_parity_test.dart --reporter expanded

# Run unchanged before and after extraction; do not recapture after a failure.
PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter test --no-pub \
  --dart-define=REPLAYER_PARITY_MODE=verify \
  --dart-define=REPLAYER_PARITY_DIR=/tmp/replayer-parity-BASELINE \
  test/tracker_replayer_pcm_parity_test.dart --reporter expanded
```

Capture refuses to overwrite existing snapshots. Each case stores losslessly
gzipped PCM16 little-endian bytes and JSON containing exact input module bytes,
platform/runtime, channel count, byte count and the row-timing map. Verify
requires this metadata and every decompressed PCM byte to match. These are
observed pre-refactor outputs, not idealized reference-player output.

With no defines, the test runs repeat-render determinism only. That default is
portable but **does not establish pre-/post-refactor parity**; use the explicit
capture/verify gate for that claim. The current cases use 44100 Hz and no dither;
they do not establish coverage of every format feature or cross-platform parity.

## Flow/timing extraction evidence

Baseline: `30ee135e`, branch `feature/composition-opt`, macOS arm64 / Dart 3.12.2.
The production file was unchanged when the snapshots were captured. A verify
run first failed on the missing snapshot; capture then passed all 33 tests.

- Local snapshots: `/tmp/replayer-parity-30ee135e/` (32 pairs).
- Snapshot checksum manifest: `/tmp/replayer-parity-30ee135e-manifest.json`.
- Exact payload compared: **48,802,824 PCM bytes**, all 32 cases unchanged.
- Focused parity + flow/timing/effect/streaming selection: **108 passed** both
  before and after (`/tmp/replayer-before.log`, `/tmp/replayer-after.log`).
- Replayer + existing determinism + optional audio regression selection:
  **89 passed, 11 opt-in skips** both before and after
  (`/tmp/replayer-baseline.log`, `/tmp/replayer-baseline-after.log`).
- Capture: `/tmp/replayer-parity-capture.log`; expected missing-baseline failure:
  `/tmp/replayer-parity-red.log`.

`lib/core/audio/replayer/flow_timing.dart` is a Dart part of
`tracker_replayer.dart`, not a new import surface. It contains the original
448-line flow/timing section (`PlayedRow`, flow gates/walk, tempo/speed helpers,
onsets, timing map and playhead lookup) without algorithm edits. Public API and
library-private access are preserved; command constants stay in the main file.
No performance claim, full-suite run, external-player audit or platform build
is implied by this maintenance extraction. Temporary artifacts may be removed
by the OS; regenerate from the baseline revision if needed, never from a changed
renderer and label those outputs as pre-refactor evidence.
