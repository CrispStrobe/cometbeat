# The isolate GEMM pool — what it buys, and how many workers

`onnx_runtime_dart` can fan each large `MatMul` and (with `poolConv: true`) each
2-D convolution across a pool of isolates, splitting by output band:

```dart
await model.parallelize(workers: N, poolConv: true);
final out = await model.runAsync(inputs, outputNames);
```

This file is the measurement record for that knob on **CometBeat's own models**.
It exists because the knob has been set from other projects' numbers before, and
the worker count in particular has already been shipped wrong once elsewhere and
corrected.

## The rules a number here has to have been produced under

Taken from the owner's standard for perf work on the sibling C++ projects, and
enforced in code by `tool/pool_workers_ab.dart` rather than left to discipline:

1. **Both paths stay.** The synchronous path is not deleted; it is the fallback
   and the web path, and it is the equality reference.
2. **Output equality is proven, not assumed.** The pool is a pure scheduling
   change — bands of the same arithmetic, concatenated — so equality is exact or
   there is a bug. The harness compares the full output and exits non-zero on a
   mismatch; a test does the same on every CI run.
3. **One arm per process.** An isolate pool, the allocator and page-cache state
   all persist inside a process, so two arms in one process measure their order.
4. **The cold run is discarded**, and the result is the **median of at least
   three** warm runs.
5. **A default does not flip on one measurement.**

Corollary that mattered here: **a shared machine cannot produce these numbers.**
The development box for this work sat at load average 17 on 4 cores, with
another project's `rustc` and a `flutter_tester` resident; its within-arm spread
was larger than the between-arm difference it was supposed to resolve. That is
why the measurement lives in `.github/workflows/pool-ab.yml` and not in a
terminal.

## How to re-run it

```
# On CI (preferred) — ubuntu + macos + windows, Basic Pitch and CREPE:
gh workflow run pool-ab.yml --ref <branch> \
    -f seconds=20 -f crepe_seconds=6 -f arms=0,1,2,4,6 -f runs=4

# Locally, if the box is genuinely idle:
dart build cli --target bin/transcribe_basicpitch.dart
dart run tool/pool_workers_ab.dart --model basicpitch \
    --bin build/cli/<host>/bundle/bin/transcribe_basicpitch \
    --seconds 20 --arms 0,1,2,4,6 --runs 4
```

Arm `0` is the synchronous path. The benchmark audio is synthesised by the
harness (a four-chord piano-ish progression), so no audio fixture lives in the
repo.

<!-- RESULTS -->

## Follow-ups this work turned up but deliberately did NOT do

Both are out of scope for the PR that added this file; both are free wins that
should not be lost.

### 1 · The app's RMVPE path is still unpooled

The pooled entry points and the paths the *app* actually takes are not the same
set. Measured on the tree as it stands:

| model | pooled in the CLI / store | pooled in the APP's provider |
|---|---|---|
| CREPE | yes (`crepeF0Estimator` → `CrepeRunConfig.fromEnv`) | **yes** |
| RMVPE | yes (`RmvpeModelStore.estimator()`) | **no** — `rmvpe_provider_io.dart` calls the unpooled `rmvpeF0` directly and never calls `estimator()` |
| Basic Pitch | yes (`BasicPitchModelStore.transcriber()`, new) | yes (new) |

So "CometBeat already pools RMVPE, FCPE and CREPE" is true of the store API and
not of the shipping app. RMVPE is the model with the strongest prior for
gaining from the pool — its own comment puts it at ~80% Conv — and its provider
is a three-line change of exactly the shape this PR made for Basic Pitch. It is
left alone here only to keep this change to one thing at a time.

### 2 · The monophonic path quantises its own pitch to the semitone

Not a performance matter, but found while reading these paths and worth more
than the pooling is. The shipped monophonic chain runs `segmentNotes` and takes
the note-HMM's `int midi` as its answer, which throws away everything finer
than a semitone. Using the HMM as a **voicing mask** instead — its note
boundaries decide *when* to answer, `pyinF0`'s own frequency decides *what* —
dominates the current arrangement on every axis, measured on CometBeat's own
engine over GuitarSet (180 files):

| GuitarSet, 180 files | octave % | gross % | median \|err\| (cents) | false alarm % |
|---|---|---|---|---|
| pYIN raw | 4.59 | 11.44 | 3.10 | 53.90 |
| pYIN + HMM (current, quantised) | 1.75 | 7.76 | **7.35** | 29.59 |
| pYIN + HMM as a **mask** | 2.14 | 6.92 | **3.00** | 29.59 |

The mask keeps all of the HMM's voicing and gross-error benefit and restores
the cents accuracy the quantisation costs. For anything that cares about
intonation rather than note identity — a tuner view, an intonation game, an
export with pitch bend — the current arrangement is a regression against the
raw detector it is built on.


## The paths themselves

| model | store entry point | pooled call |
|---|---|---|
| RMVPE | `RmvpeModelStore.estimator()` | `rmvpeF0Async` |
| FCPE | `FcpeModelStore.estimator()` | `fcpeF0Async` |
| CREPE | `crepeF0Estimator()` / `CrepeRunConfig` | `crepeF0Async` |
| Basic Pitch | `BasicPitchModelStore.transcriber()` | `basicPitchTranscribeAsync` |

`basicPitchTranscribe` (synchronous, web-safe, no `dart:io`) is unchanged and
stays the web path — `parallelize` throws on the web. The async entry points
share `_prepare` / `_windows` / `_Grids` / `_decodeGrids` with it, so only the
per-window inference differs between them.

Environment overrides, all "0 disables the pool":
`COMET_BASICPITCH_WORKERS`, `COMET_RMVPE_WORKERS`, `COMET_CREPE_WORKERS`.
