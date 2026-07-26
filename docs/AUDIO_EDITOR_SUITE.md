# Audio Editor — the swiss-army ladder (scoped 2026-07-26, opus)

**The ask (maintainer).** The Audio Editor should become a swiss-army knife with
the full bag of tricks a serious digital audio workstation carries. Work through
the vocabulary of the classic command-line audio toolchains and consider *every*
operation. Have them **all in the GUI *and* all in a CLI** — the CLI is what
makes each one unit-testable and live-testable. And: the five authoring modes
must interoperate, so **any track is editable in any other editor** (a drum lane
in the DrumKit, a guitar riff in the Tab editor, either one in the Score
Workshop, a Tracker pattern in the Audio Editor) with the **same FX** available
to every kind of track.

**Clean-room, always.** Every DSP block here is written from published theory —
the standard biquad cookbook formulas, textbook FIR/window design, published
papers on companding, spectral subtraction and time-scale modification. We do
not read, port, or adapt any GPL (or otherwise encumbered) implementation. The
*names* of effects are facts about what audio software does; the *expression* is
ours. See auto-memory `cleanroom-gpl-port-process`.

**No contender names** — not in code, not in docs, not in comments. This file
describes capabilities, never products.

---

## 1. Where we actually stand (verified, not assumed)

The engine is genuinely strong already. Do not rewrite it.

| Layer | File | State |
|---|---|---|
| Timeline model | `core/audio/daw_timeline.dart` (966 l) | Stereo; clip → `ClipSource` ("vector, not bitmap"); per-clip/track/bus/master FX chains; gain automation; buses + sends; markers; windowed render byte-identical to the full render |
| Destructive edits | `core/audio/daw_edits.dart` (309 l) | normalize · amplify · invert · remove-DC · trim-silence · stats · generator (7 shapes) · range surgery |
| FX model | `core/audio/fx/fx_spec.dart` + `fx_chain.dart` + `fx_params.dart` | **Mode-neutral** `FxSpec{type, enabled, params, automation}`, 30 `FxType`s, a param-descriptor table with ranges/units/integer/choices, presets |
| Service | `core/services/daw_service.dart` (2305 l) | ~130 verbs: undo/redo, split/trim/fade/crossfade/freeze/merge/reverse/resample, range ops, stems, instrument slots, round-trip re-source |
| GUI | `features/games/composition/daw_screen.dart` (5357 l) | Lanes, ruler, zoom, meters, markers, inspector, automation curve editor, export sheet |
| CLI | `bin/dawedit.dart` (391 l) · `bin/fxproc.dart` (157 l) | dawedit drives the *real* edit functions on a WAV. **fxproc is the weak spot**: mono-only, 7 hardcoded effects, hand-written flags — it knows nothing about the 30-effect registry |
| Interop | `core/interop/project_bridge.dart` + `shared/music/score_router.dart` | Five-mode conversion matrix with honest loss reports; score clips and tracker clips already round-trip **in-place** from the Audio Editor |

**The three real gaps**, and they are the whole of this plan:

1. **The op vocabulary has holes.** ~30 effects is a good rack, but a swiss-army
   knife also has the filter zoo (all-pass, one-pole, windowed-sinc, arbitrary
   FIR, raw biquad, Hilbert), the dynamics zoo (multi-segment companding,
   multiband, look-ahead limiting, expansion, de-essing), the channel zoo (remix
   matrix, swap, mid/side, out-of-phase extraction, crossfeed), restoration
   (DC shift, spectral noise reduction, hum/click, de-clip), rate/dither, and a
   real generator (sweeps, noise colours, pluck).
2. **The CLI does not track the engine.** Every new effect today means new
   hand-written flags, so in practice they never reach the CLI at all — which
   means they never get the cheap headless test or the "hear it in one command"
   loop. The fix is structural: **generate the CLI from the FX registry.**
3. **Interop is 40% built and the last 60% is where users live.** Drum and
   groove clips have no way back to their editors at all; a score clip can go to
   the Tracker but never return; a tab's string/fret choice is destroyed on the
   way in; an audio clip has no symbolic route; and — the big one — **saving
   bakes every clip to PCM, so reopening a project loses every model.** The
   engine's whole "vector, not bitmap" promise currently survives only until the
   user hits Save.

---

## 2. The design lever: one registry, two faces

`fx_spec.dart` (what an effect *is*) + `fx_params.dart` (what each param
*means*: range, unit, integer, choices) is already a complete machine-readable
description of the rack. The GUI's FX panel is already generated from it.

