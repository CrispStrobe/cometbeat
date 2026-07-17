# Tracker & Audio — idea backlog (plan/tasks)

Consolidated backlog of everything floated for the Tracker + audio stack. Grouped
by area; each item notes source(s) and whether a detailed handover exists. All are
delegatable the proven way — **maintainer writes contract + test suite, one agent
implements one file, maintainer integrates.** Sources: our MIT repos
(`crispaudio` / `CrispFXR-web` / `voicelab`) + OpenMPT/libopenmpt (BSD-3, portable)
+ crisp_notation (in-house).

## A. Module codecs (readers, then writers)
- ✅ **`.mod`** codec + bridge + in-app import/export (shipped).
- ✅ **`.s3m`** reader (shipped — golden oracle + real "Illustrious Fields").
- 🚧 **`.xm`** reader — pattern bit-flag packing + delta-encoded 8/16-bit samples.
- 🚧 **`.it`** reader — hardest: IT214/IT215 block variable-bit-width sample
  decompression + node envelopes. Do the decompressor as its own tested unit.
- Port base: **libxmp-lite (MIT)** loaders; libopenmpt (BSD-3) as oracle. Details +
  specs + gotchas + order (S3M→XM→IT): **`TRACKER_HANDOVER.md` §6**.
- **Writers** (later): no read-only lib helps — reference MilkyTracker/OpenMPT
  (BSD) save routines or write from spec (as we did for `.mod`).
- ✅ **Format converters** — the full N×N matrix ships: MOD↔XM↔S3M↔IT via the
  neutral `ModuleDoc` hub. Single entry point `convertModule(bytes, target)` /
  `convertDocTo(doc, target)` in `module_convert.dart` (bin/modconv.dart funnels
  through it). All 16 cells covered by a data-driven matrix test that re-parses
  each output through the hub and asserts title/note(MIDI-space)/sample-peak
  conservation (`module_convert_test.dart`). MIDI↔MOD also shipped (Score hub).

