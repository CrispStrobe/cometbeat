# CometBeat — canonical plan & pending work

> **This is the canonical PLAN** (2026-07-25 doc consolidation). All pending and
> planned work lives here; everything shipped is recorded in
> [docs/HISTORY.md](docs/HISTORY.md). Detailed curriculum/roadmap planning and the
> per-agent coordination board are in [docs/PLAN.md](docs/PLAN.md); the remaining
> single-topic reference docs are linked from the "Consolidated backlog" section
> at the end of this file.

🚧 **Idle / Last-shipped (Agent checkpoint)**
- Shipped: Synth & FX Editor (embeds Sound Lab directly into Tracker via `instrument_editor.dart`).
- Shipped: Multi-Sample Groundwork (`MultiSampleInstrument` added to `tracker_engine.dart` with correct monophonic choking semantics).

## Cello fingering (string · position · finger) — step 1 SHIPPED, steps 2–3 pending

`lib/core/notation/bowed_arranger.dart` fingers a bowed line the way the guitar
tab arranger fingers a fretted one: same Sayegh/Viterbi optimum path, but the state
is a hand FRAME (mode × anchor) instead of a set of `(string, fret)` pairs, so the
finger falls out of the geometry. Cello + double bass (Simandl 1-2-4); extensions
and thumb position are frame modes with per-note costs; a `BowedSkill` profile caps
the technique with soft costs, so a learner's fingering stays in first position and
only the notes that force it reach higher. Untrained, no model asset.
`bowed_score_fingering.dart` is the score-level entry point (id-keyed side table,
like `Score.slurs`). Gates: `kCelloFirstPosition` re-derived from geometry
(`test/bowed_arranger_test.dart`) + agreement against printed CC0 editions
(`test/bowed_arranger_accept_test.dart`, 50.3% of 193 printed fingers).

**Where the ceiling is.** A 135-point weight sweep spans 38.3–50.3%, so ~50% is
what authored weights can do on that gold set. The violin literature says why:
string choice is nearly solved by geometry, hand POSITION is subjective (ten
professionals disagree; F1 ≈ .24–.31), and expressive position choice is exactly
what a learner doesn't need — which is why the capped profiles are the useful
product and the uncapped one is the research problem.

Pending, in order:
1. **Consumers — DONE.** Fingerings show on the cello play-along, on the song screen
   (a toggle) and on the cello "Play it" staff; the games drill positions 1–4; and a
   fingered part **prints** (Export… → PDF, marks passed as a layout argument so the
   saved song is untouched). Remaining in this bullet: a **string indicator** (Roman
   numerals — `Annotation` already renders text above a staff, but attaching one to
   an imported score hits the same immutability wall as fingerings did), and
   **MusicXML-with-fingerings — DONE** (`Score.copyWith`/`NoteElement.copyWith`
   shipped in crisp_notation with a source-reading drift guard; the song screen
   exports a fingered copy through the standard export sheet).
   Historic note — the original text of this bullet:
1. ~~**Consumers.** Nothing renders this yet.~~ Cheapest real wins: fingering digits
   on cello parts in Song Book / play-along (copy `bowedFingeringDigits` into
   `NoteElement.fingerings`, which the layout engine already draws), a string
   indicator for the cello games, and lifting `cello_first_position.dart`'s games
   beyond first position. Needs a `T` glyph before thumb position can be engraved.
2. **More labels (the real lever).** Dense cello fingering barely exists: the
   entire 42k-score corpus yields **193 printed fingers** on 4 files, and no public
   cello fingering dataset exists at all. The one avenue with volume is OMR over
   long-PD fingered method books (Dotzauer, Duport, Kummer, Lee, Franchomme,
   Popper, Grützmacher, Klengel) — Audiveris has an optional "fingering digits"
   recognition topic. Bowed strings are *easier* than the guitar case: a digit over
   a note is unambiguously the finger, with none of the circled-string ambiguity
   that stalled guitar OMR. String and position stay hidden variables, which the DP
   can infer from finger + pitch + continuity (an EM setup, not plain supervision).
   ⚠ Pre-1930 prints only; a modern edition's fingering is a fresh editorial layer.
3. **Learned emission.** `BowedPositionModel` is the seam (twin of
   `TabPositionModel`); the DP keeps reachability and movement, a model only biases
   which reachable frame wins. This DP already *is* an HMM's decoder, so the first
   step is fitting transition/emission tables rather than training a network — a
   small state space needs far fewer labels than the guitar labeler did. The violin
   TNUA dataset (217k note annotations, 10 violinists) is **unlicensed** → dev/eval
   only, never shipped weights, and its geometry is violin's, so it validates the
   architecture rather than supplying cello labels. Score with MRR/nDCG against
   multiple editions, not single-label agreement.

## Automatic play-along — live pitch detection (feature area)

Live pitch/chord detection from the mic, turned into real practice modes:
tuner, sing-along, play-along with a moving score, and games. Everything sits
on one pure-Dart detection core so it stays testable headlessly and from a CLI.

## Sound Library / Instrument / FX unification (ONE ITEM LEFT — see below)

Unify the places that currently drift apart: the Tracker instrument selector,
Workshop Score "Play with an instrument", Audio Editor track/clip voicing, and
Sound Library creation tools.

- **One Sound Library surface for instruments** — *partly done; the residue is
  `@codex (score-editor-web)`, see the board.* `showMyInstrumentsSheet` IS that
  picker and is already the one every "choose an instrument" surface opens:
  Workshop, both Trackers, Drumkit, Voice Lab, the settings voice picker and
  Audio Editor (`daw_screen.dart:2963`, `includeBuiltIns: true`). What is still
  open is the *other* direction — Advanced Tracker's parallel one-off entries
  (Mod Archive, Load SoundFont, catalog browsing) belong inside that picker, and
  the web-side install path needs to work or say why not.
- ✅ **Generate FX creates instruments — DONE (verified 2026-07-26).**
  `_generateFx` (`my_instruments_sheet.dart:470`) lives in the Sound Library
  creation menu and returns a `SavedInstrument` that is merged straight into the
  library list, so a generated FX is thereafter pickable anywhere the sheet
  opens — Tracker, Workshop playback, Audio Editor voicing. It is **not**
  reachable from Audio Editor > Add clip, which was the anti-requirement.
- ✅ **Add clip adds timeline material — DONE (verified 2026-07-26).** The
  Add-clip menu (`daw_screen.dart:~4390`) offers exactly the specified set and
  nothing else: `dawAddFromLibrary`, `dawImportAudioFile`, `dawAddMusic`,
  `dawExtractSample`, `dawAddBeat` (+ tune). No sound-design entry — that work
  happens in the Sound Library.
- ✅ **Voice Shaping is an audio FX module — DONE (verified 2026-07-26).**
  `voiceShape` / `voiceChipmunk` / `voiceDeep` / `voiceRobot` / `voiceRadio` are
  `FxType` values with defaults in `fx_spec.dart`, and `daw_screen.dart`'s single
  `_clipEffectTypes` list feeds **all four scopes** — `_trackFxEditor`,
  `_masterFxEditor`, `_busEditor` and `_openClipInspector` — plus the marked-range
  FX action. So the voice-shaping DSP already processes any clip, track, bus,
  master or segment, which was the ask.

## Loop Studio consolidation (DONE — every bullet audited 2026-07-26)

