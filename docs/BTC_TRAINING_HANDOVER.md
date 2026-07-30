# Training our own chord-recognition weights — handover (2026-07-30)

**The ask.** The chord model we ship today works and is **non-commercially
licensed**, which bars it from being the default in a commercial app. Train a
replacement whose weights we own outright, on data whose licence we control.

**Who this is for.** One agent, working alone, in a sibling worktree. It assumes
no prior context beyond this file. Read §0 before anything else — two of the
premises this project is usually started on are wrong, and one of them changes
what "success" means.

---

## 0. Four things that are NOT what they look like. Read these first.

### 0.1 ⚠️ The shipped model has a **25-class** vocabulary, not a rich one

`lib/core/audio/transcription/harmony.dart` →
`btcChordLabels` is **12 major + 12 minor + `N` (no chord) = 25**. That is the
entire expressive range of the neural path today: **it cannot say a seventh at
all.**

Our *non-neural* chroma matcher already handles eight qualities
(`maj min 7 m7 maj7 sus4 dim aug`).

⇒ **The neural model is not currently the more capable path — it is the more
capable *architecture* running a small head.** This reframes the project: it is
not only about escaping a licence, it is about getting a vocabulary worth having.
Since we would generate our own labels, the target vocabulary is a *choice* (see
§3.1), and that is the real prize.

### 0.2 🛑 STEP ZERO IS A MEASUREMENT, NOT A TRAINING RUN

**Do not start by training. Start by finding out whether the model we already
have is even better than the chroma matcher at the 25 classes it does support.**

`tool/chord_template_ab.dart` already measures the chroma detector over a
synthetic grid (12 roots × 3 voicings × each quality) and reports exact/root/top3.
Baseline, measured 2026-07-30: **exact 82.6% · root 86.8%** over the shipped 8
qualities.

Run the **BTC path over the same grid**, restricted to maj/min. If the neural
model is not clearly ahead on maj/min, then:
- the licence problem is *not* blocking live grading (`BB-X5`) at all, and
- training is justified **only** by the extended vocabulary, which changes the
  priority and the design.

This is a day of work and it decides whether the rest is worth weeks. **Report
the number before proceeding.**

### 0.3 ❌ "Slakh2100 is CC BY, therefore usable" — REJECTED, and on **all three** layers

The most commonly proposed shortcut is a MIDI-rendered corpus with a permissive
wrapper. It fails, and it is worth being precise about *why*, because the same
shape will be proposed again with a different name.

**Layer 1 — the wrapper is not the grant.** A CC BY notice on the rendered corpus
covers the *renders and the compilation*. It cannot cover the MIDI underneath,
because the compiler never held those rights.

**Layer 2 — the source cannot even satisfy its own licence.** The upstream MIDI
collection states plainly that attributing the files to particular authors *is not
feasible*. That is disqualifying on its own terms: **CC BY is an attribution
licence, so a corpus that cannot identify its authors cannot be licensed under it
and cannot be complied with by anyone downstream.** This is the same failure this
repo already documented at length for uploader-asserted module licences —
*"uploader ≠ author"*, where a third party asserts a licence over work that is not
theirs. We rejected 1,752 modules on exactly that reasoning.

**Layer 3 — two copyrights underneath, not one.** The compositions are
copyrighted pop songs (axis 2), *and* a MIDI transcription carries its own
sequencer copyright on top — the point `CLAUDE.md` already makes about
classicalguitarmidi.com: *"Pitch pseudo-labels at best, sequencer copyright on
top."*

**The precedent is ours and it is direct.** FiloBass: *"Zenodo 10069709, CC BY 4.0
wrapper … bassline transcriptions of real (copyrighted) jazz recordings. Axis-1
CC BY but axis-2 DIRTY → NOT shippable."*

⇒ **Do not train on it, and do not adopt it as a named control either** — the
standing rule is that licence-unclear scrape-derived archives are not carried in
tracked docs as things we use. It is named here once, as a rejection with its
reasoning, so the next person does not re-derive it.

