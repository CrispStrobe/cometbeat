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

## Automatic play-along — live pitch detection (feature area)

Live pitch/chord detection from the mic, turned into real practice modes:
tuner, sing-along, play-along with a moving score, and games. Everything sits
on one pure-Dart detection core so it stays testable headlessly and from a CLI.

## Sound Library / Instrument / FX unification (IN PROGRESS)

Unify the places that currently drift apart: the Tracker instrument selector,
Workshop Score "Play with an instrument", Audio Editor track/clip voicing, and
Sound Library creation tools.

- **One Sound Library surface for instruments.** Built-in Tracker voices
  (Tonal / Plucked / Chiptune / Drums / Recorded), saved instruments/samples,
  SoundFont-backed voices, catalog installs, and generated FX must all be
  available from the same picker. Any screen that says "choose an instrument"
  should open that picker, not a separate chip-only palette.
- **Generate FX creates instruments.** SFXR/FX generation belongs inside the
  Sound Library creation menu so generated FX can become playable instruments in
  Tracker, Workshop Score playback, and Audio Editor score/track voicing. It
  should not be hidden behind Audio Editor > Add clip as a one-off timeline
  source.
- **Add clip adds timeline material.** Audio Editor > Add clip should stay about
  arranging clips: samples from the library, extracted/imported material, and
  demo beat/tune. Sound design tools live in the Sound Library when the goal is
  creating/selecting an instrument.
- **Voice Shaping is an audio FX module.** Shape a Voice is no longer an "add a
  clip" action. The voice-shaping DSP should be exposed under Audio Editor FX so
  it can process any WAV/sample/track/segment. Today that means a Voice Shaping
  section in track inserts; later it can grow clip/segment modules and more FX
  sections without changing the instrument picker model.

## Loop Studio consolidation (IN PROGRESS)

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
- **Controls must be scannable.** Replace Chill/Groove/Fast tempo buttons with a
  BPM slider plus numeric field. Group key, scale, swing, loop length, and sound
  choices in the same compact settings bar pattern used by Score Workshop.
- **Notation is a view of the document.** Show one or more voices/parts,
  choosing treble, bass, or grand staff per range; notation follows the actual
  selected tracks and has Start/Pause/Stop transport.
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

## Cross-mode FX + interop consolidation (PLANNED — `feature/fx-interop`)

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

## Songbook — scan sheet music into playable songs (PLANNED)

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
- **Tier 3a — Dart AEC core (IN PROGRESS).** `core/audio/echo_canceller.dart`: a
  compact **constrained frequency-domain block-NLMS** echo canceller (the linear
  core of Speex MDF / WebRTC AEC3), reusing the FFT. Testable headlessly with a
  perfectly-aligned digital mix (ERLE assertion). Deployment still needs Tier 3b
  to feed it aligned ref+mic.
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

### 2. Ecosystem Interchangeability (Workshop, Looper, DrumKit, Tab)
**Current State:**
We have `tracker_notation.dart` bridging Tracker ↔ Score Workshop. However, deep integration with other DAW tools (Looper, Tab Editor, DrumKit) is missing. 

**Implementation Steps:**
1. **Looper / Loop Mixer Bridge:** Implement a function to bake a Tracker pattern directly into a `LoopTrack` stem (`Float64List`) so it can be dropped into the Loop Mixer as a perfectly-timed, loopable clip.
2. **DrumKit Bridge:** Ensure `PercussionInstrument` directly reads from/writes to the same model used by the standalone DrumKit view. A beat tapped out physically in the DrumKit must instantly populate the Tracker's percussion channel.
3. **Tab Editor Translation:** Expand `tracker_notation.dart` to support translating plucked string channels (`KarplusInstrument`) into Tab Editor strings, mapping MIDI pitches to string/fret combinations based on tuning.

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

## Consolidated backlog (2026-07-25 doc sweep)

Pending work carried over when ~40 handover/scoping/status docs were consolidated.
**Group 1** items came from docs that were *deleted* (full detail preserved here).
**Group 2** items still have a live reference doc — the pointer is authoritative;
kept here so nothing is lost from the canonical plan.

### Group 1 — residuals from deleted docs (no other home)

**Tab / labeler / library** (was `TABCNN_GGML_HANDBACK`, `LIBRARIES_AND_TAB_SCOPING`):
- CrispASR-side (external repo): ship `libcrispasr` with `@loader_path`-relative
  rpaths (it currently bakes the CI build path, so a downloaded dylib can't find
  `@rpath/libggml.0.dylib`); lay the libs in one flat dir (split across `src/` +
  `ggml/src/` today); optional `CrispasrSession.tab()` wrapper in the pub package.
- `thesession_source.dart` — Irish-trad ABC library source (specced, absent), with
  the no-LLM flag set.
- IMSLP + CPDL/ChoralWiki conditional, country-gated library sources (A4) — gated
  behind the "real legal review" the scoping doc called for.
- `DonationConfig` tile flip-on (A5) — `donation.dart` exists but stays disabled
  until a Ko-fi/PayPal URL is set.

**Audio FX** (was `FX_HANDOVER`):
- Standalone `ring_mod`; full `distortion` set (hardClip/softClip/fuzz/wavefold);
  restore dropped sfxr params (FM, LFO); optional FFT-convolution reverb.
- Cubic-Hermite sample interpolation to replace linear `resample.dart` (improves
  recorded-voice pitch-shift quality).
- Multi-effect per-channel chain (one insert per channel today); sfxr FM/LFO into
  the instrument picker; pitch envelope on sfxr/additive voices; reverb/delay send
  on the Loop Mixer.

**Samples** (was `CC0_SAMPLE_SOURCE_HANDOFF`):
- Optional "starter-module generator": a pure `starterPattern(style, channels,
  steps)` helper + a Tracker action that `setCell`-fills a beat/riff from assigned
  CC0 samples.

**DAW real-time engine** (was `SOUND_AND_DAW_ROADMAP` P2.1):
- P2.1 real-time streaming audio engine — replace offline-render-then-play with a
  streamed graph (live faders, live-playable instruments, input monitoring,
  per-block insert processing, responsive automation). Unlocks the last DAW gaps;
  overlaps the Tracker audio arc's §E3 (`flutter_soloud`) claim. Also confirm the
  P0.1 convolution reverb landed (only biquad + dynamics verified present).

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
  unchanged (no regression). **Still open:** TPDF dither at the Int16 cast (opt-in
  — adds noise / reproducibility considerations); 2× oversampling before the filter;
  IT filter ENVELOPE + `\x87` MIDI-macro filter; and the last non-streaming path
  (short/mono/flow native multi-sample songs — already <500 MB, a separate
  byte-identical follow-up). Original v2 plan retained below for reference.

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
