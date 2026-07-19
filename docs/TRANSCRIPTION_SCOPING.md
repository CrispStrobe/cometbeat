# Automatic Music Transcription — Scoping (S1–S4)

Turn a **recording** (a sung children's song, a solo instrument, later a full
mix) into **notes → notation**, on-device, with **zero patent risk** and a
**fully MIT-compatible** licence chain. Builds on the shipped file-analysis
(`lib/core/audio/recording_analysis.dart`, `analyzeRecording`) — which today
does frame-level MPM pitch + naive segmentation and, honestly, can't transcribe
vibrato singing.

> **Not legal advice.** The patent/licence analysis below is a well-supported
> engineering read (the strongest single signal used throughout: *librosa ships
> it natively under ISC* ⇒ patent-clean + permissive; *librosa refuses to ship
> it* ⇒ encumbered). A real IP review precedes shipping anything here.

---

## 0. Why "Mary sung" fails today (the 3-problem decomposition)

Transcription is three problems stacked; singing breaks the last two:

1. **F0 estimation** — which pitch per frame. Our MPM (autocorrelation) does
   this passably on *stable* tones (the scale worked: C→C).
2. **Voicing + note segmentation** — where one note stops and the next begins.
   Singing is *legato* (no attack transient) and *portamento* (continuous
   slides): there is no clean boundary to threshold on.
3. **Pitch → note quantization** — singing has **vibrato** (±50–100 cents,
   ~5–7 Hz) and drift, so one note smears across 2–3 semitones.

Then, to get *notation* (not just a pitch list), a fourth problem:

4. **Rhythm** — onsets → tempo/beat grid → note *values* (quarter/eighth…).

Our current pipeline = S1 (MPM) + a naive S2/S3. The `melody()` median-smoother
recovers the *contour* but can't *decide* note boundaries. Fixing S2 (a note
model) is what makes sung melodies transcribe.

---

## Delivery strategy — two parallel tracks

