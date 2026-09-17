# Composition optimization implementation plan

> **For Hermes:** Use subagent-driven-development for isolated implementation and independent review.

**Goal:** Reduce avoidable editor playback work without changing audio, timing, editing, undo or capability fallbacks.

**Architecture:** Preserve existing ValueNotifiers and controllers. Isolate only verified broad update paths; do not replace working state management based on file size. Extract coherent rendering helpers from large files without altering public imports.

**Tech Stack:** Flutter/Dart, existing flutter_test and integration_test; no new runtime dependencies.

## Evidence and corrections
- Tracker and Loop Mixer already publish ticker progress through ValueNotifiers, not screen setState. DAW does the same. ValueNotifier already suppresses equal scalar values.
- Workshop timer rebuilds the screen only when its sounding-note set changes; it is not an unconditional 25 Hz rebuild.
- Tracker meters scan 1470 samples per channel per ticker update; investigate/test separately from smooth playhead scrolling.
- Initial analyzer output was truncated; no clean baseline claim is valid.
- Baseline full suite log: /tmp/full_suite_baseline.log. No claim of a hang from wait timeout alone.

## Tasks
1. Workshop: characterize playback and rebuild scope with focused widget tests; isolate sounding-note updates from toolbars, preserving stop/count-in/loop/disposal. Run RED then GREEN and existing workshop coverage.
2. Tracker: characterize meter/update costs, extract a bounded meter-update helper if justified, preserve per-frame playhead scrolling. Extract independent leaf UI components where useful. Unit and widget regressions.
3. Loop Mixer and DAW: inspect listener fan-out and paint paths; preserve existing notifier isolation; extract coherent independent painters/widgets and add paint/rebuild regression coverage rather than blanket ChangeNotifier migrations.
4. Replayer: extract one or more coherent DSP/voice responsibilities into feature files, keeping tracker_replayer.dart's import API compatible. Characterization/golden PCM parity and existing renderer tests; no algorithm changes in this split.
5. Live: add a real integration test covering all four screens, editing and transport plus render output; profile frame timing where supported. Run on available native device or browser. Preserve logs and report unavailable native/audio checks explicitly.
6. Hygiene: inspect untracked files without committing third-party corpus or scratch data; use local excludes for local scratch, not broad source ignore rules. Run full analyzer and distinguish tracked baseline from scratch diagnostics.
7. Final: format touched files first, targeted and full tests, full flutter analyze last, independent spec then quality review. No unrelated dependency/version/credential edits. Preserve existing branch/worktree state.

## Acceptance
All four editors retain edit/undo/play/stop functionality; notation highlights and smooth playheads remain correct. Renderer output unchanged for split code. No claimed speedup without recorded measurement; no claimed live verification from widget tests alone. Commit/push only verified task changes and coordination board, never unrelated local commits or corpus.
