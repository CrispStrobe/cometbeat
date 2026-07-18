# Tracker — GUI, element-handoff & universal I/O idea board

Scope captured from the user (2026-07-18): **(1)** four picked GUI items;
**(2)** hand over "elements we have in other parts of the codebase" — basic⇄
advanced tracker, waveforms generated/modified elsewhere; **(3)** wire **all**
importers/exporters "anywhere they can be of use" (ABC etc.).

This is the written-up plan. It is grounded in two read-only codebase surveys
(import/export inventory + waveform/instrument inventory, 2026-07-18), so every
idea below names the code that already exists to build on. **Nothing here is
committed engine work** — the split with `@tracker-replayer` still holds: I own
the screens (`advanced_tracker_screen.dart`, `tracker_screen.dart`,
`home_screen.dart`, other feature screens) + ARBs + docs + new app-side glue
files; **he owns** `tracker_song.dart` / `tracker_engine.dart` / `mod/*`. Any
idea that needs an engine/model change is tagged **[needs-engine]** and must be
handed to him, not done here.

Ownership legend: **[screen]** mine · **[glue]** new app-side file, mine ·
**[needs-engine]** @tracker-replayer · **[lib-exists]** the codec already exists
in `crisp_notation_core`/`mod/`, only wiring is needed.

---

## A. The four picked GUI items (all [screen])

### A1. Playhead follows song jumps  ★ correctness, unblocked
Today the moving playhead uses linear `elapsed ÷ patternMs` math
(`advanced_tracker_screen.dart` ~L310–319). On any song with `Bxx` position-
jump, `Dxx` pattern-break, or `E6x` pattern-loop — including **many imported
modules** — the highlighted row is wrong during playback.
**Fix (enabler already shipped by @tracker-replayer):** at play-start compute
`final map = resolveTimingMap(_song)` once; each frame
`final e = map[rowIndexAtMs(map, elapsed % _song.songTotalMs)]` →
`_playingOrder = e.orderIndex; _row.value = e.row`. Pure screen change.
*Test:* a 2-pattern flow song (`Dxx` break) — assert the playhead visits the
resolved row sequence, not the linear one.

### A2. Instrument column + instrument list panel  ★ FT2/IT parity, unblocked
The grid has note/vol/fx columns but **no instrument column** — you can't say
"this cell plays instrument 03." @tracker-replayer shipped `TrackerCell.instrument`
(1-based into `TrackerSong.instruments`, a real per-note pool used by imports
too) and said explicitly *"`TrackerSong.instruments` is the pool to expose in the
UI."*
**Build [screen]:** (a) an **instrument column** in the cell (a 2-hex field in
the field-cursor cycle: note → inst → vol → fx); typing digits sets
`cell.instrument`. (b) A **side/overflow instrument-list panel** listing
`_song.instruments` (number · name · type) with select-active, rename, and
"assign the picker instrument to this slot." Writing `cell.instrument` goes
through the existing engine setters — but verify those setters **preserve** the
instrument field (the replayer just fixed `setCellVolume`/`setCellEffect`/
`transposeBlock` dropping fields; the instrument write path must round-trip).
*Blocked only if* a new engine setter for the instrument column is needed →
then **[needs-engine]** a `setCellInstrument`.

### A3. VU meters + on-screen piano  (polish, [screen])
- **Per-channel VU meters:** reuse the existing `_ChannelMeter` idiom; drive
  peak/RMS from the rendered stem (we already cache loop PCM for the scope). A
  cheap version: sample `renderLoopPcm()` per channel at the playhead.
- **On-screen piano keyboard** at the bottom (MilkyTracker/Renoise feel) that
  (a) lights notes as they sound (from the same timing map as A1) and (b) is
  tappable for note entry on touch (reusing the multi-octave piano the Score
  Workshop already ships). Doubles as the touch note-entry surface.

### A4. Load + preview WAV samples  ([screen] + tiny [glue])
Today the sample editor records from mic only. Add:
- **Load a WAV file** into the sample editor: `file_selector` → `wav_io.dart`
  PCM16 reader → `Float64List` → the existing `_sampleFrom` pipeline. (Same
  entry as a recorded clip; the trim/normalize/reverse/stretch/voice-fx chain
  and the `_SampleWaveform` trim handles all just work.)
- **Preview** the (trimmed/edited) sample before assigning: a ▶ button in the
  record sheet that plays the current `_sampleFrom(...)` result once.