**So the CLI must be generated from it too.** Then adding an `FxType` gives you,
with no further work: a GUI control, a CLI verb, self-documenting `--list`
output, range validation, and a place in the shared preset format.

The shared surface is a **chain string** — one line of text that is both the CLI
argument and the app's copy/paste preset:

```
highpass freq=120 | compressor ratio=4 thresholdDb=-22 | reverb mix=0.2 | gain gainDb=-1
```

```bash
dart run bin/fxproc.dart in.wav out.wav --chain "highpass freq=120 | reverb mix=0.25"
dart run bin/fxproc.dart --list                 # every effect, param, range, unit, default
dart run bin/fxproc.dart --list compressor      # one effect in detail
```

The same string round-trips through `FxChainCodec.parse` / `.format`, so a chain
tuned by ear in the app can be pasted into a test, and a chain found in a test
can be pasted into the app. That is the "easy to unit and live test" the ask
names, and it is worth building **first** because every later slice inherits it.

---

## 3. Pillar A — the op vocabulary (DSP parity ladder)

Each row is: `FxType` + entry in `defaultFx` + ranges in `fx_params.dart` +
dispatch in `fx_chain.dart` + DSP in `crisp_dsp/` + a test that proves the
*effect*, not the plumbing (spectral assertions for filters, gain-transfer
assertions for dynamics, correlation for stereo ops). Every one then appears in
GUI and CLI automatically.

Status key: ✅ have it · 🔶 partial · ⬜ to build.

### A1 — Filters (`crisp_dsp/biquad.dart` exists; these are its missing kin)
| Op | Meaning | Status |
|---|---|---|
| low-pass / high-pass (2-pole) | resonant biquad | ✅ |
| band-pass / notch / peaking / low+high shelf | biquad family | ✅ |
| all-pass | phase rotation without magnitude change | ⬜ A1 |
| one-pole low/high-pass | gentle 6 dB/oct, the "tone knob" | ⬜ A1 |
| band-reject with width in Hz/octaves | width parameterisation, not just Q | ⬜ A1 |
| raw biquad | user-supplied b0,b1,b2,a1,a2 — the escape hatch | ⬜ A1 |
| windowed-sinc | steep brick-wall LP/HP/BP/BR with a steepness control | ⬜ A1 |
| arbitrary FIR | tap list, and a magnitude-response fit | ⬜ A1 |
| Hilbert transform | 90° phase, the building block for the stereo ops | ⬜ A1 |

### A2 — Tone curves
| Op | Meaning | Status |
|---|---|---|
| tilt EQ | one knob, dark↔bright | ⬜ A2 |
| loudness compensation | equal-loudness-contour-shaped volume | ⬜ A2 |
| de-emphasis / recording curves | the fixed historical IIR curves | ⬜ A2 |
| presence / contrast | phase-distortion "louder without louder" | ⬜ A2 |
| auto-wah | LFO-swept resonant LP | ✅ (shipped by the tracker→editors agent) |

