# KlangUniversum — Curriculum & Game Plan

Music notation and harmony for children from primary school onwards (6+),
decomposed into exciting minigames. EN/DE, modularly extendable, running on
iOS/Android/Web/Windows/macOS/Linux. Notation rendering via the MIT
[crisp_notation](https://github.com/CrispStrobe/crisp_notation) library (our own).

This file tracks **what is pending and planned**. What's already built and live
is recorded in [HISTORY.md](HISTORY.md).

## 🚧 Actively working on (agent coordination — keep in sync with origin/main)

Live board so parallel agents don't collide. **Update this at every checkpoint
and push to origin/main** before/after touching shared files. Format:
`agent · task · files touched · status`.

- **opus (parity)** · 🚧 **ACTIVE — note ornaments (trill/mordent/turn).**
  Per-note attribute like articulations (crisp_notation `NoteElement.ornament`,
  drawn by `layout_marks.dart`). Adding an `ornament` field to `EditorElement` +
  wiring `buildScore`/snapshot/loadScore in **`score_document.dart`**, then an
  ornament row in the note-property palette in
  **`composition_workshop_screen.dart`** + ARBs. Ping before editing those.
  Model first.

- **opus (tracker)** · 🚧 **ACTIVE — Tracker (pattern sequencer).** Dual-audience
  tracker (ModEdit/FT2/ST3/IT spirit, touch-first, Sandbox/Studio two-skins-over-
  one-model) built ON the shipped Loop Mixer engine (`mixStems` +
  `loop_engine.dart`). Full plan: [`docs/TRACKER_HANDOVER.md`](TRACKER_HANDOVER.md).
  Worktree `../mus-tracker`, branch `feature/tracker`.
  ✅ **Slice 0 SHIPPED** (`98cdb05`): pure-Dart `TrackerEngine` (additive), 13
  tests. ✅ **Slice 1 SHIPPED** (`775fe03`): the Sandbox grid screen (instrument
  tabs + pentatonic piano-roll + looping playback + playhead), registered sandbox
  `GameInfo 'tracker'` in composition, EN/DE, 4 tests. ✅ **Slice 2 SHIPPED**:
  sfxr chiptune instruments — focused pure-Dart port of `crispaudio`'s SynthEngine
  into **`lib/core/audio/crisp_dsp/sfxr.dart`** (+ `test/sfxr_test.dart`), a
  `SfxrInstrument` on the `TrackerInstrument` seam synthesized per-note at pitch,
  and a live `zap` chiptune channel in the default band. **Settled hot files:**
  `game_registry.dart`, both ARBs. ✅ **Slice 4a SHIPPED** (`449bd6f`): sample DSP
  in `crisp_dsp/` (resampler + granular pitch-shift + formant-shift ports from
  `crispaudio`) + `SampleInstrument` + `VoiceEffect` palette (chipmunk/monster/
  deep via formant, robot via ring-mod+bitcrush — pitch-stable so samples stay in
  tune). ✅ **Slice 4b SHIPPED:** the **record-your-voice bridge** — `record`-
  plugin `VoiceClipRecorder` (mic → Float64), a runtime-swappable `voice` channel,
  and a record/effect bottom-sheet in the tracker (EN/DE). ⚠️ **Mic path is
  device-only** — verified via the tester seam (inject a synthetic clip); real
  mic needs an on-device run. ✅ **Slice 5a SHIPPED (notation bridge,
  Tracker→Score):** `tracker_notation.dart` `trackerChannelToScore` (held runs →
  tied notes decomposed to standard values, split at 4/4 bar lines) + a StaffView
  "score view" panel toggled from the app bar (the selected channel as notation).
  ✅ **Slice 5b SHIPPED (Score→Tracker import):** `scoreToTrackerCells` (quantize
  durations to the grid, top-note-of-chord, merge tied notes, snap to pentatonic)
  + `TrackerEngine.setChannelCells` + a "Load a tune" app-bar action importing a
  built-in demo melody into the melody channel. Round-trip (Tracker→Score→Tracker)
  is unit-tested — the bidirectional bridge is complete.
  ✅ **Slice 3 SHIPPED (Studio instrument picker):** `kTrackerInstruments` palette
  (4 additive + 5 sfxr) + a `tune` app-bar action → bottom-sheet picker that
  re-voices the selected channel (`setChannelInstrument`), unlocking the chiptune
  presets. ✅ **Percussion SHIPPED:** `PercussionInstrument` (each cell = a
  one-shot drum hit, `midi` encodes the `Drum`) + a `drums` channel in the default
  band; the screen gained a **per-channel grid-row model** (drum rows w/ icons for
  percussion, pentatonic pitch rows otherwise). 🚧 **Now working:** arrangement/
  order-list + Workshop↔Tracker handoff. Handover:
  [`docs/TRACKER_HANDOVER.md`](TRACKER_HANDOVER.md).
- **opus (parity)** · ✅ **idle / SHIPPED — notation-depth batch (voltas/nav, tuplets, discontiguous selection, RhythmPolicy.split).**
  Working through the tracked roadmap in
  [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) §"Notation-depth roadmap": **(1)
  voltas + navigation** (D.C./D.S./coda; element-id anchors like clef/key), **(2)
  tuplets** (ids→`TupletSpan`), **(3) slice 3 discontiguous id-set selection**,
  **(4) slice 7 `RhythmPolicy.split`**. Each = its own commit + board update;
  each touches `score_document.dart` then `composition_workshop_screen.dart`
  (`_paletteButton`) + ARBs. **(1) voltas+nav SHIPPED** (`70bca0b`, suite 615 green); **(2) tuplets SHIPPED** (`e63730e`+`daaa443`, suite 650 green); **ALL FOUR SHIPPED** — (1) voltas+nav `70bca0b`, (2) tuplets `e63730e`+`daaa443`, (3) discontiguous selection `ca52d58`, (4) `RhythmPolicy.split` `7ffe193`+`5fda285`. The element-id-anchor + reflow work closed the whole notation-depth batch on the flat model; every add is byte-identity-guarded so the kid Sandbox surface is unchanged. **Idle.**
- **opus (parity)** · ✅ **idle / SHIPPED — repeat barlines (start/end), model +
  UI** (`959f99f` + `ad85a1a`, whole suite **599 green**). Fourth element-id-
  anchored bar attribute after clef/key/time; closes the "can't notate a repeat"
  gap and — since crisp_notation expands repeats in `playbackTimeline` — affects
  playback too. Booleans → two id **sets** stamped in `_withMidScoreChanges`
  (empty-set fast path keeps goldens byte-identical); UI = two toggle items in
  the note palette (⌃). Round-trips through MusicXML. `score_document.dart` +
  `composition_workshop_screen.dart` (`_paletteButton` only) settled again.
- **opus (games)** · ✅ **idle / SHIPPED — new-minigame + creative-mode sweep.**
  Whole suite green (verified in crash-dodging **batches** — the monolithic
  `flutter test` only SIGTERM-flakes under the machine's concurrent load, not a
  real failure; single-file/batched runs are all green). 11 units, each its own
  rebased-ff commit on `origin/main`: reading binaries *Tie or Slur* (`tie_slur`)
  + *Beam or Flag* (`beam_flag`, beam/flag verified at the crisp_notation layout
  level); four new **Connect** modes (`connect_dynamics` / `connect_rests` /
  `connect_tempo` / `connect_beats`); *Find the Key (bass)* (`key_find_bass`, the
  `PianoKeyboard` shifted two octaves down); mic-graded *Sing the Interval*
  (`sing_interval`, reuses the `sing_back` harness); the 3-basket
  **Sharp/Natural/Flat** widening of `accidental_sort` at 2★ (real ♮ via
  `NoteElement.showAccidental`); *Triad or Seventh?* (`triad_seventh`, the dom7
  built app-side, no library builder); and the **Colour Melody** grid composer
  (`grid_composer`) for pre-readers. **Hot shared files touched (all settled):**
  `game_registry.dart`, `core/tuning.dart`, the ARBs, `connect_line_screen.dart`,
  `accidental_sort_screen.dart`, `key_find_screen.dart`. **Next (unclaimed):** the
  **Loop mixer** — full handover in
  [`docs/LOOP_MIXER_HANDOVER.md`](LOOP_MIXER_HANDOVER.md).
- **opus (parity)** · ✅ **idle / SHIPPED — mid-score changes, model + UI** (whole
  suite **592 green**). The full clef/key/time mid-score-change family now works
  end-to-end on the flat model via **element-id anchors** (no bar-spine flip):
  model in `685ced2`/`0e0f736`/`3b78b1d`, UI in `81a38c7`. The UI is a "Change
  from here…" item in the note-property palette (⌃) opening a compact 3-dropdown
  dialog (clef/key/time, each defaulting to "No change", pre-filled from the
  note's bar). `score_document.dart` settled; `composition_workshop_screen.dart`
  touched only in `_paletteButton` + a new dialog. **What's next (unclaimed):**
  mid-bar clef changes (`inlineClefs`) aren't modelled yet; slice 3 (id-set
  selection) and slice 7 (`RhythmPolicy.split`) remain per WORKSHOP_PARITY.md.
- **fable (loop-mixer)** · 🚧 **ACTIVE — Loop Mixer slice 10** (the last ladder
  rung): beatbox→drum card (onset+timbre classification on new additive
  rms/zcr fields in `PitchReading`, calibrated against our own synth drums)
  + jam mode v1 (echoCancel + headphones hint, chord-fit feedback). Worktree
  `../mus-loopmixer`, branch `feature/loop-mixer-3`. **Shared files:**
  `core/audio/pitch_analysis.dart` (ADDITIVE ONLY — new optional fields,
  every existing constructor/test unchanged), `loop_engine.dart` +
  `loop_mixer_screen.dart` (mine), ARBs (additive). Pull-rebase before edits.
- **fable (loop-mixer)** · ✅ **SHIPPED — Loop Mixer 2.0 complete, slices 2–9
  all on main** (final `f248ad4`); now idle, worktree removed. One session:
  **engine v2** (`5e5d81b`: GrooveSpec, data patterns, swing, A/B/C variants,
  euclid, levels) → **screen v2** (`74c5141`: swing slider, variant badges,
  level sliders, seam-timed drum fill every 4th loop) → **chord progression
  lane** (`799f2d5`: I–V–vi–IV/I–IV–V–I/vi–IV–I–V, 4-bar loop, chord-relative
  bass+chords via ChordFollower, listen.dart roundtrip reads every bar's
  root/fifth exactly) → **live engraving** (`5ad76a9`: groove_notation.dart,
  score panel via StaffView) → **share token + WAV export** (`91e9c24`:
  'KU1.' base64 GrooveSpec, serverless) → **infinite mode** (`b512be7`:
  seeded per-seam variation — breathing hats, snare ghosts, melody
  ornaments) → **sing-a-track** (`c405337`: count-in → 2-bar mic capture →
  pentatonic-quantized 'voice' card, groove_capture.dart; cells travel in
  the share token). Slice 5 stays deferred to the Tracker; slice 10
  (beatbox→drums, AEC jam mode) is the remaining unclaimed ladder rung.
  Suite: 77 tests green across the loop suites + tracker + smoke; analyze
  clean. ⚠️ Lesson for everyone: `flutter test … | tail` EATS the exit code —
  one red smoke slipped to main that way (fixed fwd `f248ad4`); use
  `set -o pipefail` when a push gates on a piped test run.
- **opus (parity)** · 🚧 **ACTIVE — Workshop editor parity.** ✅ **SHIPPED: the
  multi-part lag is fixed** (`1d9c804`, suite **513 green**, analyze clean).
  `22f9e5f` fixed single-part; multi-part still ran **~4 full engraving passes
  per rebuild × 2 frames**. The engine was never the problem — crisp_notation
  routes every interactive setter to `markNeedsPaint` and early-returns on a
  value-equal document; **the canvas defeated each guard**: (1) `MusicFonts.load`
  handed inline to `FutureBuilder` returns `Future.value(cached)` — a new
  instance every call → resubscribe → **double rebuild** (snapshot then ignored);
  (2) `PageMetrics` has **no `operator ==`**, so a fresh-but-equal instance
  forced `markNeedsLayout()` on *every* build — which also made the deep
  `document ==` walk pure waste; (3) the discarded probe `layoutMultiPartPages`
  ran per build — **measured ~155ms (4 parts × 32 notes) / ~247ms (4 × 64)**,
  i.e. *this was the lag*; (4) `buildMultiPart()` was the one un-memoized
  builder; (5) **`_onMpDragUpdate` was missed by `22f9e5f`** → ~4 layouts *per
  pixel* on drag. Verified with temporary counters through the real rebuild
  path: 60 idle rebuilds now do **0 probes / 0 geometry misses / 0 build
  misses** (was 60 each, doubled). `MultiPartCanvas` is now **stateful** (holds
  the font future + geometry cache) — mind that if you're mid-edit on it.
  · ⚠️ **Trap for every agent here:** running `dart format` in a **fresh
  worktree before `flutter pub get`** makes it default to the **new tall style**
  (no `.dart_tool/package_config.json` → can't read `sdk: ^3.5.0`), which
  reformats the *whole repo* and **adds trailing commas that the correct style
  then treats as force-split — so a second `dart format` cannot undo it**. It
  turned an 8-line edit into a 409-line diff on the hot screen file. **Always
  `pub get` first.**
  · **Next:** lossless save/round-trip + export honesty, then plan the
  measure-spine refactor. **Maintainer decision (2026-07-16): two shelves —
  Sandbox (kid surface, unchanged) + Studio (full capability).** So the
  measure-spine + inspector are green-lit, and any depth that can't hide behind
  the shelf toggle should be viewed with suspicion.
  · Concepts + order of attack: [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) (conceptual layer above
  WORKSHOP_PLAN.md's phase log). Finding: the ~28 gaps vs. full notation programs
  reduce to **4 causes**, 3 of them ours — (1) **measures are derived, not real**
  (flat `EditorElement` list + `_packMeasures`) which alone blocks tuplets/voices/
  mid-score key-time-clef-tempo/repeats/measure-ops/cross-bar splitting *and*
  forces index-range selection; (2) no input-mode separation; (3) no inspector
  surface; (4) the canvas defeats crisp_notation's paint-only fast paths.
  **crisp_notation already models nearly all of it** — the block is app-side.
  · ⚠️ **@anyone touching the Workshop:** `22f9e5f` fixed single-part hover
  (now correctly **0 layouts**), but **multi-part is still ~4 full layouts per
  rebuild × 2 frames** — `MusicFonts.load` handed inline to `FutureBuilder`
  (fresh `Future` every build → double rebuild; snapshot then ignored),
  `PageMetrics` lacking `==` (forces `markNeedsLayout` on *every* build),
  a discarded probe layout, unmemoized `buildMultiPart()`, and **`_onMpDragUpdate`
  (`:511`) missed by `22f9e5f`** → ~4 layouts *per pixel* on multi-part drag.
  All small fixes; I'm taking them next in `multi_part_canvas.dart` +
  `composition_workshop_screen.dart` (hot — coordinate before you edit).
  · ✅ **SHIPPED — save → reopen is lossless + export honesty** (`20fa35e`, suite
  **528 green**). `loadScore` kept only `pitches.first` and dropped ties,
  articulations, dynamics and the pickup — all things `buildScore` already
  writes — so **Save → reopen silently destroyed work** (every chord collapsed to
  one note). It's now the exact inverse for everything the element stream can
  hold; the 5 new tests fail against the old code with exactly that data loss,
  incl. through MusicXML (the real Save/Open path, which turns out to preserve
  everything the editor can represent). Also: every export but MusicXML/`.mxl`
  wrote the **active part only** with no hint — crisp_notation has a multi-part
  *writer* for MusicXML alone though every text format has a multi-part *reader*,
  so the asymmetry is library-side and a real fix is a **crisp_notation ask**.
  Until then the export sheet says "All N parts" or "Only «part» — this format
  cannot hold several parts". Localized de/en.
  · 🚧 **NOW: the measure-spine refactor (Cause 1) — planned, slice 0 landed.**
  Design + slice list in [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md). Three
  corrections worth knowing if you touch the Workshop: (1) **the screen is
  already id-based** — `selectIndex`/`measureIndexOf`/`moveByIdToMeasure` have
  **zero callers in `lib/`**, so the refactor barely touches it; (2) it lands
  **on `main` in ~9 invisible slices, NOT a long-lived worktree** (353 commits/7
  days makes a long branch unmergeable; spine+reflow is byte-identical to
  `_packMeasures`, so each slice is externally invisible); (3) **no command/undo
  model** — instead lift the snapshot stack to `MultiPartDocument` (so removing
  an instrument stops being unrecoverable) and bound it. **Slice 0 = golden
  characterization tests** pinning today's exact packing
  (`test/score_document_packing_golden_test.dart`, 14 tests), including two
  **known-wrong** goldens (a whole note makes an over-full 3/4 bar; an
  overflowing note short-fills the previous bar instead of splitting+tying) so
  the refactor changing them is loud, not a silent test update.
  · ✅ **SHIPPED — slice 1: `_packMeasures` → pure top-level `reflow()`**
  (`b2df911`, model suite **134 green**, goldens byte-identical). The packer was
  an instance method reading `this.timeSignature`/`this.pickup`; it's now
  `reflow(elements, {timeSignature, pickup})` with all 3 call sites updated
  (buildScore + both grand-staff staves). This is the seam slice 2 builds on — a
  `RhythmPolicy.spill` document will reflow its stream through exactly this. New
  `reflow_test.dart` (10 tests) exercises it in isolation and locks the contract
  slice 2 needs: **reflow preserves element identity + order** (re-bars the same
  instances, never clones/reorders). Touched **only `score_document.dart`** + a
  new test.
  · ✅ **SHIPPED — mid-score clef changes; SLICE 2 RETIRED** (`685ced2`; 112
  focused tests green + goldens byte-identical + analyze clean — full suite not
  run to completion, the shared box was thrashing at load ~186 from concurrent
  Xcode + agents, OOM-killing test runs; the empty-map fast path makes a
  regression on untouched docs structurally impossible; CI runs the full suite).
  **The course-correction:** doing slice 1 revealed the planned slice 2 (flip
  `_elements` → `List<Bar>` source of truth) means rewriting **~60 index-based
  mutation sites at once** and is the *wrong* architecture for spill mode — bars
  are reflowed every edit, so they have no stable identity to anchor to. The
  low-risk mechanism is to **anchor bar-attributes to an element id** (side-map
  on the flat doc) and let `buildScore` stamp them after reflow; the id rides
  re-barring for free. Shipped that via clef: `_clefChanges: Map<String,Clef>` +
  a post-reflow pass, wired through undo/clearAll/loadScore (save→reopen keeps
  it).
  · ✅ **SHIPPED — mid-score KEY changes** (`0e0f736`, 71 focused tests green,
  goldens byte-identical). Same element-id-anchor mechanism as clef (no capacity
  impact); generalized the post-reflow pass to `_withMidScoreChanges` handling
  clef **and** key in one walk, shared `_anchoredIn<V>`, fast-path now checks
  both maps empty so byte-identity still holds. `setKeyChangeAt` + loadScore
  recovery mirror clef; test renamed → `mid_score_change_test.dart` (+6 key
  cases incl. clef+key coexisting on one bar). **Next: mid-score TIME changes —
  the one with a wrinkle:** `reflow` must switch bar capacity at the anchor
  (clef/key don't), so it's not a pure post-reflow stamp. A first-class `Bar` is
  deferred to slice 7 (`RhythmPolicy.split`, Studio), where bars keep identity.
  See the refinement box in [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md).
  · ✅ **SHIPPED — wider meters + full circle of fifths + picker crash-guard**
  (`7d954be`, suite **549 green**). The time picker was capped at 2/4·3/4·4/4 and
  the key picker at ±4 fifths — but the packer sizes bars by
  `timeSignature.toFraction()`, the engine beams 6/8 as 3+3 via `beamGroups()`,
  and `KeySignature` accepts ±7, so both were **UI caps only**. Added 2/2, 3/8,
  6/8, 9/8, 12/8, 5/4, 6/4 and the full circle of fifths (collapsed dropdowns, so
  the kid Sandbox surface is unchanged). Also closed a **latent debug crash of
  the same class**: `DropdownButton` asserts its value is among items, so opening
  a file whose meter — or, via the now-lossless `loadScore`, an odd pickup —
  falls outside the offered set threw; both `_dropdown` and the raw pickup
  dropdown now self-heal by surfacing the current value. **32nd/64th deliberately
  NOT added** (they'd clutter the always-visible value strip → Studio, per the
  two-shelves design). · ⚠️ format-trap reminder still applies: **`flutter pub
  get` before any `dart format`**, and format only *your* files (a blanket
  `dart format test/` reformats the ~7 pre-existing non-canonical files and
  churns other agents' work).
  · ✅ **SHIPPED in crisp_notation — the large-score layout ceiling (G).** User
  confirmed scores reach 30+ bars, so I measured the layout cost curve: a 4-part
  × 100-bar score took **~12.8s per layout**, and the cost was **not** the
  per-measure "natural" pass (near-free) — it was **justification**, which
  bisected `spacingStretch` for a **fixed 24 full system-layouts per system**.
  Replaced all three copies (`layoutSystems`/`layoutGrandStaffSystems`/
  `layoutStaffSystemSystems` — the last is our multi-part path) with a shared
  Illinois regula-falsi solver: **3.19 layouts/system avg (worst 14) vs 12.24**,
  same accepted result. On `crisp_notation@main` **`198ef17`** (core 1446 +
  Flutter 301 green); 6 justified-system goldens re-blessed (<1.5%, visually
  identical, barlines stay aligned). **NB the app won't see it until the local
  `../crisp_notation` clone reconciles — it's behind origin with another agent's
  uncommitted work, so I did NOT pull it; mus CI (public `@main`) already has
  it.** This was the one remaining perf ceiling I couldn't fix app-side.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop performance.** The
  editor "severely lagged" on desktop: the root cause was **`onHover` calling
  `setState` on every pointer-move pixel** → a full-screen rebuild (42-key piano +
  all rows) per pixel. Fixes (all in `composition_workshop_screen.dart`): (1)
  **guarded hover** — `_onHover` only rebuilds when the *quantized* `StaffTarget`
  changes (the ghost snaps to lines/spaces anyway, so pixel updates were pure
  waste; `StaffTarget` has value equality), cutting hover rebuilds ~10–50×; (2)
  **cached the piano widget** (`late final _pianoKeyboard`) — its config is
  constant, so Flutter now skips rebuilding all 42 keys on every editor setState;
  (3) **`RepaintBoundary`** around the canvas + the piano dock so live-drag /
  ghost / caret repaints stay local (don't repaint the whole screen). Analyze +
  23 workshop widget tests green, no behaviour change. · ⚠️ **@opus (g6)
  follow-up:** `MultiPartCanvas.build()` runs a full `layoutMultiPartPages` probe
  **+** `buildMultiPart()` (unmemoized) **+** `MultiPartView` re-layout **every
  build** — 3 layout passes per rebuild in multi-part mode. It has no `onHover`
  so it's per-interaction not continuous, but memoizing `buildMultiPart`
  (invalidate on edit) + caching the probe would make multi-part editing much
  snappier.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop file I/O overhaul.**
  (1) **Fixed macOS pickers** — added `com.apple.security.files.user-selected.
  read-write` to both `.entitlements` (the app is sandboxed; without it the
  open/save dialogs were blocked). Verified in the built `.app`. (2) **Unified**
  the ⋮ menu to one **Open…** + one **Export…** (was one item per type). (3)
  **Many more formats**: import MusicXML/`.mxl`/MIDI/ABC/MEI/`**kern`/MuseScore
  (`.mscx`/`.mscz`)/GuitarPro (`.gp`/`.gpx`); export those + LilyPond/Braille/SVG/
  PNG. Pure-Dart parsers → web build ✓, macOS build ✓. Pure `importScore()` +
  `kExportFormats` unit-tested. · ⚠️ **@opus (g6): I edited the I/O section of the
  hot `screens/composition_workshop_screen.dart`** (imports, top-level
  `importScore`/`kExportFormats`, `_open`/`_export`/`_showExportSheet`, the ⋮
  menu) — all call `_doc.buildScore()`, so your `_doc → _mpd.activePart` getter
  swap stays compatible; `git pull --rebase` (diff is localized, away from the
  field/canvas).
- **opus (g6)** · **idle / SHIPPED — G6 P4e (both crisp_notation contracts wired)**
  (on origin/main, whole suite **480 green** + analyze clean). C11 + C12 landed
  in crisp_notation, now consumed:
  ✅ **multi-part export** — Workshop MusicXML/`.mxl` writes ALL parts via
  `_musicXmlExport → multiPartToMusicXml(_mpd.buildMultiPart(), partNames:)`
  (was active-part only); round-trip tested. One part unchanged.
  ✅ **in-place editing** — `MultiPartCanvas` now renders
  `InteractiveMultiPartView` (was select-only `MultiPartView`); the screen wires
  `onStaffTap(part,target)`→setActive+place, `onHover`→placement ghost,
  `onElementTap`→cross-part select, `onElementDrag*`→setActive+moveById repitch,
  `highlightedIds`←`_mpd.selectedGlobalIds`. **The P4b v1 two-view constraint is
  lifted** — full note entry directly on the multi-instrument score. Remaining
  crisp_notation follow-ups — **now DONE too** (2026-07-15): C12b `EditorCaret`
  + C12c `ElementRegionController` shipped in crisp_notation (`afc283a`, pushed
  to its `main`) and wired here (caret + marquee in multi-part mode); C12a live
  drag preview done app-side via suppress+ghost. Multi-part MEI/ABC writers
  deliberately deferred (MusicXML covers interchange; hardened-writer refactor
  risk > value). **G6 is feature-complete, both repos on main, whole suite 482
  green.** See the parity section below for the full breakdown.
- **opus (g6)** · **idle / SHIPPED — G6 multi-instrument authoring P4a–P4d**
  (all on origin/main, each its own commit, whole suite **477 green** + analyze
  clean). Built on public `MultiPartScore`/`MultiPartView`.
  ✅ **P4a** `model/multi_part_document.dart` (+18 tests): `List<ScoreDocument>`
  container; `buildMultiPart()` pads parts to a shared bar grid + namespaces
  element ids per part (`p0:`,`p1:`…) for unambiguous cross-part taps
  (`selectByGlobalId`); per-part clef/name/transposition (transposing parts
  tagged → `atConcertPitch`); bracket/barline groups re-indexed on removePart.
  ✅ **P4b** `widgets/multi_part_canvas.dart` (+3 tests) — full-score
  MultiPartView surface (probes `layoutMultiPartPages` for a one-page height,
  `kidsScoreTheme`, viewport-bound width) — **and screen integration**: swapped
  the `_doc` field for `_mpd` (MultiPartDocument) + `ScoreDocument get _doc =>
  _mpd.activePart` (zero call-site churn); canvas swaps to the full score when
  partCount>1; **parts strip** (add · select/highlight · per-part ⋮: clef ·
  transposition C/B♭/E♭/F/A · brace-with-below · remove), localized de/en (+4
  widget tests). ✅ **P4d** multi-part **import** — `loadMultiPart` +
  `importMultiPart` (MusicXML/`.mxl`/ABC/MEI/`**kern` seed every part; others
  fall back single-part); "Open…" now opens a full score into all its parts
  (+4 tests). ⚠️ **Gap = multi-part EXPORT** (writes active part only):
  crisp_notation has no public multi-part MusicXML writer yet (only
  `scoreToMusicXml`/`grandStaffToMusicXml`) — **a crisp_notation ask (P4e)**; rich
  in-place editing directly on `MultiPartView` is the other P4e stretch. NB
  @workshop→games: your I/O overhaul + my `_doc→_mpd.activePart` getter compose
  cleanly (my `importMultiPart` sits beside your `importScore`).
- **opus (primers)** · **docs only** — **Workshop→crisp_notation parity assessment**
  (2026-07-14, in `WORKSHOP_PLAN.md`): verified crisp_notation advanced ~40 commits;
  **mus fully compatible** (429 green against `@main`, local ff'd). Finding:
  Workshop has adopted **all** landed editor contracts (C1–C10 incl. your live
  drag); the one remaining major gap is **G6 multi-instrument**, now **unblocked**
  by public `MultiPartScore`/`MultiPartView` — the old "needs a private Part
  model" CI note is moot. Recorded the G6 approach (`List<ScoreDocument>` →
  `MultiPartScore(parts:)` → `MultiPartView`) + smaller engraving wins
  (`Measure.actualDuration`, metric-aware beaming). **Did NOT touch
  `lib/features/workshop/**`** — over to you, @workshop→games. Only edited docs.
  **Wrote a comprehensive G6 handover → [`docs/WORKSHOP_G6_HANDOVER.md`](WORKSHOP_G6_HANDOVER.md)**
  (real ScoreDocument + MultiPartScore/MultiPartView API signatures, the two-view
  `MultiPartDocument = List<ScoreDocument>` architecture, phased P4a–e plan, all
  the gotchas) so a fresh agent can take G6 in its own worktree without colliding.
- **opus (workshop→games)** · **idle / SHIPPED — live drag + 5 new minigames** (all
  on origin/main, each its own commit + CI-green). **crisp_notation C10a+C10b** (the
  live drag: `suppressElementIds` clean hide + `dragPreviewOpacity` view-painted
  drag) + the Workshop **live drop caret** (`computeDropSlot`). Then 5 tap-robust
  minigames, each = one `GameInfo` + a `kStarThresholds` bracket + EN/DE ARB +
  screen + widget test (consistency + whole-project analyze green):
  **Which Clef?** (`reading.clef.*`, bare clef → T/B, +A/T at 2★),
  **Whole or Half Step?** (`reading.tone.*`, tone vs semitone on the staff + heard,
  +bass at 2★), **Same or Different?** (`pitch.hear.*`, ear discrimination, subtler
  at 2★), **Dotted or Not?** (`note_values.dot.*`, two-basket sort on the
  augmentation dot), **Ascending or Descending?** (`pitch.hear.*`, a 3–4 note run's
  direction, 4 notes at 2★). Next agent: more of the backlog (bass-clef variants,
  Louder/Softer?, Count the Notes).
- **opus (primers)** · **idle / SHIPPED (round 3)** — Learnability & UX #1–#3
  all on `origin/main`, full suite (429) green:
  **#1 module-primer fallback** (`04dc09a`) — `kModulePrimers` +
  `helpPrimerFor(game)` (own primer ?? module primer); `TutorialGate`'s reopen
  "?" uses it, so **all 100 games offer help** while auto-show stays curated
  (tests assert 100% coverage + both paths).
  **#3 mascot speech-bubble presenter** (`c0bca5d`) — `RoundHeader` shows a
  `MascotPrompt` (mascot + bubble reading the prompt) in place of the plain
  prompt; `showMascot:false` falls back for tight layouts (`read_voice` opts
  out). FeedbackLine keeps its reactions (unifying them into the header would
  need per-screen correctness — a follow-up).
  **#2 `GameAppBar` roll-out** (`a04498f` + `a5f8392`) — **~79 game screens**
  now use `GameAppBar` (the simple-form 57, then 22 more incl. screens with
  existing app-bar `actions:` and multi-line conditional titles), so the **sound
  toggle is in every game's bar**. Only module-browse, truly custom bars, and
  songs-management utility screens stay on plain `AppBar`. Fixed one over-broad
  test finder (`new_games_test` → count `MusicGlyph`, not `InkWell`).
  **#B unified single reacting mascot** (`e8e8136`) — the mascot now PRESENTS
  and REACTS in `RoundHeader`: it gained `correct` (bool?) driving
  `MascotPrompt`'s mood, and `FeedbackLine.showMascot` now defaults **false**
  (text-only feedback, no duplicate mascot). All **56** FeedbackLine screens
  pass their correctness value to `RoundHeader` too; the 4 ordering games with
  no FeedbackLine keep an idle presenter. **Learnability & UX section: complete.**
  ✅ FYI all agents: the earlier `../crisp_notation-public` `suppressIds` WIP that
  broke local mus compiles is now **landed** (crisp_notation `74fa972`, incl.
  `c374b09 suppressElementIds`) — local mus tests compile again, no stash needed.
- **opus (primers)** · **idle / SHIPPED (round 2)** — all four handover
  follow-ups on `origin/main` (`96275aa`), full suite (426 tests) green:
  (1) **8 ★ per-game primers** — bass-clef reading, ledger lines,
  sharps/flats, steps vs skips, intervals, key signatures, time signatures,
  chord symbols — each hung on its game (`note_reading_bass`, `ledger_leap`,
  `accidental_sort`, `step_skip`, `interval_ear`, `key_sig`, `time_signature`,
  `chord_chart`); `_notes()` gained `keySignature/timeSignature/chordSymbols`
  so those examples engrave the real glyphs. **21 primers now covered by the
  `tutorial_test` loop.** (2) **App-wide "?" reopen** — `TutorialGate` overlays
  a small help FAB whenever a game has a primer (no per-screen edits; no game
  uses a FAB so no collision). (3) **`GameAppBar`** — reusable title +
  app-wide `SoundToggle` + optional "?" bar; adopted on `accidental_sort` as a
  first example (broader per-screen adoption is a safe mechanical follow-up).
  (4) **Mascot presenter** — a small idle `NoteMascot` in `RoundHeader`, keyed
  by prompt so it greets each new question (size 16 / inline, so no tight
  layout overflows; opt-out via `showMascot: false`). ⚠️ noted-not-touched:
  `test/play_along_test.dart` has 4 pre-existing `require_trailing_commas`
  infos (format-vs-lint; another agent's in-flight file) — left alone to avoid
  a collision.
- **opus (primers)** · **idle / SHIPPED** — authored zero-knowledge **tutorial
  primers for the remaining 8 modules** (harmony, composition, cello, guitar,
  songs, keyboard, transpose, drums) per `TUTORIAL_PRIMERS_HANDOVER.md`, on
  `origin/main` (`0ce30f0`), CI-green locally (analyze clean, all primer +
  registry-dependent tests pass). Each hung on its module's **entry game** via
  `GameInfo.tutorial` (harmony_quiz, free_sing, cello_tuner, guitar_play_along,
  song_book, keyboard_play_along, concert_pitch, drum_read); EN+DE (B=H);
  `_notes()` gained a `clef:` param so cello/drum examples engrave on the bass
  clef. **All 13 module primers now exist and are covered by the
  `tutorial_test` build/render loop.** Still open (from the handover): the ★
  **per-game** primers (bass-clef reading, intervals, key sigs, time sig,
  cadences…); a shared **`GameAppBar`** with the "?" reopen button; mascot →
  presenter before the question.

- **opus (UX/tutorials)** · **idle / handed over** — **Learnability & UX push**
  shipped to `origin/main`, CI-green: (1) global **sound on/off** toggle
  (`AudioService._play` gate + `SettingsService.soundOn` + `SoundToggle` on Home
  & Settings) + a **speaker-route silence fix** (`configurePlaybackRoute`);
  (2) **mascot alive** — one-shot idle greet + blink in `note_mascot.dart`;
  (3) **tutorial system** — framework (`lib/shared/tutorial/`) + `GameInfo.tutorial`
  hook + `tutorial_gate.dart` (`gameRoute` auto-shows on first module-browse
  visit, gated by `autoShowTutorials` which only `main()` enables) + **5 module
  primers** (reading/values/measures/scales/chords). **Handover for authoring the
  rest of the primers → [`TUTORIAL_PRIMERS_HANDOVER.md`](TUTORIAL_PRIMERS_HANDOVER.md).**
  Still open: primers for the other 8 modules; a shared **`GameAppBar`** (to carry
  the "?" reopen + make the sound toggle app-wide); mascot → presenter before the
  question. ⚠️ note: `autoShowTutorials` defaults OFF so it never disturbs widget
  tests — only `main()` turns it on.
- **opus (this agent)** · **idle** — all this session's work is on `origin/main`,
  CI-green **and deployed live** (Vercel cap reset). Shipped: the
  **crisp_notation-public alignment** (+ hardcoded-path fix), the **shared game-test
  harness** (`useGameSurface`/`pumpGame`), and 6 games/features on crisp_notation's new
  APIs — **Roman Numerals**, **Strong Beat**, **Chord Chart**, **Handwritten-notes
  (Petaluma) theme**, and all 3 **SATB reading games** (Read / Which / Hear the
  Voice, shared `note_reading/satb_voicing.dart`) — then **widened** them: SATB
  now spans several **major keys**, and Roman Numerals gained **minor keys +
  first/second inversions** (figures) at 2★. Checked OMR on crisp_notation@main (v0.9):
  done there but recognition is native FFI + a GGUF model (not web); only the
  tokens→Score parsing is web-safe (see the OMR item below). **Batch of quick
  web-safe games — DONE, all on origin/main and CI-green** · touched
  `game_registry`, `core/tuning`, ARBs, `features/games/**` · **idle /
  last-shipped**. Shipped this batch (7): **Longest First** (note-value
  ordering), **In the Scale?** (C-major membership swipe), **Connect the Steps**
  (interval↔number, 3rd Connect-the-Notes mode), **High or Low?** (pitch-direction
  sort), **Sharp or Flat?** (accidental-sign sort), **Higher or Lower?**
  (melodic-direction ear), **Step or Skip?** (melodic-motion reading). All in
  [HISTORY.md](HISTORY.md#gamified-formats--shipped). Also unblocked shared main
  twice (formatted the workshop agent's test files failing CI's lint/format).
  **Next agent:** the full idea backlog is in the "Ideas backlog" section below —
  pick from there.
  ⚠️ **For all agents — notation theme migration (just landed):** every
  `CrispNotationTheme.kids` in `lib/features/**` was replaced by **`kidsScoreTheme`**
  (from `shared/score_theme.dart`), so the Settings "Handwritten notes" toggle
  can swap Bravura↔Petaluma app-wide. **New StaffView/MultiSystemView code should
  use `kidsScoreTheme`, not `CrispNotationTheme.kids`.** (Workshop files were left
  untouched — adopt it there if you want the toggle to reach the editor.) If you
  hit a merge conflict on a `theme:` line, keep `kidsScoreTheme`.
  ✅ **For all agents — staff-based game tests:** mus CI tracks `crisp_notation@main`,
  so its live rendering (caret/drag/beaming/voices…) can push tap/drag targets
  off CI's small surface and throw `getCenter`/`_getElementPoint` — green locally,
  red on CI. **Fix:** `import 'support/game_test_support.dart';` and call
  `await useGameSurface(tester);` first (or `pumpGame(tester, home, sri: sri)`),
  which lays the screen out on a generous surface. Don't pin the crisp_notation ref —
  the workshop agent needs `@main`'s C-contract APIs.
- **opus (AEC Tier 3b, worktree `../mus-aec`)** · **idle / last-shipped** —
  shipped **AEC Tier-3b milestones (a)–(d)**. `native/aec/` is now a real
  **Flutter FFI plugin** (miniaudio MIT-0 duplex host + our **cleanroom C port**
  of `echo_canceller.dart` — dropped BSD-3 SpeexDSP to keep the tree MIT).
  (a)(b): offline ERLE cross-check + engine int16 test + **BlackHole loopback
  ≈44 dB ERLE** live check. (c): app-side `AecEngine` seam in
  `MicrophonePitchService` behind an abstract interface (fake-driven test) —
  app never imports the plugin. (d): 5-platform plugin packaging (podspecs +
  forwarders + per-OS CMake/gradle; `ma_pcm_rb` rings for MSVC portability),
  verified by an **isolated `aec-native` CI** (native lib + offline tests +
  example `flutter build`) **green on all 5 platforms** (desktop trio + iOS +
  Android; iOS needed the miniaudio TU compiled as ObjC `.m`). **Now wired into
  the app** behind a **web-safe capability check**: `core/audio/aec_capability.dart`
  conditional-exports a `dart:ffi`-free stub on web and a `NativeAecEngine`→app
  `AecEngine` adapter elsewhere, so `flutter build web` (deploy) is unaffected
  (verified). `native/aec` is now an app path dep; `aec-native.yml` stays
  paths-filtered. **Remaining: (e) on-device tuning** (iOS/Android hardware; DTD/
  residual or SpeexDSP only if needed). Detail: `native/aec/README.md`,
  `AEC_TIER3B.md`.
- **opus (play-along/AEC, earlier)** · **idle / not actively editing** — shipped
  the **songbook browse/reorder UI**: a Songbooks section in `song_screen.dart` +
  new `songbook_screen.dart` (drag-reorder via `onReorderItem`, add-songs
  picker, remove-from-book, rename/delete) + ARB keys; 19 widget/unit tests
  green. Before that, the 4-task batch: (1) **Free Sing → Song Book** (sung melody → Score, `dd8150a`),
  (2) **play-along Easy/Medium/Hard** difficulty (`4913b9d`), (3) **tuner
  upgrades** (A4 415/440/442 + guided per-string for cello/guitar/violin,
  `f89ce42`), (4) **Songbook collections foundation** (`SongCollection` grouping
  model in `user_songs_service.dart`, CI-safe, no OMR, `fefa17a`). All green on
  origin/main. Earlier shipped: 4 scroll views, backing+platform AEC, metronome,
  tempo, play-along+chord SRI, tunes, robustness suite, AEC 3a/3b-design.
  Follow-ups open: a browse/reorder UI on top of the new collections model; AEC
  Tier-3b native plugin (design in `AEC_TIER3B.md`).
- **claude (`feature/score-workshop`, worktree `../mus-workshop`)** · Composition
  Workshop = a full touch+desktop score editor on `ScoreDocument`. Shipped:
  editor shell · multiline canvas · dynamics/articulations/ties palette (anchored
  dropdown) · range select + move/copy/cut/paste · open MusicXML/MIDI · wired
  crisp_notation **C1–C5** (staff-tap · hover ghost · drag-to-move · grand staff) ·
  **perf memoization · sweepable piano · one-row app bar · physical-keyboard
  entry · chord mode · slurs · multi-verse lyrics · hairpins · pickup/anacrusis ·
  caret · fixed staff-tap entry (place-not-move) · live-drag ghost · (i)
  shortcuts sheet · exit guard · viewport-bound width** · big unit+widget suite.
  ✅ **crisp_notation C7 + C8 landed** (`2342565`) and are **used**: **marquee-select**
  (⛶ → `ElementRegionController.elementIdsIn`), **fine drag-reorder** (horizontal
  drag → exact slot via `elementRegions` reading-order; vertical → re-pitch), and
  **SVG/PNG print-export** (`exportScoreToSvg`/`Png`). Synced local crisp_notation-
  public to public `main`. Workshop feature-complete for the planned scope.
  ✅ **Play Along — ScoreEditorController adopted.** (1) **Follow-cursor:** the
  notation view owns a `ScrollController` + `ScoreEditorController`
  (`attachViewport`+`scrollToNote`, rects from an `ElementRegionController`) so the
  staff auto-scrolls to keep the active note ~⅓ down the viewport. (2) **Practice
  loop:** tap two notes → a loop band (`setLoop`→`loopRange`) + the engine wraps
  musical time back to the loop start each pass, re-arming its notes; tap again to
  clear. Engine loop is unit-tested. (3) **Per-note error marks:** missed notes
  get an `EditorMark` (`errorOverlay`) coloured by why — blue flat · orange sharp
  · red never-on-pitch — so a learner sees which notes to drill. · touched
  `lib/features/games/playalong/play_along_screen.dart`, `core/audio/play_along.dart`
  · Also **adopted `kidsScoreTheme` in the Workshop** so the Handwritten-notes
  toggle reaches the editor.
  ✅ **Live drag — C10a + C10b landed & wired (the real note follows the
  pointer).** Shipped two additive inputs on `MultiSystemView`/
  `InteractiveGrandStaffView` to public `crisp_notation@main`: **`suppressElementIds`**
  (C10a — `LayoutPainter` skips a note's whole glyph; clean theme-independent
  hide) and **`dragPreviewOpacity`** (C10b — the view suppresses the dragged
  element and re-paints the *real* glyph translated to follow the pointer,
  snapped to pitch). The Workshop now passes `dragPreviewOpacity: 0.85` and
  **dropped its suppress + ghost drag bookkeeping** — the note itself (stem,
  accidental, flag, ledgers) moves with the cursor. Painter refactor left all
  122 goldens unchanged; pixel + gesture tested. · touched crisp_notation
  `layout_painter.dart` / `multi_system_view.dart` /
  `interactive_grand_staff_view.dart` (+ CONTRACT/CHANGELOG) and mus
  `composition_workshop_screen.dart`. Whole-project analyze clean, workshop
  widget tests green. **C10 (a+b) complete — no app-side drag fake remains.** ·
  **idle** (all shipped to origin/main) · detail:
  [WORKSHOP_PLAN.md](WORKSHOP_PLAN.md).
- _last shipped_: **Cello Play It** (mic grading in the Cello Corner) +
  play-along CI fix (colours ride `theme.elementColors`, not the private-only
  `MultiSystemView(elementColors:)` param); and **Workshop P0/P1/P2a** (About
  screen, editor foundation, caret/selection/transpose/accidentals/key).
  origin/main green + deployed.

## Principles

1. **Minigames, not lessons.** Every skill is drilled through a game with
   rounds, scores and 1–3 stars — same loop as Space Math Academy and
   WortUniversum.
2. **SRI everywhere.** Every first-try answer feeds the SM-2 engine under
   `<module>.<skill>.<detail>`. The home-screen review button drills due
   items; the Karteikasten visualizes progress.
3. **Kid-first interaction.** crisp_notation's kid theme (bold lines, ≥44 px hit
   targets), generous tap slop, no time pressure in level 1 of any game.
4. **Modular i18n.** All strings in ARB (EN/DE); a new module = registry
   entry + ARB keys + game screens. German conventions respected (B = H).
5. **Everything MIT** (font OFL). No LGPL anywhere — audio via
   `audioplayers`/`flutter_soloud` + permissively-licensed samples, never
   FluidSynth.

## Curriculum map

The module/skill structure and the games that fill it. Games already shipped are
listed for scope; `*later:*` italics mark planned extensions within a module.

| # | Module | Skills (SRI namespace) | Games |
|---|--------|------------------------|-------|
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo • Count the Beats • Sort the Beats • Connect the Symbols |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody`, `.dictation` | Reading Quiz ×2 • Place the Note ×2 • Melody Echo • Melody Dictation • Note Match • Note Order • Line or Space? • Falling Notes • Connect the Notes • Ledger Leap |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective • Beat Runner • *later: percussion-backed meter, tempo ramps, syncopation* |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? • Sound Echo • Follow the Conductor • Key Detective |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence`, `.hear` | Function Quiz • Cadence Workshop • Hear the Function |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord`, `.grand` | Find the Key • Key Quiz • Echo Keys • Play the Melody • Chord Grip • Grand Staff • Falling Keys |
| 8b | **Gitarren-Ecke** (guitar corner) | `guitar.string`, `guitar.fret` | Open Strings • Read the Tab • *later: bass tuning, fretboard-tap "find the fret", techniques (bends/slides/HO-PO), chord-grip diagrams* |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book (public-domain children's songs, real notation + lyrics, karaoke cursor) • Name That Tune • **Import**: MusicXML (paste or file pick), ChordPro, monophonic MIDI • *out of scope: polyphonic MIDI (transcription problem)* |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective • Question & Answer • My Melody (free-composition sandbox → saves to Song Book as MusicXML) • *later: melody completion with choices, cadence-based accompaniment* |

**Instrument corners** are the modular-extension pattern proven by the cello
module: a data table (string/finger map), instrument-specific games reusing the
shared machinery, and the right clefs (the library supports all four). The
**guitar corner** is the same recipe on **tablature** (crisp_notation `TabStaffView` +
`Tuning`). A violin/viola corner is the same recipe again (violin: G/D/A/E
strings, treble clef; viola: alto clef); a bass corner reuses the guitar recipe
with `Tuning.standardBass`.

## CrispNotation capabilities → new ideas

The crisp_notation library has grown well past what the app currently uses. **As of
2026-07-16 both the mus path-dep and CI resolve `crisp_notation`
(`CrispStrobe/crisp_notation@main`)** — pubspec points at `../crisp_notation/...`
and the CI/deploy workflows check the public repo out to `crisp_notation/`, so
local and CI are aligned and the new APIs are usable everywhere. The library now
lives in a single local clone at `../crisp_notation`; the earlier
`crisp_notation-public` symlink and the private clone are gone. Verified new
capabilities and what they unlock:

- **Teaching overlays on `StaffView`** (`showNoteNames`, `showBeatNumbers`,
  `showMeasureNumbers`). **Which Beat?** is shipped — it uses `showBeatNumbers`
  as a fading scaffold (beat numbers under the staff at level 1, gone at 2★).
  Still open: a native `showNoteNames` fading scaffold across the reading games.
- **ABC notation import/export** (`scoreToAbc`, ABC reader). **Both shipped** —
  ABC **import** in the Song Book (`scoreFromAbc`) and ABC **export** from the
  Composition Workshop (`scoreToAbc` → copy to clipboard). Still open: a
  "type-a-tune" mode.
- **Chord identification** (`identifyChord`, `chordSymbolFor`). **Name That
  Chord** and **Chord Builder** are shipped
  ([HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — the builder grades
  **any voicing** (root position or inversion, any octave) via `identifyChord`.
  Still open: chord symbols over the Song Book (low value — the built-in songs
  are monophonic).
- **`StaffSystemView`** (N-staff systems). **Duet** is shipped — read the
  highlighted part of a two-staff system (lower staff switches to bass clef at
  2★). Still open: SATB chorale reading, a richer Grand Staff.
- **Transposing instruments + concert-pitch toggle.** **Shipped** — a new
  **Transposing corner** with **Concert Pitch**
  ([HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)): read a written note for
  a B♭/E♭/F instrument, name the concert pitch that sounds (crisp_notation's
  `transposeBy` does the maths). Still open: a written↔concert *toggle* on
  rendered scores.
- **Up-bow / down-bow articulations.** **Bowing** is shipped (cello corner):
  read the ⊓ down-bow / ∨ up-bow marks crisp_notation draws.
- **Common/cut time (C, ¢) + pickup/anacrusis + measure numbering.** **Time
  Signatures** is shipped — read the signature (incl. C and ¢) for the beats per
  bar. Still open: spot the **upbeat (Auftakt)** with anacrusis measures.
- **Percussion clef** → **shipped**: a **Drums** corner with **Drum Read** — read
  a rhythm on the neutral percussion staff and tap it back on the drum pad in
  time (count-in, then Perfect/Good/Miss vs the notated onsets).
- **Figured bass** (SMuFL figbass) → Baroque continuo reading — advanced, later.

### New in crisp_notation-public (aligned 2026-07-13) — next builds

Fresh capabilities now resolvable in mus, ranked by fit:

- [x] **Roman-numeral harmonic analysis** (`RomanNumeral` — `.symbol` → "V7",
  "ii°"). **Shipped: Roman Numerals** (Harmonik,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — read/hear a diatonic
  triad in a key, pick its numeral; the chord is built with `Triad` and named by
  `romanNumeralOf(pitches, key)`. SRI `harmony.roman.<symbol>`. Widens I/IV/V in
  C → all diatonic triads → **all major + minor keys** (harmonic-minor V/vii°)
  **and first/second inversions** (figures `V6`, `ii6/4`) at 2★. Still open:
  **7th chords** (`V7`, `viiø7`) — needs a crisp_notation seventh-chord builder (the
  library has only `Triad`), a clean handoff.
- [x] **Metrical-accent hierarchy** (`beatStrength(Fraction) → double`).
  **Shipped: Strong Beat?** (Takte,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — a measure with beat
  numbers, one beat highlighted; strong-or-weak, graded by `beatStrength` (not
  hard-coded, so correct for 4/4, 3/4, 6/8…). Metric click accents the strong
  beats. SRI `measures.accent.<ts>_<beat>`; widens 4/4 → +3/4,2/4 → +6/8. Still
  open: a "conduct the metre" / tap-all-strong-beats variant.
- [~] **Structured chord symbols** (`chordSymbolFor`, `ChordSymbol` model).
  **Shipped: Chord Chart** (Chords,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — the symbol→notation
  matching game: read a chord symbol (G, Dm, D7…), tap its notation among four
  little staves. Lead-sheet literacy; the inverse of Name That Chord. SRI
  `chords.symbol.<symbol>`. Still open: chord symbols rendered over the Song Book
  chord sheets (in the play-along agent's songbook area).
- [~] **Voices per staff** (`Measure.voice2`, 2 voices rendered; 3–4 model-only).
  **Shipped all 3 scoped SATB minigames** (Noten lesen, gated behind Duet 2★,
  shared `satb_voicing.dart`, [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)):
  **Read the Voice** (name the note a voice sings), **Which Voice?** (highlight →
  pick S/A/T/B), **Hear the Voice** (aural: chord then one voice → which?). All 2
  voices (S+A) → full SATB, and now **several major keys at 2★** (correctly
  spelled, no voice crossing — unit-tested over 400 draws). Remaining: chorale
  inversions/7ths (root position for now). (`beam subdivision` / `appoggiatura`
  grace notes are
  separate rendering-quality wins, still open.)
- [ ] **Import breadth**: MEI, Humdrum **kern/ekern**, LilyPond, GP3/4/5,
  compressed `.mxl`. All parseable in `crisp_notation_core` today → wire into the
  Song Book import screen (web-safe, additive). Extends MusicXML/ABC/ChordPro/MIDI.
- [ ] **OMR ("photograph your sheet music")** — checked crisp_notation@main
  (v0.9, 2026-07-13): OMR is **substantially built there**, but split by
  platform, which gates how mus can use it:
  - **Recognition (image → tokens)** = CrispEmbed **Sheet Music Transformer** in
    `crisp_notation_cli/crispembed_omr.dart`: `dart:ffi` + `dart:io` + native
    `libcrispembed` + a **GGUF model**. **NOT web-compatible, not a mus dep,
    needs a ~100 MB+ model artifact.**
  - **Parsing (tokens → Score)** = `crisp_notation_core/src/omr/` (bekern · semantic ·
    lilynotes → Score/GrandStaff/StaffSystem). **Pure Dart, web-safe, already a
    mus dependency** (0 ffi/io refs).
  - So a client-side photo→score in the **deployed web app is not a quick win**.
    Realistic paths: **(a)** web-safe **"import OMR tokens"** in the Song Book
    (reuse the core parsers; cheap; niche without on-device recognition);
    **(b)** a **native-only** photo flow (Android/iOS/desktop) on the AEC agent's
    pattern (native plugin + web-safe conditional-export stub) + camera + the
    GGUF model — a big swing; **(c)** server-side recognition (no infra yet).
- [x] **Alternate SMuFL fonts** (Petaluma / Leland / Leipzig descriptors).
  **Shipped: "Handwritten notes" theme** (Settings toggle,
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped)) — renders all notation in
  **Petaluma** (jazz/handwritten, SIL OFL 1.1, vendored in `assets/smufl/`,
  license on the About page). All ~50 StaffView sites now go through
  `shared/score_theme.dart`'s `kidsScoreTheme`, switched by the setting. Still
  open: Leland/Leipzig as further options; a live preview in Settings.

### crisp_notation moved a LOT further (checked 2026-07-14)

Since the 07-13 alignment, `CrispStrobe/crisp_notation@main` advanced ~40+ commits
(still v0.4.0). **mus is fully compatible** — after fast-forwarding the local
`../crisp_notation-public` to match CI, `flutter analyze` is clean and the **full
suite (429) is green** against it, so none of the churn broke anything mus uses.
(Local checkout was behind CI's `@main`; now realigned. mus rides all of this
for free.) The genuinely new capabilities, ranked by mus fit:

- [ ] **Multi-part / full-score rendering (the "C6" line)** — new `MultiPartScore`
  model + **paginated `MultiPartView`/`MultiPartPageView`** (render several
  instruments/staves as line-broken pages), **cross-part hit-testing**, per-group
  barlines (`BarlineGroup`), multi-part PNG/SVG/CLI export ("every part"). This is
  a real new tier above our single-staff + `StaffSystemView` duet. *mus fit:* an
  **ensemble / full-score reader** (e.g. a real SATB chorale on 2–4 staves, or a
  score-following view for a multi-instrument tune). M–L, genuinely new surface.
- [ ] **MuseScore `<Drumset>` import + TAB-clef import** — MusicXML now reads a TAB
  clef (was aborting) and MuseScore files yield **drum hits on their line +
  notehead**. *mus fit:* feeds the **Drums** and **Guitar** corners with imported
  material; pairs with the existing Song Book import screen. S–M.
- [ ] **Interchange breadth + fidelity now hardened** — multi-voice **kern**
  (`*^` split spines) and **ABC** (`&` overlay) round-trip; **MEI** multi-staff
  importer (`staffSystemFromMei`); UTF-16/BOM file decoding; a round-trip
  **fidelity harness** + music21 oracle. Supersedes the older "import breadth"
  item above — MEI/kern/ABC/MuseScore import is now robust enough to wire into the
  Song Book. S each (additive, web-safe).
- [ ] **Workshop-facing editor APIs** — `suppressElementIds` (clean element hide
  during live drag, **mus already uses this**) + **view-owned live-drag preview
  `dragPreviewOpacity`** (C10b). Plus engraving the Workshop gets for free:
  **metric-aware secondary beaming** (beams grouped by the meter hierarchy),
  **`Measure.actualDuration`** (explicit irregular/pickup-bar length), every-N
  **measure numbering**, per-group barlines, and layout crash-hardening on
  degenerate spans. → see the **Workshop parity** pass below.
- [ ] **Braille music export** (`.brl`, incl. key/time sigs + chords; tab
  notation complete) — an accessibility angle, not obviously kid-facing. Later.

### Workshop → crisp_notation feature-parity (2026-07-14)

The Composition Workshop is a full touch/desktop score editor, and **G6
multi-instrument authoring is now feature-complete** (2026-07-15, on
origin/main): `MultiPartDocument` (`List<ScoreDocument>` + active part, padded
bar grid, per-part id namespacing) → the full-score `InteractiveMultiPartView`
canvas with a parts strip (add/select/clef/transposition/brace/remove),
multi-part **import** (`multiPartScoreFromMusicXml/Abc/Mei/Kern`), multi-part
**export** (crisp_notation **C11** `multiPartToMusicXml`), and **in-place
editing** on the full score (crisp_notation **C12** `InteractiveMultiPartView`:
staff-tap-to-place, hover ghost, cross-part select, drag repitch). See
`docs/WORKSHOP_G6_HANDOVER.md` + `docs/WORKSHOP_CRISP_NOTATION_CONTRACTS.md`.

**crisp_notation G6 follow-ups (the "left opens") — DONE 2026-07-15:**
- ✅ **C12b — `EditorCaret` on `InteractiveMultiPartView`** (crisp_notation
  `afc283a`): the render paints a caret before its `beforeElementId` — the id
  locates the part, so it lands in the right staff. mus `_mpCaret` feeds the
  active part's caret (namespaced).
- ✅ **C12c — `ElementRegionController` on `InteractiveMultiPartView`**
  (`afc283a`): `RenderMultiPartView implements ElementRegionProvider`; a
  controller binds for marquee / cross-part region queries. mus binds `_regions`
  + shows the rubber-band overlay in multi-part mode (`_applyMpMarquee` selects
  within the most-covered part).
- ✅ **C12a — live drag preview** (no lib change needed): built app-side from the
  existing `suppressElementIds` (hide the dragged note) + placement ghost
  (`onElementDragUpdate` moves it under the pointer) — same visual as single-part
  `dragPreviewOpacity`. A dedicated multi-part `dragPreviewOpacity` (real-glyph
  translation) is an optional future nicety, not required.
- ⏸️ **C11b — multi-part MEI/ABC writers** — **deliberately deferred.** MusicXML
  (`multiPartToMusicXml`, done) is the universal multi-part interchange format;
  adding `multiPartToMei`/`multiPartToAbc` means refactoring the oracle-hardened
  single-part writers for low marginal value + real regression risk. Multi-part
  export stays MusicXML/`.mxl`; other formats export the active part. Revisit
  only if a concrete MEI/ABC multi-part need appears.

**Non-G6 parity polish — assessed & (partly) shipped 2026-07-15:**
- ✅ **Measure numbers in the editor** — crisp_notation `MultiSystemView` gained
  opt-in `showMeasureNumbers` (system-start numbering off `SystemLayout.
  firstMeasure`, paint-only, defaults off — ported from `png_export`'s
  convention; it previously existed only on `StaffView`). Wired a **"Bar
  numbers"** toggle in the Workshop ⋮ menu, wired to **all three** editor
  canvases — single-staff (`MultiSystemView`), grand-staff
  (`InteractiveGrandStaffView`) and multi-part (`InteractiveMultiPartView`) all
  gained the same opt-in system-start numbering. **Feature complete.**
- ✅ **Metric-aware beaming** — already automatic: the layout engine
  (`_computeBeamGroups`) derives beam windows from the meter during layout, so
  the editor needs no opt-in. Nothing to wire.
- ⏸️ **`Measure.actualDuration`** — the model already supports explicit
  irregular-bar lengths (`Measure.actualDuration` + `effectiveDuration`), and the
  editor already handles the pickup case; exposing arbitrary irregular bars is a
  niche editor feature, deferred until asked.
- ✅ **`showNoteNames` overlay** — shipped. crisp_notation gained a
  **`NoteNameStyle`** (letter / German-H / solfège) threaded through the layout
  engine's note-name overlay (was fixed English) + `showNoteNames` on
  `MultiSystemView`; the Workshop **"Note names"** ⋮ toggle overlays each note's
  name **on all three editor canvases** (single-staff, grand-staff, multi-part —
  the flags now forward through the grand-staff/multi-part layout paths too),
  **spelled per the app's note-naming setting** (germanH → H for B, solfège →
  do/re/mi, auto → locale). **Feature complete.**
- ✅ **Per-group barlines in the chrome** — shipped. `MultiPartDocument`
  `toggleBarlineBreakAfter`/`hasBarlineBreakAfter` recompute `barlineGroups`; a
  **"Break barline below"** item in each part's ⋮ menu breaks the systemic
  barline between instrument groups (crisp_notation already paints them). **All
  Workshop→crisp_notation parity items are now shipped.**
Details + the running contract log: `docs/WORKSHOP_PLAN.md` +
`docs/WORKSHOP_CRISP_NOTATION_CONTRACTS.md`.

## Difficulty progression (within each game)

Games start at the easiest concrete slice and widen per level (driven by
stars + `kWinsRequiredForLevelUp`, tuning.dart):

- Reading/Placing: naturals on the staff → ledger lines (middle C!) →
  accidentals → mixed clefs.
- Measure Filler: 4/4 with h/q/e → 2/4, 3/4 → dotted notes → 6/8.
- Scale Detective: C/F/G major → all majors → natural minor → harmonic minor.
- Chord Quiz: major root position → minor (Dur/Moll!) → inversions →
  diminished/augmented.
- Function Quiz: C/F/G major → all keys → minor keys (with harmonic-minor
  dominant) → hear the function (audio).

## Delivery

- GitHub: `CrispStrobe/klang-universum` (app), `CrispStrobe/crisp_notation` (lib).
- **CI** (`.github/workflows/ci.yml`): every push/PR runs format + analyze +
  test and uploads coverage (~85% of `lib/`). It checks out `crisp_notation` as a
  sibling so the `../crisp_notation` path dependency resolves on the runner.
  Analyzer is strict (`strict-casts`/`strict-raw-types`); the `build` symlink
  is untracked (it points at a dev-only SSD path and would dangle on CI).
- Web: Vercel (`mus` project), prebuilt `build/web`, same pattern as voc.
  A root `.vercelignore` drops the Flutter build's `*.symbols` debug maps
  (~8 MB, never fetched at runtime) from the upload; the served bundle is
  brotli (main.dart.js ~924 KB, canvaskit.wasm ~2.85 MB, fonts tree-shaken).
- pub.dev publication of crisp_notation: deliberately **not yet** (maintainer
  decision); everything is consumed via path/git.

## Learnability & UX — zero-knowledge onboarding (P0/P1 shipped; content ongoing)

> **Status (shipped to origin/main, CI-green):** the **sound on/off toggle** +
> silence fix, the **mascot idle-greet**, and the **tutorial system** are live —
> now with **all 13 module primers + 8 ★ per-game primers** (21 total, covered
> by the `tutorial_test` loop), an **app-wide "?" reopen** (a help FAB overlaid
> by `TutorialGate` on any game with a primer), a reusable **`GameAppBar`**
> (title + app-wide `SoundToggle` + optional "?"; adopted on `accidental_sort`
> so far), and a **mascot presenter** in `RoundHeader` (idle greet per question).
>
> **Remaining follow-ups (this section, ranked by value ÷ effort):**
> 1. **Help on every game.** Only 21/100 games carry a primer, so the other 79
>    show no "?"/first-run help. **Fix without per-game edits or auto-show spam:**
>    give `TutorialGate` a **module-primer fallback** — a `kModulePrimers` map
>    (module → its general primer) so the "?" opens the module primer for any
>    game lacking its own, while **auto-show stays curated** (entry + ★ games
>    only, so a module's intro doesn't re-pop on every game). *(S · registry +
>    tutorial_gate.)*
> 2. **`GameAppBar` roll-out.** Adopt it across the ~84 remaining screens
>    (module-by-module) to put the sound toggle in every bar. Mechanical but
>    collision-prone (hot screen files); the reopen "?" is already app-wide via
>    the overlay, so this is now mostly about the in-bar toggle. *(L · sweep.)*
> 3. **Fuller mascot presenter.** Upgrade the idle presenter to a
>    `MascotPrompt` (mascot + speech bubble that reads the question) and default
>    `FeedbackLine.showMascot = false`. *(M · `game_widgets`/`note_mascot`.)*
> 4. **New-game hygiene (see backlog §G):** new games adopt the tutorial hook +
>    mascot API; audit the recent sort/arcade games for reduced-motion + the
>    sound toggle.

The bet: a child with **no** prior music knowledge should be able to open any
minigame, be taught the facts it needs (with heard + seen examples), and play it
through. Plus fix a sound regression and give sound a global switch. (Original
structural map, now mostly addressed: every screen built its own AppBar — a
shared `GameAppBar` now exists but isn't swept in yet; the mascot lived only in
`FeedbackLine` — now also presents in `RoundHeader`; the tutorial/help system is
built and live.)

### P0 — App-silence regression
Symptom: audio goes silent app-wide, suspected after play-along. Likely cause:
there is **no global audio-session / `AudioContext`** (`main.dart`, `AudioService`),
so the `record` mic flips the iOS/Android session to record/`playAndRecord` (routes
to the quiet earpiece) and does not restore it, muting `audioplayers` afterwards.
Fix: set a global playback `AudioContext` (speaker-routed, mixes/ducks) once at
startup; have `MicrophonePitchService.stop()` restore it; verify metronome +
backing + SFX are audible before **and after** using the mic. (No repro device
here — validate on macOS/web locally + reason from the session model; confirm on
hardware in (e)-style testing.)

### P0 — Global sound on/off toggle in the top bar
- **Behavior:** one chokepoint — gate `AudioService._play()` with `if (!soundOn) return;`
  (`core/services/audio_service.dart`). Mutes notes/chords/SFX/ticks/backing for
  all 97 games at once; the **mic is unaffected** (intonation games still work).
- **State:** add `soundOn` to `SettingsService` (SharedPreferences, mirrors the
  existing `showTimer`/`instrument` pattern), synced to `AudioService` at
  `main.dart` where `instrument` already is.
- **UI (app-wide):** there is no shared AppBar, so introduce a shared
  **`GameAppBar`** helper (a `PreferredSizeWidget`) that carries the speaker
  on/off action **and** the tutorial "?" button (below), and migrate game
  screens onto it module-by-module. Ship the toggle immediately on Home +
  Settings; the per-game top-bar icon lands as screens adopt `GameAppBar`.

### P1 — Mascot: from idle prop to guide
`NoteMascot` (`shared/widgets/note_mascot.dart`, moods idle/happy/oops) currently
sits in `FeedbackLine` (between the question and the 4 options, 53 screens) doing
nothing at rest. Move it to a **presenter** role: a `MascotPrompt` (mascot +
speech bubble that reads the question) inside `RoundHeader`, **before** the
question; default `FeedbackLine.showMascot = false` (feedback text stays). Give
the mascot a gentle **idle animation** (breathe/blink/sway) so it's alive, and
keep the happy/oops reactions. Editing the two shared widgets
(`game_widgets.dart`, `note_mascot.dart`) reaches every game uniformly.

### P1→P2 — Tutorials for every minigame (the big one)
Each game gets a short, **illustrated + playable** explanation of exactly the
musical facts it drills, so a zero-knowledge child can clear it.
- **Framework:** a `Tutorial` model = ordered steps, each with text + optional
  **notation** (`StaffView`/`kidsScoreTheme`) + optional **"listen" example**
  (`AudioService.playSequence`/`playMidiChord`/…). A `TutorialSheet` renders it.
  Shown **auto on first entry** (persist "seen" per game id) and reopenable via
  the **"?"** in `GameAppBar`. New optional hook on `GameInfo`
  (`game_registry.dart`), e.g. `Tutorial Function(AppLocalizations)? tutorial`.
- **Content:** author module-by-module (10 modules, 97 games), EN/DE in the
  ARBs, teaching the underlying knowledge — staff & clefs, note/rest values &
  beats, meter/measures, scales (Dur/Moll), intervals & chords, harmony (T/S/D),
  the cello/guitar/piano corners — each with a heard example and a shown example.
  Reuse one shared "primer" per module where games overlap, specialized per game.
- **Phasing:** (1) framework + "?" + first-run gating + `GameAppBar`; (2)
  author the note-reading + note-values primers (highest-traffic); (3) sweep the
  remaining modules. Coordinate ARB/`game_registry` edits (hot files) with the
  parallel agents.

## Competitive analysis & opportunity roadmap

Benchmarked against 30+ music-learning apps (mid-2026, four research sweeps:
gamified-instrument, theory/ear-training, kids-focused, and
sight-reading/composition + DACH). Competitor names are deliberately kept out of
this repo; the notes below describe capability *categories*, not products.

### The strategic read

- **Our real competition is not the big paid instrument-tutor apps.** Those are
  adult-first, treat notation as a display mode, and have no German-curriculum
  tie-in. In the DACH market we compete with a couple of free incumbents (a
  curriculum-aligned school platform and a public-broadcaster kids' site) plus a
  thin cluster of small theory/notation tools.
- **The children's notation-literacy niche is genuinely thin.** German teaching
  materials note that note-reading is required in every Bundesland yet there is
  little kindgerechtes Unterrichtsmaterial zum Notenlernen — that gap is the
  opening.
- **Two open moats:** explicit **Lehrplan alignment** (only the incumbent school
  platform claims it) and **genuinely bilingual EN/DE pedagogy** (rivals are
  German-only or English apps with translated strings — almost none are built
  bilingual).
- **Where we already lead** (rare among kids' apps): SM-2 spaced repetition,
  real four-clef notation, theory/harmony depth (T/S/D, cadences), a composition
  sandbox with MusicXML export, bilingual EN/DE — and now **live mic input**.
- **The structural gap that used to set the strong rivals apart — live
  real-instrument input — is now closed on the mic side** (play-along/sing-along,
  tuner, chord listener; see HISTORY). MIDI input remains open.

### Opportunity backlog (implement top-to-bottom)

Effort S/M/L; fit ♪–♪♪♪ (mission fit for a kids' notation/theory app). Source =
the app category the idea comes from. Shipped items live in
[HISTORY.md](HISTORY.md#opportunity-backlog--shipped).

**Strategic bets — extend the SM-2 / notation core**
- [ ] Parent view + multi-child profiles. *(kids' practice apps.) M · ♪♪.*

- [x] Lehrplan alignment + German framing. **Shipped**: a **Curriculum** screen —
  generic progress levels tied to **school years** (Klasse 1–2 … 9–10), each
  topic mapped to the games that drill it, with a *readiness* meter from the
  child's stars, a "continue here" marker on the recommended level, and
  per-level / weakest-topic practice runs. Readiness blends **star coverage ×
  SM-2 retention** (`SriService.masteryUnder(namespace)`), so it reflects both
  breadth and whether skills actually stuck. The engine (`Curriculum → Level →
  Topic → gameIds`) keeps per-region variants as drop-in data. *Open: optional
  per-Bundesland variants (rough matching is fine).*
- [ ] Sound-toy creative modes that feed notation (grid composer + geometric
  rhythm toy for pre-readers). *(browser music sound-toys.) M · ♪♪.*
- [ ] Color-coded kids' notation editor with MusicXML/MIDI export. *(kids'
  notation-editor apps.) M · ♪♪.* Closest to our existing sandbox.
- [ ] Teacher / LMS layer for school licensing (roster, assign-and-track, Google
  Classroom). *(classroom notation/DAW platforms.) L · ♪♪.* Schools buy per-seat.

**Big swings — category table-stakes, heavy lift**
- [x] Real-instrument input — **mic side shipped**: live pitch/chroma detection
  powers **Play-along / Sing-along** (moving-score grading), a **Tuner**, and a
  **Chord Listener** ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)).
  *Open: MIDI input; wiring mic grading into more of the corners.*
- [ ] Generative sight-reading + performance grading — endless non-repeating
  exercises scored for pitch & rhythm. *(generative sight-reading services.) L · ♪♪♪.*
  Answers the teacher-reported material shortage directly. *(Staff Runner is the
  kid-scale stepping stone; mic grading now exists to score the performance.)*

### Live-mic follow-ups (the mic pipeline is shipped — exploit it)

Now that live pitch/chroma detection, the `PlayAlongEngine`, and the moving-score
UI exist, these are high value ÷ effort because the hard infra is done:

- [x] **"Perform It" — mic-graded reading.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note is shown;
  the child **plays or sings it** and the pitch detector verifies it
  (octave-agnostic, sustained-match), instead of tapping a letter. Feeds the
  shared `note_reading.<clef>.*` SM-2 pool. The kid-scale core of the
  generative-sight-reading big swing.
- [x] **Sing-back ear training.** **Shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a note plays; the
  child sings it back and the mic grades it (octave-agnostic). Target is *heard*,
  not shown — trains pitch memory & matching, needs no instrument. Feeds the ear
  pool `scales.hear.*`.
- [ ] **Play-along for the Song Book.** Extend play/sing-along to the real
  public-domain songs — play or sing Twinkle & co. against the moving score. *M · ♪♪.*
- [~] **Mic grading in the instrument corners.** "Play this note/string/finger"
  verified by the mic. **Cello shipped**
  ([HISTORY.md](HISTORY.md#live-microphone--pitch-detection)): a first-position
  note + string/finger hint, played on the real cello and graded by the mic
  (octave-agnostic, feeds `cello.play.*`). Guitar & piano corners still open. *M · ♪♪.*
- [ ] **Parent view + multi-child profiles.** *(kids' practice apps. M · ♪♪.)* A
  parent dashboard over the curriculum **readiness** — each child's school-year
  progress at a glance; per-child profiles. (Also listed under Strategic bets.)

Caveats: competitor prices/age-ratings drift; some DACH adoption/award figures
are self-reported — verify before external citation.

## Gamified formats (from the sibling-app survey)

New *interaction mechanics* surveyed across `../voc` and `../space_math_academy`.
Shipped formats (memory pairs, sequence, sort-into-buckets, swipe, falling-notes,
connect-a-line) live in [HISTORY.md](HISTORY.md#gamified-formats--shipped).
Sub-variant sweep **mostly done** (Jul 2026 batch): shipped **Longest First**
(note-value ordering), **In the Scale?** (swipe membership), **High or Low?** +
**Sharp or Flat?** (two-basket sorts on pitch-direction / accidental-sign),
**Higher or Lower?** (direction-by-ear), **Step or Skip?** (motion reading), and
**Connect the Steps** (interval↔number, a 3rd Connect-the-Notes mode). Details in
[HISTORY.md](HISTORY.md#gamified-formats--shipped). Still open from this survey:

- [ ] **Major/minor sort** — drag written triads into Major / Minor baskets by
  reading their quality on the staff. *Note: this reads quality visually (harder,
  ~9+); `major_minor_ear` already covers the aural version. Lower priority — a
  niche tile for the top of the age range.*
- [ ] **Falling-notes "catch the longest"** — a note-*values* mode of the arcade.
  *Caveat: `falling_notes_screen.dart` is ~930 lines of ticker/combo logic and
  its tests lean on the animation clock — a real lift, and less tap-robust than
  everything else in the batch. Budget accordingly.*
- [ ] **Melody-recall ear variant** of the sequence format — hear a 3–5 note
  tune, tap it back. *Check overlap first: `melody_echo`, `echo_sequence`, and
  `sound_echo` already exist; only build if it adds a distinct twist (e.g.
  tap-back on a staff rather than a keyboard).*

### Toy-inspired mechanics (electronic-toy lineage)

Classic hand-held electronic music/reaction toys, reimagined for notation & ear
training. Shipped: Sound Echo, Follow the Conductor
([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).

- [x] **Strum toy** — swipe/strum across the screen to sound a chord or arpeggio;
  a free "air-instrument" jam built on the existing fretboard/keyboard widgets. *S–M.*
  **Shipped** ([HISTORY.md](HISTORY.md#toy-inspired-mechanics--shipped)).
- [ ] **Loop mixer** — tap/place cards that each trigger a synced musical loop
  (bass / chords / melody / drums), layering a mix in time. Creative sound-toy.
  *L — needs multi-track synced loop playback.*
- [ ] **Two-hand split** — left and right zones each run their own short
  sequence/beat to keep going at once (piano-hands coordination). *M–L, advanced.*
- [ ] **Move-to-the-beat caller** — a move/gesture is called on each beat; perform
  it in time (rhythm + reaction). *M.*

### New minigame concepts (original — not from the surveys)

Fresh ideas that fit the machinery we already have (crisp_notation notation, pure-Dart
audio, the SM-2 engine, the falling/connect/reaction engines) and target skills
the curriculum doesn't yet drill.

**All shipped** — Ledger Leap, Key Detective, Odd One Out, Note Whack, Interval
Ladder, Staff Runner, Chord Grip Hero, Dynamics & Tempo Charades, Note Snake, and
Recital Mode all live now
([HISTORY.md](HISTORY.md#original-concepts--shipped)). New original ideas get
added here as they come up.

## Loop Mixer 2.0 — the groovebox ladder (roadmap)

**STATUS 2026-07-16: slices 1–9 SHIPPED** (see the board entry + HISTORY.md;
slice 5 deferred to the Tracker by design). **Only slice 10 remains open**
(beatbox→drum card + AEC jam mode — unclaimed).

Evolve the shipped Loop Mixer (`32ebb96`) from kid toy into something adults
find genuinely fascinating. Guiding idea: **kids love cause-and-effect; adults
love depth that reveals itself** — a toy that turns out to be an instrument,
a system that responds to *you* (the mic!), and output worth keeping. The
ladder is also a stealth curriculum: layers → arrangement → harmony → rhythm
design → ear-to-instrument. Depth stays behind the shelf (Sandbox/Studio
philosophy): the five-cards surface never gets harder. Division of labour vs.
the **Tracker** (opus, `TRACKER_HANDOVER.md`): the Tracker is the *editing*
surface (pattern grids, sample instruments); the Loop Mixer is the *playing*
surface (layering, feel, harmony, generativity, the mic). Both sit on the same
`loop_engine.dart`/`mixStems` foundation — engine work here is additive and
keeps existing signatures stable.

**Architecture spine** (decides everything else):
- **`GrooveSpec`** — one small serializable value object = the entire groove
  state (enabled set, tempo, swing, per-track variant + level, progression,
  seed). Engine renders `spec → WAV` (pure, cached). Makes the share token,
  save slots and tests trivial.
- **Patterns become DATA, not closures** (drums = per-voice hit rows; melodic
  = (midis, lengthSteps) cells) so variants, engraving, sing-a-track and
  generative variation all operate on one model — and the Tracker can reuse it.
- **Seam scheduler** — the single looping player stays for the steady state
  (native loop = perfectly gapless); a second player only swaps a *changed*
  render at the next loop boundary (fills, variation, infinite mode). Instant
  toggles keep the shipped phase-preserving `play(position:)` path.
- Stay offline-render + audioplayers until an actual wall (live filter sweeps
  / continuous tempo bend would need a streaming path — flag, don't build).

**Slices** (each independently shippable, in order):
1. ✅ v1 shipped (`32ebb96`).
2. **Engine v2** — GrooveSpec + data patterns + **swing** (off-eighth delay
   0–60%, the biggest feel-per-LOC win) + **per-track variants** (A/B/C) +
   **euclidean drum generator** (Bjorklund; hits/rotation per voice) +
   per-card **level**. Pure Dart + tests; screen keeps the v1 surface.
3. **Screen v2 + seam scheduler** — swing slider, variant cycling on cards,
   level control, bar-quantized "armed" apply for seam-timed changes, auto
   drum-fill every 4th loop.
4. **Chord progression lane** — pick I–V–vi–IV / I–IV–V–I / vi–IV–I–V; loop
   becomes 4 bars (1 per chord); bass + chords render chord-relative, melody
   stays C-pentatonic (works over the axis progressions). Suddenly it's a song.
5. ~~Step editor~~ — **deferred to the Tracker** (its Sandbox view IS the
   step editor, over the same engine). No duplicate grid UI here.
6. **Live engraving** — the groove as a real multi-part crisp_notation score
   in a collapsible panel (the app's signature "you're writing notation" trick).
7. **Keep it** — WAV export/share (bytes already exist), groove **share
   token** (GrooveSpec → short base64 string, serverless, matches the
   no-tracking stance), save slots (mirror `user_songs_service`).
8. **Infinite mode** — seeded per-iteration variation via the seam scheduler
   (ghost notes, melody ornaments, arrangement drift). Never the same twice.
9. **Sing a track into existence** — hum a riff → MPM pitch track → quantize
   to key + step grid → a sixth card plays it on the synth (reuse Free Sing /
   melody recorder pipeline). The headline feature. (Distinct from the
   Tracker's record-your-voice-as-*instrument* — this is melody *capture*.)
10. **Beatbox → drum card** (onset + crude kick/snare/hat classification) and
    **Jam mode** (groove plays, child plays cello over it through the AEC
    path, app shows what they play vs. the harmony — the loop mixer becomes a
    play-along backing band). Big; needs the AEC on-device path.

## Ideas backlog for the next agent (Jul 2026 handoff)

Brain-dump of every game/feature idea still on the table after the Jul-2026
web-safe batch, ranked roughly by value ÷ effort. **All are web-safe (no native
FFI) unless flagged.** Reuse the existing scaffolds — a new game is one `GameInfo`
in `game_registry.dart` + a screen + a `kStarThresholds` bracket in
`core/tuning.dart` + ARB keys (EN/DE) + a widget test. Follow the strict
`dart format` → `flutter analyze` (whole project) → `flutter test` → commit →
push → watch-CI loop, and keep the board above in sync (parallel agents!).

**Reusable scaffolds proven this batch (copy them, don't reinvent):**
- *Two-basket sort* — `pitch_sort_screen.dart` / `accidental_sort_screen.dart`
  (Draggable→DragTarget, `onWillAcceptWithDetails` gates the drop). Test drives
  real drags and tries each basket until one accepts (`pitch_sort_test.dart`).
- *Binary ear* — `direction_ear_screen.dart` (replay button + two answer
  buttons; `@visibleForTesting` tester interface exposes the correct answer so
  the test taps it).
- *Binary staff-read* — `step_skip_screen.dart` (staff card + two buttons).
- *Swipe/tap card* — `in_scale_screen.dart` (swipe + tap labels + arrow keys).
- *Connect-a-line* — add a `ConnectMode` case to `connect_line_screen.dart`.
- All staff-based tests **must** use `pumpGame`/`useGameSurface` (CI's 800×600
  surface throws `getElementPoint` otherwise — see the board's ✅ note).

### A. Tap-robust minigames that fill a real skill gap (best value)
- [x] **Whole-step or Half-step?** — **shipped** (Noten lesen): read a 2nd on the
  staff and tap tone vs semitone (half steps hide at E–F/B–C), and hear the
  interval; treble at 1★, +bass at 2★. SRI `reading.tone.<whole|half>`. See
  [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Same or Different?** (binary ear) — **shipped** (Tonleitern): two notes
  play → same pitch or different; clear leap → subtler gaps at 2★. SRI
  `pitch.hear.<same|diff>`. See [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Which Clef?** (binary) — **shipped** (Noten lesen): a bare clef on an
  empty staff; tap Treble or Bass, widening to Alto/Tenor at 2★. SRI
  `reading.clef.<name>`. See [HISTORY.md](HISTORY.md#crisp_notation-powered--shipped).
- [x] **Dotted or Not?** (two-basket sort) — **shipped** (Notenwerte): drag note
  glyphs into Dotted/Plain baskets by reading the augmentation dot (value varies
  so shape alone doesn't give it away). SRI `note_values.dot.<dotted|plain>`. See
  [HISTORY.md](HISTORY.md#gamified-formats--shipped).
- [x] **Ascending or Descending?** (binary ear) — **shipped** (Tonleitern): a 3–4
  note run plays → climbs up or steps down; 4 notes at 2★. A step past Higher or
  Lower?. SRI `pitch.hear.<asc|desc>`. See
  [HISTORY.md](HISTORY.md#gamified-formats--shipped).
- [x] **Count the Notes** (ear) — **shipped** (Tonleitern): a phrase of 2/3/4
  distinct notes plays → tap how many you heard. Aural attention, no staff, three
  answer buttons, `playPhrase`. SRI `pitch.hear.count<n>`. See
  [HISTORY.md](HISTORY.md).

### B. Cheap depth — widen games that already exist (S effort each)
- [~] **Bass-clef variants** of the new sorts/readers — a `clef` constructor
  param + a second `GameInfo` doubles the content (mirror how `note_reading` /
  `place_note` ship treble + bass). **Shipped:** ✅ *Step or Skip? (bass)*
  (`step_skip_bass`) · ✅ *High or Low? (bass)* (`pitch_sort_bass`) — each with
  its own `progressId` so treble progress is untouched. · ✅ *Sharp or Flat?
  (bass)* (`accidental_sort_bass`). · ✅ *Find the Key (bass)* (`key_find_bass`,
  keyboard) — the staff→piano bridge, bass clef: the `PianoKeyboard` shifts two
  octaves down (C2..B3) so the low staff naturals (G2..A3) land on real keys;
  own `progressId`, and the SRI token carries the octave so bass items never
  collide with treble. (`Connect the Notes` already ships `connect_line_bass`.)
- [x] **Step, Skip, or Leap?** — **shipped**: `step_skip` (and its bass variant)
  becomes a 3-way at 2★ — Step (2nd) / Skip (3rd–4th) / Leap (5th+), a third
  answer button + `reading.motion.leap`; below 2★ it stays the binary drill.
- [x] **3-basket sorts** — **shipped**: *Sharp or Flat?* (`accidental_sort`, +bass)
  widens to a **Sharp / Natural / Flat** 3-basket sort at 2★; below 2★ it stays
  the binary ♯/♭ drill (mirrors Step→Skip→Leap). The natural glyph (♮) is real —
  crisp_notation renders it via `NoteElement.showAccidental` on an unaltered
  pitch (`alter:0 + showAccidental:true → accidentalNatural`, verified at the
  layout level). Card sign refactored bool→`int alter` (+1/0/-1). SRI gains
  `accidentals.sign.natural`.
- [~] **More Connect modes** — note↔piano-key, rest↔note-value, Italian-term↔
  meaning, dynamic-mark↔meaning, instrument↔clef. Each is one `ConnectMode` case.
  **Shipped:** ✅ *Connect the Dynamics* (`connect_dynamics`, note_values) — match
  each dynamic mark glyph (pp…ff) to its meaning word (very soft…very loud); 4
  clear steps for beginners, mp/mf join at 2★. SRI `reading.dynamics.*` (shared
  with `dynamics_duel`, so the reading and compare-loudness drills reinforce one
  skill). ✅ *Connect the Rests* (`connect_rests`, note_values) — match each rest
  glyph to the note it equals in length (quarter rest ↔ "quarter note"); whole/
  half/quarter/eighth for beginners, sixteenth at 2★. SRI `note_values.rest.*`.
  ✅ *Connect the Tempo Words* (`connect_tempo`, note_values) — match each Italian
  tempo word to its meaning (Largo ↔ "very slow"); Largo/Adagio/Allegro/Presto
  for beginners, the middle terms (Andante/Moderato/Vivace) at 2★. SRI
  `reading.tempo.*` (shared with `tempo_duel`). ✅ *Connect the Beats*
  (`connect_beats`, note_values) — match each note-value glyph to how many beats
  it lasts in 4/4 (whole 4 / half 2 / quarter 1 / eighth ½; sixteenth ¼ at 2★).
  SRI `note_values.beats.*` — the duration-in-beats twin of the symbols mode
  (which teaches the *name*). Remaining Connect idea worth doing: instrument↔clef
  — but awkward cardinality (few clefs, many instruments) makes a weak 4-pair
  round; parked. NB the **note↔piano-key** bridge is already its own game, not a
  Connect mode: `key_find` (staff note → tap the key) now ships treble **and**
  bass, both on the reusable `lib/shared/widgets/piano_keyboard.dart`
  (`PianoKeyboard`, already used across ~7 games).

### C. Reading vocabulary the curriculum wants but we don't drill
- [x] **Louder or Softer?** — **shipped** (`dynamics_duel`, note_values): two
  SMuFL dynamic glyphs (pp…ff) as cards, tap the louder; a compare-two duel like
  Faster or Slower?. SRI `reading.dynamics.<mark>`. (`charades` covers the aural
  side; this is the reading side.)
- [x] **Faster or Slower?** — **shipped** (`tempo_duel`, note_values): two Italian
  tempo terms (Largo…Presto) as cards, tap the faster; a compare-two duel like
  Duration Duel but text-based. SRI `reading.tempo.<term>`.
- [x] **Tie or Slur?** — **shipped** (`tie_slur`, note_reading): read the curve —
  same pitch (tie, `NoteElement.tieToNext`) vs different pitch (slur,
  `Score.slurs`); a binary staff-read like Step or Skip?. SRI
  `reading.curve.<tie|slur>`.
- [x] **Beam or Flag?** — **shipped** (`beam_flag`, note_reading): read the two
  looks of eighths — joined by a beam (two eighths on one beat) vs each keeping
  its flag (eighths split by an eighth rest). A binary staff-read; the beam/flag
  contrast was verified at the crisp_notation layout level (same-beat eighths →
  1 beam; eighth-rest between → 0 beams). SRI `reading.beam.<beamed|flagged>`.

### D. Ear-training expansion (mic infra is shipped — exploit it)
- [x] **Sing/play the interval** — **shipped** (`sing_interval`, chords): two
  notes play (root→top), the interval's name is shown, and the child sings the
  TOP note back; the mic grades it octave-agnostic (pitch class), held briefly —
  reusing the `sing_back` capture harness. Third/fourth/fifth for beginners,
  second+sixth at 2★. SRI `intervals.sing.<name>` — the sung twin of Interval
  Ear. (Built on crisp_notation's `Interval` + `Pitch.transposeBy`.)
- [x] **Rhythm echo by tap** — **already shipped** as `rhythm_tap` (Notenwerte):
  a one-measure rhythm plays and is shown as notation, the child taps it back on
  a pad, and timing is graded onset-by-onset relative to the first tap (so the
  absolute start doesn't matter). SRI `note_values.rhythm.p<index>`. (Kept the
  onset-diff grader rather than the `beat_runner` falling-lane clock — for a
  call-and-response echo, comparing relative onsets is the right model.)
- [x] **Chord-quality-by-ear widening** — **done**: `major_minor_ear` widens from
  major/minor to a 4-way (adds **diminished + augmented** as a 2×2 grid) at 2★;
  below 2★ it stays the binary drill. The **dominant-7 tier** shipped as its own
  binary ear game — *Triad or Seventh?* (`triad_seventh`, chords): a major triad
  vs a dominant-7 (triad + a minor 7th), tap which. No 7th-chord *builder* was
  needed — the dom7 is built app-side from the major `Triad`'s pitches +
  `root.transposeBy(Interval.minorSeventh)`. SRI `chords.hear.<triad|seventh>`.

### E. Creative / toy modes (higher ceiling, higher effort)
- [ ] **Loop mixer** — tap cards that trigger synced loops (bass/chords/melody/
  drums). *L — needs multi-track synced playback.* (Also in the toy list above.)
- [x] **Grid composer for pre-readers** — **shipped**: *Colour Melody*
  (`grid_composer`, composition) — a 5-colour (C-pentatonic) × 8-beat grid; taps
  place notes that render live to a real `Score` (StaffView underneath), and play
  back with rests intact (`playChordSequence`, empty beats = silence). A sandbox
  like My Melody (no stars). The bridge to notation for non-readers.
- [ ] **Melody doodle → hear it back** — freehand a contour, quantise to pitches,
  play it. Feeds the songbook.

### F. Infrastructure / platform (not kid-facing games)
- [x] **Web-safe OMR-tokens import bridge** — **shipped** (2026-07-15): the
  Workshop ⋮ menu → **"Paste notation tokens…"** parses pasted **bekern** via
  `importBekern` = `MultiPartScore.fromStaffSystem(bekernToStaffSystem(text))`, so
  a multi-spine paste seeds one instrument part per spine (reuses the G6
  multi-part doc); a single spine loads into the active part. Pure helper
  unit-tested (1-/2-spine) + a widget test pastes tokens → notes. Localized
  de/en. (The image→tokens OMR recognition stays native/out-of-scope.)
- [ ] **`showNoteNames` scaffold** — an accessibility/beginner toggle overlaying
  letter names on noteheads. **Partly blocked:** crisp_notation exposes
  `showNoteNames` only on `StaffView` (not `MultiSystemView` — which most mus
  games + the Workshop use), so an *app-wide* toggle needs crisp_notation to
  surface the flag on the other views first (a crisp_notation ask). A
  StaffView-only version is possible now but covers few screens. Also decide how
  it interacts with the app's `noteNaming` setting (German H/B vs English vs
  Solfège — the crisp_notation flag likely draws fixed English letters; verify).
- [ ] **7th chords in Roman Numerals** — `roman_numeral_screen.dart` is ready for
  it but needs a crisp_notation **seventh-chord builder** (V7/ii7…). *CrispNotation handoff
  — can't ship against an unreleased API since CI tracks public `crisp_notation@main`.*
- [ ] **Leland / Leipzig font options** — extend the Bravura↔Petaluma switch
  (`shared/score_theme.dart`) with more SMuFL faces. *CrispNotation-side bundling.*
- [ ] **MIDI input** — the one real-instrument input still open (mic side shipped).
  *L, big swing.*
- [ ] **Parent view + multi-child profiles** and **Teacher / LMS layer** — see the
  Opportunity backlog above; both are product-level, per-seat monetisable.

### G. Polish / cross-cutting (small, always welcome)
- [ ] New games should adopt the just-landed **per-game tutorial** hook on
  `GameInfo` and the **mascot-as-guide** in `RoundHeader` (UX agent's work — check
  `game_widgets.dart` for the current API before wiring).
- [ ] Audit the new games for the **sound on/off toggle** + **reduced-motion**
  paths (the sorts/arcades animate).
- [ ] Consider grouping the fast-growing `note_reading` module (it's large) or
  surfacing the new binary drills as a "Warm-ups" strip for the youngest.