---

## B. Element handoff (the "hand over what we have elsewhere" ask)

### B1. Basic ⇄ Advanced tracker carry-over  ★ high value, [screen]
**Finding:** both trackers are built on the **same** `TrackerEngine`. Beginner
(`tracker_screen.dart`) drives a `TrackerEngine _engine` + A–D slot snapshots
(`exportCells()`/`importCells()`); Advanced drives a `TrackerSong` that *wraps* a
`TrackerEngine`, and already `import`s `tracker_screen.dart`. **But both mode
switches start fresh:** `tracker_screen.dart:1263` → `const AdvancedTrackerScreen()`
and `advanced_tracker_screen.dart:1957` → `const TrackerScreen()` carry nothing.
**Build:**
- `AdvancedTrackerScreen({TrackerSong? initialSong})` [screen] — additive param.
- **Beginner → Advanced:** in the mode-switch handler, build a `TrackerSong`
  from `_engine.channels` + each non-empty slot as a pattern (slots → patterns,
  channels → channels). Chromatic/endless is a superset of the pentatonic grid,
  so this is lossless.
- **Advanced → Beginner:** Advanced is a superset (chromatic, N channels, N
  rows). Offer a **best-effort down-map** (first bar, map channels onto the
  Beginner band, snap off-scale notes) with a clear "some detail won't fit"
  notice — or, cleaner, make Advanced→Beginner a *fresh* switch but keep
  Beginner→Advanced the lossless promote path. Decide with the user.
- *Test:* place notes in Beginner, switch, assert the Advanced `noteCount` /
  positions match.

### B2. Free the trapped waveform — sample reuse & a sound library
**Finding:** a recorded/edited sample is **trapped** on one channel: a
`SampleInstrument` with no `toJson`, absent from the `KU1.` token, stripped by
Song-Book/MusicXML/MIDI. The only escape today is the **Basic tracker's `.mod`
export** (embeds PCM via `mod_bridge.dart trackerToMod`).
- **B2a. "Copy sample to another channel / into the picker"** [screen] — a UI
  action calling the existing `setChannelInstrument` with the same instrument.
  No serialization needed; pure reuse. Quick win.
- **B2b. PCM-preserving module export from *Advanced*** — Advanced's module
  export currently goes through the Score path and **drops PCM**; Basic's keeps
  it. Route Advanced module export through the sample-aware `trackerToMod`
  bridge so recorded samples survive. **[needs-engine/glue]** (touches
  `mod_bridge.dart` region) — coordinate with @tracker-replayer.
- **B2c. Serializable sound** **[needs-engine]** — give `SampleInstrument`
  (base64 PCM) / `SfxrInstrument` (`SfxrParams` is all numbers → trivial JSON) a
  `toJson`/`fromJson`, then a per-sound share token or a "Sound Library"
  save-slot store (like the `KU1.` token but for one instrument). This is the
  real backbone of cross-feature sound sharing; propose to @tracker-replayer.
- **B2d. Surface `MultiSampleInstrument`** [screen, latent] — a full XM/IT-style
  multi-zone keymap instrument exists (`multi_sample_instrument.dart`) but is
  **used in no screen**. Expose "build a keymap instrument from N samples" in
  the instrument panel (A2). Latent parity capability, already tested.

### B3. Loop Mixer ⇄ Tracker  ([glue] converter + [screen] wiring)
**Finding:** the Loop Mixer's `GrooveSpec` is fully serializable (`KU1.` token)
and holds `userCells` (sung melody as note cells), `beatRows` (beatboxed drums),
`userInstrument` (an `Instrument` name) — but **no converter to tracker** exists.
- **B3a. Import a groove into the tracker** [glue]: a `grooveSpecToTrackerSong`
  converter (`PatternCell{midis,steps}` → `TrackerCell` runs;
  `beatRows` → a `PercussionInstrument` channel; `userInstrument` → an
  `AdditiveInstrument` channel). Then an **"Open in Tracker" / "Paste KU1 token"**
  action in the Advanced tracker. Turns a sung+beatboxed groove into an editable
  pattern — a marquee handoff.
- **B3b. Export a tracker pattern as a groove** (nice-to-have) — the reverse, so
  a tracker beat can seed the Loop Mixer's jam mode.

---

