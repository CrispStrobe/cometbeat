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
   saved song is untouched). **String indicator — DONE** (Roman numerals at
   crossings and on the opening stopped note, never on an open string, since an open
   pitch names its own string; rides in the same copy). **MusicXML-with-fingerings —
   DONE** (`Score.copyWith`/`NoteElement.copyWith`
   shipped in crisp_notation with a source-reading drift guard; the song screen
   exports a fingered copy through the standard export sheet). The `T` glyph this
   bullet once waited on is in the library now, so thumb position engraves too.
   **Everything in this bullet is shipped; what remains in the arc is 2 and 3.**
2. **More labels — CLOSED (measured 2026-07-26/27).** Both routes were tested to a
   number rather than argued about.
   **OMR: dead.** Our own OMR cannot carry fingerings by construction (SMT → `bekern`
   → Humdrum `**kern`, no fingering in that vocabulary). Audiveris 5.11 CAN — it
   exported real `<fingering>` from a PD 19th-c. Dotzauer print — but at **~20% recall**
   (4 of ~15–25 printed on the page) with a diagnosable precision failure (a harmonic
   circle read as finger `0`, which our own geometry rejects automatically). AGPL-3.0,
   so an offline tool only, never bundled.
   **Symbolic: exhausted.** Streaming-scanned the full PDMX release (`mxl.tar.gz`,
   **254,035 scores**): 1,538 carry a fingering → **236 bowed parts / 9,324 labels** →
   after the documented ship gate (`composer_name` → Wikidata death ≤1955 AND
   `license_conflict == False`) **51 parts / 1,282 labels**, of which **6 cello parts /
   121 labels**, and 2 of those were scores we already had. **Net: +55 cello labels
   (193 → 248).** The entire 254k corpus adds 28% to our gold set.
   **The gate is not ceremony:** it rejected Hozier, John Williams, Howard Shore, Toby
   Fox, Chrono Trigger, Pokémon and four in-copyright Kreisler pieces — all tagged
   `publicdomain`/`cc-zero` by their uploaders. PDMX's axis-2 is self-attested; a
   licence field is a claim, not a clearance (`docs/CORPUS_LICENSING.md`, PDMX OVERHAUL).
   ⚠ The gate under-clears in a fixable way: `"J.S. BACH"` and
   `"Luigi Boccherini (1743-1805)"` both come back UNKNOWN — string formatting, not
   copyright. A normalisation pass on `bin/pdmx_pd_composer.py` would recover rows
   across the whole catalog; flagged to its owner, not changed here.
   **What is left, and it is not a corpus:** a cellist annotating for a few hours, with
   the arranger pre-filling so they correct rather than type. That is how TNUA (violin,
   217k notes) was built, and it is the only route that produces dense expert labels.
   The 55 new labels ship as a second acceptance slice
   (`test/data/cello_fingering_gold_pd.json`, 58.2% agreement vs the first set's 50.3%).

3. **Learned emission — CLOSED with item 2.** 248 labels cannot fit transition/emission
   tables that beat authored weights, let alone train a neural emission model. The seam
   stays (`BowedPositionModel`, the bowed twin of `TabPositionModel`) so a model can
   drop in if dense labels ever exist; nothing else is worth building against 248.
   The literature's own numbers say why this is not a loss: hand position is subjective
   (ten professionals, F1 ≈ .24–.31), and the capped-skill profiles that the app
   actually uses are near-deterministic from geometry alone.

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
- **Tracker→editors sweep — 2 items handed to `daw-suite`** ✅ **BOTH DONE**
  (2026-07-27, per maintainer; the sweep itself is in
  [docs/HISTORY.md](docs/HISTORY.md)). They lived in the DAW/export surface, so
  they were handed off to avoid collisions, then implemented additively:
  - ✅ **DAW bounded-memory save (`6cc269ab`).** New web-safe `stream_save.dart`
    seam (io/stub conditional import); `showAudioExportSheet` gained an optional
    `WavStreamProducer`; `_exportAs` streams the WAV to disk via `streamTimelineWav`
    → `streamBytesToFile` for the plain full-mix WAV / native-rate / 16-bit /
    no-dither case (guarded on `!stem && !range && !normalize`), so *Save* stops
    calling `bakeStereo()`+whole-file-in-RAM there. Web + every other choice fall
    back to the in-memory bake (unchanged). Byte-identical output; seam-tested.
  - ✅ **Export dither (`128eec8c`).** Optional deterministic (fixed-seed) TPDF
    dither in `pcmFloatToWav` (default off → byte-identical) + a 'Dither' sheet
    toggle (WAV only), threaded through `build`/`_exportAs`. +4 tests.
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
2. **Smooth Scrolling Matrix:** PARTIAL — the playhead already tracks a
   FRACTIONAL within-row position (`_playFrac` in `advanced_tracker_screen.dart`,
   drawn sub-row), but the auto-scroll that follows it still `jumpTo`s at row
   granularity rather than easing. Genuinely-open remainder: ease the follow
   scroll + a block-by-block pattern-matrix overview. Low priority (cosmetic).
3. ~~**Advanced Keyboard Handling:**~~ (DONE — verified 2026-07-26, roadmap was
   stale.) `advanced_tracker_screen.dart` has `HardwareKeyboard.isShiftPressed`
   multi-cell selection (Shift+arrows), `_selectTrack`/`_selectPattern`,
   cross-channel block copy/cut/paste/paste-mix/transpose/clear (a Block menu +
   shortcuts, `_clipboard`), and value interpolation (`_interpolateBlock` volumes,
   `_interpolateNotesBlock` chromatic, `_fillInstrumentBlock`). Test GAP: the
   block ops have no unit coverage (the screen test covers only trim/env math) —
   a documented follow-up.

### 4. Deep Instrument Modulation (Macros & Envelopes) — CORE DONE (2026-07-26)
**Current State:**
Per-tick instrument MACROS ship for the additive voice (see
[docs/HISTORY.md](docs/HISTORY.md)). Sample-voice macros + a macro editor UI
remain.

**Implementation Steps:**
1. ~~**Macro Data Model:**~~ (DONE) `MacroSequence` (`lib/core/audio/macro_sequence.dart`)
   — a per-tick step table for volume/pitch/arpeggio/pan/duty with a sustain loop
   and a release segment; pure + exhaustively tested.
2. ~~**Tick-level Rendering (additive):**~~ (DONE) `AdditiveInstrument` carries an
   optional `macros` list; the additive tick voice in `tracker_replayer.dart`
   applies volume (amplitude), pitch and arpeggio (semitones) per tick from
   note-on. OPT-IN — absent macros keep every render byte-identical. Codec
   serializes them.
3. ~~**Sample-voice + reachability:**~~ (DONE) macros apply in the sample tick
   voice too, and `TrackerSong.usesMacros` routes a macro'd song through the tick
   replayer so `renderSongWav` actually sounds them (was silently taking the fast
   offline path).
4. ~~**Stereo path + pan target:**~~ (DONE) macros apply in the stereo tick voice
   (`_renderSampleChannelStereoTicks`) — used for PANNED songs — including the PAN
   target (meaningful only in stereo); additive stereo already worked via the
   mono-delegate-then-pan path.
5. ~~**Mono variable-timing path:**~~ (DONE) macros apply in the mono
   variable-timing render (`_renderChannelIntoVariable` additive loop +
   `_renderSampleChannelIntoVariable`), so a non-default-speed / mid-song-
   tempo-change song modulates.
6. ~~**Macro editor UI:**~~ (DONE) an "Instrument Macros" section in the Sample
   instrument editor — add/remove one macro per target + a drag-to-set bar editor
   with step-count and loop/release pickers. Macros are now user-authorable and
   persist. (Fixed a latent `SampleInstrument.copyWith` macro-drop along the way.)
7. **Remaining slices (open, all niche):** the STEREO variable-timing path
   (`_replayVariableStereoFloat` — a song BOTH panned AND mid-song-tempo, the
   rarest intersection); the DUTY target (needs a pulse/square voice); a macro
   editor for the ADDITIVE-instrument path (today the editor's additive branch
   opens the Sound Lab); and §3.3 block-op unit tests.

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

✅ **G1 — DONE (`d6186fd2`). Metrics built, and running them found four defects.**
`test/support/audio_compare.dart` = level · envelope correlation · lag ·
spectral similarity, each isolating one fault, as a LIBRARY with 19 tests of
its own against synthesised signals (the A/B is opt-in and never runs on CI).
What running it exposed: **the A/B had never actually run** (gated on a
licence-restricted file absent from every checkout — now gated on a fixture we
own); **the reference was non-deterministic** (`openmpt123` defaults to
`--dither 1`, and dither is random — the same inputs gave lags of 21504 and
29696; now `--dither 0`, and our own render is verified byte-identical run to
run); **the old RMS check peak-normalised before differencing**, so it could not
see a level error by construction — it rated `golden.mod` "-0.8 dB" where the
real delta is **-16.4 dB**; and **our `golden.mod` render is nearly silent**
(RMS 0.00037). ✅ **Those anomalies are RESOLVED as fixture artifacts** (investigated
2026-07-26). The golden.* files are far more degenerate than "minimal" suggests
— they are **a single note playing a five-sample waveform**:

| fixture | channels | note triggers | sample lengths |
|---|---|---|---|
| golden.mod | 4 | 2 | 8 |
| golden.xm | 1 | 1 | 5 |
| golden.it | 1 | 1 | 5, 10, 10 |
| golden.s3m | 1 | 1 | 8 |

So: golden.mod's "near silence" is 2 notes × 8 samples spread over 7.68 s of
mostly nothing (peak 0.072, RMS 0.00037); the ±16 dB level spread is two engines
disagreeing about interpolating a 5–8 sample source and about per-channel
scaling; the 17%-short XM/IT renders are end-of-song/tail handling on a 4-row
single-note pattern. **None of it is evidence about musical fidelity**, which is
exactly why they stay report-only.

✅ **DONE — and it found a real bug on its first run.** `test/fixtures/musical.mod`
(generated by `tool/make_musical_fixture.dart`, so it is reproducible and
licence-clean because we author it): 4 channels, 2 patterns × 64 rows, 15.4 s,
a **looped** 256-sample band-limited saw, a melody spanning two octaves with the
four voices moving at different rates. Verified `openmpt123` reads it as
ProTracker M.K. Deliberately effect-free — it answers "do we play the right
notes, at the right pitch, at the right level?", the narrowest useful question,
so a failure localises.

On its first A/B it exposed **a one-sample rounding error that silently disabled
sample LOOPING** for ordinary modules (`module_instrument_bridge.dart`): loop
points were rescaled onto the engine rate but rounded independently of the
resampled buffer, so a whole-sample loop landed one sample past the end,
`SampleInstrument.loops` went false, and every held note became a ~30 ms click.
Fixed + swept by `module_loop_rescale_test.dart` (13 rates × 6 lengths). The
fixture measured the repair: **spectral similarity 0.746 → 0.920** and level
−14.20 dB → +3.76 dB against OpenMPT.

⬜ **Still open on this fixture, unclaimed:** envelope correlation is 0.222 — we
agree with OpenMPT about the pitches now, much less about the loudness CONTOUR,
which points at note envelopes/volume ramping rather than at pitch. And we sit
~3.8 dB louder overall. Neither is investigated. *Original finding:*
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
red between macOS dev and Linux CI.

✅ **G2 — DECIDED + ENFORCED (`tracker_render_determinism_test.dart`).** The
policy, in one line: **the render is deterministic PER PLATFORM, and that is
all we claim.**

* **Guaranteed, and now tested** for all four formats: rendering the same module
  twice on the same machine gives byte-identical audio. Several suites already
  leaned on this without stating it — every "byte-identical with the feature
  added" gate compares two renders and would pass or fail spuriously if the
  renderer wobbled — so it is the foundation those gates stand on and it has a
  test of its own. A companion test proves the comparison can separate two
  genuinely different modules, so the suite cannot pass vacuously.
* **Not guaranteed:** bit-identical audio across platforms. `_tanh` is built on
  `exp()`, which is platform libm. We have NOT measured our own divergence; the
  reference measurement is ~0.01% of samples at ~115 dB down, i.e. inaudible.
* **⚠️ The operating rule:** never commit a golden RENDERED WAV and compare it
  byte-exactly — we develop on macOS and CI runs Linux, so it is an intermittent
  red waiting to happen. Compare two renders made in the SAME run, or compare at
  signal level with `test/support/audio_compare.dart`. Committing golden module
  BYTES stays fine (`mod_codec_test`): parse→write is integer work with no libm
  in it.

🔶 **G3 — HALF DONE.** ✅ The **LED low-pass filter** is shipped by 
(tracker-complete): `E0x` (MOD/XM) and `S0x` (S3M/IT) drive a `_HardwareLowPass`
with a per-sample on/off schedule — flagging it here is what routed it to them,
since `E0x` IS that command. ⬜ **Still absent: the Paula clock.** No PAL
(3,546,894.6 Hz) / NTSC switching, and no pitch derived from clock ÷ output rate;
ours stays a pure c5speed/finetune model, which is why MOD playback is tuned to
A440 rather than to the hardware. **MEASURED: we render 17.1 CENTS SHARP of OpenMPT** ⚠️ (I first wrote FLAT — the sign was mine, not the metric's: `AudioComparison.of(ours, openmpt)` reports how far the SECOND is sharp of the first, so −17.1 means OpenMPT is flat of us) on
`musical.mod` (`detuneCents` in `audio_compare.dart`, verified to ±3 cents
against synthesised offsets). So the Paula-clock hypothesis is confirmed, with a
size attached: not a rounding wobble, but not gross either — about a sixth of a
semitone, consistent across the piece. The degenerate `golden.*` fixtures report
`n/a` rather than a number, which is the metric refusing to guess.

🔶 **BUILT BEHIND A GATE — `--dart-define=PAULA_CLOCK=1`** (`kPaulaClockPitch`
in `module_convert.dart`), because a change to every module render should be
checkable before it is committed to. The arithmetic: the Amiga plays the
reference period 428 at `3546895 / 428 = 8287.1 Hz` while the conventional
reference is 8363 Hz — **−15.8 cents** — so pitching from the reference sits
~16 cents SHARP of the hardware, accounting for the measured 17.1 to within
~1.3 cents (ProTracker's period table is not exactly geometric).

**A/B, same fixtures, gate off → on:**

| fixture | detune | spectral | envelope |
| --- | --- | --- | --- |
| musical.mod | −17.0 → **−1.3** | 0.922 → **0.962** | 0.233 → **0.619** |
| effects.mod | −25.4 → **−5.3** | 0.862 → **0.882** | 0.188 → **0.363** |

Every metric improves and the tuning error essentially disappears. The envelope
jump is a side effect worth noting: once the pitches agree the two renders stop
beating against each other, so their loudness contours line up too.

⬜ **Flipping the default is the remaining call** — it changes how every module
sounds, in @opus (tracker-complete)'s area. The evidence is now one command
away: run the A/B with and without the flag.

✅ **G4 — NON-GOALS, DECIDED.** What we refuse to chase, so the replayer can be
finished rather than approached forever. Written from what the code already
does, not from ambition; revise freely, but revise it *deliberately*.

1. **We are not a hardware emulator — we emulate what was AUTHORED FOR.** The
   LED low-pass (`E0x`/`S0x`) and OPL2/YM3812 FM are in scope because composers
   wrote music that depends on hearing them. Paula's incidental artifacts are
   not: 8-bit DMA quantisation, its aliasing signature, per-chip mixing quirks.
   We render offline at the engine rate with Catmull-Rom interpolation, which is
   *better* than the hardware and deliberately so — this is a music-education
   app, not a preservation emulator.
2. **No bug-emulation of other players.** No pre-1.17 OpenMPT swing, no legacy
   pattern-loop quirks, no proprietary envelope release nodes. A module that
   depends on another player's bug is out of scope; we play the format.
3. **Not bit-identical to any other player, ever.** We target *musical*
   equivalence, measured by `test/support/audio_compare.dart` against OpenMPT —
   same notes, same pitches, same levels, same timing. Sample-exact parity is
   not a goal and would forbid our own interpolation and limiter. (See also the
   determinism policy above: per-platform only.)
4. **MPTM is refused, not half-read.** `ModuleFormat` is mod/s3m/xm/it. An
   OpenMPT-extended module should be rejected with a clear reason rather than
   silently mis-parsed.
5. **No VST/AU hosting and no external MIDI out.** IT MIDI macros are in scope
   only where they map onto our own filter (`Zxx` cutoff/resonance); macros
   addressing outboard gear are carried as data and ignored.
6. **Writers target round-trip fidelity, not authoring parity.** We write what
   we can read back losslessly. IT214/215 sample compression stays unimplemented
   (`it_writer.dart` says so) — uncompressed output is correct, just larger.

**The test of a good non-goal is that it closes an argument.** If one of these
starts costing real musical accuracy — a module people actually want to hear
sounding wrong because of it — that is a reason to revisit the entry, and the
A/B is now able to tell us so with numbers.

✅ **Loose end RESOLVED (2026-07-26, @opus tracker-complete).** `s3m_reader.dart`'s
comment claimed "We do NOT emulate the OPL chip" — wrong: `tracker_song_module.dart`
builds an S3M type-2 sample into a real `OplInstrument` (YM3812) for playback,
while the reader keeps a PCM approximation (`synthesizeAdlibWaveform`) as a
sample-path fallback and preserves the register block for byte-identical
re-export. Comment rewritten to describe both intended paths accurately.

✅ **G5 — DONE (`d6186fd2`).** `_kOpenMptPath` was pinned to one Cellar version,
so a routine `brew upgrade` silently skipped the whole audit. Resolved from
`PATH` now, with the Homebrew prefix as a fallback.


#### Open follow-ups from the arc (recorded 2026-07-26, none claimed)

The A/B **gates** now — on `musical.mod`, at spectral > 0.85, |level| < 8 dB,
|detune| < 35 cents. Thresholds come from measured values and are set so they
would have caught the loop-rescaling bug (spectral 0.746, level −14.2 dB). Its
remaining numbers are the follow-up list:

| what | measured | reading |
| --- | --- | --- |
| spectral similarity | 0.920 | we play the right notes |
| detune | −17.1 cents (**we are SHARP**) | G3, Paula clock — now BUILT behind a gate |
| **level** | **+3.76 dB** | **we are consistently LOUDER** |
| **envelope correlation** | **0.222** | **loudness CONTOUR disagrees** |

🔶 **Loudness parity — DIAGNOSED, and the main cause was a MISSING FEATURE.**
The density sweep (1/2/3/4 active channels: +4.01 / +3.76 / +3.54 / +3.22 dB)
ruled out summation — the gap is ~4 dB at a SINGLE channel and shrinks as
channels are added, the shrinkage being our `tanh` limiter compressing the
larger sum. A volume sweep (64/48/32/16) held it at 4.01–4.17 dB with both
engines scaling linearly, so the volume MAPPING was right too.

Comparing L and R separately found it: **openmpt123 pans MOD channels L-R-R-L at
3:1, and we panned everything dead centre.** Full amplitude went into both
channels instead of being split across them, and the arithmetic closes exactly —
their mono downmix (0.1502+0.0501)/2 = 0.1002 against our 0.1588 is a ratio of
1.586, i.e. **+4.00 dB**, the measured gap.

✅ **Fixed** (`_protrackerPan` in `tracker_song_module.dart`): MOD now gets the
Amiga layout, which is a real feature — a `.mod` stores no panning, so without
it every module rendered mono-in-stereo and lost the wide ping-pong image the
format is known for. Level gap **+4.01 dB → +2.68 dB**.

⬜ **Residual ~2.7 dB is a GAIN CONVENTION, and is a product decision.**
`_channelGain` uses a `0.6` base; matching the reference exactly would mean
re-calibrating it, which changes how every module sounds in the app. Not a bug —
neither convention is canonical — so it is recorded rather than quietly tuned.
A smaller loose end: our measured split came out 3.6:1 where the reference is
3:1, so something applies a little extra separation; worth a look if anyone is
in that code.

⬜ **Envelope correlation 0.222.** The one number the loop fix barely moved
(0.103 → 0.222). We now agree about *which* pitches sound and much less about
*how loud, when* — so it points at note envelopes or volume ramping rather than
at pitch or mixing. Worth chasing after loudness, since a level error would
muddy any envelope measurement.

✅ **Effect-coverage fixture — DONE.** `test/fixtures/effects.mod` (same
generator): one effect family per CHANNEL — arpeggio `0xy` · vibrato `4xy` ·
portamento `1xx`/`2xx` · volume slide `Axy` — each working on ONE long note, so
the effect has something to modulate. Bends go up then back down within each
16-row run, so a one-sided error cannot hide. It GATES (spectral > 0.80; the
threshold is per-fixture because pitch-bending material honestly diverges more
than plain notes, and one shared number would be too loose for `musical.mod` or
too tight for this).

✅ **First finding from it, since EXPLAINED: effect material is ~8 cents further out.**
`effects.mod` measured **−25.4 cents** against `musical.mod`'s −17.0. The guess
was that portamento and vibrato, which compute pitch, amplify the base offset —
and the Paula-clock A/B confirmed it: with the gate on, effects.mod moves
−25.4 → **−5.3** alongside musical.mod's −17.0 → **−1.3**. Same root cause.
**Detune stays ungated on this fixture** until the gate's fate is decided.


### 6. Replay-fidelity AUDIT LADDER — scoped tasks (opened 2026-07-27)

**Why this exists.** A listening test on `~/Desktop/mod-tuning-ab/raw/` found that
BOTH our renders — default and Paula-clock — diverge audibly from libopenmpt,
libxmp and micromod on the SWEEPING effects, in a way the Paula switch does not
explain. The measurements agree and I had under-read them:

| effects.mod | spectral | envelope |
| --- | --- | --- |
| libopenmpt ↔ libxmp (*the references agreeing*) | **0.926** | 0.630 |
| ours B (paula) ↔ libopenmpt | 0.882 | 0.363 |
| ours B (paula) ↔ libxmp | 0.869 | 0.301 |
| ours A (default) ↔ libxmp | 0.851 | 0.078 |

⚠️ **Calibration lesson: my gate was set against the wrong baseline.** I gated
`effects.mod` at spectral > 0.80, so 0.87 PASSED — while the two references
agree at 0.93 and our envelope correlation is half theirs. The right reference
point is *how well the independent engines agree with each other*; anything
materially below that is our deviation. **Re-set the gates that way (task X0).**

**What this section is not:** one bug. Effects are several independent
mechanisms (per-tick rate, depth scaling, waveform, memory/recall semantics,
tick-0 handling), so "effects are off" has to be split before it can be fixed.

#### Oracles now available (all verified working this session)

| tool | formats | gives us |
| --- | --- | --- |
| `openmpt123` (libopenmpt) | MOD/XM/S3M/IT | audio; the de-facto standard |
| `xmp` (libxmp) | MOD/XM/S3M/IT | audio; independent codebase |
| `mod2wav` (micromod) | MOD | audio; accuracy-focused |
| `xm2wav` (ibxm) | MOD/XM/S3M | audio; same author, different engine |
| MultiPLAY | MOD/XM/S3M/IT/MTM | audio; **uses the 8363 convention** — outlier on MOD tuning, still useful elsewhere |
| pt2-clone | MOD | SOURCE only (GUI, no headless render) — authoritative on ProTracker semantics |
| **NodMOD** (Python) | MOD/XM/S3M | STRUCTURE + an independent flow/timing model (`iter_playback_rows` → pattern/row/start_sec/speed/tempo). No audio, no IT. |
| `test/support/audio_compare.dart` | — | level · envelope · lag · spectral · detune |

Build/run notes: `xmp` via Homebrew; MultiPLAY `make bare`; micromod
`cc mod2wav.c micromod.c`; ibxm `cc xm2wav.c ibxm.c`; NodMOD `PYTHONPATH=<clone>/src`.

#### The ladder — check each stage before trusting the next

**X0 — Re-baseline every A/B gate against inter-reference agreement.**
Measure how far apart libopenmpt/libxmp/ibxm are on each fixture, and gate our
deviation relative to THAT, not an absolute. Done when a render that a listener
can distinguish from the references fails the gate.

**X1 — One effect per fixture.** `effects.mod` runs four effects on four
channels at once, so a failure cannot be localised — which is why it read as
"effects are a bit off" instead of naming a command. Emit one fixture per
effect (arpeggio `0xy`, porta up/down `1xx`/`2xx`, tone porta `3xx`, vibrato
`4xy`, tremolo `7xy`, volume slide `Axy`, offset `9xx`, and the `Exy`
sub-commands we claim), each a single sounding channel. Done when every claimed
command has a fixture and a measured deviation.

**X2 — Vibrato/tremolo depth, rate and waveform.** The user-audible one. Check
per-tick step, depth scaling, waveform table (sine/ramp/square), whether the
LFO retriggers on a new note, and tick-0 behaviour. Oracle: X1 fixtures vs
three engines + pt2-clone's source for ProTracker semantics.

**X3 — Portamento family.** `1xx`/`2xx` step per tick, `3xx` target snapping,
period clamping at the table edges, and effect MEMORY (a bare `300` continuing
the previous rate) — memory bugs are invisible on a single-row fixture and
obvious on a sustained one.

**X4 — Volume slide + tremor semantics.** `Axy` per-tick vs per-row, the
"both nibbles set" ambiguity ProTracker and later trackers resolve differently,
and interaction with `5xy`/`6xy` (porta/vibrato + volume slide combinations).

**X5 — Timing/flow against NodMOD.** `iter_playback_rows()` yields
(pattern, row, start_sec, end_sec, speed, tempo) from an independent
implementation. Compare against our `songFlowTimeline`/`resolveTimingMap` over
a corpus of order-list shapes: `Bxx` jumps, `Dxx` breaks, `E6x` pattern loops,
mid-song speed/tempo changes. **No audio needed, so this one can run in CI.**

**X6 — Reader field audit, per format.** Our codec tests are self round-trips
(`parse(write(x)) == x`), which cannot catch a misunderstanding our reader and
writer SHARE. Cross-check parsed structure against NodMOD (MOD/XM/S3M) and
against `openmpt123 --info`. IT has no structural oracle — treat it as the
highest-risk reader and lean on audio there.

**X7 — Writer audit: our writer → THEIR reader.** Write each format from a
known doc, load it with NodMOD and libopenmpt, assert the structure matches
what was authored. `probe_file` already reports zero warnings on our MOD; make
that a test rather than a one-off, and extend to XM/S3M.

**X8 — Fixture independence.** `musical.mod`/`effects.mod` are written by OUR
writer, so a writer bug is baked into every A/B that uses them. Author the same
content with NodMOD and confirm both files render identically; any difference
is our writer, not our replay.

**X9 — Extend the A/B to XM/S3M/IT.** `convertToXm`/`convertToS3m`/`convertToIt`
already exist, so the same musical content can be emitted in all four formats.
⚠️ Expect DIFFERENT failure modes, not the same one four times: XM/S3M/IT store
an explicit sample rate per sample, so the MOD tuning question does not recur —
what these probe is envelopes, NNA, volume/pan models and effect semantics.
IT is thinnest on oracles (libopenmpt + libxmp only) and richest in features,
so it carries the most risk.

**X10 — Sample-playback layer.** Interpolation, loop wrap (see the one-sample
rescale bug already fixed), 8- vs 16-bit and stereo sample paths, `9xx` offset
clamping, ping-pong loops. Oracle: single-note fixtures per case.

Ordering: **X0 → X1** first (they make everything else measurable), then X5 and
X6/X7 (cheap, CI-able, no audio), then X2/X3/X4 on the isolated fixtures, then
X9/X10. X8 whenever a result looks impossible.

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
- Richer inspector: multi-select view ✅ (edits a whole selection), rest
  properties ✅ (rest-length control, `opus (rest-props)`), bar-attribute editing
  (⬜ still open — see scoped item 3 below).
- Categorized *insertion* palettes (dynamics / lines / repeats / text), distinct
  from the modification inspector.
- Voice-2 v1 gaps — **RE-AUDITED 2026-07-26 against the code; mostly stale:**
  dynamics/lyrics on voice 2 ✅ (`buildScore` harvests markings from BOTH voices),
  slurs ✅ (shared `_slurs`, `canSlur` reads the active voice), cross-voice
  tap-select ✅ (`_onElementTap` follows `voiceOfId`→`setActiveVoice`). Still open:
  `buildGrandStaff` showed voice 1 only (⬜ → **fixed by `opus (voice2-gaps)`**);
  the grand-staff view still carries no dynamics/slurs/lyrics for EITHER voice
  (pre-existing limitation, follow-up); mid-score meter/key changes are bar-level
  and anchor on voice-1 bars by design (revisit only if per-voice changes are
  wanted).
- Grace-note LIST beyond a single run (a crisp_notation library ask); cross-part
  in-place ghost/drag note entry on `MultiPartView` (the "C11" ask).
- Wire `Measure.actualDuration` into the pickup/anacrusis path; verify rendered
  output reflects crisp_notation's metric-aware secondary beaming.

**Advanced/Beginner Tracker UX** (was `HANDOVER_DAW_UX` §C — also on the docs/PLAN.md
codex backlog): collapse the oversized Advanced-Tracker menu into Import/Open ·
Library · Edit · View · Playback · Export groups and align its import/save
vocabulary with Score Workshop; make the Beginner Tracker a genuinely capable kid
live-loop surface (quick start, layer parts, record a voice, arrange sections).

#### Scoped next candidates (2026-07-26, `opus` — clean picks are exhausted, these carry trade-offs)

These are the substantial items left after the easy wins shipped; scoped here so
whoever picks one starts from a plan, not a re-survey. Item 2 is being done now.

1. **Advanced-Tracker menu grouping** (`advanced_tracker_screen.dart`, ~7.1k lines
   — a HOT file). ⚠️ **SCOPE CORRECTION (2026-07-26, after inspection):** this is
   NOT a single oversized menu to regroup — the actions are spread across *many*
   bottom sheets, toolbars and dialogs (Load SoundFont `~2210`, Load WAV `~3012`,
   Load Song `~3976`, Export sheet `~4619`, per-channel mixer header `~2363–2517`,
   etc.). Collapsing them into **Import/Open · Library · Edit · View · Playback ·
   Export** is a genuine multi-surface UI restructure, not a menu regroup — larger
   and riskier than first scoped, and it wants a maintainer design pass (which
   entries move where, what stays a toolbar button) before a blind refactor.
   `opus (daw-suite)` is adjacent (DAW/tracker round-trip). Value HIGH
   (maintainer-flagged), but do it deliberately, with the extensive
   `advanced_tracker_screen_test.dart` in mind — not as a quick sweep.
2. **Voice-2 gaps → `buildGrandStaff` keeps voice 2** (`score_document.dart`). Done
   by `opus (voice2-gaps)`: a two-voice document now engraves as a two-hand grand
   staff (voice 1 → treble / RH, voice 2 → bass / LH) instead of dropping voice 2;
   a single voice keeps the pitch auto-split. The other voice-2 sub-gaps were found
   stale (see the Voice-2 bullet above). Follow-up: carry dynamics/slurs/lyrics onto
   the grand-staff view (both voices — a pre-existing grand-staff limitation).
3. **Bar-attribute editing in the inspector** — ✅ **DONE (`opus (bar-attributes)`).**
   The inspector's Structure section now carries inline **Key** and **Time
   signature** dropdowns (for a single selection) that read/write
   `keyChanges`/`timeChanges` via `setKeyChangeAt`/`setTimeChangeAt` and apply on
   selection — no need to open "Change from here…" for the common case; the fuller
   dialog stays for clef/tempo/volta/navigation. Reused `_changeRow` + the existing
   `_keyChoices`/`_timeChoices`, no new l10n. ⚠️ follow-up noted: a time change
   anchored at the *very first* element exports a degenerate MusicXML document (the
   base time sig is already that meter) — pre-existing in the "Change from here"
   path, worth a look but out of scope here.

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
