# Test-coverage report & campaign (2026-07-27)

A record of the coverage-measurement effort: the infrastructure bug that made a
whole-suite number impossible, the harness that routes around it, the 80.0%
baseline it produced, the pure-logic gaps that were then closed, and the honest
ceiling where further unit testing stops being possible.

**Operational how-to lives in [`tool/coverage/README.md`](../tool/coverage/README.md).**
This document is the findings + methodology.

---

## 1. TL;DR

- `flutter test --coverage` could not run to completion: it aborts the **entire**
  suite with `Cannot add event while adding stream` the instant one test spawns
  an isolate/process. Nine tests do.
- A committed harness (`tool/coverage/{run.sh,merge.py}`) excludes the known
  spawners, runs the rest in **batches** under coverage, **falls back to
  per-file** when an unknown spawner aborts a batch, then merges the lcov parts
  (DA + BRDA by max hit) and reports.
- **Baseline: 80.0% line coverage** across `lib/` (61,890 / 77,385 lines; 532 /
  601 files loaded).
- The map confirmed the worst-covered files are FFI / native-transcription /
  ONNX-model-store / plugin wrappers (integration-tested) and export-shell
  barrels — **not** genuine gaps.
- The genuine pure-logic gaps it surfaced were then **closed file-by-file: ~25
  files raised, 23 to 100%** (across the main sweep and an 83–90% follow-up
  tier), each re-verified with scoped coverage before commit.
- Every remaining low-coverage file hits a **structural unit-test ceiling**
  (native/ONNX runtime, live plugin, isolate spawn, process-env var, or a big
  DSP core / widget body covered by integration suites).

---

## 2. The collection bug

`flutter test --coverage` collects coverage for the whole run through the VM
service's `coverage` package. When a test spawns a Dart isolate or a child
process mid-collection, collection throws:

```
Cannot add event while adding stream
```

and the **entire** coverage run is lost — not just that test. The full suite is
also too slow to finish under coverage in one shot. This is why a whole-suite
number had been marked "infrastructure-blocked" for weeks.

### The nine spawners

Excluded up front (grep for `Isolate.`/`Process.`/`compute(`), plus two the
per-file fallback discovered at runtime:

```
dawedit_cli · flac_glint_live · fxproc_cli · module_wild ·
mp3_decode_roundtrip · rendersong_cli · stream_export ·
tracker_audio_regression · streaming_procedural
```

(`tmp_ly_validate` also failed per-file collection.)

---

## 3. The harness

`tool/coverage/run.sh`:

1. Lists every `test/**/*_test.dart`, drops the known spawners.
2. Runs the rest in **batches of 40** with
   `flutter test --coverage --coverage-path=coverage/parts/batch_NN.info …`.
3. If a batch produces no lcov (an unknown spawner aborted it), it **falls back
   to per-file** for that batch, so only the one bad file is lost (logged to
   `coverage/parts/failed.txt`).

`tool/coverage/merge.py`:

- Merges every `coverage/parts/*.info` — **DA (line) and BRDA (branch) records by
  max hit** across parts — into `coverage/merged.info`.
- Enumerates all `lib/**/*.dart` and reports: overall %, worst-covered **loaded**
  files (real gaps inside tested code), and **never-loaded** files (split into
  untestable ffi/stub/gen shells vs. others).

There is no `lcov` binary on this machine, so the merge is a small custom parser
(~130 lines). `coverage/` is gitignored; only the tooling is tracked.

### Run cost

~45–75 min wall-clock (601 files, batches under coverage). Runs headless in the
background. On this Mac, wrap with the broken-Ruby env from `CLAUDE.md`.

---

## 4. Baseline findings (80.0%)

| Metric | Value |
| --- | --- |
| lib `.dart` files | 601 |
| files with any coverage | 532 |
| overall line coverage | **61,890 / 77,385 = 80.0%** |
| lcov parts merged | 53 |
| files lost to spawners | 2 (`streaming_procedural`, `tmp_ly_validate`) |

**The worst-covered files are all expected.** The 0–35% band is almost entirely:

- **Native transcription / ONNX**: `*_model_store.dart`, `onnx_ort_*`, `fcpe`,
  `hubert`, `separate_*`, `crispasr_ffi_*`.
- **Codec FFI**: `opus_glint_ffi`, `vorbis_glint_ffi`, `flac_glint_ffi`,
  `encode_capability_ffi`.
- **Plugin wrappers**: `voice_clip_recorder`, `voice_pool`, mic screens.
- **Generated data / barrels**: `app_localizations_*`, `mp3_huffman_tables`,
  `*_ffi/_stub/_io/_web` conditional-export shells.