### B4. Extend the Beginner tracker — full range + longer music, without overwhelming kids
User ask (2026-07-18): "extend beginner tracker mode significantly, but NOT
overwhelm kids totally… full tonal range and longer music." The Beginner
(`tracker_screen.dart`) is deliberately a **fixed 8-step (one 4/4 bar),
C-pentatonic, per-channel octave-shifted** grid with A–D slots — so a whole song
caps at ~4 bars and can't leave the pentatonic. Keep it friendly but lift the two
hard ceilings:
- **Longer music** [screen, maybe needs-engine for row count]: more/longer
  patterns — either more slots than A–D, or a **bars selector** (1/2/4 bars =
  8/16/32 steps) so kids can make a real verse. The engine already supports any
  `rows`; the UI hardcodes `steps = 8`. A gentle "＋ add a bar" button beats a
  raw row-count field.
- **Full tonal range** [screen]: an **optional octave/range control** (a "low ↔
  high" shifter, or a "more notes" toggle that widens the pentatonic to a full
  diatonic/chromatic row set) so the melody isn't locked to five notes in one
  octave — while defaulting to the safe consonant grid so nothing sounds wrong
  out of the box. Progressive disclosure: the simple grid stays the default; the
  wider range is a toggle, not the front door.
- **Bridge, not a cliff:** the cleanest "don't overwhelm but don't cap them"
  answer is **B1** — when a kid outgrows the Beginner grid, *Promote to Advanced*
  carries their groove over losslessly. So B4 is "raise the Beginner ceiling a
  bit" + B1 is "the escape hatch to the full tracker." Design the two together.
- *Coordination:* pattern-length/row changes that need engine support are
  **[needs-engine]** (@tracker-replayer owns `tracker_engine.dart`); the range
  UI + bars UI are [screen].

## B5. Surface the engine features @tracker-replayer shipped (GUI catch-up)
The engine raced ahead of the GUI. On `main` now but NOT (fully) surfaced in the
Advanced tracker — the user flagged "we do not yet have it all in the GUI":
- **Stereo panning** (`TrackerChannel.pan`, `setChannelPan`, `8xx`/`kFxSetPan`,
  `usesPan`→stereo render). **→ per-channel PAN slider in the mixer [DONE]**;
  8xx pan authoring is already in the effect editor.
- **Per-pattern variable length** (`TrackerSong.setPatternRows(i, rows)`). The UI
  `setRows` should target the CURRENT pattern only (per-pattern), + a per-pattern
  length control in the arrangement bar. This is also the real "longer music"
  answer for B4 now that the engine supports it. **[TODO]**
- **Volume + pan envelopes** (`TrackerChannel.volumeEnvelope`/`panEnvelope`,
  `VolumeEnvelope`/`PanEnvelope`, `setChannelVolumeEnvelope`/`…Pan…`). A simple
  per-channel envelope editor (a few draggable points) in the mixer. **[TODO]**
- **Mid-song tempo/speed** (`Fxx`): ⚠ **VERIFIED A GAP → [needs-engine,
  @tracker-replayer].** A GUI-authored `Fxx` tempo (probe: `F28` = 40 BPM at
  row 8 of a 16-row pattern) leaves `debugSongTotalMs` UNCHANGED (2000 → 2000),
  so `resolveTimingMap`/`songTotalMs` are NOT tempo-command aware — the visual
  playhead won't track a tempo change even though Feature A renders the audio
  with it. `resolveTimingMap`/`songTotalMs`/`effectiveTiming` live in
  `tracker_replayer.dart`/`tracker_song.dart` (his). The screen side is already
  correct (it consumes the map every frame); once the map accounts for per-row
  Fxx, the playhead follows for free. **Filed for @tracker-replayer.**

## C. Wire ALL importers/exporters everywhere useful

**Finding (matrix):** the library has an enormous codec set; most is wired **only
in the Score Workshop**. The trackers, Loop Mixer, Song Book, My Melody and Free
Sing each expose a thin, inconsistent subset. ABC is the flagship example — a
full reader *and* writer exist (`scoreFromAbc`/`multiPartScoreFromAbc` +
`scoreToAbc`/`multiPartToAbc`) but are wired **only** in Workshop (both) and Song
Book (import paste).

