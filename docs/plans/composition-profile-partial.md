# Exploratory native profile — partial, stopped by scope change

**Not a four-editor success or an optimization baseline.** One actual macOS profile run completed with exit **1**: playback phases collected for Advanced Tracker, DAW and Loop Mixer (3/4); Workshop failed a harness assertion. User then narrowed scope to one Advanced Tracker hotspot and requested no more profiling. This section describes the initial run only; subsequent single-editor measurements and the rejected experiment are recorded below. No production code was edited by the initial harness task.

## Reproduction and artifacts

Wrapper invoked:

```sh
python3 tool/run_composition_profile.py --output /tmp/composition-profile-exploratory-01
```

Actual command (workdir `/Users/christianstrobele/code/mus-composition-opt`):

```sh
PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter drive --profile -d macos --driver=test_driver/composition_profile_driver.dart --target=integration_test/composition_profile_test.dart --dart-define=PROFILE_RUN_ID=20260917T193416Z --dart-define=PROFILE_REVISION=30ee135e2967249a5dd48f72d49640fed433ea5a
```

Artifacts preserved at `/tmp/composition-profile-exploratory-01/`:
- `flutter-drive.log` — full build/test output, exit 1
- `metrics.json` — raw per-frame timings and complete VM allocation snapshots
- `summary.json` — descriptive timing/CPU/RSS aggregates and failure stacks
- `command.json`, `processes-before.txt`, `exit-code.txt`

Sandbox source: `/Users/christianstrobele/Library/Containers/com.crispstrobe.cometBeat/Data/tmp/composition-profile/20260917T193416Z/metrics.json`.

Verified starting HEAD `30ee135e2967249a5dd48f72d49640fed433ea5a`, branch `feature/composition-opt`. Flutter 3.44.4 / Dart 3.12.2, macOS 26.2 arm64, device pixel ratio 2. Other agents were active, including replayer tests and a mechanical source split. The HEAD metadata is not a guarantee of a clean source snapshot at compilation: rerun uncontended with a recorded diff before any before/after claim.

## Workloads and metrics

Real app startup and providers, real native audio plugins, profile-mode guard, fullyLive binding and real wall-clock waits; no synthetic ticks. Each editor: setup, 2s idle, start+2s, 6s playback. Allocation snapshots run outside the timing window, with no forced GC/reset. Frame timings come from SchedulerBinding callbacks, filtered by engine timestamps. CPU is Darwin `clock(3)` cumulative **whole-process/all-thread CPU**, not UI-isolate time. RSS is process memory, not allocation rate.

| Playback workload | Frames | Mean build ms | Build p99 ms | Mean raster ms | Raster p99 ms | Process CPU ms / wall ms |
|---|---:|---:|---:|---:|---:|---:|
| DAW: demo beat + demo tune, looping | 346 | 2.188 | 6.314 | 1.200 | 1.896 | 2451.346 / 6002.292 |
| Loop Mixer: starter, drums+bass+chords | 349 | 0.787 | 1.463 | 1.034 | 2.252 | 1479.321 / 6001.219 |
| Advanced Tracker: built-in demo song, follow-play + oscilloscope | 287 | 4.296 | 76.465 | 1.480 | 2.666 | 5855.026 / 6002.131 |

Advanced Tracker playback process CPU was 97.55% of one core. Build max 86.295ms; total-span p99 88.172ms; 25/287 total spans exceeded 16.67ms (not a dropped-frame count). RSS before/after: 969,048,064 / 859,881,472 bytes. VM `getAllocationProfile` genuinely worked in profile mode: heap usage 582,534,768 → 581,617,376 bytes, external usage 2,491,040 → 50,416 bytes. **Do not interpret these snapshots as allocation throughput**: accumulated counters also decreased, and collection/snapshot overhead affects live memory. Raw snapshots remain available for inspection. No CPU stack sampling trace was captured; async TimelineTask phase markers are defined in the harness but not exported as a timeline artifact.

