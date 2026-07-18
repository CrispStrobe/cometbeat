# libopenmpt oracle — verifying module effect import

`libopenmpt` (BSD-3, via the `openmpt123` CLI) is the reference implementation for
MOD/S3M/XM/IT playback. We use it as an **A/B oracle** to verify our cross-format
effect import (does our replayer make an imported module behave like the
reference?). It is a **dev / verification tool**, NOT a committed test dependency
(CI has no libopenmpt) — the committed tests verify the mapping *structurally*
(effect bytes → the right `fxCmd`/`fxParam`).

## Setup (macOS)

```
brew install libopenmpt        # provides openmpt123 (+ the lib)
openmpt123 --version           # confirm
```

## The A/B workflow

```
OUT=/tmp/oracle
# 1. Reference render (the oracle):
cp module.s3m $OUT/o.s3m
openmpt123 --render --samplerate 44100 --channels 1 --no-float \
  --output-type wav --force --quiet $OUT/o.s3m          # → $OUT/o.s3m.wav

# 2. OUR render (import → replay):
dart run bin/render_module.dart module.s3m $OUT/mine.wav

# 3. Compare the note/effect trajectory (the pitch detector is the yardstick):
dart run bin/listen.dart --wav $OUT/o.s3m.wav          # reference
dart run bin/listen.dart --wav $OUT/mine.wav           # ours
```

A porta-up should read as a **rising** pitch in both; a vibrato as a wobble; a
pattern break as a truncated section; etc. Author small tonal test modules with
one effect each (a sine `S3mSample` + a note + the effect on following rows) via
the format writers (`writeS3m`/`writeIt`) so the effect is isolated. Real modules
are gitignored (copyright) — keep only license-clean fixtures committed.

## What the oracle FOUND (2026-07-18)

Running the porta A/B (a 1-channel sine S3M with `Fxx` porta-up) exposed a real
limitation that a structural test alone would have missed:

- **Reference:** the note glides up (A3 → B3 → F4 → C5 …). ✅
- **Ours:** flat at A3. ❌

The S3M→ours **mapping is correct** (the imported porta cells carry `fxCmd=0x1`,
verified) — but the replayer applies the **per-tick PITCH/VOLUME effects**
(porta/vibrato/tremolo/`Cxx`/`Axy`) only in the **additive tick voice**. Module
imports are **sample** voices (`SampleInstrument`), which the replayer renders as
one-shot per-note buffers with NO per-tick modulation. So imported porta/vibrato/
tremolo/volume don't *sound* on sampled channels — for ANY format (MOD/XM too),
not just S3M/IT.

What DOES apply to sample voices today: notes, per-cell instrument, `9xx` sample
offset (implemented inside `SampleInstrument.renderChannel`), and the FLOW
commands (`Bxx`/`Dxx`/`E6x`) which are resolved format-agnostically in `walkFlow`.

**The real remaining work (bigger than a mapping table):** a **per-tick sample
voice** in the replayer — a resampling read-pointer with per-tick pitch (porta/
vibrato/arp) and volume (tremolo/`Cxx`/`Axy`) modulation, the sample-instrument
analogue of the additive tick voice. Once that lands, every imported module's
pitch/volume effects (MOD/XM/S3M/IT alike) light up, and the S3M/IT mappings here
become audible. This is the honest outcome of doing S3M/IT oracle-first: the gap
was found before shipping a mapping that silently wouldn't play.

## Status

- **Per-tick SAMPLE voice: BUILT** (`_renderSampleChannelInto` in
  `tracker_replayer.dart`). A sample channel that carries per-tick effects now
  renders through a resampling read-pointer with per-tick pitch/volume, so
  porta/vibrato/tremolo/`Cxx`/`Axy`/arp SOUND on sampled channels.
  **Oracle-verified:** the porta S3M now reads as a rising glide in ours
  (A3→C4→G4→C5) matching openmpt123's rise (A3→B3→F4→C5) — both reach C5; the
  intermediate rate differs by our documented musical-approximation porta rate.
  Effect-free sample channels keep the byte-identical whole-channel render (gated
  by `_hasPerTickEffect`).
- **Sample LOOP points: DONE + oracle-verified.** `SampleInstrument` carries
  `loopStart`/`loopLength` (scaled to the engine rate in `sampleInstrumentFromDoc`);
  looping notes render through a wrapping read-pointer (`_resampleLooping` in the
  whole-channel path, and an inline wrap in the per-tick sample voice). A
  looping-sample S3M (a short sine, loop over the whole sample, one note held ~16
  rows) reads as a **flat sustain across the whole note in BOTH** openmpt123 and
  ours (per-0.2s RMS ≈ constant), whereas the same sample with the loop flag OFF
  decays to silence after ~one sample length in both — exactly the loop/one-shot
  distinction. Non-looping samples keep the byte-identical one-shot resample path.
- **Variable-timing sample per-tick effects: DONE.** A SAMPLE channel that carries
  per-tick effects AND a mid-song tempo/speed change (or a per-pattern length
  change) now renders through `_renderSampleChannelIntoVariable` (the variable-span
  sibling of `_renderSampleChannelInto`) instead of falling back to
  one-shot-per-note, so porta/vibrato/tremolo/`Cxx`/`Axy` sound on that path too;
  effect-free sample channels keep the cheaper `_renderNonAdditiveVariable`
  one-shot path. Test: a sample channel with a porta + a 120→80 mid-song tempo
  change still reads as a rising pitch. `songTotalMs`/`resolveTimingMap` are
  already mid-song-tempo-aware (verified: onsets go non-uniform after the change).
  **No known replayer follow-ups remain.**
- **S3M** command→`fxCmd`/`fxParam` table: implemented in
  `module_convert._s3mEffectToFx` (core commands, structural test + oracle-
  verified). **IT** (`_itEffectToFx`) is DONE too — oracle-verified: an IT porta reads NEARLY IDENTICALLY to openmpt123 (A2 C3 G3 C4 F#4 C5 F5 C6 F6 B6 in both). All four import formats (MOD/XM/S3M/IT) now carry + SOUND their effects.