### C0. The systematic fix — a shared `MusicIoMenu` component  ★ [glue]
Stop copy-pasting per-screen I/O. Build **one** reusable widget:
`MusicIoMenu({ required Future<MultiPartDocument> Function() read, required void
Function(MultiPartDocument) write, Set<IoCap> caps })` that offers every codec
the screen opts into (import + export), handling file pick / paste / save
uniformly. Every music screen mounts it with a `read`/`write` adapter. This is
what makes "wired anywhere it can be of use" true and maintainable instead of a
scatter of one-off menu items. All codecs it calls **[lib-exists]**.

Then the concrete coverage gaps it closes:

### C1. ABC everywhere  ★ user-called-out, [lib-exists]
Add ABC **import + export** to: Advanced Tracker, Beginner Tracker, Loop Mixer,
My Melody, Free Sing. All already have a `Score`/MusicXML path;
`module_notation.dart:586` even defines an unused `TextNotation.abc` branch.
Near one-liners via the shared menu (C0).

### C2. Beginner Tracker — add XM/S3M/IT export  [lib-exists]
Beginner exports **MOD only** though `writeXm/writeS3m/writeIt` + `convertDocTo`
exist (Advanced already exposes all four). Add the format picker.

### C3. Advanced Tracker — broaden import  [lib-exists]
Advanced imports MusicXML/MIDI only. Add ABC / MEI / Humdrum `.krn` / MuseScore
`.mscx/.mscz` / Guitar Pro `.gp/.gpx` import (the multi-part readers exist and
Workshop already uses them).

### C4. Advanced Tracker — broaden notation export  [lib-exists]
Beyond MIDI/MusicXML/module, add: ABC, MEI, kern, LilyPond, `.mxl`, **PDF**
(`score_pdf.dart`), SVG, PNG, Braille, MuseScore `.mscx`. Via C0 these are free.

### C5. Loop Mixer — notation import + module export  [lib-exists]
Loop Mixer exports MusicXML but can't **import** notation, and can't emit a
module. Add notation import (seed a groove from a Score) and module export
(`multiPartToModuleDoc`→`convertDocTo`).

### C6. My Melody / Free Sing — real export menu  [lib-exists]
Both only "Save to Song Book" (MusicXML). Give them the full export menu
(ABC/MIDI/MusicXML/module/PDF) via C0.

### C7. Song Book — export UI  [lib-exists]
Song Book is import-only; a stored `ImportedSong` is MusicXML → `Score`. Add an
**export** action so any saved song can be re-emitted to any format (ABC, MIDI,
LilyPond, PDF, module…). High leverage: the Song Book becomes the app's format
hub.

### C8. Module ⇄ notation text bridges  [lib-exists]
`moduleToMusicXml` / `moduleToTextNotation` / `scoreFromTextNotation`
(`module_notation.dart`) are library-only (only the `bin/*.dart` CLIs call
them). Surface "convert a module to notation" (and back) — e.g. import a `.mod`
straight to the Score Workshop, or export a tracker song as LilyPond via the
module path.

### C9. Long-tail codecs  [lib-exists]
`asciiTabToScore` (ASCII-tab **import**) is wired in **no** screen — add to
Workshop import. `scoreToGpif` (Guitar Pro **text** export) exists but no screen
writes GP — add to Workshop export (note: no binary `.gp` writer exists, GPIF
text only).

---

## D. Suggested execution order (slices, each its own commit, checkpointed)

1. **A1 playhead-follows-jumps** — small, correctness, unblocked. *(do first)*
2. **C0 `MusicIoMenu` + C1 ABC in the trackers** — the systematic win; ABC is
   the user's flagship. Land the shared component with tracker ABC/module/score
   I/O routed through it, then fan out.
3. **A4 load+preview WAV** + **B2a copy-sample-to-channel** — small [screen]
   reuse wins.
4. **B1 Basic⇄Advanced carry-over** — needs one product decision (Adv→Beg
   down-map vs fresh); ask the user.
5. **A2 instrument column + list** — bigger; verify/【maybe】needs a
   `setCellInstrument` engine setter (coordinate).
6. **C2–C9 I/O fan-out** — once C0 exists, each screen is a small adapter:
   Beginner XM/S3M/IT (C2), Advanced broad import/export (C3/C4), Loop Mixer
   (C5), My Melody/Free Sing (C6), Song Book export (C7), module↔text (C8),
   long-tail (C9).