## B. Sampling (the "steal/record/shape a sound" toys)
- ✅ **Cubic-Hermite (Catmull-Rom) interpolation** SHIPPED (`resampleCubic` in
  `crisp_dsp/resample.dart`; `SampleInstrument` + the borrow bridge use it). Smoother
  pitch-shift (RMS error <0.5× linear on a pitched sine) → directly improves the
  **borrowed module sample** + **recorded-voice** instruments. *(Was also FX_HANDOVER #2.)*
- **Borrow a sample from a module** — import a `.mod`/`.s3m`/`.it` sample's PCM as a
  tracker `SampleInstrument` ("steal an instrument sound from a classic module").
  The codecs already expose the PCM; wire a picker: module → sample → instrument.
- ✅ **Multi-sample instruments** SHIPPED — `MultiSampleInstrument` + `SampleZone`
  (`multi_sample_instrument.dart`): a sample per note-range (XM/IT keymap model),
  each note resamples the nearest zone. `MultiSampleInstrument.mapped([(sample,
  baseMidi)…])` auto-splits ranges at base-note midpoints ("map recorded notes
  across the keyboard"). Render acceptance proves the chosen zone reaches the audio
  (`multi_sample_instrument_test.dart`). *(Not yet surfaced in the picker UI.)*
- ✅ **Sample editing** SHIPPED (core) — `sample_edit.dart`: `trimPcm` /
  `trimSilence` / `normalizePcm` / `fadeIn` / `fadeOut` / `reversePcm`, all
  non-destructive (input never mutated). `sample_edit_test.dart`. *(loop-point =
  an engine sustain-loop change, still open; UI slots still open.)*
- **Instrument envelopes** — volume/pitch ADSR-ish envelopes on sampled/sfxr voices
  (from OpenMPT/IT). *(Also in FX_HANDOVER #4.)*

## C. Audio FX — full effort in **`FX_HANDOVER.md`**
Complete the crispaudio effect chain (chorus/delay/flanger/reverb/ring-mod/full
distortion set + sfxr FM/LFO), richer voicelab presets + PSOLA time-stretch, a
per-channel effect chain in the Tracker, tempo **swing/groove**, and the cubic
interpolation above. Order + contracts/tests plan: `FX_HANDOVER.md`.

## D. Notation bridge (Tracker/Module ↔ Score/MIDI/MusicXML)
- ✅ Tracker→Score (per-channel staves), Score→Tracker (chord split), MIDI↔MOD hub.
- ✅ **ModuleDoc ↔ Score bridge** SHIPPED (`lib/core/audio/mod/module_notation.dart`,
  Flutter-free): `moduleChannelToScore` / `moduleToMultiPart` (one staff per
  sounding channel, clef auto) and the reverse `scoreToModuleDoc` /
  `multiPartToModuleDoc` (chord-split, and a rest survives via `DocCell.off` —
  the new neutral note-off). `module_notation_test.dart` round-trips
  Score↔doc, doc↔multiPart, and module→multi-part→MIDI end-to-end.
- ✅ **Multi-track MIDI** SHIPPED — `multiPartToMidi` assembles a format-1 SMF
  (one MTrk per part; `scoreToMidi` is single-Score/format-0), with
  `splitMultiTrackMidi` as the inverse for round-trips.
- ✅ **Module ↔ MusicXML** SHIPPED — `moduleToMusicXml` / `musicXmlToModuleDoc`
  through the library's `multiPartToMusicXml` ⇄ `multiPartScoreFromMusicXml`.
- ✅ **Bidirectional CLI** — `bin/notaconv.dart` now converts BOTH ways by
  extension: module→(.mid/.xml), and `.mid`/`.xml`→module (`--multi` =
  multi-track). Live-verified: module→multi-track-MIDI→.xm and
  module→MusicXML→.it round-trip through real files.
- ✅ **Note-off through the codecs** SHIPPED — XM (97) / IT (255) / S3M (254)
  key-off now maps to/from `DocCell.off` in `module_convert.dart` (read + write),
  so a rest survives a REAL module-bytes round-trip (Score→doc→bytes→doc→Score),
  tested per-format. MOD has no key-off, so a rest rings through there (asserted +
  documented). The N×N matrix is unaffected (readers only set note-off on the
  actual key-off byte, which the goldens don't use).
- **Score→Tracker beyond one bar** — more of the grid / variable pattern length.
- **Live Workshop↔Tracker handoff** — open a Workshop score directly into the
  Tracker and back (the converter's ready; this is app plumbing).

## E. Tracker Studio depth (from `TRACKER_HANDOVER.md` §1/§4)
- **Variable pattern length** (e.g. 16/32/64 rows) + more channels — also unblocks
  faithful module import.
- **Keyboard entry** (desktop/web jamming), a **retro FT2/IT skin** (Studio theme),
  full chromatic mode, an on-grid **volume column** UI (dynamics already in the
  model), per-cell effect column display.
- **Percussion**: more drum voices; a dedicated drum-kit sample instrument.

## F. Playback & polish
- ✅ Gapless two-player swap.
- **Song → WAV export** (render the whole arrangement to a file).
- **libopenmpt.js** optional *accurate* module preview player (web/WASM only) — for
  faithful playback of arbitrary imported modules. Against the pure-Dart ethos;
  lowest priority.

## G. Test infrastructure
- **OpenMPT "tricky test cases"** as codec fixtures (verify licence) — strengthens
  the codec suites. Meanwhile: hand-authored golden oracles (committed) + real wild
  files (gitignored, local) is the working pattern.
- **CC0 real modules** (OpenGameArt) committed as CI fixtures where licence allows.

## H. CLI tools (headless, pure-Dart — `dart run bin/<x>.dart`)
Everything in `lib/core/audio/` is **Flutter-free pure Dart** (that's why
`bin/listen.dart` already runs headless), so most of the audio/codec stack can be
exposed as CLI tools — great for scripted acceptance tests (the proven
`render → dart run bin/listen.dart --wav → assert` loop), batch conversion, and CI
without a device. Candidates, roughly in value order:
- ✅ **`bin/modinfo.dart`** SHIPPED — parses ANY module (`.mod`/`.s3m`/`.xm`/`.it`,
  sniff by signature) and dumps structure: format, title, channels, speed/tempo,
  order, patterns, per-sample name/length/loop/c5speed (`--patterns` lists rows).
  The Dart port of the Python inspectors; doubles as a fixture-verifier.
- ✅ **`bin/modconv.dart`** SHIPPED — converts between formats (out format = output
  extension, e.g. `modconv song.s3m song.xm`) via the neutral-hub converters, and
  `--extract-samples <dir>` writes each sample to a `.wav` ("steal an instrument",
  §B, from the shell — verified PCM-exact via `wavBytes`).
- ✅ **`bin/render.dart`** SHIPPED — renders a Loop Mixer groove (a `KU1.` share
  token, or `--demo`) to a `.wav` via the pure-Dart `LoopEngine`; `--send reverb|
  delay` for the master send, `--print-token`. Live-verified: token round-trips
  byte-identical; `listen.dart` reads the groove's bass root back.
- ✅ **`bin/notaconv.dart`** SHIPPED — module → Standard MIDI File, importing the
  **Flutter-free `crisp_notation_core`** directly (`scoreToMidi`) — NOT the Flutter
  `crisp_notation`. Busiest (or `--channel N`) channel's rows → a Score → MIDI;
  1084 note-ons out of the real "terrascape" module. **Found + fixed a latent app
  bug in passing:** `scoreToMidi` drops notes without ids, so the Tracker's own
  "Export MIDI" was silent — `_trackerAsScore` now sets ids (`8a753e1`).
  (MusicXML from the shell — `multiPartToMusicXml` — is a further extension.)
- ✅ **`bin/fxproc.dart`** SHIPPED — applies a crisp_dsp effect to a `.wav` offline:
  `--effect reverb|delay|chorus|flanger|distortion|ringmod|stretch` + the voice
  presets (chipmunk/robot/alien/…), params `--mix/--drive/--carrier/--factor/--kind`.
  Live-verified: `--stretch 1.5` → exactly 1.5× frames; `listen.dart` reads a
  reverbed groove back with pitch intact.
- ✅ **The headless CLI suite is COMPLETE**, incl. **`bin/mus.dart`** — one
  dispatcher over all six: `mus listen|info|conv|render|midi|fx …` (imports each
  tool's `main` in-process, forwards the tail args). Each tool is a thin `main()`
  over the Flutter-free `lib/core/audio`; the heavy logic stays in `lib/` +
  unit-tested. **Nothing left in §H.**