> Audited against the code, bullet by bullet, because the IN-PROGRESS marker had
> outlived the work: ✅ **one loop document** — captured sung/beatboxed layers are
> symbolic (`MelodicPattern` / `DrumRowsPattern` via `setUserTrack` /
> `setBeatTrack`), never baked stems. ✅ **one transport** — `GaplessLoopPlayer`
> over flutter_soloud, seam-safe periodic buffers, boundary swaps without a
> restart. ✅ **one primary workflow** — the Beginner-Tracker hub tile is retired
> and `PerformScreen` is out of navigation (referenced only by its own file and
> tests), so the redundant entries are gone. ✅ **scannable controls** — BPM
> slider (`loop_mixer_screen.dart` ~3685) plus numeric field (~3702). ✅
> **notation is a view** — per-track staves following the selection, sharing the
> transport, with treble/bass/**grand** chosen from each track's actual range.
> ✅ **verification** — pure tests for periodic rendering, boundary swaps,
> editable per-track events and staff choice, plus widget tests for the
> workflow/transport.
>
> The one thing left is a judgement call, not code: whether to DELETE the archived
> `perform_screen.dart` (dead but still tested) now that parity is proven. The
> retirement map gates that on a sign-off, so it stays.

Live Looper / Perform, Loop Mixer, and Beginner Tracker currently expose three
overlapping but incompatible editing experiences. They must converge on one
musical loop document and one transport; the beginner view is a simpler skin,
not a second playback engine.

- **One loop document.** Every audible voice/track must have editable symbolic
  events (drums, pitched notes, chords, and imported material) plus its selected
  instrument. Editing a beat/tune must change those events and re-render the
  exact voice, never a black-box baked stem.
- **One transport.** Start, pause, stop, loop length, BPM, and playhead phase
  are shared. Loop swaps happen at a musical boundary without stopping and
  restarting the audio player. The loop buffer must be periodic and seam-safe.
- **One primary workflow.** Loop Studio opens in a focused beginner layout with
  direct track controls; an Advanced view reveals the full matrix, per-track
  instruments, sends, effects, and arrangement. Remove redundant mode choices
  where they only lead to different non-editable copies of the same groove.
- ✅ **Controls must be scannable — DONE (verified 2026-07-26).** The BPM control
  is a slider (`loop_mixer_screen.dart` ~3685, `kMinTempoBpm`..`kMaxTempoBpm` →
  `_setTempo`) PLUS a numeric field (~3702, `onSubmitted` → `_setTempo`), so
  Chill/Groove/Fast is no longer the only tempo control. The style presets that
  remain are GROOVE styles, not tempo — which the bullet explicitly allows.
- ✅ **Notation is a view of the document — DONE (grand staff landed 2026-07-26).**
  It engraves every enabled track, follows the selection, and shares the
  transport. The missing piece was the clef: `clefForGrooveCells` returned ONE
  clef, so a track straddling middle C was forced onto a single staff and its far
  end vanished under ledger lines (the "hard-coded clef choices" the retirement
  map lists under Replace). `grooveStaffForCells` (`groove_notation.dart`) now
  returns `GrooveStaff.treble|bass|grand` from the range actually used, and
  `_buildScorePanel` renders `GrandStaffView` for the grand case — reusing the
  primitive the Tab Workshop already uses, not new notation code.
  The rule is "at least two notes clearly on EACH side of middle C" (a third of
  margin either way). A single low pickup or high grace note therefore does not
  split the staff. A span-based rule was tried and removed: >2 octaves fires on a
  treble line with one low pickup — exactly the incidental note the count guard
  exists to ignore — and it was redundant, since notes bunched at two extremes
  already give two clear notes per side. +20 tests (15 classifier boundaries,
  5 widget).
- **Verification.** Add pure tests for periodic loop rendering, boundary swaps,
  editable per-track events, and clef selection; add widget tests for the
  beginner/advanced workflow and transport states before removing old surfaces.

## Five-mode product architecture (DECIDED)

The product has five top-level authoring modes. They are different musical
mental models over one shared project/document model, not five unrelated apps:

1. **Tracker** — a classic pattern-sequencer successor: pattern matrix,
   rows/channels, instruments, ticks, effect commands, macros, sample
   playback, pattern order, and tracker interchange (MOD/XM/S3M/IT/MIDI).
2. **Loop Studio** — a creator-to-professional loop workflow: record, capture,
   quantize, overdub, arrange sections, edit every voice, choose instruments,
   mix, and perform over loops. Simple and Advanced layouts edit the same loop
   document; they are not separate modes.
3. **Score** — multi-part conventional notation and engraving: voices, chords,
   lyrics, clefs, analysis, playback, and print/interchange exports.
4. **Tab** — guitar/bass/cello/string-instrument notation: tuning, strings,
   frets, fingering, chord diagrams, notation, and instrument-aware playback.
5. **Audio** — the DAW: clips, regions, recording, buses, automation, inserts,
   Voice Shaping and future FX, mixing, and final export.

### Loop Studio UX contract

Loop Studio opens directly into an audible, editable project. The first screen
must make the following obvious without tutorials: what is playing, which tracks
are active, where the playhead is, how long the loop is, the BPM, and where the
user can change the actual notes/hits.

- The top transport bar is shared and stable: Start/Pause, Stop, loop length,
  BPM slider plus numeric field, undo/redo, Save, and Export.
- The first content band is the track lane. Each track exposes play/mute/solo,
  level, instrument, record/overdub, and an Edit button. Editing opens the
  actual symbolic events for that track, not a decorative preview or a baked
  audio blob.
- Simple layout shows one friendly event lane per track with large cells,
  piano/pad input, quantize, and a small number of safe controls. It is suitable
  for a child copying a performance video.
- Advanced layout adds the full matrix, exact event durations, velocity,
  per-track instruments, effects, sends, automation, section scenes, and
  arrangement. It remains the same project and transport.
- Settings use compact grouped bars like Score Workshop: BPM/loop, key/scale,
  swing, quantize, sound, and arrangement. Preset words such as Chill/Groove/
  Fast may remain as named starting points, but never as the only tempo control.
- Sheet Music is a synchronized projection of selected Loop Studio tracks:
  multiple voices are visible, clefs follow pitch range, grand staff is used
  for a genuinely mixed voice, and the same transport controls it.
- Record, import, and play-in actions always create editable track events first;
  rendering to audio is an explicit bounce operation into Audio mode.

### Integration and retirement map

- **Keep and integrate:** `LoopEngine` timing/pattern model, `LoopStack` undo /
  mute primitives, `BeatBridge` / `MelodyBridge`, groove capture and quantize,
  per-track instrument voicing, scene/arrangement concepts, periodic rendering,
  groove notation, and the shared Sound Library.
- **Refactor into Loop Studio:** Perform's recording/overdub flow, Loop Mixer's
  track cards, beat editor, tune editor, scene launcher, jam/follow tools, and
  the transport. Their symbolic data must become one editable track model.
- **Use as Tracker interop:** Beginner Tracker's approachable keyboard/grid
  ideas and Advanced Tracker's precise pattern/effect concepts. Tracker remains
  a separate top-level mode because tick/pattern authoring is a different job.
- **Replace:** duplicate Loop Mixer/Perform playback clocks, restart-based loop
  swaps, black-box tune/beat previews, hard-coded clef choices, and separate
  beginner/advanced persistence formats.
- **Archive behind a branch until parity is proven:** the current standalone
  Perform screen, current Loop Mixer screen, and Beginner Tracker screen. Do not
  delete them until Loop Studio passes transport, recording, editable-track,
  import/export, notation, and web smoke tests; then keep their useful pure
  primitives but remove their redundant navigation entries.

### Shared project boundaries

```
Project
├── Tracker patterns / instruments / effect commands
├── Loop Studio tracks / symbolic events / sections
├── Score parts / voices / metadata
├── Tab arrangements / tunings / fingerings
├── Audio tracks / clips / regions / automation
└── shared instruments, samples, FX, and export references
```

Interop is explicit: Tracker patterns can become Loop Studio tracks; Loop
Studio tracks can open in Tracker, Score, Tab, or Audio; Score and Tab can feed
pitched Loop Studio tracks; Audio can receive any mode as a clip and can return
through transcription/analysis with documented losses.

## Cross-mode FX + interop consolidation (SHIPPED — all 12 items, `feature/fx-interop`)

**Why.** The five modes each grew their own FX vocabulary and their own
converters over what is already *one* shared DSP library (`lib/core/audio/
crisp_dsp/`, 20 modules) and *one* shared notation model (crisp_notation
`Score`/`MultiPartScore`). The result is four incompatible effect models, five
copies of `pitchFromMidi`, two copies of the duration ladder, and an interop
graph with holes (no Tab↔Tracker) where every edge silently drops whatever the
target model cannot express.

**Audit (2026-07-26, measured on `origin/main`).**

| FX model | Mode | Types | Params | Automation | Serialized | Chain |
| --- | --- | --- | --- | --- | --- | --- |
| `DawClipEffect` / `DawClipEffectType` (`daw_timeline.dart`) | Audio | 27 | ✅ `Map<String,double>` | ✅ | ✅ JSON | ✅ |
| `TrackerChannelEffect` (`tracker_engine.dart`) | Tracker | 7 | ❌ hardcoded | ❌ | name only | ✅ |
| `VoiceEffect` (`crisp_dsp/voice_fx.dart`) | Instrument | 9 | ❌ hardcoded | ❌ | ❌ | ❌ |
| `TrackEffect` (`daw_timeline.dart`, legacy) | Audio | 7 | via bridge | ❌ | ❌ | ❌ |
| — | Tab | **0** | — | — | — | — |
| ad-hoc sends (`loop_engine.dart`) | Loop | partial | ❌ | in `GrooveSpec` | ❌ |

`DawClipEffect` is a strict superset of the other three and is the only one with
params, automation, and persistence. It is therefore the **canonical model**;
the other enums become *preset name* lookups that resolve to a chain.

**Interop edges.** Present: Score↔Tracker (`tracker_notation.dart`,
`multipart_to_tracker.dart`), Score↔Module MOD/XM/S3M/IT (`mod/
module_notation.dart`), Score↔Tab (`TabDocument.toScore`/`.fromScore`),
Beat→Tracker (`beat_to_tracker.dart`), Loop→Score (`groove_notation.dart`,
`melody_bridge.dart`). Missing: **Tab↔Tracker**, **Loop↔Tab**, and a single
entry point with a **documented loss report**.

**Two design decisions that the whole arc rests on.**

1. *One FX rack.* `FxSpec { FxType type; bool enabled; Map<String,double>
   params; Map<String,List<FxAutomationPoint>> automation }` plus
   `applyFxChain` / `applyFxChainStereo`, living mode-neutrally in
   `lib/core/audio/fx/`. Every mode holds `List<FxSpec>`. Legacy enums survive
   as presets, so no persisted file breaks.
2. *Lossless side-car.* A converter that cannot represent something in the
   target model must not drop it. `SymbolicAnnotations` is a bag keyed by a
   stable event address (`track/channel/part` + `step/tick` + `voice`) carrying
   the un-representable payload (string+fret, technique, capo, tracker fx
   command, lyric, articulation). Round-trip identity then becomes a *testable
   property*, not a hope.

### Ordered work items

Each item is independently shippable and independently testable. Build in
order; A1 and B1/B2 unblock everything else.

#### A — one FX rack across all five modes

- **A1. Extract the FX engine into `lib/core/audio/fx/`.** *(unblocks A2–A6)*
  - New `fx/fx_spec.dart`: `FxType` (the 27 `DawClipEffectType` members, same
    names, same order), `FxSpec`, `FxAutomationPoint`, `FxPreset`,
    `defaultFx(FxType)`, `fxPresetChain(FxPreset)`, `toJson`/`fromJson`,
    `cacheKey`.
  - New `fx/fx_chain.dart`: `applyFxChain(Float64List, List<FxSpec>, int
    sampleRate)` and `applyFxChainStereo(...)`, moved verbatim from
    `daw_timeline.dart` (`applyClipEffectChain`, `_applyClipEffect`,
    `_applyStereoClipEffectChain`, `_applyAutomated*`).
  - `daw_timeline.dart` keeps the old names as aliases —
    `typedef DawClipEffect = FxSpec;`, `typedef DawClipEffectType = FxType;`
    (Dart allows typedefs to enums), `const defaultDawClipEffect = defaultFx;`,
    `const applyClipEffectChain = applyFxChain;` — and re-exports `fx/`.
    **No call site in `daw_service.dart` / `daw_screen.dart` changes.** This is
    deliberate: those files are hot with parallel DAW agents.
  - Done when: `daw_timeline.dart` contains no DSP dispatch; the DAW suite is
    green unchanged.
  - Tests (`test/fx_spec_test.dart`, `test/fx_chain_test.dart`): every `FxType`
    round-trips JSON; unknown type name → `null`, not a throw; `enabled:false`
    is bit-identical identity; an empty chain is identity; each type on a
    1 kHz sine is finite and within ±1.0; `cacheKey` is stable across equal
    chains and differs on any param change.

- **A2. Tracker channel FX become `FxSpec` chains.**
  - `TrackerChannel.fxChain: List<FxSpec>` alongside the existing
    `effects: List<TrackerChannelEffect>`; `fxForChannelPreset(e)` maps each of
    the 7 presets to the params currently hardcoded in `applyChannelEffect`.
  - `tracker_song_codec.dart` writes `fxChain` (full params) and still reads
    legacy `effects: ['reverb', …]`; a file written by the old codec loads to
    the equivalent chain.
  - Render path prefers `fxChain` when non-empty, else the legacy list.
  - Tests: for all 7 presets `applyFxChain(stem, fxForChannelPreset(e))` is
    **sample-identical** to `applyChannelEffect(stem, e)`; a legacy
    `.cbtrk` fixture loads and renders identically; chain length is preserved
    (the `mixStems` same-length invariant).

- **A3. Instrument / Voice FX become `FxSpec` chains.**
  - `fxForVoicePreset(VoiceEffect) → List<FxSpec>` for all 9 presets.
  - Instrument Builder (`instrument_editor.dart`) gains a free-form chain on
    top of the preset, persisted with the instrument
    (`tracker_instrument_codec.dart`).
  - Tests: for all 9, `applyFxChain(s, fxForVoicePreset(v))` is sample-identical
    to `applyVoiceEffect(s, v)`; `kPitchPreservingVoiceEffects` members still
    round-trip a pitch probe within 5 cents after the chain.

- **A4. One FX rack widget.** `lib/shared/widgets/fx_rack.dart` +
  `lib/core/audio/fx/fx_params.dart` (a descriptor table: per `FxType`, the
  param list with min/max/default/unit/l10n label key).
  - The rack renders add / remove / reorder / bypass plus one slider per
    descriptor — **driven entirely by the table**, so a new `FxType` needs no
    UI edit.
  - Hosts: DAW inserts, Tracker channel FX, Instrument Builder, Loop Studio
    sends, Tab track FX.
  - Tests: `fx_params_test.dart` asserts every `FxType` has a descriptor and
    every descriptor default equals `defaultFx(type).params`; widget test adds
    reverb → tweaks `roomSize` → reorders → bypasses and asserts the emitted
    chain.

- **A5. Loop Studio sends become `FxSpec`.** `GrooveSpec` gains a per-track
  chain; the `KU1.` share token stays backward compatible (absent key = no FX).
  - Tests: token round-trip with and without FX; a spec without FX renders
    byte-identically to today (regression guard on the seam-click invariant).

- **A6. Tab gets FX.** `TabTrack.fxChain`; tab playback routes
  `renderMultiPartWithInstrument` output through `applyFxChain`. Ship a guitar
  preset set (clean / crunch / overdrive / chorus / spring reverb / wah) as
  `FxPreset` entries, so this is data, not new DSP.
  - Tests: preset chains are non-empty and length-preserving; a tab with an
    empty chain renders byte-identically to today.

#### B — symbolic core DRY

- **B1. One `pitchFromMidi`.** `lib/shared/midi_pitch.dart` already holds the
  canonical version. Delete the copies in `mod/module_notation.dart`,
  `tracker_notation.dart`, `tab_document.dart`, `groove_notation.dart` and
  import it. Keep a per-file re-export only where the symbol is part of that
  file's public surface.
  - Tests: `midi_pitch_test.dart` covers all 128 MIDI numbers (step, alter,
    octave), and asserts the four ex-copies' call sites still spell identically.

- **B2. One duration ladder.** New `lib/shared/music/step_duration.dart` with
  `durationToSteps`, `durationLadder(stepsPerBeat)`, `decomposeSteps`. Delete
  the verbatim copies in `mod/module_notation.dart` and `tracker_notation.dart`;
  point `tab_document.dart`'s `kTabDurations`/`_stepsOf` at it.
  - Tests: golden decompositions for 1..64 steps at stepsPerBeat 1/2/4/8;
    `decomposeSteps` always sums back to the input; parity assertions against
    the pre-refactor outputs for both ex-copies.

#### C — the interop matrix

- **C0. `lib/core/interop/symbolic_annotation.dart` — the side-car.**
  - `EventAddress { int track; int step; int voice; }` (stable, comparable),
    `SymbolicAnnotations` = `Map<EventAddress, Map<String, Object?>>` with typed
    accessors for the known keys (`string`, `fret`, `technique`, `capo`,
    `fxCmd`, `fxParam`, `lyric`, `articulation`, `velocity`).
  - JSON round-trip; merge; `restrictToTrack`.
  - Tests: round-trip, address equality/hash, unknown keys survive untouched.

- **C1. Tab ↔ Tracker, direct and lossless.** `lib/core/interop/tab_tracker.dart`.
  - `trackerSongFromTabDocument(TabDocument) → (TrackerSong, SymbolicAnnotations)`
    — **one tracker channel per string**, which is the natural mapping and makes
    string/fret survive *natively* rather than via the side-car.
  - `tabDocumentFromTrackerSong(TrackerSong, {SymbolicAnnotations?}) → TabDocument`.
  - Technique mapping where a native tracker command exists: slide →
    portamento (`3xx`), vibrato → `4xx`, hammer/pull → legato (no retrigger),
    bend → pitch slide; everything else rides the side-car.
  - Tests: **round-trip identity** on a fixture `TabDocument` (columns,
    string/fret, techniques, tuning, capo) with and without annotations; a
    slide really becomes a portamento cell; a 6-string tab yields 6 channels.

- **C2. Loop ↔ Tab.** Via `Score` + annotations, reusing C0/C1 and the existing
  `groove_notation.dart`. Pitched loop tracks become a tab arrangement using
  `tab_arranger.dart`'s fretting plan; a tab becomes a pitched loop track.
  - Tests: a pitched groove → tab → groove preserves pitches and step grid.

- **C3. `lib/core/interop/project_bridge.dart` — one façade + loss report.**
  - `enum AppMode { tracker, loop, score, tab, audio }`.
  - `ConversionResult { Object? document; SymbolicAnnotations annotations;
    ConversionReport report; }` where `ConversionReport { List<String> lost;
    List<String> approximated; bool lossless; }`.
  - `convert({required AppMode from, required AppMode to, required Object doc})`
    dispatches to the existing converters (C1, `tracker_notation`,
    `module_notation`, `TabDocument.toScore`, `multipart_to_tracker`,
    `daw_sources`) — it **adds no new DSP or notation logic**, it is routing
    plus honest reporting.
  - Tests: a matrix test over all 25 `(from,to)` pairs — each either produces a
    document or reports `unsupported`; **no pair throws**; identity pairs are
    lossless; every lossy pair names what it lost.

- **C4. "Open in…" everywhere.** `lib/shared/widgets/open_in_menu.dart`, driven
  by `ProjectBridge`, shown in all five mode toolbars; it previews the loss
  report before converting ("Tab → Tracker keeps string/fret; bends become
  pitch slides").
  - Tests: widget test — the menu lists exactly the modes the bridge can reach
    from the current mode, and the report text renders.

### D — finishing the interchangeability map (SHIPPED, `feature/fx-interop`)

> D1–D3 done, and **E1–E4 wire it all into the screens**: the shared `FxRack`
> now hosts in the Tracker's channel-effect sheet (E1), a new per-track Tab
> guitar rig (E2) and the Loop Mixer's master bus (E3), and the shared
> `OpenInMenu` is in the Tab and Advanced Tracker toolbars (E4).
>
> Two things learned wiring it, worth keeping: (a) `OpenInMenu` needed a
> `targets` filter, because CONVERTING and OPENING are different problems — the
> bridge can produce a document for every reachable mode, but a screen can only
> offer a destination it has a route to push, and offering one it cannot open
> would convert the user's work and then drop it. (b) Every FX host is additive:
> the legacy preset path (7 tracker chips, 2 loop sends) stays as the quick
> path and still renders through the old code, so no saved project changes how
> it sounds.
>
> **Not wired, deliberately:** `daw_screen.dart` — daw-ux owns its FX UI and it
> already has one; and Loop's own "Open in…" (the Loop Mixer already has a
> hand-rolled "Open in Tracker" round-trip that auto-publishes on exit, which is
> richer than the generic menu — replacing it is that agent's call, not mine).

C1–C4 built the matrix, but two edges are still second-class and one section of
the Tracker roadmap below (§2 *Ecosystem Interchangeability*) is only half
wired. All three are the same shape: a converter exists in ONE direction, so the
reverse either does not exist or detours through a mode that distorts it.

- **D1. Direct Tracker <-> Loop, symbolically.** Today the Loop Mixer's "Open in
  Tracker" goes `Loop -> Score -> Tracker` (`trackerSongFromMultiPart`), and
  C3's `tracker -> loop` edge goes via **Tab** — which fret-maps everything onto
  six strings. That is fine for a guitar part and wrong for a piano or drum
  channel. Add `lib/core/interop/loop_tracker.dart`:
  `loopCellsFromTrackerChannel` / `trackerChannelFromLoopCells`, both symbolic
  (a `PatternCell` run <-> a channel's cells), and repoint C3's two tracker/loop
  edges at it.
  - Both models are already a monophonic-per-step grid, so the only real work is
    the grid ratio: a loop step is an eighth, a tracker row is
    `1 / timing.stepsPerBeat` of a beat. Whole-number ratios are exact; anything
    else quantizes and must say so.
  - Tests: round-trip identity at matching grids; a 4-steps-per-beat tracker
    song halving cleanly onto the loop grid; velocity and chords surviving;
    the report naming the quantization when the ratio is not integral.

- **D2. Tracker percussion -> DrumKit** (PLAN.md §2.2's missing half).
  `beat_to_tracker.dart` already turns a `SharedBeat` into percussion channels;
  nothing reads them back, so a beat edited in the Tracker cannot return to the
  Drum Kit. Add `sharedBeatFromTrackerSong` in
  `lib/core/interop/drum_tracker.dart` — the exact inverse, so round-trip
  identity is a testable property rather than a hope.
  - Tests: `beat -> song -> beat` is identity (rows, tempo, swing, per-drum
    voices); a song with no percussion channel yields null rather than an empty
    beat; a channel edited in the Tracker shows up in the returned rows.

- **D3. §2.3 is already done** — `tab_tracker.dart` (C1) is exactly the
  "translate plucked-string channels into Tab strings" item, and does it better
  than the roadmap asked (one channel per string, so the mapping is native
  rather than re-derived from pitch). Marked below.

### Collision policy for this arc

`daw_timeline.dart`, `tracker_engine.dart`, `tracker_song_codec.dart`,
`loop_engine.dart`, and `tab_document.dart` are all hot with parallel agents.
Every item above is therefore **additive with legacy aliases kept**: no call
site is rewritten in the same commit that moves code. Claim on the
`docs/PLAN.md` board before each item, and push after each.

## Tab Editor navigation (DONE)

- Add a three-dot overflow menu to the Tab Editor and move lower-frequency
  actions out of the crowded top bar.
- Keep transport, import, save, and primary editing controls immediately
  reachable; put inspect mode, clear/reset, and future utility actions in the
  overflow menu.
- Ensure every menu action has an explicit effect in the editable tab document,
  rather than only changing a label or preview.

Implemented in `7e05bd55`, `62efa301` and covered by `test/tab_workshop_test.dart`:
the overflow menu owns utility actions, chord picking changes voicing/playback,
and the no-op Demo riff action was removed.

## Architecture (done, `feature/pitch-detection-spike`)

```
mic (record plugin) ─┐
WAV file ────────────┼─→ StreamingAudioAnalyzer ─→ PitchReading  (mono, MPM/NSDF)
stdin PCM (CLI) ─────┘        (sliding window)   └─→ ChordReading  (chromagram+templates)
```

- `core/audio/pitch_analysis.dart` — McLeod Pitch Method detector → note + cents.
- `core/audio/chroma_analysis.dart` — FFT + chromagram + fuzzy chord templates.
- `core/audio/streaming_analyzer.dart` — pure-Dart windowing, shared by mic + CLI.
- `core/audio/microphone_pitch_service.dart` — the only plugin-facing file.
- `core/audio/wav_io.dart` — PCM16 WAV reader.
- `bin/listen.dart` — CLI: `--wav`, `--stdin` (live), `--selftest`, `--chords`.
- `core/audio/play_along.dart` — scoring engine for play/sing-along (see below).

Detectors are proven headlessly (synth-based unit tests, all green) and via the
CLI on real audio; the mic path is verified on macOS. Only the live *acoustic*
feel (latency, real-instrument chord accuracy) still wants on-device tuning.

## Modes & games

### 1. Tuner — DONE (real)
Chromatic/cello tuner: big note, cents needle, in-tune zone. Cello-first
(fretless intonation is where it matters). Keeper tile.

### 2. Play-along (moving score) — DONE
Target notes are scored against your live pitch (correct pitch within a cents
window for enough of a note's duration = hit); `PlayAlongEngine` is pure-Dart
and unit-tested. **Four switchable scroll views** (a menu in the app bar):
highway (piano-roll), falling (vertical), notation (real engraved staff +
moving cursor, via crisp_notation), and coach (big current/next note for beginners).
Cello/guitar/keyboard charts + count-in metronome.

### 3. Sing-along — DONE (v1)
The same engine + screen with a vocal-range melody preset. Voice is the same
monophonic detection; only the chart/labelling differs.

### 4. Chord listener — DONE (spike)
Names the chord you strum/play with runner-up guesses + a chroma bar chart.

### 5. Chord-progression play-along — DONE
A moving chord chart (C–G–Am–F): strum the progression as it scrolls; each
chord is scored by the fuzzy ChordDetector (`ChordProgressionEngine`, top-2
lenient match). Records to ProgressService + stars. Validated end-to-end via
the BlackHole loop — all four roots detected on real captured audio (the
7th/maj7 variants are expected overtone pickup, hence the lenient match).

## Songbook — scan sheet music into playable songs (DONE — audited 2026-07-26)

> Audit against the code, because the PLANNED marker was badly out of date:
> ✅ **collection model** — `SongCollection` in `user_songs_service.dart` +
> `songbook_screen.dart` (named, ordered books; drag-reorder; remove-from-book
> without deleting the song). ✅ **persistence** — `UserSongsService.load/_save`
> over SharedPreferences. ✅ **OMR → notation bridge** — `songs/import/
> omr_import{,_io,_stub}.dart` + `import_screen.dart`, consuming CrispEmbed's
> GGUF engines as intended. ✅ **per-song metadata** — composer / key / tempo,
> derived from the stored MusicXML, persisted, shown in the book (2026-07-26).
> ✅ **source image retained** — `import/omr_source_store{,_io,_stub}.dart` keeps
> the photo in the same `~/.cache/crisp_notation` tree as the model cache, and
> `ImportedSong.hasSourceImage` records it (`4c86257b`).
> ✅ **re-run correction flow** — `_RescanButton` on the song row re-runs
> recognition on the retained scan and replaces the notation, so a bad read is
> fixed without re-photographing (`4c86257b`).
>
> ⇒ **This section is now complete.** Everything it scoped is built.
>
> ✅ Related sibling-repo bug, FIXED (crisp_notation `d8589c5`): the MusicXML
> reader took its tempo from `<metronome>` only and ignored `<sound tempo="…">`,
> so files from exporters that write just the playback attribute imported with no
> tempo. `<metronome>` stays authoritative (it is what the score PRINTS);
> `<sound tempo>` is the fallback. Our own writer already emitted both, which is
> exactly why round-trip tests never caught it.

Product feature, not a detector: let the user build **songbooks** from real sheet
music. Flow: import/scan a score photo → **Optical Music Recognition** → notation
→ store as a song the existing play-along/notation modes can drive → group songs
into named collections (browse / search / reorder / export).

- **OMR engine — reuse CrispEmbed, don't rebuild.** `CrispEmbed` already ships
  two validated OMR engines with Dart FFI bindings (`CrispEmbedOmr`): **SMT**
  (printed pianoform → bekern) and **Polyphonic-TrOMR** (printed/camera-robust →
  rhythm/pitch/lift → symbolic notation, `cstr/tromr-GGUF`). Auto-detected from
  the GGUF; a plain photo of a staff system works. So this app consumes those
  GGUFs via the FFI wrapper rather than porting any model here.
- **Scope TBD:** persistence format (song = source image + recognized notation +
  metadata), per-song metadata (title/composer/key/tempo), collection model,
  and an edit/re-run flow for correcting recognition mistakes before it becomes a
  chart. Bridge OMR notation → the app's internal note/chart representation that
  `PlayAlongEngine` / the `crisp_notation` notation view already consume.
- Flagged here so the OMR work in CrispEmbed and this app's songbook UI stay
  aligned; sequencing vs. the AEC/backing work is open.

## Audio codecs — what remains

Import/export is **DONE and at parity across native and web** (shipped
2026-07-26; see [docs/HISTORY.md](docs/HISTORY.md) and the canonical table
[docs/AUDIO_CODEC_MATRIX.md](docs/AUDIO_CODEC_MATRIX.md)). What is left:

- **FLAC encode — not planned.** glint decodes FLAC and ships no FLAC encoder.
  Writing one is a real project, and nothing in the app asks to write FLAC.
- **Vorbis encode — scoped, unclaimed, probably not worth it.** Redundant for
  export (Opus wins at every bitrate; two `.ogg` producers is a UX trap). The
  ONLY genuine trigger is **writing `.sf3` SoundFonts**, which are Vorbis by
  definition — today we can only read them. Full handover with the clean-room
  affidavit, an 8-slice plan and an honest cost estimate lives in the **glint**
  repo: `docs/VORBIS_ENCODER_HANDOVER.md`. Do not start it unless SoundFont
  authoring is actually wanted.
- **AIFF is read-only.** We parse AIFF/AIFF-C and never write it. ~40 lines of
  pure Dart if the symmetry is ever wanted; nothing requests AIFF output today.
- **Native MP3 is not the default.** Both encoders ship and the export sheets
  let you pick; the default stays the pure-Dart one because its output is what
  the golden/ffmpeg tests pin and it is identical on every platform. Flipping it
  is one line once glint's has mileage here.
- **Per-platform builds are CI's job now**, not a manual chore:
  `.github/workflows/glint-native.yml` covers all five platforms plus the wasm,
  and `ci.yml`'s `android-build` asserts the codec is actually inside the APK.

## Known constraints / follow-ups (not yet done)
- **Backing audio vs. mic (AEC):** see the dedicated section below — count-in
  metronome + optional backing (tiers 0/1) shipped; a Dart AEC core is the next
  step; a native full-duplex plugin is the production fix.
- **Localization:** DONE — the four modes have de/en `AppLocalizations` keys,
  and the tuner/chord/play-along note readouts respect the note-naming setting
  (German H, solfège) via `spelledMidiName`. Chart names + the Hz/clarity
  readout stay language-neutral.
- **Progress/stars:** DONE — play/sing/guitar/keyboard play-along record to
  `ProgressService` (score = notes hit) with `kStarThresholds` brackets and a
  `GameResultView` (stars + Play again) on finish.
- **Real-instrument tuning:** validated end-to-end through the real macOS audio
  stack via a **BlackHole loopback** self-test (sox plays a scale to the
  BlackHole *output* device; ffmpeg captures the BlackHole *input*; the CLI
  detects it). Recovered a full C-major scale within a few cents — thresholds
  held on real captured audio, no retune needed. Reproduce:
  ```bash
  ffmpeg -f avfoundation -i ":<BlackHole idx>" -t 8 -ar 44100 -ac 1 bh.wav &
  sox scale.wav -t coreaudio "BlackHole 2ch"          # non-intrusive; default device untouched
  dart run bin/listen.dart --wav bh.wav
  ```
  **Robustness characterized** headlessly (`test/pitch_robustness_test.dart`):
  the detector holds pitch through ±20-cent 5-6 Hz **vibrato** (within 25¢), never
  reports a WRONG note as **noise** rises (it gives up gracefully, surviving to
  ≥0.25 noise amplitude), detects soft (pp) dynamics while gating out silence,
  and stays on the fundamental for **rich/bright timbres** (no octave errors).

  **The real-acoustic-instrument-into-a-physical-mic pass is human-gated** (needs
  someone to actually play). On-device protocol:
  1. Cello/guitar/voice → open the **Tuner**; sustain each open string / a sung
     note. Expect the right note, needle steady, cents within a few of a
     reference tuner.
  2. **Play along** a slow chart (½× tempo); confirm hits register and the live
     dot tracks. 3. **Chord listener**: strum open chords; confirm the top guess.
  4. Note failure modes (bow noise, breath, room reverb, low SNR) for tuning
     `clarityThreshold`/`energyGate` against real signal.
- **Phase 3 (full polyphonic transcription):** still out of scope; would layer
  on the same chromagram.

## Backing audio & echo cancellation (AEC)

Goal: play audible backing through the speaker *during* play/sing-along without
the mic grading the speaker. Two corrections shape the design:
1. **Pitch-domain gating is self-defeating here.** In play-along the user
   *matches* the backing, so echo and desired signal share the same pitch — you
   can't gate "the backing's pitch" without gating the user. Real cancellation
   must be **waveform-domain** (subtract a reference-derived echo estimate).
2. **A pure-Dart AEC starves on alignment.** `audioplayers` (out) and `record`
   (in) are two plugins on two clocks — no shared timebase. The *algorithm*
   ports fine (we have an FFT); the *deployment* needs sample-accurate ref+mic,
   which only an OS-integrated or native full-duplex path provides.

### Tiers
- **Tier 0 — headphones (DONE).** No acoustic coupling → backing works with zero
  AEC and zero pitch loss. Backing toggle plays the melody at the downbeat;
  label says "use headphones". The clean answer for real practice.
- **Tier 1 — platform AEC (DONE).** Backing toggle also flips on
  `RecordConfig.echoCancel` (iOS VoiceProcessingIO / Android VOICE_COMMUNICATION
  / macOS voice-processing). Real OS AEC, but its AGC/NS reshape the waveform and
  cost pitch accuracy. **Needs on-device measurement** (can't be tested via the
  BlackHole digital loopback — no speaker→mic path).
- **Tier 2 — Dart pitch gate: SKIPPED** (self-defeating for play-along, per #1).
- **Tier 3a — Dart AEC core (BUILT + VERIFIED; blocked on 3b for deployment).**
  `core/audio/echo_canceller.dart`: a compact **constrained frequency-domain
  block-NLMS** echo canceller (the linear core of Speex MDF / WebRTC AEC3),
  reusing the FFT. Its stated verification exists — `test/echo_canceller_test.dart`
  asserts high ERLE on an echo-only mix and near-end preservation under
  double-talk (verified 2026-07-26). Nothing is left to write here: deployment
  needs Tier 3b to feed it aligned ref+mic, which is the real blocker.
- **Tier 3b — native full-duplex plugin (DESIGNED, not started in code).** One
  native audio engine that owns playback+capture on a shared clock and runs a
  real AEC. This is the production fix. Full architecture, Dart API, per-platform
  build, CI-safety rules and verification plan: **[docs/AEC_TIER3B.md](docs/AEC_TIER3B.md)**.
  Stack: **miniaudio** (MIT-0, full-duplex host) + **SpeexDSP** (BSD, the AEC).
  Days–weeks; must be built in an isolated branch and kept out of the app's
  pubspec until it compiles green on all 5 CI platforms.
- **Tier 4 — neural (IF NEEDED).** `DTLN-aec` (MIT, TFLite, tiny, on-device) or
  `DeepFilterNet` (MIT/Apache). Watch: speech-trained nets may not preserve a
  sung/played note's *pitch*.

### Permissive libraries (all BSD/MIT/Apache — usable or portable)
SpeexDSP echo canceller (BSD, port/FFI) · WebRTC AEC3 / webrtc-audio-processing
(BSD, FFI) · DTLN-aec (MIT, TFLite) · DeepFilterNet (MIT/Apache) · miniaudio
(MIT-0) · Oboe (Apache) · KISS FFT / PFFFT (BSD).

## Testing
- `flutter test` — unit tests for every detector + the play-along engine.
- `dart run bin/listen.dart --selftest --chords` — headless smoke test.
- `dart run bin/listen.dart --stdin` fed from `sox`/`ffmpeg` — live mic.
- macOS/iOS builds need the GEM-env wrapper (see CLAUDE.md / appstore.md).

## Advanced Tracker module: Feature Gap Analysis & Roadmap

To evolve our tracker into a world-class, perfect UX environment (drawing on
classic pattern-editor conventions without adopting a rigid hardware-emulator
path), we must focus on universal instrument support, seamless ecosystem
interchangeability, and power-user ergonomics.

### 1. Universal Instrument Ecosystem & Editing
**Current State:** 
Our `TrackerInstrument` hierarchy (`AdditiveInstrument`, `SfxrInstrument`, `SampleInstrument`) is robust but lacks a unified, deep editing UI. We want to support all kinds of sounds interchangeably without forcing hardware constraints.

**Implementation Steps:**
1. ~~**Instrument Editor Overlay:** Create `instrument_editor.dart` inside the Studio UI with a real-time testing keyboard.~~ (DONE)
2. ~~**Sample Editor:** For `SampleInstrument`, build a waveform viewer with draggable handles for `loopStart`/`loopLength`, ping-pong toggles, and base MIDI tuning.~~ (DONE)
3. ~~**Synth & FX Editor:** For `SfxrInstrument` or FM models, embed the existing `lib/features/sound_lab/sound_lab_screen.dart` to expose its rich slider UI directly in the tracker.~~ (DONE)
4. ~~**Multi-Sample Groundwork:** Enable `MultiSampleInstrument` to map different sample IDs across the keyboard (essential for complex DrumKits and realistic acoustic patches).~~ (DONE)

### 2. Ecosystem Interchangeability (Workshop, Looper, DrumKit, Tab) — DONE
**Current State:**
All three items shipped (C1, D1, D2). Every edge is symbolic and reversible, and
every conversion returns a `ConversionReport` naming what it could not carry;
`ProjectBridge` (`lib/core/interop/project_bridge.dart`) is the single entry
point. What remains open is UI: no screen hosts the shared `FxRack` or the
`OpenInMenu` yet — see the D-series note in the cross-mode FX section above.

**Implementation Steps:**
1. ~~**Looper / Loop Mixer Bridge**~~ (DONE, D1) — and done SYMBOLICALLY rather
   than as a baked stem, which is the stronger form: `lib/core/interop/
   loop_tracker.dart` converts a tracker channel to/from `PatternCell`s, so the
   result stays editable in the Loop Studio instead of arriving as audio. A
   baked `Float64List` is still available via `TrackerEngine.renderLoopFloat`
   when a clip really is wanted.
2. ~~**DrumKit Bridge**~~ (DONE, D2) — `beat_to_tracker.dart` already carried
   DrumKit → Tracker; `lib/core/interop/drum_tracker.dart` adds the inverse
   (`sharedBeatFromTrackerSong`), so the trip is now two-way and
   `beat → song → beat` is asserted to be identity.
3. ~~**Tab Editor Translation**~~ (DONE, C1) — `lib/core/interop/tab_tracker.dart`
   does this better than described: rather than mapping pitches onto strings
   after the fact, it puts **one channel per string**, so the fingering is
   native and survives a round trip instead of being re-derived.

### 3. Visual Excellence & Workflow (classic tracker ergonomics)
**Current State:**
The Studio UI (`tracker_screen.dart`) is functional but lacks the slick, real-time visual feedback and rapid navigation of elite modern trackers.

**Implementation Steps:**
1. ~~**Real-time Oscilloscopes & Meters:**~~ Tap the `_stem(channel)` cache in `TrackerEngine`. Pass this data to an `OscilloscopeWidget` using `CustomPainter` to draw vivid, real-time waveforms and VU meters per channel. (DONE)
2. **Smooth Scrolling Matrix:** Evolve the grid rendering to support pixel-smooth playhead scrolling (rather than rigid row-by-row jumping) and a dynamic pattern matrix where channel loops can be visualized block-by-block.
3. **Advanced Keyboard Handling:** Add `FocusNode` and `KeyEvent` handlers for lightning-fast multi-cell selection (shift+arrows), cross-channel copy/paste, and value interpolation directly in the grid.

### 4. Deep Instrument Modulation (Macros & Envelopes)
**Current State:**
Instruments are static per note run, lacking tick-level modulators.

**Implementation Steps:**
1. **Macro Data Model:** Create a `MacroSequence` class for Volume, Panning, Pitch, and Arpeggio envelopes.
2. **Tick-level Rendering:** Transition `mixStems` and `renderChannel` to evaluate notes tick-by-tick, updating the instrument's active frequency and amplitude based on the `MacroSequence`.

### 5. Comprehensive Effect Command Set & Flow Control
**Current State:**
`TrackerCell` holds hex `fxCmd/fxParam`, but we currently only process volume commands. 

**Implementation Steps:**
1. **Unify Pitch Effects:** Move arpeggio/porta/vibrato from the `TrackerEffect` enum into the hex pipeline, evaluating them tick-by-tick during `renderChannel`.
2. **Flow & Groove Commands:** Support Speed (`Fxx`), Pattern Break (`Dxx`), and Position Jump (`Bxx`). Rewrite `renderSong` as a dynamic state machine that respects these navigation commands.
3. **Sub-row Timing:** Implement Note Delay (`EDx`) and Note Cut (`ECx`) directly in the offline renderer to allow complex swing and ghost notes.


### 5. Replay fidelity — gaps found by comparing against an independent player

Read across to **savage_modplayer** (Daniel Müller, Swift/macOS, WTFPL) — like
ours an **independent replay engine rather than a libopenmpt wrapper**, covering
MOD/S3M/XM/IT. It is player-only (no editing, no writers, no conversion), so the
comparison is only useful on the *replay* axis; on scope we are the larger
system. Two places we are already ahead and should not "learn" backwards:
**Catmull-Rom interpolation** (they use linear) and **module writing** (they
never attempt it — which is where most of our recent effect-mapping bugs lived).

⚠️ **Take approaches and hardware facts, not expression.** WTFPL permits literal
copying, but a Paula clock constant is a fact and "compare spectra as well as
RMS" is a method; lifting Swift into Dart would buy nothing and muddy provenance.

**G1 — Our reference-comparison metrics are too weak to catch a tuning error.**
`test/tracker_audio_regression_test.dart` renders through our pipeline and
`openmpt123` and compares **duration + RMS deltas**. Their `reference_compare.py`
compares duration, **envelope correlation**, **onset/lag alignment** and
**spectral similarity**. That gap is not academic for us: we convert Amiga
periods to MIDI notes (`periodToMidi`/`midiToPeriod`) and render via
`_freqOfMidi`, i.e. **A440 equal temperament rather than the Paula clock**. A
systematic tuning offset from that choice leaves duration identical and RMS
nearly identical — our harness would pass it. We have not measured whether we
actually drift; the point is that **our current metrics cannot tell us**.
*Do this first: the other gaps are hard to evaluate without it.*

**G2 — No stated cross-platform determinism policy.** They document theirs and
measured it: `tanh` in the limiter rounds differently in glibc vs Darwin libm →
LSB shifts in ~0.01% of samples, ~115 dB down, inaudible. We have the same
exposure (`tracker_replayer.dart` `_tanh` is built on `exp()`, still platform
libm). **We are safe today** — our byte-identical gates compare two renders
*inside one run*, and `mod_codec_test`'s golden compare is module **bytes**
(parse→write, pure integer), not audio. The trap is ahead of us: if anyone
commits a golden *rendered* WAV compared byte-exactly it will be intermittently
red between macOS dev and Linux CI. Decide the policy before that happens.

**G3 — No Amiga hardware model.** Two concrete absences: the **LED low-pass
filter** (~3.2 kHz, the "dull" Amiga mode) and a **Paula clock** with PAL
(3,546,894.6 Hz) / NTSC switching, pitch derived from clock ÷ output rate. Ours
is a pure c5speed/finetune model. ➜ **`E0x` IS the Amiga filter command**, so
this lands inside `@opus (tracker-complete)`'s claimed "E0x/S0x hardware filter"
work — theirs to take, noted here so it is not lost.

**G4 — We have no written non-goals.** They state theirs: no pre-1.17 OpenMPT
bug-emulation (swing, legacy pattern loops, proprietary envelope release nodes),
MPTM detected-but-refused, IT to `cmwt=0x0216`. Writing down what we refuse to
chase is how a replayer stays finishable — ours is currently open-ended.

**G5 — Harness brittleness (5 minutes).** `_kOpenMptPath` is pinned to
`/opt/homebrew/Cellar/libopenmpt/0.8.7/bin/openmpt123` — one Homebrew version,
macOS only. Resolve the binary from `PATH` instead.

## Consolidated backlog (2026-07-25 doc sweep)

Pending work carried over when ~40 handover/scoping/status docs were consolidated.
**Group 1** items came from docs that were *deleted* (full detail preserved here).
**Group 2** items still have a live reference doc — the pointer is authoritative;
kept here so nothing is lost from the canonical plan.

### Group 1 — residuals from deleted docs (no other home)

> ⚠️ **This list is STALE in places — check before you build.** An audit on
> 2026-07-26 found **nine** of its items already shipped (the whole Audio-FX
> block bar one, and the starter-module generator), because the list was frozen
> when ~40 docs were consolidated and never re-checked against the code. Each
> line below now says ✅/⬜ with `file:symbol` evidence where it's been verified.
> **If you pick something up, grep for it first** — with this many agents, a
> stale to-do costs more than a missing one. Items with no marker are unverified,
> not necessarily open.

**Tab / labeler / library** (was `TABCNN_GGML_HANDBACK`, `LIBRARIES_AND_TAB_SCOPING`):
- CrispASR-side (external repo): ship `libcrispasr` with `@loader_path`-relative
  rpaths (it currently bakes the CI build path, so a downloaded dylib can't find
  `@rpath/libggml.0.dylib`); lay the libs in one flat dir (split across `src/` +
  `ggml/src/` today); optional `CrispasrSession.tab()` wrapper in the pub package.
- ❌ **DO NOT BUILD — settled as excluded (corrected 2026-07-26).**
  `thesession_source.dart` was listed here as "specced, absent", which reads as
  an invitation to implement it. It isn't one:
  [docs/CORPUS_LICENSING.md](docs/CORPUS_LICENSING.md) — the authoritative doc —
  lists thesession under **"Not reachable (settled)"** and states *"thesession.org
  is ODbL **+ a no-LLM clause + composer-copyright risk** → excluded entirely;
  hosting it on HF can't honour 'no LLM use'."* It also notes ODbL is Tier C
  (share-alike), and **Tier C is not shippable at all until the app enforces
  SA-propagation** — once SA content enters an Editor, every export/save/share
  has to affirm SA on the output, which isn't built.
  So this needs no code; it needed the two docs to stop disagreeing. If it is
  ever revisited it starts with the SA-propagation work and a licence review, not
  with a source adapter.
  *(For context, `lib/features/library/sources/` holds cometbeat_catalog ·
  commons · freepats · github_abc · gregobase · modarchive · openscore · vcsl.)*
- IMSLP + CPDL/ChoralWiki conditional, country-gated library sources (A4) — gated
  behind the "real legal review" the scoping doc called for.
- `DonationConfig` tile flip-on (A5) — `donation.dart` exists but stays disabled
  until a Ko-fi/PayPal URL is set.

**Audio FX** (was `FX_HANDOVER`) — ✅ **VERIFIED DONE 2026-07-26, except one item.**
Audited each line against the code rather than re-implementing; all but the last
had already shipped, so this block was a trap for the next agent to redo:
- ✅ Standalone `ring_mod` → `crisp_dsp/ring_mod.dart` (`ringModFx`).
- ✅ Full `distortion` set → `crisp_dsp/distortion.dart` has `hardClip`/`softClip`/
  `fuzz`/`wavefold` (`DistortionKind`).
- ✅ sfxr FM/LFO → `crisp_dsp/sfxr.dart` carries `fmDepth`/`lfoDepth`/`lfoSpeed`.
- ✅ Cubic-Hermite interpolation → `resampleCubic` in `crisp_dsp/resample.dart`,
  used by `sound_library.dart` + `tracker_replayer.dart`.
- ✅ Multi-effect per-channel chain → `tracker_engine.dart` applies an ordered
  chain of inserts per stem; the DAW has clip/track/bus/master chains.
- ✅ Reverb/delay send on the Loop Mixer → `loop_engine.dart` `_applySend` /
  `_applySendStereo`.
- ✅ FFT-convolution reverb → `crisp_dsp/convolution_reverb.dart` (synthesized IR,
  FFT overlap-add) existed and was tested, **but was only reachable from the Voice
  Lab.** Now wired into the shared FX rack as `FxType.convolutionReverb`
  (appended; `.cbdaw` stores effects by name) with tail/decay/pre-delay/mix, so
  clips, tracks, buses and the master can use it alongside the algorithmic
  Freeverb. Tests assert it actually behaves like a reverb — decaying tail,
  pre-delay moves the onset, deterministic (fixed IR seed, so baked clips stay
  byte-identical), and audibly different from `FxType.reverb`.
- ✅ **DONE (verified 2026-07-26)** — pitch envelope on both voices:
  `pitchEnvSemitones`/`pitchEnvDecay` on `crisp_dsp/sfxr.dart`'s `SfxParams` AND
  on `synth.dart`'s additive voice (`238fa39e`). ⇒ **the whole Audio-FX block is
  now done.**

**Samples** (was `CC0_SAMPLE_SOURCE_HANDOFF`):
- ✅ **DONE (verified 2026-07-26)** — "starter-module generator" shipped as
  `starterBeatHits` in `lib/features/library/starter_pattern.dart` (pure, with
  `test/starter_pattern_test.dart`) plus the Tracker action wired in
  `advanced_tracker_screen.dart` (`case 'starterBeat'`).

**DAW real-time engine** (was `SOUND_AND_DAW_ROADMAP` P2.1):
- 🔶 **IN PROGRESS — slice 1 SHIPPED 2026-07-26: the windowed render.**
  `renderTimelineWindowStereo(timeline, fromSample:, toSample:)` renders just the
  asked-for span instead of allocating a full-length buffer per lane plus the
  master. A two-second preview of a twenty-minute arrangement now costs two
  seconds of memory, and clips that don't overlap the window are never touched.
  **Byte-identical to the matching slice of the full render** — that's the whole
  contract, and 18 tests pin it across overlapping lanes, mid-fade windows, clip
  FX, stereo width, mute/solo, past-the-end (zero-padded) and unlimited renders.
  Why it's exact: a clip's FX chain runs on that clip's own bounded buffer, so it
  doesn't depend on where the window falls, and the master limiter is per-sample
  and stateless (now extracted so both paths run literally the same code).
  `timelineWindowIsBounded` names the constructs that DO couple across a window —
  track inserts, track gain automation, bus routing/sends, master FX — because a
  reverb tail or an automation ramp reaches in from outside it. Those lanes fall
  back to a full render + slice: still exact, just without the saving. (Same
  philosophy as the Tracker's `songCanStreamFlowVariable`.)
  ⬜ **The rest of P2.1 is OWNED, not unclaimed — do not pick it up here.** The
  coordination board settles it: *"real-time streaming engine (**= @tracker-ui
  §E3, THEIRS**)"*, and `opus (tracker-ui)` is 🚧 ACTIVE. That covers driving
  PLAYBACK block-by-block (so faders/automation apply live instead of on the next
  bake), live-playable instruments, and input monitoring. The Tracker has also
  already shipped its own streaming mixer (Renderer v2.1), so the engine likely
  exists there to reuse.
  The windowed render above was deliberately scoped to stop at that line: it is a
  pure additive core function, useful on its own, and commits nobody to an engine
  choice. **@tracker-ui: `renderTimelineWindowStereo` is ready to be the DAW's
  block source when §E3 lands** — it already renders an arbitrary
  `[from, to)` span byte-identically, which is the awkward half of block playback.
- ✅ **DONE** P0.1 convolution reverb — `crisp_dsp/convolution_reverb.dart`
  (synthesized IR + FFT overlap-add) landed and is tested; as of 2026-07-26 it's
  also wired into the shared FX rack as `FxType.convolutionReverb`, where before
  it was reachable only from the Voice Lab.

**Score Workshop** (was `WORKSHOP_G6_HANDOVER`, `WORKSHOP_NEXT_HANDOVER`,
`WORKSHOP_PLAN`):
- Richer inspector: multi-select view, rest properties, bar-attribute editing.
- Categorized *insertion* palettes (dynamics / lines / repeats / text), distinct
  from the modification inspector.
- Voice-2 v1 gaps: voice 2 carries no dynamics/lyrics/slurs; tuplets and mid-score
  changes anchored while voice 2 is active stamp to voice-1 bars; cross-voice
  tap-select is unwired; `buildGrandStaff` shows voice 1 only.
- Grace-note LIST beyond a single run (a crisp_notation library ask); cross-part
  in-place ghost/drag note entry on `MultiPartView` (the "C11" ask).
- Wire `Measure.actualDuration` into the pickup/anacrusis path; verify rendered
  output reflects crisp_notation's metric-aware secondary beaming.

**Advanced/Beginner Tracker UX** (was `HANDOVER_DAW_UX` §C — also on the docs/PLAN.md
codex backlog): collapse the oversized Advanced-Tracker menu into Import/Open ·
Library · Edit · View · Playback · Export groups and align its import/save
vocabulary with Score Workshop; make the Beginner Tracker a genuinely capable kid
live-loop surface (quick start, layer parts, record a voice, arrange sections).

### Group 2 — pointers to live reference docs (detail lives there)

- **Tracker replayer effect coverage** → [docs/REPLAYER_EFFECT_COVERAGE.md](docs/REPLAYER_EFFECT_COVERAGE.md):
  `Rxy`/`Txy` importer wiring (one line each in the `.xm` reader); fine F-nibble
  slides (need a source-format flag); `Gxx`/`Hxy`/`Mxx`/`Nxy` global/channel volume
  (need a mix-stage scalar); `Pxy`/`Kxx`/`Lxx`/`Xxx` + XM volume-column mini-commands;
  `E0x`/`E8x`/`EFx` (rare).
- **Tracker format fidelity** → [mod_pending.md](mod_pending.md).
  **🚨 ACTIVE / HARD REQUIREMENT: the module renderer must NEVER exceed 500 MB
  RAM** for any render (long native IT/XM included). The DEFAULT render must
  produce output in bounded time-blocks streamed to a sink — never hold a
  whole-song `Float64List` mix. Verify peak RSS with `bin/bench_render.dart`.
  - **Shipped (feature/tracker-complete, 2026-07-25):** render benchmark
    (`bin/bench_render.dart`, reports peak RSS); per-note buffer reuse +
    native-NNA two-pass render; native IT/XM fadeout release; S3M
    stereo/AdLib/packed + DP30 ADPCM decode + OPL/AdLib FM-approximation
    synthesis; MOD `M!K!`; XM 16-bit; cross-format `S1x/S2x/S3x/S4x` mapping;
    bounded streaming/range export
    (`--stream/--from-order/--to-order/--chunk-orders`); export-loss report;
    native flow/order timeline view. **Memory:** importer sample-dedup (the big
    win — the importer was cloning each sample up to ~120× across keymap slots),
    streamed CLI output, and direct-accumulate for the variable + native stereo
    render paths — buddhia3.it went ~2.8 GB→~440 MB, all byte-identical.

  #### Renderer v2 — per-sample streaming mixer + quality

  **Status 2026-07-25:** v2.1 (streaming mixer) SHIPPED and v2.2/v2.3 quality
  largely SHIPPED. Every song type now streams in ~65k-frame row-chunks with
  per-voice state carried across chunks → **flat RAM at any length, byte-identical**
  (buddhia3.it ~2.8 GB→347 MB; wonderfulpain 873→335 MB; a 20-min command song
  1.87 GB→283 MB, flat to 40 min). Quality: resonant IT low-pass filter (initial
  cutoff/resonance + Zxx, per-voice biquad, gated so non-filter songs stay
  byte-identical); 4-point Catmull-Rom interpolation in the tick path (was linear);
  MultiPLAY-style note-on soft-start + hard-cut residue anti-click. Oracle A/B
  unchanged (no regression).

  **Polish round SHIPPED (2026-07-26):** MOD tag-alias preservation
  (OCTA/FLT8/CD81/M!K!); IT filter cutoff **envelope**; IT **MIDI-macro** filter
  (F0F0 cutoff/resonance); **opt-in deterministic TPDF dither** (`--dither`,
  default off = byte-identical); finished **cross-format Sxy** mapping + accurate
  export-loss report (S0/S5/S7/S9/SA/Z verified genuinely unmappable, named in the
  report); **streamed the last native path** (long mono native-NNA now <500 MB —
  a 17.9-min song 264 MB flat); **OPL2 waveform-select + connection topology** for
  AdLib synthesis; **velocity-range + non-sample multi-sample zones** (model +
  render + editor). All corpus-byte-identical where required, oracle-gated where
  output changed, each with unit tests.

  **Dropped (proven pointless):** 2× oversampling of the resonant filter — the IT
  filter is a linear biquad capped ~5.1 kHz, far below Nyquist, so it cannot
  alias; oversampling only helps nonlinear/near-Nyquist filters.

  **Genuinely remaining (small / niche):** IT `\x87` non-default MIDI macros +
  per-channel active-macro selection; cycle-exact OPL2 (per-note ADSR operator
  envelopes — the static-PCM AdLib synth can't express them); one contrived memory
  edge (stereo + flow + non-variable + long + native — not corpus-exercised);
  deeper native editors (raw effect-memory, native S3M header, in-place
  flow-command editing, multi-split-per-note velocity UI). Original v2 plan below.

  Reference architecture studied: **MultiPLAY** (`github.com/logiclrd/MultiPLAY`,
  cloned at `../MultiPLAY`). It plays MOD/XM/S3M/IT in a few MB of RAM with good
  quality by (a) holding **one PCM copy per distinct sample** with keymaps as
  pointer/index tables (`sample_instrument.h:47` `sample* note_sample[120]` +
  `tone_offset[120]`; `Load_IT.cc:1331`), and (b) a **pure sample-by-sample
  streaming mix** — one output frame accumulated from all voices, pushed to the
  sink, no whole-song/pattern buffer (`MultiPLAY.cc:759-1014`). Its quality is not
  a fancy interpolator (it uses 2-point **linear**, `math.h:14`) but: all mixing in
  **double**; **anti-click** (10-sample note-on fade-in `sample_builtintype.h:402`
  + decaying residue tail on hard cut `channel.cc:180,600`); a per-voice **2-pole
  resonant IT filter** (`channel.cc:622`); correct **looped-neighbour**
  interpolation; NNA via lightweight extra voices that **share PCM**
  (`channel.cc:279-344`, `Channel_DYNAMIC.cc`).

  - **v2.1 — per-sample/block streaming mixer (durable ≤500 MB at ANY length).**
    Replace the whole-song `Float64` L/R accumulator (the last non-streaming piece,
    ~230 MB) with a MultiPLAY-style mix: walk order→pattern→row→tick; each channel
    is a **voice state struct** (fractional `readPos` + integer index, envelope
    cursor, fade, filter state, effect memory); accumulate all voices into a small
    fixed **block** (a few ms), convert to Int16, stream to the sink; reuse the
    block. NNA/DCT/DCA = lightweight ancillary voices sharing PCM (no extra audio).
    Envelopes = shared node shape + per-voice cursor (linear interp). RAM becomes
    flat regardless of song length; targets ≤500 MB for the whole corpus AND
    arbitrarily long songs, in-app playback included. Byte-identical where the math
    already matches; any unavoidable divergence documented + oracle-verified.
  - **v2.2 — quality parity with MultiPLAY (deliberate, documented output change,
    oracle-gated):** double-precision mix end-to-end; **anti-click** note-on ramp +
    hard-cut residue tail; per-voice **2-pole resonant IT filter** (Zxx / IT filter
    envelopes); correct looped-neighbour interpolation.
  - **v2.3 — quality BEYOND MultiPLAY (our differentiators):** 4-point
    **cubic/Hermite** interpolation (we already use cubic on some paths — unify it),
    optional **2× oversampling** before the filter, and **TPDF dither** at the final
    Int16 cast (MultiPLAY does none of these). Each opt-in-verified vs the oracle.
  - **Verification:** `bin/bench_render.dart` peak RSS < 500 MB on buddhia3.it,
    _dont_look_back_.xm, and a synthetic multi-hour song; `bin/oracle_ab.dart`
    A/B vs libopenmpt for quality; the acceptance suites stay green.

  - **Other remaining (lower priority):** unmapped cross-format effects
    (`S0/S5/S7/S9/SA/Z`); MOD FLT8/OCTA alias preservation; cycle-exact OPL; deeper
    native editors (raw effect-memory, native S3M header, velocity zones, in-place
    flow editing); per-sample gain/pan; exact envelope release curves.
- **Tracker GUI + interop ideas** → [docs/TRACKER_GUI_HANDOFF_IDEAS.md](docs/TRACKER_GUI_HANDOFF_IDEAS.md)
  and [docs/TRACKER_IDEAS.md](docs/TRACKER_IDEAS.md): envelope editor UI, per-pattern
  length UI, shared `MusicIoMenu` import/export, groove↔Tracker↔Loop-Mixer bridges,
  drumkit/BoomBox screen + more drum voices, VU meters + on-screen keyboard,
  `SoundLibraryService` persistence, Song→WAV export, sample-borrow-from-module,
  sample loop-point editing, instrument ADSR envelopes, CI module fixtures.
- **Sound Library UI (Advanced Tracker §C)** → [docs/SOUND_LIBRARY_UI_CONTRACT.md](docs/SOUND_LIBRARY_UI_CONTRACT.md):
  localize `soundfont_sheet.dart`; l10n the 5 new `Drum` voices; `SoundFontRef` cheap
  persistence; route "Export module" through PCM-preserving `moduleDocFromSong`; wire
  `SoundLibraryService` over `instrumentToJson`/`fromJson`.
- **Neural TTS packaging** → [docs/TTS_MACOS.md](docs/TTS_MACOS.md): release
  dylib embed + Developer-ID sign; iOS `.xcframework`; Android `jniLibs` per ABI;
  prove the web/WASM `crispasr` path; optional CPU-only build.
- **OMR on pure-Dart ONNX** → [docs/OMR_ONNX_HANDOVER.md](docs/OMR_ONNX_HANDOVER.md):
  export TrOMR/SMT to ONNX + publish to HF; validate ONNX-vs-ggml parity; add
  `omr_onnx.dart` behind `recognizeSheetMusic`, route web → onnx.
- **Native AEC** → [docs/AEC_TIER3B.md](docs/AEC_TIER3B.md) / [native/aec/README.md](native/aec/README.md):
  milestone (e) on-device tuning on real iOS/Android hardware; app opt-in
  `setDtd(true)`+`setRes(true)` on a 1024-block engine when speaker-backing is on;
  wire the adaptive learning-rate into `aec_shim`/`aec_engine`; optional SpeexDSP
  behind a build flag only if real-room residual demands it.
- **Transcription frontier** → [docs/TRANSCRIPTION_SOTA_HANDOFF.md](docs/TRANSCRIPTION_SOTA_HANDOFF.md):
  W-METRE metrical quantiser (note durations/tuplets/ties via DP); W-PIANO-MT3
  slice 2 (MT3 seq2seq multi-instrument); W-DRUMS finer kit + pattern-quantise;
  optional W-NOTATION PM2S neural model. (Patent-free algorithm rules:
  [docs/TRANSCRIPTION_SCOPING.md](docs/TRANSCRIPTION_SCOPING.md) appendix.)
- **SVC/RVC determinism** → [docs/SVC_SITE_B_HANDOVER.md](docs/SVC_SITE_B_HANDOVER.md):
  confirm the exported RVC graph contains the Site-B `RandomNormal` node; run the
  3-way harness (Python-ref vs `rvc.dart` vs ggml) and gate on `max_abs < 1e-5`.
- **Corpus / licensing engineering** → [docs/CORPUS_LICENSING.md](docs/CORPUS_LICENSING.md):
  Tier-C ShareAlike/ODbL stays unshippable until the app enforces SA-propagation on
  Editor export/save/share (not built); broader pop/film title-copyright sweep of
  PDMX; catalog re-emit + payload purge of the 24 quarantined holiday MIDIs;
  per-file licence verification for Iowa MIS / Discord GM SFZ / AVL / Flame.
- **Tab-labeler quality** → [docs/TAB_LABELER_ROADMAP.md](docs/TAB_LABELER_ROADMAP.md):
  movement-smoothness + span regularizers in training; DP-in-the-loop / CRF training
  if >85% agreement doesn't fall out; EGSet12 ingest; string-shift augmentation;
  model-card/HF hygiene.
- **Tab Editor pro-parity** → [docs/TAB_EDITOR_PARITY.md](docs/TAB_EDITOR_PARITY.md):
  close the gap to industry-standard tab editors AND make the editor faithfully
  edit what we import/export (`.gp`/MusicXML/MIDI round-trip). Phased steps A0–E2:
  finer rhythm/tuplets/ties, time-sig/key/repeats/voltas/tempo-map, parametric
  techniques (bend curves, whammy, slide kinds, harmonics, palm-mute…), dynamics,
  second voice, per-track instrument/mixer, drum-tab, practice tools, PDF export.
  A0 (round-trip harness + the 7 existing techniques now survive import→edit→export)
  shipped; A1+ pending, each scoped for a fresh agent in the doc.