7. **B3 Loop Mixer→Tracker groove import** — the marquee cross-feature handoff.
8. **A3 VU meters + on-screen piano** — polish.
9. **[needs-engine] hand-offs to @tracker-replayer:** B2b PCM-preserving Advanced
   module export, B2c serializable sound + share token, B2d MultiSample surfacing
   (screen part mine, engine part his). File these on the board for him.

## E. Coordination
- Every slice: update the 🚧 board + `git pull --rebase origin main` + push
  before touching a hot shared file (`composition_workshop_screen.dart`,
  `loop_mixer_screen.dart`, `import_screen.dart`, `home_screen.dart`,
  `tracker_screen.dart`, the ARBs) and after each ship.
- **Do not edit** `tracker_song.dart` / `tracker_engine.dart` / `mod/*` — those
  are @tracker-replayer's; the **[needs-engine]** items are proposed to him, not
  done here.
- Shared new glue files (`MusicIoMenu`, `grooveSpecToTrackerSong`) are mine to
  create under `lib/features/...`/`lib/core/audio/` app-side.

---

# D. Workshop as a mini-DAW — modes, keyboard, sample library, drumkit, interconnection

New arc (user, 2026-07-18): keyboard UX fixes; "change instrument" → a real
**samples library** + a **DAW module** (beginner + advanced) to change every
sample/fx; **Loop Mixer as a Workshop MODE** (not just a Compose tile) with
maximum interconnection; a **Drumkit/BoomBox** mode + a GarageBand-style virtual
drumkit and its interconnection. Grounded in two read-only surveys (keyboard
widgets · modes/loop-mixer/drums/instruments, 2026-07-18).

## D0. The through-line — Workshop = a shell of MODES over shared documents
The home "Workshop" button is a `PopupMenuButton<int>` (`home_screen.dart:186`)
switching Score(default) / Advanced-Tracker(1) / Tab(2). Make it the app's DAW
shell: add **Loop Mixer(3)** and **Drumkit(4)**, and let every mode exchange
content through interchange types that ALREADY EXIST — `MultiPartScore`
(notation; every mode now imports/exports via the shared `MusicIoMenu`),
`TrackerSong` (grids), `GrooveSpec` (grooves), `DrumRowsPattern` = `Map<Drum,
List<bool>>` (beats) — plus a future serializable **Sound Library**. "Open in
<mode>" everywhere, converting through these types. The only missing glue is 2
converters + 1 store + a few `initialX` constructor params; everything else
composes.

## D1. Keyboard UX (Score + Tracker) — [screen] + additive [shared widget]
Both screens use the shared `PianoKeyboard` (`lib/shared/widgets/
piano_keyboard.dart`), which sizes via `LayoutBuilder` (keyWidth =
maxWidth/whiteKeyCount); the caller fixes width with `SizedBox(width: whiteKeys *
_pianoKeyWidth)`. Score: 42 keys × **46px** const, height 140, scrolls (NO
scrollbar), pre-scroll ~C3; zoom (`_zoom`) only scales the STAFF. Tracker: 42 ×
**40px** const, height 72, scrolls WITH scrollbar; `_zoom` only scales the GRID;
`_octave` is the computer-keyboard base only and does NOT move the piano; key
hints are a **separate legend strip** (`_showKeyHints`), not on the keys.
Fixes:
- **(a) Zoom/size** [screen] — make `_pianoKeyWidth` a state var × a `_pianoZoom`
  (~0.7–2.0) with +/- buttons; rebuild the `SizedBox`. (Score caches
  `_pianoKeyboard` as a `late final` — must key it off zoom or un-cache.)
- **(b) Scroll** — both already scroll; add a `Scrollbar` to the Score piano for
  parity.
- **(c) Key hints ON the keys** [shared widget, additive] — add `Map<int,String>
  keyHints` to `PianoKeyboard` and render a small caption on each white/black
  key. Tracker builds the map from its computer-key→midi table at the current
  `_octave`, so hints move with the octave. (Its label API today is note-name
  only — `keyColors` is the sole per-key hook.)
- **(d) Octave centers the keyboard** [screen] — on `_octave` change,
  `_pianoScroll.animateTo(offsetForOctave)` (offset from `startMidi`,
  `_pianoKeyWidth`, 7 white/oct, minus half the viewport). No widget change.