### A3 — Dynamics (`crisp_dsp/dynamics.dart` has compressor + gate)
| Op | Meaning | Status |
|---|---|---|
| compressor / gate | threshold·ratio·knee·attack·release·makeup | ✅ |
| companding, multi-segment | a piecewise dB-in→dB-out transfer curve with its own attack/decay — the general case that subsumes compressor, expander and gate | ⬜ A3 |
| multiband companding | crossover into N bands, a curve per band | ⬜ A3 |
| look-ahead limiter | true ceiling with no pumping (master's tanh knee is a soft-clip, not a limiter) | ⬜ A3 |
| expander / downward expansion | the gate's continuous cousin | ⬜ A3 |
| de-esser | band-sidechained compression | ⬜ A3 |
| overdrive / distortion / bit-crush | | ✅ |

### A4 — Channels & stereo field
| Op | Meaning | Status |
|---|---|---|
| pan / width | constant-power pan, M/S width | ✅ |
| swap channels | | ⬜ A4 |
| remix matrix | arbitrary `out[i] = Σ w·in[j]`, incl. up/down-mix | ⬜ A4 |
| mid/side encode + decode | as explicit ops, so M and S can be processed apart | ⬜ A4 |
| out-of-phase extraction | side-only — the classic centre-cancel / instrumental trick | ⬜ A4 |
| headphone crossfeed | binaural fatigue reducer | ⬜ A4 |
| balance / per-channel gain | | ⬜ A4 |
| auto-pan | LFO pan | ⬜ A4 |

### A5 — Restoration
| Op | Meaning | Status |
|---|---|---|
| DC shift | deliberate offset (we have DC *removal*) | ⬜ A5 |
| noise profile → spectral reduction | learn a noise fingerprint from a marked range, subtract it spectrally. **The single most-wanted repair tool**; we already have a radix-2 FFT in `chroma_analysis.dart` | ⬜ A5 |
| hum removal | fundamental + harmonic notch comb (50/60 Hz) | ⬜ A5 |
| click / crackle removal | derivative-outlier detect + interpolate | ⬜ A5 |
| de-clip | reconstruct flat-topped peaks | ⬜ A5 |

### A6 — Time & pitch (`time_stretch.dart`, `pitch_shift.dart`, `resample.dart`)
| Op | Meaning | Status |
|---|---|---|
| pitch shift (tempo kept) | | ✅ |
| tempo change (pitch kept) | | ✅ |
| speed change (both together) | | ✅ `resampleClip` |
| pitch **bend envelope** | timed pitch changes across the clip, not one constant | ⬜ A6 |
| stretch quality tiers | window/overlap exposed; a quality knob | 🔶 A6 |
| high-quality rate conversion | band-limited SRC with quality tiers + explicit anti-alias filter | 🔶 A6 |
| up/down-sample (raw) | with and without filtering, for the deliberate aliasing sound | ⬜ A6 |

### A7 — Generation (`daw_edits.dart: generateWave`, 7 shapes)
| Op | Meaning | Status |
|---|---|---|
| sine/square/saw/triangle/white/pink/silence | | ✅ |
| brown / blue / violet noise | the rest of the colour set | ⬜ A7 |
| sweep / chirp | linear + log frequency ramps (the measurement signal) | ⬜ A7 |
| plucked string | Karplus-Strong — `crisp_dsp/karplus.dart` already exists, unreachable from here | ⬜ A7 |
| multi-shape with per-shape ramps + envelope | | ⬜ A7 |
| DTMF / test tones / impulse | | ⬜ A7 |

---

## 4. Pillar B — non-FX editor operations

These are not same-length transforms, so they are not `FxType`s. They live in
`daw_edits.dart` (pure) → `DawService` (undo/notify) → `bin/dawedit.dart` (CLI)
→ inspector UI. Same three-way testability as the Tier-1 ops.

| Op | Meaning | Status |
|---|---|---|
| normalize · amplify · invert · remove-DC · trim-silence · crop · silence-range | | ✅ |
| **pad** | insert silence at a position / both ends | ⬜ B1 |
| **repeat** | loop a clip or range N times | ⬜ B1 |
| **silence detection anywhere** | not just edges: find every silent gap over a threshold/length | ⬜ B1 |
| **auto-split on silence** | one long take → one clip per phrase, on its own lane | ⬜ B1 |
| **splice** | join two takes with an equal-power crossfade at a point | 🔶 B1 (crossfade exists between adjacent clips) |
| **dither + noise shaping** | on any bit-depth reduction, not only export | ⬜ B2 |
| **full statistics** | peak · RMS · DC · crest factor · dynamic range · effective bit depth · zero-crossings · clip count, per channel, `--json` | 🔶 B3 |
| **voice-activity trim** | speech-aware leading/trailing trim | ⬜ B4 |
| **spectrogram to PNG** | `core/audio/spectrogram.dart` exists; no CLI | ⬜ B5 |
| **batch/macro** | apply a chain string to many clips / lanes / a folder of files | ⬜ B6 |

---

## 5. Pillar C — five modes, one document (the interop matrix)

**The promise:** every track, whatever it is, opens in every editor that can
meaningfully hold it, and comes back changed. The conversion machinery already
exists (`ProjectBridge`, with per-route loss reports). What is missing is that
the Audio Editor mostly does not *use* it, and that Save throws the models away.

### What exists
- Score clip → Score Workshop / Tab Workshop, **with in-place return** ✅
- Score clip → Tracker (one-way; no return) 🔶
- Tracker clip → Tracker, exact document, **with in-place return** ✅
- `ProjectBridge.convert(from, to)` for tracker ↔ loop ↔ score ↔ tab ✅

### What is missing
| # | Gap | Why it matters |
|---|---|---|
| **C1** | **`.cbdaw` bakes every clip to PCM on save** | Reopen a project and every clip is dead audio. The "vector, not bitmap" engine survives only until Save. **Highest priority in this pillar.** |
| **C2** | Drum clips (`DrumSource`) and groove clips (`GrooveSource`) have no accessor and no route | A beat sent from the DrumKit can never be re-opened in the DrumKit |
| **C3** | No universal "Open in…" | The routing exists in `ProjectBridge` but the Audio Editor hardcodes two special cases instead of asking it |
| **C4** | Tab fidelity is lost inbound | A tab arrives as `MultiPartScore`; string/fret/fingering are discarded, so Audio Editor → Tab re-frets from scratch |
| **C5** | Audio clips have no symbolic route | "Transcribe this clip → notes → any editor" is the honest bridge and it is not wired |
| **C6** | No lane-level send | You can send a clip somewhere; you cannot send a whole lane |
| **C7** | FX rack not surfaced in every mode | The model is mode-neutral already; Tracker/Loop/Tab/Score just don't expose the full rack |

### The target matrix
Rows = what a lane holds, columns = where it can be opened. `↔` = round-trips in
place, `→` = one-way with a loss report, `T` = via transcription (explicit,
estimated).

|  | Audio | Score | Tab | Tracker | DrumKit | Loop |
|---|---|---|---|---|---|---|
| **Audio (sample)** | ↔ | T | T | T | T | T |
| **Score** | ↔ | ↔ | ↔ | ↔ | → | ↔ |
| **Tab** | ↔ | ↔ | ↔ | ↔ | → | ↔ |
| **Tracker** | ↔ | ↔ | ↔ | ↔ | → | ↔ |
| **Drum** | ↔ | → | → | ↔ | ↔ | ↔ |
| **Groove** | ↔ | → | → | ↔ | ↔ | ↔ |

Every non-`↔` cell must show its loss report **before** the user commits — the
machinery for that is already in `ConversionResult.report`.

### C7 in detail — the same FX everywhere
`FxSpec` is already mode-neutral, and the Tracker's per-cell commands already
coexist with it. So "all FX for all track kinds" is mostly a surfacing job:
- an Audio Editor lane holding *any* source kind already gets the full rack ✅
  (this half of the ask is already true);
- what is missing is the reverse — the Tracker/Loop/Tab/Score previews should
  offer the same rack on their own output, with the chain string as the
  interchange format so a chain travels with the track when it moves.

---

## 6. Pillar D — the DAW-grade extras the ladder never asked for

| # | Item |
|---|---|
| D1 | Ripple delete / ripple insert on a time selection (everything after moves) |
| D2 | Clip groups / linked clips; nudge by grid or ms |
| D3 | Per-clip gain envelope (clip-level automation, distinct from lane automation) |
| D4 | Loudness metering: integrated / short-term / momentary LUFS + true-peak; correlation meter; spectrum analyser |
| D5 | Take lanes + comping (record several passes, choose per phrase) |
| D6 | Tempo map (the timeline's bpm is a single number today) |

---

## 7. Build order

Foundations first, because everything after them is cheaper if they exist.

```
F1  chain-string codec + registry introspection        ← every later slice uses it
F2  bin/fxproc.dart regenerated from the registry      ← the test/hear loop
F3  chain string as copy/paste preset in the GUI

A1  filter zoo        A3  dynamics zoo        A4  channel/stereo zoo
A5  restoration       A6  time/pitch          A2  tone curves      A7  generators

B1  pad/repeat/split-on-silence/splice        B3  full stats
B2  dither+noise shaping                      B4  VAD      B5  spectrogram CLI

C1  .cbdaw v2 — models survive save           ← highest-value single slice
C2  drum + groove round-trip
C3  universal Open-in via ProjectBridge
C4  tab fidelity inbound
C5  transcribe-this-clip
C6  lane-level send        C7  rack in every mode

D…  as pulled
```

Each slice: `dart format` → tests → `flutter analyze` (whole project) → small
commit → board update + push. Acceptance for a DSP slice is a *behavioural*
test (spectrum, gain transfer, correlation), plus a CLI invocation that a human
can hear.

## 8. Non-goals (stated so they are not re-litigated)

- **A real-time audio graph.** The app is offline render-then-play by design;
  the windowed renderer is what makes that fast. Not changing it here.
- **Third-party plugin hosting.** A native plugin ABI is a different project and
  most plugin standards come with licence entanglements we deliberately avoid.
- **Editing symbolic models *from* the waveform.** Audio → notes is estimation,
  and it stays behind the explicit Transcribe door (C5) rather than pretending
  to be a peer conversion.
