# CometBeat — Curriculum & Game Plan

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

> Only 🚧 **ACTIVE** entries are live claims — don't edit another agent's ACTIVE
> claim. The long chronological log of shipped board entries has been moved to
> [HISTORY.md → "Agent coordination board — shipped log"](HISTORY.md#agent-coordination-board--shipped-log-chronological).
> **Pending, actionable work is scoped in the two blocks immediately below.**

- **opus (coverage)** · ✅ **idle / SHIPPED — regression tests for untested parser
  branches** (test-only, no lib changes). Pinned confirmed coverage gaps in
  deterministic pure-logic parsers: `wav_io.dart` (non-PCM/non-16-bit rejection,
  no-data-chunk, stereo downmix, truncated-data clamp, word-aligned multi-chunk
  walk, channels<1 guard), `midi_import.dart` (SMPTE rejection, no-notes throw,
  monophonic overlap-drop, running-status, format-1 track selection, rest-gap
  insertion), `SriItemData`/`GameProgress` `fromJson` default-fill + roundtrip,
  and `parseAnyModule`'s unknown-format throw. 19 new cases across 4 new test
  files; whole-project analyze clean.

- **opus (primer-coverage)** · 🚧 **ACTIVE — real per-concept primers for every
  game** (learnability §1, multi-batch). Audit: 130 games, 29 had a per-game
  primer, **101 fell back to their module primer**. `helpPrimerFor` already
  guarantees *some* help (tutorial_gate_test asserts it), but a module intro often
  never teaches the game's actual concept — `tie_slur` fell back to "here's the
  staff". **Filter applied:** a game needs its own primer iff its drilled concept
  is absent from its module intro (~21 new concepts covering ~35 games); the rest
  are genuinely covered. Reuse-wiring: bass variants → `readingBassPrimer`,
  `interval_ladder`/`connect_intervals` → `intervalsPrimer`. **Landing module by
  module in small commits** (primers.dart + both ARBs + game_registry +
  tutorial_test are hot — rebasing each batch). Worktree `../mus-primer-coverage`,
  branch `feature/primer-coverage`. Batch 1: note_values (tempo / dynamics /
  dotted / rests).

- **opus (primers-mine)** · ✅ **idle / SHIPPED — per-game tutorial primers for 3
  games** (learnability §1). The games I shipped this session now teach their
  concept on first entry / via the "?": **spot_upbeat** → new `upbeatPrimer`
  (downbeat vs a pickup that leans in), **enharmonic** → new `enharmonicPrimer`
  (F♯ = G♭, one key/two names, incl. the German Fis/Ges twins), **major_minor_sort**
  → reuses `chordsPrimer` (already teaches major-bright / minor-soft). Both new
  primers hang on their game via `GameInfo.tutorial`, EN/DE, and are covered by the
  `tutorial_test` build/render loop. (`transpose_write` already had
  `transposePrimer`.) Analyze clean; tutorial + consistency suites green.

- **opus (spacing)** · ✅ **idle / SHIPPED — "Close or Open?" SATB spacing
  minigame** (scoped item #1's remaining suggestion — a *fresh* voice-leading
  skill). Read an SATB chord on the grand staff, tap **close** vs **open**
  position (soprano-tenor span ≤ vs > an octave). Own close/open voicing generator
  (consecutive chord tones = close; skip-one = open) over the reused
  `satb_voicing.dart` rendering; 1★ C-major primary triads, 2★ five keys × all 7
  diatonic triads. Per-game `spacingPrimer` (close/open primer), SRI
  `note_reading.spacing.<close|open>`, unlocks at `duet ≥ 2★`. Device-adaptive
  layout (staff scales into the available height, so open voicings never overflow
  the 800×600 smoke surface). `spacing_read_test` (voicing invariant × 200 seeds
  × wide/narrow + widget flow), registry-smoke + consistency green; analyze clean.

- **opus (tracker)** · 🚧 **ACTIVE — FX extensions**: bell (FM) instrument in the
  picker, a **multi-effect per-channel chain** (list of effects, not one), a
  **pitch envelope** on sampled instruments, and a **Loop Mixer reverb/delay send**.
  **HOT files:** `core/audio/tracker_engine.dart`, `crisp_dsp/envelope.dart`,
  `features/games/composition/tracker_screen.dart` + **both ARBs** (tracker side);
  `core/audio/loop_engine.dart` + the loop-mixer screen (send side). Small commits,
  one per extension; rebasing before each push.

- **opus (smufl)** · ✅ **idle / SHIPPED — Leland + Leipzig notation faces**. The
  binary "handwritten notes" toggle is now a 4-way **Notation font** picker
  (Bravura / Petaluma / Leland / Leipzig), all SIL OFL 1.1. New `ScoreFont` enum +
  `musicFontFor` in `shared/score_theme.dart`; `SettingsService.scoreFont`/
  `setScoreFont` persist under `score_font` and **migrate** the legacy
  `handwritten_notes` bool → Petaluma (`handwrittenNotes`/`setHandwrittenNotes`
  kept as shims). Assets vendored under `assets/smufl/` (`.otf`/`.ttf` + metadata +
  OFL), declared in `pubspec.yaml`, OFL registered in `custom_licenses_registry`.
  ChoiceChip picker in `settings_screen`; ARBs `notationFont*`/`scoreFont*` (EN/DE).
  `notation_fonts_test` (6 cases, both alt metadata parse as valid SMuFL) + the 2
  settings widget tests green; whole-project analyze clean. ⚠ overlaps the
  workshop-inspector `showNoteNames` claim on `settings_service`/`settings_screen`/
  both ARBs — coordinate on rebase.

- **opus (aecmos)** · ✅ **idle / SHIPPED — AECMOS neural MOS scoring in the AEC
  eval CLI**. `onnx_runtime_dart` (pure-Dart, public sibling) gained the conv/GRU
  ops AECMOS needs, so the metric `AEC_TIER3B.md` rejected as "needs a native ORT"
  now runs in pure Dart. Wired **dev-only / headless** (zero app or web-bundle
  impact): `onnx_runtime_dart` as a **dev_dependency** (path `../onnx_runtime_dart`),
  the copied `AecmosScorer` + `MelFrontEnd` under `bin/aecmos/` (with an
  `ignore_for_file: depend_on_referenced_packages` — the dev-dep is the intended
  boundary), and `bin/aecmos.dart <model|run-id> <lpb> <mic> <enh> <st|nst|dt>`.
  The model is a **user-provided** Microsoft AEC-Challenge artifact (run ids
  1663915512/1663829550 @ 16k, 1668423760 @ 48k) in
  `~/.cache/onnx_runtime_dart_models/` — never bundled, so full scoring is a
  local/dev tool (not CI). `test/aecmos_smoke_test.dart` (model-free: mel
  front-end shape/finiteness + scorer rejects an unknown run id — the DSP is
  exhaustively tested upstream). CI + deploy check out `CrispStrobe/onnx_runtime_dart`
  as a sibling (every `pub get` resolves dev deps). `AEC_TIER3B.md` corrected.
  Full-project analyze clean (bar one pre-existing `roman_numeral_test` lint, not
  mine); smoke test green. NOT touching the app / native plugin / game registry.
  ✅ **Now turnkey:** the 16 kHz + 48 kHz models are mirrored (MIT, attributed to
  microsoft/AEC-Challenge) at <https://huggingface.co/cstr/aecmos-onnx> with a
  model card; the CLI's run-id shortcut resolves `aecmos_<run-id>.onnx` from the
  cache and its "model not found" message prints the `hf download` command. (Run
  id `1663829550` not mirrored — available upstream.)

- **opus (tracker)** · ✅ **idle / SHIPPED — FX remainder (FX_HANDOVER §1/§4/§5)**.
  **Swing** (`TrackerTiming.swing` + swing-aware onsets across every renderer + an
  app-bar toggle); **sfxr FM/LFO** (`crisp_dsp/sfxr.dart` fmDepth/fmRatio/lfoDepth/
  lfoSpeed, gated on depth>0 so presets stay byte-identical; a 'bell' preset);
  **per-note volume envelopes** (`crisp_dsp/envelope.dart` + `SampleInstrument`
  declick). Each its own commit + test; all engine/screen suites green.
  **FX_HANDOVER §1–§5 essentially complete** (only extensions remain). ⚠ avoid
  backticks in `git commit -m "…"` under zsh — they command-substitute (dropped a
  word in `651c2c2`).

- **opus (tracker)** · ✅ **idle / SHIPPED — record voice slow/fast (time-stretch)**.
  A Slow/Normal/Fast chip row in the record sheet applies the shipped `timeStretch`
  (pitch-preserving) to a clip before it becomes the voice instrument
  (`_voiceStretch` in `tracker_screen.dart` + tester seam `voiceStretch`/
  `setVoiceStretch`/`voiceSampleLength` + ARBs `trackerSpeed{Slow,Normal,Fast}`).
  Screen test: inject at 1.5× → voice sample ~1.5× longer. **FX_HANDOVER §3 complete.**

- **opus (tracker)** · ✅ **idle / SHIPPED — voicelab voice presets** (alien/cyborg/
  radio/demon). `VoiceEffect` in `voice_fx.dart` gains 4 presets composing formant +
  the shipped `ring_mod`/`distortion` + a 1-pole bandpass (radio); record-sheet icons
  + labels + ARBs (EN/DE). The applyVoiceEffect test (iterating `VoiceEffect.values`,
  now asserting length-preserving too) auto-covers them. **Record voice menu: Normal/
  Chipmunk/Monster/Deep/Robot/Alien/Cyborg/Radio/Demon.** 31 screen + voice tests
  green; analyze clean.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — note-name reading scaffold**
  (`4052f00`, user-requested; the "showNoteNames" item was NO LONGER
  crisp_notation-blocked — `StaffView` supports the boolean). A persisted
  `SettingsService.showNoteNames` (default off, sibling of `colorScaffold`) + a
  Settings toggle; a shared `ReadingStaffView` wrapper (`features/games/widgets/`)
  reads the setting so games opt in with a one-line `StaffView`→`ReadingStaffView`
  swap. Wired into 9 games where the note's NAME is NOT the task (`whole_half`,
  `tie_slur`, `articulation_read`, `beam_flag`, `note_value_quiz`, `measure_fill`,
  `spot_upbeat`, `bowing`, `beat_count`) — **deliberately NOT the naming quizzes**
  (printing the letter reveals the answer) **nor the read-to-produce games**
  (`perform_it`/`cello_play_it` — the shown note IS what you must sing/play, so the
  name would reveal it). That's the safe+valuable set; the rest are unsafe or
  low-value (rhythm on a single repeated pitch). **Per-locale spelling now works**
  (`252acd6`): added a
  `noteNameStyle` param to `StaffView` in the **public crisp_notation lib**
  (`7b72632`, mirrors `MultiSystemView`; default `letter` → byte-identical for
  existing callers), and `ReadingStaffView` passes `noteNameStyleFor(context)`, so
  on-staff names honour the English / German-H / solfège setting. Library +
  app both green; `test/reading_staff_test.dart` asserts germanH → German. Rebased
  through the concurrent `ScoreFont` refactor of SettingsService/settings ARBs.
  Follow-up (optional): extend the wrapper to more name-safe games (one line each).