## D2. Sample library + DAW instrument editor — [screen]/[glue] + [needs-engine]
"Change instrument → a samples library; change every sample; a DAW module,
beginner+advanced." Extends §B2. **Finding:** the in-song instrument taxonomy is
rich (additive/sfxr/sample/multi-sample/percussion) but instruments are
**ephemeral — embedded in the in-memory `TrackerSong`; there is NO persistent
sample library across sessions** (the only prefs store is `UserSongsService` =
MusicXML songs). `MultiSampleInstrument` is defined but **used in no UI**.
- **D2a. `SoundLibraryService` (persistent store)** [glue] — save/load named
  sounds across sessions (SharedPreferences/files), mirroring `UserSongsService`.
  Needs instrument serialization → **[needs-engine]** `toJson`/`fromJson` for
  `SampleInstrument` (base64 PCM + baseMidi/env/loop), `SfxrInstrument`
  (`SfxrParams` is all numbers), `MultiSampleInstrument` (zones) in
  `tracker_engine.dart`/`multi_sample_instrument.dart` — file a contract for
  @tracker-replayer (this is §B2c).
- **D2b. DAW instrument editor** [screen] — ONE editor for any instrument.
  **Beginner** = a few presets + big sliders (voice fx chipmunk/robot/…, sample
  trim/normalize/reverse/stretch, sfxr dice, the volume/pan-envelope presets I
  shipped). **Advanced** = the full parameter set — every sfxr field + the
  `crisp_dsp` fx chain from `docs/FX_HANDOVER.md` (filter/reverb/delay/
  distortion/pitch/formant) + envelope breakpoints. Reuses the record sheet +
  `_SampleWaveform` trim + `_kEnvelopePresets`.
- **D2c. "Change instrument" → the library** [screen] — replace the flat
  `kTrackerInstruments` picker with: pick a saved sound · new from
  mic/WAV/sfxr/additive · edit (D2b) · save to library. Surface
  `MultiSampleInstrument` ("build a keymap from N samples", §B2d).

## D3. Loop Mixer as a Workshop mode + interconnection — [screen] + [glue]
Loop Mixer is a working sandbox reached as a **composition game tile**
(`game_registry.dart:1105`), with `KU1.` token round-trip (`grooveToken` /
`loadGrooveToken`) but **`const LoopMixerScreen({aecFactory})` has no
`initialSpec`**, and **NO GrooveSpec↔TrackerSong converter exists**.
- **D3a. Mode** [screen] — add "Loop Mixer"(3) to the home dropdown; keep the
  tile (or point it at the mode).
- **D3b. Seed from another mode** [screen] — `LoopMixerScreen({GrooveSpec?
  initialSpec})`.
- **D3c. Groove ⇄ Tracker** [glue] — `grooveSpecToTrackerSong` (`userCells`→a
  melodic channel, `beatRows`→a `PercussionInstrument` channel,
  `userInstrument`→an `AdditiveInstrument`) + the reverse for the shared subset.
  "Open groove in Tracker" · "Send tracker pattern to Loop Mixer."
- **D3d. Groove ⇄ Score/Song Book** — export already works (shared sheet, just
  shipped). Add "Open groove in Score Workshop" (`grooveParts`→`MultiPartScore`→
  `CompositionWorkshopScreen(initialScore:)`).

## D4. Drumkit / BoomBox mode + virtual drumkit — [screen] + [needs-engine]
**Finding:** `Drum` = {kick, snare, hat} (only 3), `renderDrum`/
`renderDrumPattern` (`synth.dart`), `DrumRowsPattern` = `Map<Drum,List<bool>>`
(the beat model shared by the Loop Mixer beat track AND the tracker's
`PercussionInstrument`), beatbox→`DrumRowsPattern` via `beat_capture.dart`. There
is a **single-pad** tap game (`drum_read_screen.dart`) but NO multi-pad kit / no
step-grid drum editor.
- **D4a. New `DrumkitScreen`** [screen], home dropdown(4). Two faces like the
  tracker: **BoomBox (beginner)** = a GarageBand-style **tappable pad grid**
  (plays `renderDrum` on tap) + a simple **step beat-grid** editing a
  `DrumRowsPattern`; **Advanced** = more steps, per-step velocity, swing.
- **D4b. More drum voices** [needs-engine] — the enum has only 3; toms/clap/
  cymbal/ride need `synth.dart renderDrum` + `Drum` — file for @tracker-replayer;
  the UI adapts to whatever `Drum.values` exist.
