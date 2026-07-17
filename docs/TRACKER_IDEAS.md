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
- **Format converters** once codecs land: MOD↔XM↔S3M↔IT via model bridges
  (each is a sample+pattern model). MIDI↔MOD already shipped (Score-bridge hub).

## B. Sampling (the "steal/record/shape a sound" toys)
- ✅ **Cubic-Hermite (Catmull-Rom) interpolation** SHIPPED (`resampleCubic` in
  `crisp_dsp/resample.dart`; `SampleInstrument` + the borrow bridge use it). Smoother
  pitch-shift (RMS error <0.5× linear on a pitched sine) → directly improves the
  **borrowed module sample** + **recorded-voice** instruments. *(Was also FX_HANDOVER #2.)*
- **Borrow a sample from a module** — import a `.mod`/`.s3m`/`.it` sample's PCM as a
  tracker `SampleInstrument` ("steal an instrument sound from a classic module").
  The codecs already expose the PCM; wire a picker: module → sample → instrument.
- **Multi-sample instruments** — a sample per note-range (the XM/IT instrument
  model): record several notes, map across the keyboard. Bigger model change.
- **Sample editing** — trim / loop-point / normalize / fade a recorded clip (ideas
  from voicelab + crispaudio's timeline editor). Longer clips, multiple voice slots.
- **Instrument envelopes** — volume/pitch ADSR-ish envelopes on sampled/sfxr voices
  (from OpenMPT/IT). *(Also in FX_HANDOVER #4.)*

## C. Audio FX — full effort in **`FX_HANDOVER.md`**
Complete the crispaudio effect chain (chorus/delay/flanger/reverb/ring-mod/full
distortion set + sfxr FM/LFO), richer voicelab presets + PSOLA time-stretch, a
per-channel effect chain in the Tracker, tempo **swing/groove**, and the cubic
interpolation above. Order + contracts/tests plan: `FX_HANDOVER.md`.

## D. Notation bridge (Tracker ↔ Score/MIDI)
- ✅ Tracker→Score (per-channel staves), Score→Tracker (chord split), MIDI↔MOD hub.
- **Multi-track MIDI export** — today it's a single block-chord Score; export each
  channel as its own MIDI track (needs a channels→multi-track writer, since
  `scoreToMidi` is single-Score).
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
- **`bin/fxproc.dart`** — apply the crisp_dsp effects/voice_fx (§C) to a `.wav`
  offline (chipmunk/robot/formant a recording without the app). All the DSP is
  already pure functions.
- Packaging note: keep each tool a thin `main()` over the library (like
  `listen.dart`); the heavy logic stays in `lib/` and stays unit-tested. A single
  `bin/mus.dart` dispatcher (`mus info|conv|render|…`) could wrap them later.
