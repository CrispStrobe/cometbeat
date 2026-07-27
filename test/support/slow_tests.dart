// Which expensive test tiers the default `flutter test` runs.
//
// The suite is ~4700 tests over ~190 files. On the dev Mac (4 performance + 4
// efficiency cores) a full run took 32m52s, and a suite that expensive stops
// being run — which is not hypothetical: a real licence regression sat on main
// for days because the full run was too costly to be routine, and nobody saw
// the red.
//
// Measured 2026-07-27, and the shape is lopsided rather than uniformly slow:
//
//   piano_test.dart                     18m01s   ← one file, over half the run
//   native_tick_zone_reuse_test.dart     3m29s
//   loop_mixer_test.dart                 2m23s
//   kokoro_synth_test.dart               1m57s
//   …the remaining ~185 files            ~19m combined
//
// So a couple of tiers are gated behind opt-in flags and everything else — all
// the app-behaviour and widget coverage — still runs by default.
//
// Two flags rather than one, because the reasons differ and you often want one
// without the other: [kRunModelE2e] needs a multi-hundred-megabyte model on
// disk, [kRunHeavy] just needs patience.
//
//   flutter test --dart-define=MODEL_E2E=1     # ONNX end-to-end / parity
//   flutter test --dart-define=HEAVY=1         # long renders, CLI subprocesses
//   flutter test --dart-define=MODEL_E2E=1 --dart-define=HEAVY=1   # everything
//
// `String.fromEnvironment` + "is it non-empty", never `bool.fromEnvironment`:
// the bool form only accepts the literal `true`, so `=1` silently leaves the
// flag OFF. That trap already cost this repo once — see the note in
// `tracker_audio_regression_test.dart` — so it is written down here as well.
//
// When you gate a group, leave a NAMED skip behind (see [describeSkip]). A test
// that silently disappears reads as coverage that exists, which is worse than a
// slow suite.

const String _modelE2eRaw = String.fromEnvironment('MODEL_E2E');
const String _heavyRaw = String.fromEnvironment('HEAVY');

bool _on(String raw) => raw.isNotEmpty && raw != '0';

/// End-to-end / runtime-parity tests that load a real ONNX model.
///
/// These already skip when the model is not cached, so CI never ran them; this
/// flag is about the developer machine that HAS the models, where they dominate
/// the run.
final bool kRunModelE2e = _on(_modelE2eRaw);

/// Long renders, offline DSP sweeps and tests that spawn a CLI subprocess.
///
/// Pure compute — no model download needed, they are simply slow.
final bool kRunHeavy = _on(_heavyRaw);

/// The message for the placeholder test left in a gated-out group.
String describeSkip(String flag, String why) =>
    'skipped — pass --dart-define=$flag=1 to run ($why)';