- **D4c. Interconnection** — the Drumkit edits a `DrumRowsPattern`, the SAME type
  the Loop Mixer beat track and the tracker percussion channel use. So
  Drumkit→Loop Mixer (`setUserBeatTrack`), Drumkit→Tracker (percussion channel),
  beatbox→Drumkit — one beat model, many editors.

## D5. Ownership + execution order (code step by step)
- **[screen] mine:** D1 keyboard, D3a/b/d Loop-Mixer-mode + Open-in-X, D4a
  DrumkitScreen, D2b/c DAW editor + library picker UI.
- **[glue] mine (new files):** `grooveSpecToTrackerSong` (D3c),
  `SoundLibraryService` (D2a).
- **[needs-engine] → @tracker-replayer contracts:** instrument `toJson`/
  `fromJson` (D2a), more `Drum` voices (D4b).
- **Order:** **(1) D1 keyboard fixes** (concrete, high value, mostly mine) →
  **(2) D3a+b Loop Mixer as a mode** (small) → **(3) D3c groove↔tracker converter
  + Open-in-X** → **(4) D4a Drumkit/BoomBox** (pad + step grid over
  `DrumRowsPattern`) → **(5) D2 sound library + DAW editor** (biggest; editor UI
  first over existing instruments, then the store once serialization lands).

---

# E. Audio output architecture — findings (CrisperWeaver, glint) + what to learn

Investigated 2026-07-18 (two read-only repo surveys) after the question "how do
we output audio, should we use glint, anything to learn from CrisperWeaver's
multi-track?".

## How WE output audio today
Everything is **offline-rendered in Dart** → one WAV → played via the
**`audioplayers`** plugin. `synth.dart mixStems` / `renderDrumPattern` /
`tracker_replayer` sum all stems into a `Float64List`; `wavBytes` makes a PCM16
WAV; `GaplessLoopPlayer` double-buffers two `AudioPlayer`s to loop without a
seam; one-shots (pad hits, previews) call `playWavBytes`. Mic = `record`.
**Consequence:** there is **no live per-track mixer** — a fader/mute/solo change
re-renders the WHOLE mix and swaps it in phase (`_syncPlayback`). Fine for loops;
not real-time multi-track (can't ride one track's gain live without a re-render;
per-play latency limits tight monitoring).

## CrisperWeaver (../CrisperWeaver) — what its "multi-track" actually is
It **isn't** multi-track: it's a single-track offline ASR/TTS app (Flutter +
`just_audio`/`just_audio_media_kit`). One mono `Float32List` buffer; editing is
sample-level **splice** (trim/cut/split → a new WAV), no summing of two signals
anywhere, no pan/mute/solo, one stream ever plays. So it sits **at or below** our
altitude for mixing and CONFIRMS the "render-offline → play-one-file" pattern
rather than improving it. **But three techniques are worth lifting:**
- **★ Move the offline mixdown to a worker ISOLATE** (`Isolate.run(() => …)`) +
  a path/spec-keyed render cache, so the UI never janks on a big render. OUR
  `_syncPlayback` re-renders on the main isolate on every fader move / edit — on
  a long tracker song or the Loop Mixer that can stutter. This is the concrete,
  high-value lesson. (CrisperWeaver: `audio_edit_service.dart` isolate+cache.)
- A **prefetch/consume** isolate pattern (decode/render the next thing while the
  current plays) — maps onto pre-rendering the next pattern.
- A cheap **duration probe** (a throwaway player parses length without decoding).
- NB CrisperWeaver itself **bundles `glint`** as a codec fallback + for MP3/AAC/
  Opus export — so glint is already a proven ecosystem dependency.

## glint (../glint) — a CODEC suite, NOT an output engine
glint is a clean-room **MIT C++17 audio *codec* library**: MP3 / AAC-LC / Opus
encode+decode, WAV I/O, and a Kaiser windowed-sinc **resampler** — offline
(buffer→buffer), with real **Dart/Flutter FFI bindings** (`glint_audio`) that
build for Android + iOS (+ WASM). It **never opens an audio device**: no
playback, no mixer, no multi-track. So:
- **Audio OUTPUT / real-time multi-track → NO.** glint cannot make sound or mix.
- **Compressed EXPORT → YES, real value.** Our "save audio" is WAV-only; glint
  adds shareable **MP3/AAC/Opus** export from Flutter (`GlintEncoder`/
  `GlintAacEncoder`/Opus). A genuine feature for the export sheet.