- **opus (tracker)** · ✅ **idle / SHIPPED — ring-mod + crunch in the channel FX
  picker**. DSP units `9b1b4c8`; `TrackerChannelEffect` now has `ringMod` (Robot) +
  `crunch` (distortion) with `applyChannelEffect` cases; labels + ARBs (EN/DE); the
  picker sheet + the engine test (now iterating the enum) auto-cover them. 50
  engine+screen tests green; analyze clean. **Channel FX menu: none/Echo/Chorus/
  Flanger/Reverb/Robot/Crunch.**

- **opus (majmin-sort)** · ✅ **idle / SHIPPED — "Major or Minor?" triad-sort
  minigame** (backlog §B — the *reading* counterpart to the aural
  `major_minor_ear`). A two-basket drag-sort on the `accidental_sort` scaffold:
  each card renders a **triad** on the staff; drag it into the Major / Minor
  basket (Diminished joins as a 3rd basket at 2★, mirroring accidental_sort's ♮).
  Built with crisp_notation `Triad(root, ChordQuality)`; the chord sounds on a
  correct drop. New `features/games/chords/major_minor_sort_screen.dart` +
  `GameInfo` (chords module) + tuning `[100,400,550]` + EN/DE ARBs (reuses the
  existing `majorLabel`/`minorLabel`/`diminishedLabel`) + `test/major_minor_sort_test.dart`
  (real drag gestures + the 2★ three-basket widen). SRI
  `chords.quality.<major|minor|diminished>`. Analyze clean; consistency + star
  suites green.

- **opus (enharmonic)** · ✅ **idle / SHIPPED — "Enharmonic Twins" minigame**
  (item 1, a genuine gap — nothing else drills enharmonic equivalence). A binary
  staff-read on the `tie_slur` scaffold: two whole notes are shown (each with its
  accidental) across two bars; same sound spelled two ways (F♯/G♭) or genuinely
  different? Graded by `midiNumber` equality (exact — the child must read past the
  spelling). Five sharp/flat twins at 1★; the white-key twins (E♯=F, F♭=E) join at
  2★; "different" rounds are guaranteed non-enharmonic and non-trivial (adjacent
  steps, ≥1 accidental). Correct → both notes play. New
  `features/games/note_reading/enharmonic_screen.dart` + `GameInfo` + tuning
  `[100,600,900]` + EN/DE ARBs + `test/enharmonic_test.dart` (3 tests incl. a
  per-round invariant `answerSame ⇔ notesShareMidi`). Analyze clean; consistency +
  star suites green.

- **opus (tracker)** · ✅ **idle / SHIPPED — per-channel FX chain (Tracker)**. The
  shipped DSP units (`crisp_dsp/modulated_delay.dart` + `reverb.dart`) are now wired
  in: `TrackerChannelEffect{none,delay,chorus,flanger,reverb}` + `applyChannelEffect`
  + a mutable `effect` on `TrackerChannel`, applied to the stem in
  `_renderWithDynamics` before `mixStems`; `setChannelEffect` invalidates the cache.
  UI: a `graphic_eq` app-bar button → an effect-picker bottom sheet (localized
  EN/DE). Engine test (applyChannelEffect: none=identity, each effect ≠ dry;
  setChannelEffect changes the mix, none restores it) + a screen tester-seam test.
  analyze clean; 50 engine+screen tests green.

- **opus (transpose-write)** · ✅ **idle / SHIPPED — "Write It for the Instrument"
  minigame** (remaining-work item 1). The inverse of Concert Pitch, doubling the
  thin Transpose corner: a **concert pitch** (what sounds) is shown on the staff;
  name the note a B♭/E♭/F instrument must **read** to produce it. B♭ only at 1★,
  +E♭/F at 2★; correct → the concert pitch plays. SRI `transpose.<instr>.write_<step>`
  (distinct leaf, never clobbers the forward game's SM-2 items). New
  `features/games/transpose/transpose_write_screen.dart` + `GameInfo` + tuning
  `[100,600,900]` + EN/DE ARBs (parameterized prompt) + `test/transpose_write_test.dart`
  (3 tests incl. a round-trip pinning the transposition inverse vs the forward
  maths). Built during the `CometBeat` rename window (held the push, rebased onto
  the renamed tree). Analyze clean; consistency + star suites green.

- **opus (rename)** · ✅ **idle / SHIPPED — full app rename `KlangUniversum` →
  `CometBeat`** (new working name; checked clear on app stores / web / TM search).
  Package id `klang_universum`→`comet_beat` (**342 Dart files, ~1,768 imports**),
  display names (iOS/macOS/Android/Linux/Windows/web/l10n `appTitle`), bundle ids →
  `com.crispstrobe.cometBeat` (app not yet published), XM-writer tracker stamp,
  README + this header + active docs. `flutter analyze` clean; rename-sensitive
  tests green (widget/home/about/settings/live-flow/xm). GitHub repo renamed
  `klang-universum`→**`CrispStrobe/cometbeat`** (remote + CI checkout `path:` in
  `ci.yml`/`deploy.yml` updated). **Only remaining external item:** rename the
  Apple provisioning profile in the Developer portal, then update
  `ios-release.yml:PROFILE_NAME` (still `Klang Universum AppStore CI`). `HISTORY.md`
  keeps the old name by design (historical log).

- **opus (upbeat)** · ✅ **idle / SHIPPED — "Spot the Upbeat" minigame**
  (remaining-work item 1). A binary staff-read (Takte module): a short two-bar
  melody starts either on the downbeat (a full first measure) or with a pickup /
  anacrusis (an incomplete first measure), and the child taps **Upbeat** vs **On
  the beat**. The pickup is a real `Measure(..., pickup: true)` so the first bar
  genuinely holds less than the meter (proper anacrusis — the pickup is borrowed
  from the last bar). At 2★ the note-count shortcut is defeated (mixed-rhythm full
  bars: half+quarter+quarter shows 3 noteheads but fills 4/4; pickup of 1–2
  notes). Correct → the melody plays. SRI `measures.upbeat.<yes|no>`;
  `kStarThresholds` `[100,600,900]`. `features/games/measures/spot_upbeat_screen.dart`
  + `GameInfo` + tuning + EN/DE ARBs + `test/spot_upbeat_test.dart` (3 tests, incl.
  a per-round structural invariant: upbeat ⇔ short pickup first bar). Analyze clean;
  registry/consistency + star-score suites green.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — the last two voice-2 gaps:
  meter changes + cross-voice tap-select** (`9ceadac` model + `3da6ad2` model+screen).
  (1) **Meter changes desynced the voices** — a time change anchors to one element
  id, in one voice's stream, so the other voice's `reflow` never re-barred (a 2/4
  change gave bar 1 two quarters in v1 but three in v2). `_timeChangesFor(voice,
  scale)` re-keys `_timeChanges` onto each voice by cumulative onset, so a change in
  either voice re-bars both; identity for single-voice → byte-identical goldens.
  `test/voice2_time_change_test.dart`. (2) **Cross-voice tap-select** — crisp_notation
  hit-testing IS voice-agnostic (verified: `staff_view.dart:393`, regions from all
  voices), so `onElementTap` fires with v2 ids; but mutations resolve ids in the
  active voice only. Added `ScoreDocument.voiceOfId`; `_onElementTap` now follows the
  caret to the tapped note's voice (`setActiveVoice` then select). Inert on the
  single-voice Sandbox surface. `test/voice2_cross_voice_test.dart` + a widget test.
  **The voice-2 v1-limit arc is now FULLY CLOSED** — voice 2 is a first-class voice
  for render, persistence, and editing.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 mid-*bar* clef
  changes** (`5071194`). MODEL-only (`score_document.dart`). `_withInlineClefs`
  walked voice-1 elements only, so a mid-bar clef anchored on a voice-2 note was
  stored but never emitted — the **last voice-1-only harvest in `buildScore`**. Now
  collects the onset walk (`_collectInlineClefs`) from both voices, merged
  onset-sorted; `loadScore` recovers a voice-2 anchor whose onset has no matching
  voice-1 boundary (`_recoverInlineClef`, try v1 then v2). Empty-v2 → byte-identical
  (inline-clef + packing goldens hold). `test/voice2_inline_clef_test.dart`. **With
  this, `buildScore` harvests every voice-anchored attribute from BOTH voices**
  (dynamics, lyrics, tuplets, bar changes, mid-bar clefs). Only two voice-2 gaps
  remain, both niche/ambiguous: a **TIME change** anchored on voice 2 (feeds
  reflow's bar capacity by id — genuinely hairy) and **cross-voice tap-select**
  (screen; may be blocked on crisp_notation hit-testing returning v2 ids on tap).

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 mid-score bar
  changes** (`27c8568`). MODEL-only (`score_document.dart`). A clef/key/tempo/
  repeat/volta/nav change anchored on a voice-2 note (the setters run on the active
  voice) was stored but never stamped — `_withMidScoreChanges` scanned voice-1 bars
  only. It now builds a per-bar voice-2 id list (`_v2IdsByBar`, same-grid so bar
  indices align) and `_anchoredIn`/`_anchoredInSet` fall back to it (voice-1 anchor
  still wins). Round-trips (reopen re-anchors to the bar's first voice-1 element).
  Empty-v2 → byte-identical (goldens hold). `test/voice2_midscore_test.dart`.
  **Out of scope (documented):** a TIME change anchored on voice 2 (feeds reflow's
  bar capacity by id) and mid-*bar* inline clefs on voice 2. This closes the
  voice-2 v1-limit arc except those two + cross-voice tap-select (screen).
  *(Also, in passing: fixed 6 files that raced the rename with stale
  `klang_universum` imports — landed upstream as `3a4d5db`, so my dup was deduped.)*

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 tuplets** (`fdf1d6a`).
  MODEL-only (`score_document.dart`; no screen overlap). A tuplet made while voice 2
  was active was doubly broken — `_withVoice2`'s reflow omitted `durationScale`
  (triplet members overflowed the bar) and `_withTuplets` positioned only voice-1
  members (no bracket). Fix: v2 reflow now passes `durationScale: _tupletScale()`;
  the per-bar span emitter is factored to `_tupletSpansByBar(voiceBars, voice:)`,
  reused by `_withTuplets` (voice 0) and `_withVoice2` (voice 1, so crisp_notation
  brackets it as an inner voice — `layout_tuplets.dart:33`); `loadScore` recovers
  `span.voice==1` via a per-bar voice-2 id list. Empty-v2 fast path untouched →
  packing goldens byte-identical. `test/voice2_tuplet_test.dart` (packs scaled +
  emits a voice-1 3:2 span + save→reopen round-trip); 178 Workshop-model tests +
  analyze green. **Remaining voice-2 v1 gaps (unclaimed):** mid-score bar changes
  anchored on a voice-2 note don't stamp (bar-level stamps read voice-1 bars; note
  a *time* change anchored to v2 is extra-hairy — it also drives reflow bar
  capacity); cross-voice tap-select (screen).

- **opus (tracker)** · ✅ **idle / SHIPPED — "borrow a sample from a module"**
  (core `7dd8ab2` + UI). A "Borrow instrument…" item in the Tracker app-bar menu:
  pick a `.mod/.s3m/.xm/.it`, choose one of its samples from a dialog, and it
  becomes the selected channel's instrument (`sampleInstrumentFromModule` +
  `setChannelInstrument` → setState → `_syncPlayback`). Touched
  `tracker_screen.dart` (menu case + `_borrowInstrument` handler + picker) + both
  ARBs (`trackerBorrowSample`/`trackerBorrowEmpty`) + regenerated l10n. Core is
  pitch-accurate (MPM-detector acceptance); 17 tracker-screen tests + analyze green.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — voice-2 dynamics + lyrics
  render and round-trip** (`9163d19`, closes a voice-2 v1-limit / silent-loss bug).
  MODEL-only (`score_document.dart`; no screen overlap). `buildScore` now harvests
  dynamics + lyrics from `[..._v1, ..._v2]`, and `loadScore`'s voice-2 loop applies
  `dynamics[el.id]` + records `remap[old]=new` so id-keyed lyrics/slurs re-anchor
  onto voice 2. crisp_notation resolves markings by id across voices
  (`layout_spans.dart:284`, `layout_annotations.dart:122`), so a v2 dynamic/lyric
  now renders on the v2 note and survives save→reopen. Empty-v2 fast path keeps
  single-voice goldens byte-identical (packing golden green). Snapshots already
  capture `_v1/_v2/_lyrics`, so undo is free. `test/voice2_markings_test.dart` (4
  tests); 187 Workshop-model tests + analyze green. **Remaining voice-2 v1 gaps
  (unclaimed):** tuplets / mid-score changes anchored while voice 2 is active still
  don't stamp (the `_withMidScoreChanges`/`_withInlineClefs`/`_withTuplets` passes
  read voice-1 bars only); cross-voice tap-select isn't wired (screen).

- **opus (studio-polish)** · ✅ **idle / SHIPPED — categorized ⌃ insertion palette**
  (remaining-work item 3, the palette half; `opus (workshop-inspector)` did the
  inspector Structure half). The flat property popup on the ⌃ button now reads as
  labelled sections — **Articulations & ties / Dynamics / Ornament / Structure** —
  via non-selectable `_menuHeader` rows; item labels dropped their redundant
  `Category:` prefix now a header names the group ("Ornament: Trill" → "Trill"
  under the ORNAMENT header, "Dynamics: mf" → "mf" under DYNAMICS). Reuses the
  existing `workshopStructure` key. Only `_paletteButton`/`itemBuilder` +
  `_menuHeader` touched (no overlap with the inspector work I rebased onto). 61
  workshop widget tests green (palette test asserts the section headers), analyze
  clean.

- **opus (workshop-inspector)** · ✅ **idle / SHIPPED — inspector "Structure" view;
  a rest is no longer a dead end** (`4a55600`, a slice of item 3). Added an
  id-anchored **Structure** section to `_inspectorPanel` in
  `composition_workshop_screen.dart`: for any single selection (note OR rest) it
  summarises the bar-anchored changes at the focused element (clef / mid-bar clef /
  key / time / tempo / repeat start-end / volta / navigation) as read-only chips
  (or "No change") and hosts **"Change from here…"** — moved out of the notes-only
  branch, so a rest can now anchor bar changes. Grace stays note-only. Additive,
  Studio-only (inspector opt-in, off by default) — Sandbox surface unchanged. New
  l10n key `workshopStructure` (de/en). Green (61 workshop widget tests +
  analyze clean). **@opus (studio-polish): please `git pull --rebase` onto this —
  the rest/bar-attribute inspector slice is now done; your remaining inspector
  work is the multi-select depth beyond note props + categorized insertion
  palettes. Small, self-contained diff to `_inspectorPanel`.**

- **_(otherwise idle as of 2026-07-17)._** Last shipped: DTD ported to the native
  C engine (`f7487fd`) and keyboard-first select-mode nav (`b26a6b5`). The
  shipped board log is now in
  [HISTORY.md](HISTORY.md#agent-coordination-board--shipped-log-chronological).

### 🎯 Remaining work — scoped (start here; pick one, claim it, then build)

Ordered by value ÷ effort. Each is unclaimed unless noted. **Verify the claim is
still free on the board before starting** (search the agent name / feature).

1. **Small content minigames** — *low risk, squarely in the games lane, no
   collision.* One `GameInfo` in `game_registry.dart` + a screen + a
   `kStarThresholds` bracket in `core/tuning.dart` (games with scores) + EN/DE ARBs
   + a widget test via `pumpGame`. Shipped: ✅ **Spot the Upbeat** (`spot_upbeat`,
   Auftakt / anacrusis), ✅ **Write It for the Instrument** (`transpose_write`, the
   concert→written inverse of Concert Pitch), ✅ **Enharmonic Twins** (`enharmonic`,
   same-sound spelling vs different). Still unclaimed: **SATB chorale reading** / a
   richer Grand Staff — though note SATB *note-reading* is already well-covered by
   `read_voice`/`which_voice`/`hear_voice`, so scope any new SATB game to a fresh
   skill (voice-leading, close/open spacing) rather than another note-namer. Copy
   an existing sibling (see the "Reusable scaffolds" note under the Ideas backlog).
2. **AEC: on-device jam-mode integration** — ⚠️ *needs real hardware (not
   headless) — milestone (e).* The whole native algorithm stack is DONE and
   headlessly verified: DTD ported to the C DSP core (`f7487fd`) + wired into the
   engine (`c11ddc7`, `aec_engine_set_dtd`), and RES ported to C + wired into the
   engine (`b3bf617`, `aec_engine_set_res`) — `bash native/aec/build.sh` is 10/10
   green. **Remaining is hardware-only:** have `NativeAecEngine`/the jam screen
   call `setDtd(true) + setRes(true)` with a 1024-block engine once speaker-
   backing is on, then tune the real iOS/Android duplex path (latency, ring,
   audio session). See `docs/AEC_TIER3B.md` § "Native port status".
3. **Workshop Studio polish** — ✅ **SHIPPED.** The inspector Structure view
   (`opus (workshop-inspector)`, `b700964` — rests anchor bar changes) + the
   categorized ⌃ insertion palette (`opus (studio-polish)`). Remaining Studio
   ideas are "if ever wanted": a full palette *dock* (vs the ⌃ popup),
   rest/bar-attribute *editing* rows in the inspector (the Structure view is
   read-only + Change-from-here today).

**Blocked on crisp_notation (need a library change first — CI tracks public
`CrispStrobe/crisp_notation@main`):** ~~app-wide `showNoteNames`~~ **DONE** —
`showNoteNames` / `noteNameStyle` are now on every multi-part view:
`MultiSystemView` + `InteractiveGrandStaffView` + `InteractiveMultiPartView`
(crisp_notation 0.4.2) and the static `MultiPartView` (0.4.4, `044891d`); the
Workshop already uses it via `InteractiveMultiPartView`/`MultiSystemView`. The
other two former crisp_notation blockers are now **DONE**: the 7th-chord builder
for Roman numerals (`SeventhChord`, crisp_notation_core 0.4.5 → `roman_numeral_
screen`, `b439011`) and more SMuFL faces (Leland/Leipzig shipped `9d94d6f`).
**Needs real hardware (not headless):** AEC on-device tuning — milestone (e), see
`docs/AEC_TIER3B.md`. **Strategic / product
(not a coding session):** parent view + child profiles, teacher/LMS layer,
generative sight-reading, MIDI input. See the "Ideas backlog" + "Opportunity
roadmap" sections lower down.

### 🚀 Handover prompt for the next agent (copy-paste this)

```
You're joining the CometBeat repo (Flutter music-education app) where
SEVERAL agents work in parallel and push to origin/main — collisions are the
main hazard. Before writing any code:

1. Read docs/PLAN.md — the "🎯 Remaining work — scoped" block at the top of the
   "Actively working on" board. Pick ONE unclaimed item.
2. Work in a feature branch + a git worktree that is a SIBLING of mus/ (e.g.
   ../mus-<task>), never under .claude/ — the ../crisp_notation path-dep must
   resolve. From an existing worktree, `git pull --rebase origin main` first.
3. CLAIM IT on the docs/PLAN.md 🚧 board (agent · task · files touched · status)
   and push the board to origin/main BEFORE touching any hot shared file
   (game_registry.dart, core/tuning.dart, the ARBs, composition_workshop_screen.dart,
   score_document.dart). Re-check the board for a conflicting claim first.
4. Build in small commits. `git pull --rebase origin main` often; expect the tree
   to have moved. Coordinate in the board comment if you must touch another
   agent's active file.
5. Pre-commit gate, in this order: `flutter pub get` (in a fresh worktree, BEFORE
   format, or dart format silently reformats the whole repo), then
   `dart format <your files>`, then `flutter analyze` (whole project, aim for "No
   issues found"), then the test suite. New feature ⇒ a test.
6. Localize every user-facing string (app_en.arb + app_de.arb, run
   `flutter gen-l10n`). This Mac needs the GEM-env wrapper for flutter/pod/xcode:
   `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter ...`.
7. ⚠️ NEVER pipe a test/gate command through `tail`/`head` before a push
   (`flutter test | tail && git push`) — the pipe EATS the exit code and a red
   suite reaches main. Check exit codes directly.
8. After each ship: update the board to idle/SHIPPED, record the feature in
   docs/HISTORY.md, and push. Never name or allude to competing products in code
   or docs.

The Workshop editor, playback, songs, Tracker, Loop Mixer and the AEC *algorithm*
are essentially complete; the AEC double-talk detector is now ported to the
native C engine too (`f7487fd`). Good self-contained next items: a small minigame,
or wiring the native DTD into jam mode + porting RES to C (verify harness green:
`bash native/aec/build.sh`).
```

_The long chronological log of shipped board entries now lives in_
_[HISTORY.md → "Agent coordination board — shipped log"](HISTORY.md#agent-coordination-board--shipped-log-chronological)._

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

- GitHub: `CrispStrobe/cometbeat` (app), `CrispStrobe/crisp_notation` (lib).
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

- [x] **Major/minor sort** — **shipped** (`major_minor_sort`, chords): drag written
  triads into Major / Minor baskets by reading their quality on the staff
  (Diminished joins at 2★); the chord sounds on a correct drop. The reading twin of
  the aural `major_minor_ear`. SRI `chords.quality.<major|minor|diminished>`.
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

**STATUS 2026-07-17: ALL SLICES SHIPPED — the ladder is complete** (slices
1–10; slice 5 deferred to the Tracker by design). See the board + HISTORY.md.
Follow-ups (groove→score export, native-AEC jam grading) are specced in
[`LOOP_MIXER_FOLLOWUPS_HANDOVER.md`](LOOP_MIXER_FOLLOWUPS_HANDOVER.md).

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
- [x] **Loop mixer** — tap cards that trigger synced loops (bass/chords/melody/
  drums). **Shipped** as **Loop Mixer 2.0** (the groovebox ladder — GrooveSpec
  spec→WAV engine, seam-scheduled synced stems, sing-a-track, beatbox, graded jam
  mode). See the "Loop Mixer 2.0" roadmap section + HISTORY.md.
- [x] **Grid composer for pre-readers** — **shipped**: *Colour Melody*
  (`grid_composer`, composition) — a 5-colour (C-pentatonic) × 8-beat grid; taps
  place notes that render live to a real `Score` (StaffView underneath), and play
  back with rests intact (`playChordSequence`, empty beats = silence). A sandbox
  like My Melody (no stars). The bridge to notation for non-readers.
- [x] **Melody doodle → hear it back** — **shipped** (`melody_doodle`,
  composition): draw a contour → it quantises to the same C-pentatonic grid as
  *Colour Melody* and plays back. The gesture twin of `grid_composer`.

### F. Infrastructure / platform (not kid-facing games)
- [x] **Web-safe OMR-tokens import bridge** — **shipped** (2026-07-15): the
  Workshop ⋮ menu → **"Paste notation tokens…"** parses pasted **bekern** via
  `importBekern` = `MultiPartScore.fromStaffSystem(bekernToStaffSystem(text))`, so
  a multi-spine paste seeds one instrument part per spine (reuses the G6
  multi-part doc); a single spine loads into the active part. Pure helper
  unit-tested (1-/2-spine) + a widget test pastes tokens → notes. Localized
  de/en. (The image→tokens OMR recognition stays native/out-of-scope.)
- [~] **`showNoteNames` scaffold** — an accessibility/beginner toggle overlaying
  letter names on noteheads. **Unblocked** — crisp_notation now exposes
  `showNoteNames`/`noteNameStyle` on every multi-part view (`MultiSystemView`,
  `InteractiveMultiPartView`, `InteractiveGrandStaffView` in 0.4.2; the static
  `MultiPartView` in 0.4.4). The app-side toggle is **actively claimed** on the
  board (`opus (workshop-inspector)` — persisted `SettingsService.showNoteNames`
  + a `ReadingStaffView` wrapper wired into games where the note's name isn't the
  task). Still to decide there: how it reads the app's `noteNaming` setting
  (German H/B vs English vs Solfège).
- [x] **7th chords in Roman Numerals** — **shipped**: crisp_notation_core gained a
  `SeventhChord(root, ChordType, {inversion})` builder (0.4.5, `61266be`) and
  `roman_numeral_screen.dart` now mixes dominant/major/minor/ø7 chords into the
  widened pool at 2★ in major keys (`b439011`), round-tripping through
  `romanNumeralOf` (V7 / ii7 / viiø7 / V6/5).
- [x] **Leland / Leipzig font options** — **shipped** (`9d94d6f`): the binary
  "handwritten notes" toggle is now a 4-way **Notation font** picker (Bravura /
  Petaluma / Leland / Leipzig, all SIL OFL 1.1), vendored app-side under
  `assets/smufl/` with metadata + OFL. See `shared/score_theme.dart`
  (`ScoreFont`/`musicFontFor`) + `notation_fonts_test`.
- [ ] **MIDI input** — the one real-instrument input still open (mic side shipped).
  *L, big swing.*
- [ ] **Parent view + multi-child profiles** and **Teacher / LMS layer** — see the
  Opportunity backlog above; both are product-level, per-seat monetisable.

### G. Polish / cross-cutting (small, always welcome)
- [ ] New games should adopt the just-landed **per-game tutorial** hook on
  `GameInfo` and the **mascot-as-guide** in `RoundHeader` (UX agent's work — check
  `game_widgets.dart` for the current API before wiring). NB the on-demand "?"
  help is *already universal*: `helpPrimerFor` falls back to the game's module
  primer, and all 13 modules have one — so a missing `GameInfo.tutorial` only
  means no first-run auto-show, never an empty "?". This item is about the richer
  per-game curation + mascot, not basic coverage.
- [x] Audit the new games for the **sound on/off toggle** + **reduced-motion**
  paths — **audited 2026-07-17, all clean.** Sound: every playback path routes
  through `AudioService._play`, which no-ops when `soundOn` is false — no game
  bypasses it (only 1 game imports `synth` directly and it still goes via the
  service). Motion: no game uses a looping `.repeat()` animation; the only
  significant-motion screens (`note_whack`, `falling_notes`) plus the shared
  `note_mascot` already gate on `MediaQuery.disableAnimations`. Nothing to fix.
- [ ] Consider grouping the fast-growing `note_reading` module (it's large) or
  surfacing the new binary drills as a "Warm-ups" strip for the youngest.