The 68 "never-loaded" files are all conditional-export shells (`export … if
(dart.library.io)`), bare enums, or generated dictionaries — **no genuine
pure-logic gaps hide there.**

---

## 5. Files raised off the map

Each entry: closed the gap the map named, verified by re-running scoped coverage
on that file, format→analyze-clean→commit.

| File | Before → After | What was closed | Commit |
| --- | --- | --- | --- |
| `core/audio/rhythm_quantize.dart` | 78 → **100** | `beatMsFromBpm`, public `snapToGrid`, `QuantizedHit` ==/hashCode/toString, collide-at-every-grid → cap fallback, empty paths | `9c45c194` |
| `features/games/note_reading/reading_hint.dart` | 55 → **100** | `readingHintText` — all 7 localized interval arms (same/step/skip/far × up/down) | `ae5abb66` |
| `core/audio/chord_progression.dart` | 83 → **100** | `inCountIn`, `reset()` | `50a8002b` |
| `core/audio/mod/module_doc.dart` (DocCell) | ~55 → **100** region | `DocCell.isEmpty` / `==` / `hashCode` | `1eb8ede7` |
| `core/audio/mod/xm/s3m/it_module.dart` | 55–62 → regions closed | format exceptions, `.empty()`/`.identity()` factories, per-format cell isEmpty/==/hashCode | `d1a872bc` |
| `core/audio/mod/mod_module.dart` | struct semantics | `ModFormatException.toString`, `ModCell` ==/hashCode | `b51d1057` |
| `features/library/source_registry.dart` | 71 → **100** | `defaultHttpGet` success + non-2xx via `http.runWithClient` + `MockClient` | `4f9baf06` |
| `core/audio/mod/module_flow_timeline.dart` | 85 → **100** | speedChange (Fxx + Axx `kFxSetSpeedFull`), patternLoop, all flow mutators, `clearFlowCommand` every-kind, value semantics | `8f95ecdd` |
| `features/progress/sri_item_label.dart` | 60 → **100** | `describeSriItem` — every module namespace + `_prettify` fallbacks | `28bf62f5` |
| `core/services/debug_service.dart` | 68 → **100** | `load` / `enableMenu` / `setUnlockAll` persistence + no-op early returns | `17476c86` |
| `core/audio/play_along.dart` | 84 → **100** | loop getters, `nextIndex` (incl. −1), `judged`, `reset`, `scaledStarScore`, `copyWith()` `?? this.bpm` fall-through | `91f51d76` |
| `core/audio/tracker_native_command.dart` | 74 → **100** | XM mnemonics (`_xmMnemonic`), default/negative fallbacks, `setNativeVolpan` + volpan describe + `clearNativeProvenance` | `093f282e` |
| `features/games/composition/music_inspect.dart` | 67 → **100** | `inspectBody` card (chord row, function swatch + `_functionText` arms, detail, NCT) + `showInspect` sheet | `2a834081` |
| `features/library/soundfont_download.dart` | 79 → **88**\* | `IoSoundFontCache.cacheDir` override + home-relative fallback | `00e2bd37` |
| `features/games/composition/tabcnn_emitter.dart` | 68 → 68\* | vanilla-variant + resample branches via the fake-runner seam | `9ca16b63` |

\* **Ceiling, not a gap** — see §7.

### Follow-up sweep — the 83–90% pure tier

A second, finer sweep (files 83–90% covered, ≥8 lines, non-native) found a tier
of near-covered pure files with small closeable gaps — mostly value semantics,
enum labels, and one-branch edges the main suites skipped:

| File | Before → After | What was closed | Commit |
| --- | --- | --- | --- |
| `core/audio/streaming_mixer.dart` | 87 → **100** | `BufferedSink` length/clear, `StreamingMixer.loopLength`, empty-loop `ArgumentError` guards | `130c8728` |
| `features/library/license_policy.dart` | 87 → labels closed | every `LicenseKind.label` arm + `LicenseBlocked.toString` (classifier itself is connector-suite-covered) | `130c8728` |
| `core/audio/sample_pitch.dart` | 88 → **100** | short-buffer single-pass branch + the crossfade-loop path | `26536e91` |
| `core/audio/sound_library.dart` | 89 → **100** | the non-engine-rate resample branch (22.05 → 44.1 kHz) | `26536e91` |
| `core/curriculum/coverage_gaps.dart` | 88 → **100** | `report()`'s DANGLING + UNTRAINED branches (synthetic `CoverageReport`) | `881d606f` |

### Earlier in the same campaign (pre-harness, additive suites)