- **Higher-quality resampling → maybe.** `glintResample` (Kaiser sinc) could
  replace our linear `crisp_dsp/resample.dart` for sampled instruments (quality).
- ⚠ Its "noise-shaping" is *codec* quantization-noise shaping, NOT a PCM
  dither/requantizer — don't expect a dither lib.

## The real conclusion — two independent paths
1. **Smoothness now (unblocked, ours):** render the mixdown in an **isolate** +
   cache (the CrisperWeaver lesson). Removes jank from Loop-Mixer/Tracker fader
   moves without changing the audio model. Highest bang-for-buck.
2. **Compressed export (unblocked):** wire **glint** (`glint_audio` FFI) into the
   shared export sheet → MP3/AAC/Opus. Optional: glint's Kaiser resampler for
   sample instruments.
3. **True real-time multi-track (the DAW dream, bigger):** neither glint nor
   CrisperWeaver provides it. It needs a real-time engine — **`flutter_soloud`**
   (SoLoud: many PCM voices on a mixing bus, live per-voice volume/pan, low
   latency, cross-platform incl. web) or a miniaudio/AudioTrack FFI layer. Only
   worth it if we want live faders/solo WITHOUT re-render; a large swap of the
   `audioplayers`+offline-WAV core. Scope it separately if the DAW (D2) demands
   live mixing; the isolate render (#1) covers most of the pain until then.

## E — execution notes (E1 shipped; E2 de-risked; E3 scoped)

**E1 (isolate render) — SHIPPED (first cut).** Loop Mixer WAV export runs on
`Isolate.run`, sending only the small `GrooveSpec` (rebuild+render in the
worker), so a long export never freezes the frame. The LIVE in-phase loop swap
stays SYNCHRONOUS on purpose: making it async would break the phase swap, and a
sample-heavy song's isolate send-copy has its own main-thread cost that offsets
the win. Follow-up: apply the same one-shot-render→isolate pattern to module
export + the tracker's play-from-top full render (with a token guard so a
superseded render doesn't swap in late).

**E2 (glint MP3/AAC/Opus export) — a NATIVE-BUNDLING effort, de-risked.**
`glint_audio` (`~/code/glint/bindings/dart`, pub name `glint_audio` v0.9.0) is a
**bring-your-own-`libglint`** FFI binding: it `DynamicLibrary.open('libglint.
dylib'/'.so'/'.dll')` with **no prebuilt lib and no Flutter plugin build hook**.
So this is the SAME shape as our `native/aec/` plugin, NOT a pubspec wire-up —
adding a bare dep would red CI/the app (open() fails at runtime; a path dep to
`~/code/glint` is absent in CI). **De-risked:** `libglint.dylib` (857 KB) builds
cleanly from glint's CMake `glint_shared` target on this macOS (`cmake -B … &&
cmake --build … --target glint_shared`). **Plan (mirror the AEC, macOS-first):**
(1) a `core/audio/glint_capability.dart` seam that is **web-stubbed** and returns
null where `libglint` isn't bundled; (2) build + bundle `libglint.dylib` into the
macOS Runner (Android `.so` per-ABI / iOS framework later); (3) `glint_audio`
added ONLY where bundled + **excluded from CI analyze** like the AEC; (4) wire
`GlintEncoder`/Opus into the shared `music_export.dart` sheet, platform-gated.
Optional: `glintResample` (Kaiser sinc) to replace linear `crisp_dsp/resample.
dart` for sampled instruments. This needs an app build to verify (env-wrapper),
so it's its own careful slice — not folded into a screen commit.

**E3 (real-time multi-track engine) — the biggest, scoped last.** Replaces the
`audioplayers`+offline-WAV core with a real-time mixer so faders/solo/mute are
live WITHOUT a re-render. Candidate: **`flutter_soloud`** (SoLoud — many PCM
voices on a bus, per-voice volume/pan, low latency, cross-platform incl. web via
wasm). Migration: load each stem as a SoLoud sound; play them as simultaneous
voices; map track gain/pan/mute/solo onto voice params; keep offline WAV render
only for EXPORT. This touches every playback callsite (`GaplessLoopPlayer`, the
tracker/loop-mixer/drumkit transports) — a multi-day core swap with real
web/latency verification. Do it only when the DAW (D2) genuinely needs live
mixing; E1 (isolate render) removes most of the jank pain until then.