**The transferable rule: a permissive wrapper cannot launder the layer beneath
it.** Check what the compiler actually had the right to grant, every time.

### 0.4 ✅ Two premises that ARE correct, verified in our own tree

- **Code MIT / weights NC is real and already documented.**
  `harmony_model_store.dart:8` — *"the BTC code is MIT, but the released weights
  are trained on Isophonics annotations (CC-BY-NC-SA-4.0 — NON-COMMERCIAL)"*, and
  `licenseSpdx = 'CC-BY-NC-SA-4.0'` gates download AND cached loads.
  📌 **Fix on your way past:** `bin/transcribe_chords.dart:13` calls it *"The MIT
  BTC model"*, which is wrong and contradicts the store. One-line doc fix.
- **22.05 kHz mono is correct.** `harmony_cqt.dart:114` — *"Compute the CQT
  feature for audio22k (mono, 22050 Hz)"*, hop **2048**, timestep **108** frames,
  ONNX tensors `cqt` → `chord`. Match these exactly or nothing loads.

---

## 1. What we already have, which is more than it looks like

**The renderer is not `tool/chord_template_ab.dart`** (that is a 200-line test
harness that happens to synthesise chords). The real synthesis chain is:

| piece | what it gives you |
|---|---|
| `bin/rendersong.dart` | any notation format → WAV/MP3 **through a SoundFont**, Flutter-free |
| `lib/core/audio/midi_render.dart` | MIDI → audio, per-track SF2/SFZ voices |
| `lib/core/audio/sf2/` | SF2 + SFZ + multisample loaders |
| **232 registry instruments** | Tier A/B, licence-cleared, real velocity-layered kits |
| `lib/core/audio/fx/` | ~30 FX types — **this is your augmentation stack** |
| `lib/core/harmony/chord_spec.dart` | the chord vocabulary (compositional, any quality) |
| `lib/core/harmony/comp_arranger.dart` | **real voicings** — close/drop2/drop3/shell/rootless/inversions |
| `lib/features/games/songs/import/jams.dart` | reads **and writes** JAMS chord annotations in 5 dialects |

⇒ We can render *labelled-by-construction* audio at scale: every quality × every
voicing × every inversion × every instrument × every tempo, with the ground truth
known exactly because we generated it.

**And real clean audio is already acquired.** `docs/CORPUS_LICENSING.md:405` —
JAMS Tier-A corpus on the VPS (`jams-corpus/tierA`): **GuitarSet 360 (CC BY)** ·
Harmonix 912 (MIT) · jams-pkg 7 (ISC) · OpenEWLD-eu-pd 103 (MIT). GuitarSet is
recorded *for* the dataset — *"nothing underneath ✅"* (line 637) — and ships
chord annotations in its JAMS, which **our own importer already parses**.

---

## 2. The data plan

### 2.1 Synthetic (the bulk) — ours outright

Generate progressions, not isolated chords: a model trained on isolated chords
learns onsets, not harmony. Use `comp_arranger` so voicings are realistic and
voice-led rather than random stacks.

Vary, deliberately and independently: root · quality · inversion/voicing shape ·
instrument (sample the 232) · register · tempo · chord duration (½–4 bars) ·
articulation · added bass line · added melody over the top · silence and `N`
regions. **Include `N`** — a model that never sees "no chord" will hallucinate one
everywhere.

**Augment with the FX rack**: reverb (room simulation is the single biggest
synth-to-real gap), EQ tilt, compression, saturation, background noise, level
variation, and mild pitch/time jitter. This is the difference between a model that
works on our renderer and one that works on a phone microphone.

### 2.2 Real (the anchor) — GuitarSet first

GuitarSet is the held-out reality check and a training source in its own right.
Its JAMS → `.lab` conversion is nearly free through `jams.dart`.