Start/stop and clock advancement assertions passed for those three playback workloads. This does not prove physical speaker output. Captured audio-warning list was empty.

## Exact Workshop failure and known harness defect

`flutter-drive.log:566–580`:

```text
workshop: Expected: true
  Actual: <false>
workshop did not start
... composition_profile_test.dart:190
```

The harness incorrectly asserts `TransportService.isPlaying` for Workshop. Production Workshop does **not** publish playback to TransportService: `_startPlayback` owns `_playClock` / `_playTimer`, and `_tickPlayback` drives sounding-note highlights. The play tap may have worked; the shared transport assertion cannot establish that it failed. Workshop idle/start metrics exist, but no valid playback phase was collected. The stop helper has the same incorrect shared-transport dependency. Fix future harness assertions by observing Workshop's actual stop control/highlights (and changing highlights), not by adding production transport instrumentation. Work was halted before implementing/verifying that repair. An in-progress edit was reverted, leaving the actually executed harness version, not an uncompiled half-fix.

## Subsequent Advanced Tracker experiment: rejected

Run one editor with `python3 tool/run_composition_profile.py --editor advanced_tracker --output /tmp/NEW-RUN-DIRECTORY`.
The runner now records a tracked-source diff and the profiler collects VM CPU samples outside each measurement window. Untracked harness files are not included in that diff. CPU samples are UI-isolate observations, not whole-process attribution. The summary also contains those raw samples and can be large.

Baseline `/tmp/tracker-profile-isolated-02` and experiment `/tmp/tracker-profile-after-01` both exited 0 with playback assertions passing:

| Six-second playback | Baseline | Separate waveform/playhead repaint layers |
|---|---:|---:|
| Frames delivered | 261 | 195 |
| Build mean ms | 4.905 | 3.882 |
| Build p95 ms (computed from raw frames) | 9.979 | 11.267 |
| Build p99 ms | 98.879 | 27.468 |
| Raster mean ms | 1.597 | 2.307 |
| Process CPU ms | 6617.208 | 6285.971 |

The reduction in average build time is not an overall improvement: p95 build, raster time and frame delivery worsened. A repeat attempt produced no metrics; subsequent native compilation failed with `No space left on device`. Build cleanup recovered space, and the focused waveform-picture retention regression passed again. The optimization was then **reverted**, not retained as a performance claim. Its patch and regression are archived at `/tmp/oscilloscope-rejected.patch` and `/tmp/oscilloscope_repaint_test.dart`; the test is deliberately outside the suite because it asserts a rejected implementation.

No reproducible p99/throughput win has been established. The archived CPU samples are too sparse near the long frames to attribute the ~99 ms stall; recorded frame data lacks exact build-start/end timestamps. Do not infer a widget-build bottleneck from `buildDuration` alone or add post-frame scheduling without evidence. Future investigation needs precise frame/timeline correlation, not another speculative production change. Workshop observation remains deferred.

## Verification limits

Build succeeded in profile mode (179.3MB app). Driver correctly returned exit 1 despite macOS integration-plugin warning. Final full-project analysis passed. Same-platform replayer parity was reverified against the original captures. The final full-suite attempt reached 3,295 passed / 16 skipped, then stopped producing output for over 45 minutes with no remaining test workers; it was terminated, not accepted as a passing suite (the wrapper's exit text is not completion evidence). Both Workshop live tests passed. The isolated audio-cache test built but failed to launch with `Error waiting for a debug connection`; its assertions never ran in that attempt. Logs: `/tmp/composition-final-suite.log`, `/tmp/composition-final-live.log`, `/tmp/composition-suite-hang.sample.txt`, `/tmp/composition-bounded-final.log`. These are verification gaps, not proven production defects. Harness files are intentionally preserved as **partial** support, not a passing four-editor deliverable. No performance optimization is retained.