- **Track A — pure-Dart clean-room (recommended v1).** A **pYIN**-style pipeline
  (probabilistic F0 + a note-state HMM) + classical rhythm DSP. **Monophonic**
  (solo instrument *and* solo voice, i.e. sung children's songs). *No model
  files, no assets* — fits the app's on-device / no-asset ethos and CI. All DSP
  + dynamic programming; no learned weights; patent-clean.
- **Track B — neural via ONNX (accuracy + polyphony).** Run **CREPE** (F0) or
  **Basic Pitch** (full polyphonic note events) through the **`onnx_runtime_dart`
  dep we already ship**. Needs a few-MB model bundled/downloaded. This is the
  path to transcribing *real polyphonic songs*, which a monophonic detector
  fundamentally can't do.

Track A ships the "sung children's song" win with zero assets; Track B is the
reach for real multi-instrument music. They share S3/S4 and the notation output.

---

## S1 — F0 estimation (per-frame pitch + voicing)

**Have:** `PitchDetector` (McLeod/MPM NSDF autocorrelation) — good on stable
mono tones, octave-error-prone, no probabilistic voicing.

| Option | What | Licence / patent | Runtime | Effort |
|---|---|---|---|---|
| **A1 · pYIN (clean-room)** | Probabilistic YIN: many F0 candidates → **Viterbi** smoothing + voiced/unvoiced. Kills octave errors, robust on voice. | **Patent-clean, permissive** — librosa ships `pyin`/`yin` natively under **ISC** (the tell). Clean-room from Mauch & Dixon 2014. | pure Dart | **M** |
| A2 · CREPE (ONNX) | CNN on raw audio; the DL pitch tracker. | **MIT** (marl/crepe), weights incl. ONNX export exists. | `onnx_runtime_dart` + ~few-MB model | S (integ) + model |
| A3 · PESTO (ONNX) | Lightweight self-supervised, real-time. | verify (research licence) | ONNX | S + model |

**Verdict:** **A1 pure-Dart pYIN first** (asset-free, the big jump over MPM);
**A2 CREPE ONNX** as an optional accuracy tier. Slot behind `analyzeRecording`
so callers are unchanged.

---

## S2 — Note segmentation (F0 contour → note events) — *the "Mary" fix*

| Option | What | Licence / patent | Runtime | Effort |
|---|---|---|---|---|
| **B1 · pYIN note-HMM / "Tony" model (clean-room)** | HMM over **note-pitch states** with attack / stable / silent sub-states + self-transitions; **Viterbi** → note onsets/offsets/pitch. Vibrato is absorbed by the stable state; portamento by transitions. | Algorithm patent-clean (same pYIN family; librosa-adjacent). **Tony/Vamp code is GPL → paper-only clean-room**, never copy. | pure Dart | **M–L** |
| B2 · Basic Pitch (ONNX) | Does F0 **and** note segmentation jointly, **polyphonic**, pitch-bend aware. | **Apache-2.0** (spotify/basic-pitch) incl. model + patent grant. ONNX/TFLite/CoreML exports exist. | `onnx_runtime_dart` + ~few-MB model | S (integ) + model |

**Verdict:** **B1** is the monophonic note segmenter that turns "Mary sung" from
wobble into a melody, asset-free. **B2 Basic Pitch** is the polyphonic path and
is *architecturally already possible here* (ONNX runtime in deps; Apache-2.0
clean) — the single highest-leverage neural addition.

---

## S3 — Tuning & pitch quantization

Turn each note's F0 track into a MIDI note, correct for a recording not at A440.

- **Global tuning estimate:** histogram the voiced F0 pitch-classes (mod 12 in
  cents) → the peak's offset from 12-TET is the recording's tuning; correct by
  it. Classical, **unpatented**, pure Dart. **S.**
- **Per-note pitch:** robust median of the (tuning-corrected) F0 over the note's
  *stable* region (ignore attack/transition frames) → vibrato-averaged MIDI.
- Reuse the pentatonic-snap idea from `groove_capture.snapToPentatonic`,
  generalised to chromatic + a key estimate.

**Effort S**, pure Dart, patent-clean.

---

## S4 — Rhythm → notation (onsets → beat grid → note values → sheet music)

| Step | Method | Licence / patent | Notes |
|---|---|---|---|
| Onset detection | **Spectral flux** / complex-domain | unpatented classical | Pure Dart. ⚠ avoid patented **SuperFlux** variants. |
| Tempo estimation | Onset-envelope **autocorrelation / Fourier tempogram** | unpatented | Pure Dart. |
| Beat tracking | **Ellis dynamic-programming beat tracker** (2007) | **patent-clean** — librosa `beat_track` ships it under ISC | Clean-room pure Dart. ⚠ **avoid madmom DBN/downbeat** (Böck patents + non-commercial clause). |
| Quantise | Snap onsets/durations to the beat grid → note values | — | **Reuse the shipped `rhythm_quantize.dart`** + the estimated tempo. |
| Notation | `(pitch, onsetBeat, durBeats)` → `crisp_notation` **Score** | — | Engrave on `StaffView`; **MusicXML/MIDI export already exists**. |

**Effort:** onset/tempo **S** each, Ellis beat **M**, quantise **S** (mostly
reuse), notation **S** (reuse). Patent-clean throughout.

---

## Leverage already in this repo

- **`onnx_runtime_dart`** (path dep) → CREPE / Basic Pitch / SPICE ONNX (Track B).
- **CrispASR / ggml** (Apache-2.0, on device) → *not* the fit for these music
  models (they export to ONNX, not GGML). Best reserved for a **future lyrics
  track** (Whisper-via-ggml) to pair words with the transcribed melody — a
  karaoke-grade "notes + words" output. Noted, out of S1–S4 scope.
- **`rhythm_quantize.dart` / `rhythm_convert.dart`** → S4 quantisation + routing
  a transcription into Tracker/Score/MusicXML (converters already exist).
- **`crisp_notation`** → notation + MusicXML/MIDI/LilyPond export (all shipped).
- **`recording_analysis.dart`** → the file entry point; the pYIN pipeline slots
  in behind `analyzeRecording` with the same `RecordingAnalysis` surface.

---

## Patent / licence appendix (the hard constraint)

**SAFE — MIT-compatible + patent-clean** (use freely; clean-room from papers):
- **YIN / pYIN** — librosa ships natively (ISC) ⇒ patent-clean; clean-room from
  Mauch & Dixon 2014 / de Cheveigné & Kawahara 2002.
- **HMM / Viterbi / DTW** — textbook, unpatented.
- **CQT / HCQT** — Brown 1991 / Schörkhuber–Klapuri 2010, academic; librosa ISC.
- **Spectral-flux / complex-domain onset** — classical, unpatented.
- **Ellis DP beat tracker** (2007) — librosa `beat_track` (ISC), patent-clean.
- **CREPE** — **MIT**. **Basic Pitch** — **Apache-2.0** (patent grant). **SPICE**
  — **Apache-2.0**.

**AVOID — patent-encumbered or non-permissive:**
- **Melodia** (predominant-melody salience) — **patented** (QMUL/MTG); librosa
  refuses to ship it (external Vamp plugin only). Never use.
- **madmom** DBN **beat/downbeat** trackers — **Böck patents** + non-commercial
  clause. Use Ellis DP instead.
- **SuperFlux** and some vocoder/pitch-shift methods — patent-flagged; avoid.
- **MP3/AAC** — not needed (we decode via ffmpeg externally / already WAV).

**Clean-room rule:** reimplement **algorithms** (uncopyrightable) from the
**papers**. Never copy GPL implementations — **Tony, the Vamp pYIN plugin, aubio,
Sonic Visualiser** are **GPL**; read the maths, write our own Dart.

---

## Sliced delivery plan (each ships + is validated on real recordings)

1. **S1a — pYIN F0** (pure Dart) behind `analyzeRecording`; validate the F0 track
   on the scale + Mary recordings (fewer octave errors, clean voicing).
2. **S2 — note-HMM segmentation** (pure Dart) → **"Mary" transcribes** to a real
   melody (the headline milestone).
3. **S3 — tuning + per-note quantisation** → correct notes for off-A440 audio.
4. **S4 — onset + tempo + Ellis beat + quantise** → note *values* (rhythm).
5. **S5 — → `crisp_notation` Score + MusicXML** → "record → sheet music."
6. **Track B (parallel/optional) — Basic Pitch ONNX** → *polyphonic* songs.

## Validation methodology

- Real public-domain / CC recordings (Wikimedia Commons), as already used:
  solo-instrument scale ✓, sung "Mary" (the S2 target), piano I–IV–V–I ✓.
- A tiny **mir_eval-style** note metric harness (onset + pitch F-measure vs a
  known melody) so each slice has a number, not just eyeballing.
- CLI: extend `bin/listen.dart` with `--transcribe` (notes + durations) once S4
  lands; `--melody` already prints the smoothed line.

## Effort summary

| Slice | Effort | Assets | Risk |
|---|---|---|---|
| S1a pYIN F0 | M | none | low (well-documented) |
| S2 note-HMM | M–L | none | med (the modelling work) |
| S3 tuning/quantise | S | none | low |
| S4 onset/tempo/beat/quantise | M (Σ) | none | low–med |
| S5 → notation/MusicXML | S | none | low (reuse) |
| Track B Basic Pitch ONNX | S–M | ~few-MB model | low (Apache-2.0, ONNX ready) |