⚠️ **Guitar-only is a domain**, not the world. A model trained on GuitarSet alone
will be a guitar chord recogniser. Blend it with synthetic multi-instrument audio.

### 2.3 Optional, with caveats

- **MusicNet** — PD classical compositions with freely-licensed performances
  (verify per-recording before use). Real acoustic audio, but **classical only**
  and **no chord labels** — they must be derived symbolically, which imports the
  error of whatever derives them. Useful for acoustic realism, not for labels.
- **Slakh2100 and any other MIDI-rendered corpus** — see §0.3. Rejected outright,
  not merely deprioritised.

### 2.4 🛑 The one hard prohibition

**Do NOT train on the existing model's predictions.** Distilling an NC teacher
into "our own" student launders the licence through a training step. Every label
must come from our own generation or from a licence-clean annotation.

---

## 3. The build

### 3.1 Decide the vocabulary FIRST — it is the whole point (§0.1)

Options, in increasing order of ambition:
1. **25 classes** (maj/min/N) — matches the shipped head, so the ONNX/GGUF drops
   into `harmony.dart` with **zero app change**. The safe first target: it proves
   the pipeline end to end and immediately removes the licence blocker.
2. **~61 classes** — add `7 · m7 · maj7` (12 roots × 5 + N). Covers most of what a
   chart needs and what our chroma matcher already attempts.
3. **~170 classes** — the full quality set. Best ceiling, most data hungry, and
   the class imbalance is severe (nobody plays `Cm(maj7)` often), so needs
   deliberate balancing since we generate the data.

**Recommendation: ship (1) first to prove the pipeline and clear the licence, then
(2).** `harmony.dart`'s `btcChordLabels` and the argmax decode are the only app
code that changes when the head grows.

### 3.2 Match the front end exactly

22050 Hz mono · hop 2048 · timestep 108 frames · normalisation from
`btc-cqt.bin` (`int32[4]{nBins,nFft,nFreq,hop} · float32[2]{mean,std} ·
float32[nBins]lengths`). If you retrain with different CQT parameters you must
also emit a new `btc-cqt.bin` and keep the two versioned together — a mismatched
pair fails silently as garbage predictions, not as an error.

### 3.3 Train, convert, ship

Upstream training code is MIT (**verify at the repo before use, do not take this
file's word for it**). No local GPU — the VPS is 2-core/2 GB — so this is a rented
GPU or Colab job; the model is small and this is hours, not weeks, of compute.

Export to **ONNX** first: `HarmonyModelStore` already does download-on-demand,
caching and gating, so shipping is a URL change plus dropping the licence gate.
GGUF via the crispasr/ggml seam is a **later consolidation** (`BB-H5`) and buys no
capability.

---

## 4. Acceptance — what "done" means

1. **§0.2 measured and reported** before training starts.
2. Held-out **real** audio, never synthetic-only: GuitarSet split by *player*, not
   by clip, or the model memorises a guitar.
3. Beat the chroma baseline on the same synthetic grid
   (`tool/chord_template_ab.dart`), and report both numbers side by side.
4. A **licence provenance file** listing every data source with its SPDX id and
   its axis-2 status, in the style of every other ingest in this repo. Weights we
   cannot document the provenance of are worth no more than the NC weights.
5. The new checkpoint loads through the **existing** `HarmonyModelStore` path with
   the licence gate **removed for it specifically** — and the NC model's gate
   still intact, because it stays available as an opt-in.
6. `bin/transcribe_chords.dart:13` corrected (§0.4).

## 5. What this does NOT block

`BB-H1` (bass-band chroma), `BB-H2` (compression), `BB-H3` (tie-break) and `BB-H6`
(symbolic models offline) are all independent and cheaper. **A live-grading path
that needs no model at all is worth more than a better model**, because it works
offline, on any device, with no download and no licence. Train the model because
we want chart-from-audio to ship commercially — not because the chroma path is
inadequate for grading.