| File(s) | What | Commit |
| --- | --- | --- |
| chord/free-sing mic screens | fake-capture stream seams (`debugChords` / `debugReadings`) → detection→display path headlessly | `be18ce9f` |
| `shared/music_io/license_gate.dart` | export-time licence gate dialog (clear / blocking / share-alike) | `cfe13dca` |
| `core/audio/mp3/mp3_reservoir.dart` | bit-budget bookkeeping (main_data_begin banking/cap, byte-exact reconstruction) | `7c22aa81` |
| `core/audio/mp3/mp3_psycho.dart` | psychoacoustic invariants (Parseval, tonality ∈ [0,1], mask ATH-floor + monotonicity) | `73da2e2a` |

---

## 6. Testing patterns that worked

- **Value semantics** (`==` / `hashCode` / `isEmpty` / `toString`) — the single
  most common gap. Round-trip suites build the structs but never compare or print
  them. Cheap, high-signal (dedup and change-detection depend on them).
- **Localized switches** — l10n label functions (`readingHintText`,
  `describeSriItem`, `_functionText`) need a `BuildContext`; a `Builder` under a
  MaterialApp with the l10n delegates reaches every arm. l10n-independent outputs
  (`"G4 · Treble"`, `"C major"`) can be asserted exactly.
- **Injected fakes over the real world** — `http.runWithClient` + `MockClient`
  for `defaultHttpGet`; the existing `TabWindowRunner` fake for the tab emitter;
  `SharedPreferences.setMockInitialValues` for `DebugService`.
- **Fake-capture seams** — a default-off `@visibleForTesting Stream<…>?` on the
  mic screens, subscribed in `initState`, with the plugin service made **lazy** so
  it's never constructed on the test path (production path byte-identical when the
  seam is null).

### Two traps caught

1. **The `?? default` line-attribution artifact.** For `x ?? this.field` on its
   own line, the coverage tool attributes the line to the *right-hand* access —
   so it stays "uncovered" until a call actually falls through the `??`. Covering
   `copyWith(bpm: X)` did **not** cover `bpm ?? this.bpm`; a no-arg `copyWith()`
   was needed. Same for `cache ?? IoSoundFontCache()`.
2. **Analyze before commit.** One push landed a CI-fatal
   `avoid_redundant_argument_values` info because analyze ran *after* the commit
   (fixed in `64f6830b`). The order is **`dart format` → `flutter analyze` →
   (only if clean) commit** — infos are CI-fatal here.

---

## 7. The unit-testable ceiling

**Scope note (corrected after the follow-up sweep):** the ceiling below applies
to the **deeply-blocked** files — the <70% native/plugin band and the big DSP
cores. It is *not* a claim that everything else is done: a first pass declared
the ceiling too early and missed a whole **83–90% pure tier** (§5's follow-up
sweep) that was in fact closeable. When re-measuring, always sweep the near-100%
band too — the cheapest wins (value semantics, enum labels, one-branch edges)
hide there, not just in the obvious 0–40% band.

With that tier now closed, every *remaining* low-coverage file needs something a
unit test structurally cannot provide. This is a boundary, not a backlog:

| Blocker | Files (examples) |
| --- | --- |
| **Native ggml / ONNX runtime** | `transcription/*` (fcpe, hubert, separate_*, crispasr_ffi_*), `tabcnn_emitter`'s `TabCnnEmitter`/`audioToTab`, `onnx_ort_*` |
| **Live plugin** (record / SoLoud) | `voice_clip_recorder`, `voice_pool`, `live_voice`, `soloud_live_voice` |
| **Isolate spawn** (`compute`) | `tabcnn_to_document.audioToTabDocument`, the CLI/roundtrip tests |
| **Process-env vars** | `soundfont_download` Windows `USERPROFILE` / `COMET_SOUNDFONT_DIR` fallbacks |
| **Big DSP core** (golden/render-tested) | `midi_render` pedal paths, `tracker_replayer`, `aec_offline`, `audio_export` |
| **Widget body** (larger UI, lower ROI) | `music_picker`, `instrument_editor`, `sample_waveform_widget`, `multi_part_canvas` |

To push past it you'd introduce fake seams into the native/plugin layers (as was
done for the mic screens and the tab runner) or accept widget-test ROI on the big
UI files — both deliberate scope decisions, not cleanup.

---

## 8. Reproducing

```bash
# from the repo root; wrap with the broken-Ruby env if pod/xcode run (see CLAUDE.md)
bash tool/coverage/run.sh          # ~45–75 min → coverage/parts/*.info
python3 tool/coverage/merge.py     # merges → coverage/merged.info + prints the report
```

Scoped single-file check (what verified each closure above):

```bash
flutter test --coverage --coverage-path=/tmp/x.info test/<file>_test.dart
# then grep DA:<line>,0 for the target SF in /tmp/x.info
```

Add `--branch-coverage` inside `run_cov` for BRDA (branch) records; `merge.py`
already merges them.
