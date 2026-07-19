# Transcription → industry-SOTA — worker handover prompts

The pure-Dart monophonic pipeline (Track A: pYIN → note-HMM → tuning → octave
cleanup → rhythm → MusicXML) and the neural polyphonic engine (Track B: Basic
Pitch ONNX) both ship, validated on 10 diverse PD/CC recordings (see the SOTA
roadmap in `docs/PLAN.md` and the `transcribe-w1` / `transcribe-basicpitch` board
entries). The **auto-router (N1, `route.dart`)** picks between them; the **in-app
surface (N2)** is being built by the same author.

This doc holds the standalone prompts for **everything else on the SOTA roadmap**.

## How many workers do we need?

**7 standalone worker tasks, run in 3 waves.** The frozen `contracts.dart` seam
(`PitchTrack` / `NoteEvent` / `RhythmGrid`) makes almost everything independent —
an engine swaps behind the seam without touching a consumer — so these can run in
parallel. Recommended ordering by leverage:

| Wave | Worker | What | Why now |
|---|---|---|---|
| **1** | **W-CREPE** | ✅ *adapter shell + decoder + harness PRE-BUILT* — worker only publishes the ONNX + confirms 2 tensor names | highest quality-per-effort; fixes sung-voice octave-doubling + drift |
| **1** | **W-METRE** | ✅ *slice 1 (`estimateMeter`) SHIPPED* — remaining: metrical quantisation | correct barlines/anacrusis/meter, not assumed 4/4 |
| **1** | **W-SEP** | source separation → per-stem multi-part transcription | the single biggest jump: "transcribe a whole song" |
| **2** | **W-HARMONY** | neural chord + key estimation | lead sheets; enharmonic spelling input |
| **2** | **W-NOTATION** | ✅ *COMPLETE* — key+spelling, clef, chords, voice+staff separation all shipped (optional PM2S later) | turns a note dump into a READABLE engraving |
| **3** | **W-PIANO-MT3** | piano-specialist model, then seq2seq multi-instrument | near-SOTA polyphonic; frontier |
| **3** | **W-DRUMS** | ✅ *DSP path (kick/snare/hat) SHIPPED* — remaining: finer kit + pattern-quantise | pairs with `beat_capture.dart`; completes the band |

Wave 1's three are what "reaching SOTA" hinges on. Waves 2–3 are quality/polish
and frontier; spin them up as capacity allows. N1+N2 are already owned.

---

## § Shared context (every worker reads this first)

You're joining the **CometBeat** repo (Flutter music-education app). SEVERAL
agents push to `origin/main` in parallel — collisions are the main hazard.

- **Worktree**: work in a feature branch + a git worktree that is a **SIBLING of
  `mus/`** (e.g. `../mus-crepe`), never under `.claude/` — the `../crisp_notation`
  path-dep must resolve. From an existing worktree, `git pull --rebase origin
  main` first.
- **Claim it** on the `docs/PLAN.md` 🚧 board (agent · task · files · status) and
  push the board BEFORE touching any hot shared file. Re-check for a conflicting
  claim first.
- **Build env (this Mac)**: wrap every flutter/pod/xcode call with
  `PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter ...`.
- **Pre-commit gate, in order**: `flutter pub get` (fresh worktree, before format)
  → `dart format <your files>` → `flutter analyze` (aim "No issues found") → your
  tests. New feature ⇒ a test. NEVER pipe a gate through `tail`/`head` before a
  push (it eats the exit code). Commit small; `git pull --rebase origin main`
  often. Co-author trailer: `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **The seam — DO NOT EDIT** `lib/core/audio/transcription/contracts.dart`:
  ```dart
  typedef PitchFrame = ({double timeMs, double f0Hz, double voicedProb});
  typedef PitchTrack = List<PitchFrame>;
  typedef NoteEvent  = ({int midi, double onMs, double offMs, double confidence});
  typedef RhythmGrid = ({double bpm, List<double> beatMs, List<double> onsetMs});
  typedef GriddedNote= ({NoteEvent note, double startBeat, double beats});
  ```
  Your engine consumes/produces these types so it drops into the router
  (`route.dart`) and the S5 engraver (`transcribe.dart`) unchanged.
- **Testing harness — the "done" ruler**: `test/transcription/note_metrics.dart`
  — `notePrf(expected, detected, {onsetTolMs, pitchTol})` /
  `onsetPrf(...)` (mir_eval-style P/R/F). LOCK with synthetic renders scored by
  this; VALIDATE on real PD/CC Wikimedia recordings via an `ffmpeg`/`sox` download
  recipe in the commit message (no audio bundled; CI has no network → any real /
  model path is **skip-if-absent**). Report the F-number in each commit.
- **PATENT + LICENSE — HARD RULE**: everything must be patent-free +
  MIT/Apache-2.0-compatible. Clean-room from PAPERS; never copy GPL/AGPL code
  (aubio, Essentia, Vamp, Sonic Visualiser, Tony). **AVOID**: Melodia (patent),
  madmom DBN beat/downbeat (Böck patents + non-commercial licence), SuperFlux
  (patent). **SAFE**: pYIN, YIN, CQT, Viterbi, spectral-flux, Ellis DP beat,
  CREPE (MIT), Basic Pitch (Apache-2.0), Demucs/HTDemucs (MIT), Open-Unmix (MIT),
  Onsets&Frames (Apache), `piano_transcription_inference` (MIT), MT3 (Apache).
- **Neural engines**: download-on-demand (no model in the bundle; ship the model's
  NOTICE next to it), and `!kIsWeb`-guard the native path (onnx pulls `dart:io`)
  so the web build keeps the pure-Dart monophonic fallback. Follow the pattern in
  `basic_pitch.dart` + `basic_pitch_model_store.dart`.
- **Your files only**: create NEW modules under
  `lib/core/audio/transcription/<your>.dart` + `test/transcription/<your>_test.dart`.
  Do not touch another worker's module. Coordinate on the board for any shared
  file (`route.dart`, `transcribe.dart`, `rhythm.dart`, `bin/listen.dart`, ARBs).

---

## WAVE 1

### W-CREPE — neural monophonic F0 (the highest-leverage upgrade)

> ✅ **ADAPTER SHELL + DECODER + HARNESS PRE-BUILT (`aa1cb95b`):** `crepe.dart`
> (resample→16k, framing, per-frame normalise, 360-bin activation→f0 decode — all
> unit-tested) + `crepe_model_store.dart` (native download-on-demand, mirrors
> BasicPitchModelStore, `_modelUrl` is a TODO placeholder) + `crepe_test.dart`
> (7 tests; decoder fully locked, model-gated block skip-if-absent). It already
> plugs into the router's `F0Estimator` seam. **Remaining (≈ an afternoon):
> export/publish the MIT CREPE ONNX, set `_modelUrl`, confirm the `_inputName`/
> `_outputName` tensor names against the export, add a cosine-parity fixture.**
> Backend is free — ORT / FFI / ggml — anything yielding a 360-bin activation.
> **Consider RMVPE (MIT) as the quality tier after CREPE** — SOTA on sung f0 and
> robust to accompaniment; the same shell + seam accept it unchanged.

**Role.** Add CREPE (Kim et al. 2018, MIT) as a neural F0 estimator behind the
`PitchTrack` contract — an accurate, timbre-robust alternative to pYIN that fixes
the sung-voice octave-doubling and pitch-drift the pure-Dart chain shows on real
singing.

**Files.** `lib/core/audio/transcription/crepe.dart` +
`test/transcription/crepe_test.dart` + a `crepe_model_store.dart` (mirror
`basic_pitch_model_store.dart`). Optional: a `--crepe` flag demo in a NEW
`bin/transcribe_crepe.dart` (do NOT edit `bin/listen.dart`, another worker owns it).

**Build.** CREPE takes 16 kHz mono, 1024-sample frames (hop configurable), and
outputs a 360-bin pitch activation (20-cent resolution, C1–B7); the f0 is the
weighted average around the argmax bin, voicing = peak activation. Export the
`crepe-tiny` or `crepe-small` ONNX (smallest that hits accuracy) — verify the ONNX
matches the reference (cosine ≥ 0.99 vs the Python `crepe` on a fixture, exactly
like Basic Pitch did). Resample 44.1 k→16 k with `crisp_dsp/resample.dart`
(`resampleLinear`, ratio = 44100/16000). Emit `PitchFrame`s (`timeMs`, `f0Hz`,
`voicedProb`). Run on `onnx_runtime_dart` (`Tensor.float`, `session.runAsync`).

**Done.** (1) `crepeF0(Float64List mono, {int sampleRate}) → PitchTrack`.
(2) Model download-on-demand + `!kIsWeb`-guard + skip-if-absent tests. (3) A
model-gated test: synth C-major scale → `crepeF0` → `segmentNotes` scored by
`notePrf`, note-F ≥ 0.9, ZERO octave errors. (4) Reference-parity test vs a
committed fixture. (5) Deterministic no-model tests (resample shape, silence
safe). (6) Wire into `route.dart` as an alternative monophonic path (coordinate
on the board — small edit) OR expose it so the router author can. (7) Commit the
real-recording win: the sung "Row Your Boat" / "Mary" F-number vs pYIN.

---

### W-METRE — downbeat, time-signature, metrical quantisation

> ✅ **Slice 1 SHIPPED (`abb81a5c`, `metre.dart`, 6 tests):** `estimateMeter(
> RhythmGrid) → Meter{beatsPerBar, beatUnit, downbeatMs}` (downbeat/phase +
> triple-vs-duple; default candidates `{4,3}` since onset TIMES can't split 4/4
> from 2/4 — needs onset strengths). Wired into `transcription_service` (the
> Score gets the detected time signature). **Remaining for this worker: the
> metrical quantiser below.**

**Role.** Our Ellis DP beat (`rhythm.dart`, patent-free) finds the pulse but not
bar 1 or the meter, and S5 assumes 4/4 with greedy note-values. Slice 1 added the
downbeat + time-signature estimator; the remaining slice is a proper metrical
quantiser so the output has real note durations/tuplets/ties (not greedy
note-values), using `estimateMeter`'s `downbeatMs` for bar-aligned splitting.

**Files.** `lib/core/audio/transcription/metre.dart` +
`test/transcription/metre_test.dart`. You MAY extend `rhythm.dart` (coordinate on
the board — it's a shared transcription file) or keep everything in `metre.dart`
consuming its `RhythmGrid`.

**Build.** Downbeat: a bar-level dynamic program over the beat grid — score a
candidate downbeat phase + bar length (2/3/4 beats) by onset strength on strong
beats + a metre prior; pick the best. Clean-room (NOT madmom's DBN). Metrical
quantise: extend `quantizeToGrid` — snap onsets/durations to a subdivision grid
(with a swing estimate), then a DP that trades quantisation error against
notational complexity → `NoteDuration`s incl. dotted/tuplet, tied across
barlines. Reuse `rhythm_quantize.dart` if it fits.

**Done.** (1) `estimateMeter(RhythmGrid) → ({int beatsPerBar, int beatUnit,
List<double> downbeatMs})`. (2) A metrical quantiser producing gridded notes with
tuplet/tie info that S5 (`transcribe.dart`) can engrave (coordinate the seam with
its author). (3) Synth tests: a 3/4 vs 4/4 pattern → correct `beatsPerBar`; a
melody with a pickup → downbeat NOT on note 1; a triplet → a tuplet, not three
skewed eighths. (4) Validate on a real waltz + a march recording; report the
detected meter in the commit.

---

### W-SEP — source separation → per-stem multi-part transcription (biggest lever)

> ✅ **PREPARED + GLUED — only the model remains.** (1) Assembly glue
> (`20a1f066`, `stems.dart`, 6 tests): `transcribeStems`/`transcribeSong` route
> each stem → engine (vocals/bass mono, other → chords, drums → W-DRUMS) →
> `MultiPartScore`. (2) HTDemucs adapter shell (`50c996a6`, `separate.dart` +
> `separate_model_store.dart` + `separator_provider` + 6 tests): mono→stereo,
> per-segment normalise, overlapping inference + triangular overlap-add
> (reconstructs identity EXACTLY), stem mapping — all tested; ONNX call wired to
> onnx_runtime_dart; `demucsSeparator(model)` yields the injected `Separator`.
> **⇒ NEW (2026-07-19): W-SEP is UNBLOCKED — onnx_runtime_dart 0.10.x fast-pathed
> HTDemucs (ConvTranspose ~5× + GLU fusion) and CrispASR gained `--separate`
> (htdemucs 4-stem + mel-band-roformer, MIT).** The Dart `crispasr 0.8.11`
> package does NOT bind `--separate` yet, so the clean path is a Demucs ONNX via
> the onnx_runtime_dart htdemucs fast path (mirrors basic_pitch). **Remaining:
> publish/convert the MIT HTDemucs ONNX, set `_modelUrl`, confirm the 2 tensor
> names + segment length.**

**Role.** The reason we fail on full songs is mixed sources. Split a song into
stems and transcribe each with the right engine → a multi-part score. This is the
jump from demo to industry-grade. **The assembly is done (`stems.dart`); your job
is the separation model.**

**Files.** `lib/core/audio/transcription/separate.dart` +
`separate_model_store.dart` + `test/transcription/separate_test.dart`. A demo CLI
`bin/transcribe_song.dart` (NEW file). Heavy models → **opt-in, native-only**.

**Build.** Export Open-Unmix (`umx`/`umxhq`, MIT — smaller) or HTDemucs (MIT —
bigger, better) to ONNX. `separate(Float64List mono) → ({vocals, bass, drums,
other})` each a `Float64List`. Then route stems: vocals → CREPE/monophonic (via
`route.dart`), bass → monophonic, other → Basic Pitch polyphonic, drums →
W-DRUMS' classifier (or leave a hook). Assemble a `MultiPartScore`
(`multiPartToMusicXml` already exists). Download-on-demand, `!kIsWeb`, skip-if-
absent; be explicit in the model NOTICE about size.

**Done.** (1) `separate(mono, {sampleRate}) → Stems`. (2) A model-gated test: mix
two synth stems (a bass line + a triad) → `separate` → each stem's transcription
recovers its own notes (cross-talk below a threshold). (3) An end-to-end
model-gated test on a short real multi-instrument clip → a `MultiPartScore` with
≥2 non-empty parts. (4) Deterministic no-model tests (stem shape/length,
silence). (5) Report the per-stem note-F on the real clip in the commit.

---

## WAVE 2

### W-HARMONY — neural chord + key estimation

**Role.** Upgrade the chroma-template chord/key detection to a small neural model
for accurate lead sheets and to feed enharmonic spelling.

**Files.** `lib/core/audio/transcription/harmony_nn.dart` +
`harmony_model_store.dart` + `test/transcription/harmony_nn_test.dart`. Compare
against the existing `chroma_analysis.dart` / `analyze()` (crisp_notation), don't
replace them.

**Build.** A permissive CRNN chord model (e.g. a small BTC/CRNN trained on
chroma/CQT, exported to ONNX — verify licence of the checkpoint you port; if none
is clean, train a tiny one from a permissive dataset and ship the weights
Apache-2.0). Input: CQT or the existing chromagram. Output: per-frame chord label
(major/minor/7th/…) + a global key. Emit a chord timeline the Song Book / AnaVis
view and S5 can consume. Fall back to the chroma templates when no model.

**Done.** (1) `estimateChords(Float64List mono) → List<({double startMs, double
endMs, String chord})>` + `estimateKey`. (2) Model-gated test: synth I–IV–V–I →
correct labels + key; beats the chroma-template baseline on a hand-built
ambiguous case. (3) Real recording (the brass-band Amazing Grace) → a sensible
progression in the commit. (4) Deterministic + skip-if-absent.

---

### W-NOTATION — score-level: readable engraving (voice/staff + spelling)

> ✅ **Slice 1 SHIPPED (`7a87e751`, `notation.dart`, 10 tests):** `estimateKey`
> (Krumhansl-Schmuckler) + `spellMidi` (line-of-fifths, key-correct accidentals,
> exact octave) + `respell(Score)` (re-spells notes + stamps the KeySignature);
> wired into `transcription_service` (the Score now carries the right key +
> accidentals, and TranscriptionResult exposes the key). ✅ **Slice 2 SHIPPED
> (`07811aea`): `chooseClef` — bass for a low line, treble otherwise.** ✅
> **Polyphonic chords SHIPPED (`a26f4f45`): chord-aware `transcribeToScore` —
> simultaneous notes → one multi-pitch note-head, held chords merge; monophonic
> unchanged.** ✅ **Voice/staff separation SHIPPED (`ade609ab`, `voices.dart`,
> 7 tests): `separateVoices` (≤4 voices; melody over a held bass → 2 voices; a
> block chord stays 1) + `toGrandStaff` (treble+bass split, aligned, valid
> grand-staff MusicXML).** **⇒ W-NOTATION COMPLETE** — only the optional PM2S
> neural slice (expressive timing → notated rhythm) is left, if ever wanted.

**Role.** Turn a flat `NoteEvent` stream into a READABLE score: separate voices
and hands/staves, add a key signature, and spell enharmonics correctly. Slice 1
did key + spelling; the remaining slice is voice/staff separation.

**Files.** `lib/core/audio/transcription/engrave.dart` +
`test/transcription/engrave_test.dart`. Post-processes a `Score` /
`List<NoteEvent>`; reuse `crisp_notation` (`Pitch`, `KeySignature`, voices 1–4 on
`Measure`, grand-staff). Coordinate with `transcribe.dart`'s author on where this
slots (probably a stage after `transcribeToScore`).

**Build.** (a) Key/spelling: from the detected key (W-HARMONY or `analyze()`),
spell each midi with the correct accidental (C♯ vs D♭) and set the
`KeySignature`. (b) Voice separation: split overlapping notes into ≤4 voices by a
cost model (pitch continuity + minimal crossing). (c) Staff split for wide range
(grand staff: bass clef below middle C). Optional later slice: a PM2S neural
model (performance-MIDI → notated rhythm) for expressive timing — separate
model-gated file.

**Done.** (1) `engrave(Score, {Key?}) → Score` (spelled + voiced + staff-split).
(2) Tests: a piece in G major spells F♯ (not G♭) with a 1-sharp key sig; two
overlapping lines → two voices; a wide-range piece → grand staff. (3) A real
piano clip (Für Elise) → both hands on two staves in the commit note.

---

## WAVE 3 (frontier — opt-in, larger models)

### W-PIANO-MT3 — near-SOTA polyphonic engine

**Role.** Two slices, biggest-instrument-first. **Slice 1**: a piano-specialist
high-resolution onset/offset model (ByteDance/Kong, MIT
`piano_transcription_inference`) → near-SOTA solo-piano note-F. **Slice 2**: a
seq2seq multi-instrument model (MT3, Apache-2.0) distilled/quantised to a feasible
ONNX — one model, many instruments — IF a small-enough export exists (MT3 is
large; timebox the feasibility check first and report before committing to it).

**Files.** `lib/core/audio/transcription/piano_nn.dart` (+ `mt3.dart`) + stores +
tests. Both emit `List<NoteEvent>` (MT3: per-instrument → multi-part). Behind the
router as premium native engines. Same download-on-demand / `!kIsWeb` /
skip-if-absent rules.

**Done.** (1) `pianoTranscribe(mono) → List<NoteEvent>`; reference-parity fixture
+ a model-gated real solo-piano clip beating Basic Pitch's note-F (report both).
(2) MT3 feasibility memo in the commit + a working call if the export is viable.

---

### W-DRUMS — drum transcription

**Role.** Transcribe the drum stem into per-drum onsets (kick/snare/hi-hat/…) →
a drum part. Pairs with the existing beatbox classifier.

**Files.** `lib/core/audio/transcription/drums.dart` +
`test/transcription/drums_test.dart`. Reuse `beat_capture.dart`'s onset/classify
approach (brightest-loud-attack-frame spectral features) and/or a small CNN;
consume W-SEP's drum stem when present, else the full mix.

**Build.** Onset detection (spectral flux, already in `rhythm.dart`) → per-onset
classify into a drum-kit lane by band-energy features (low=kick, mid-noise=snare,
high=hat), or a tiny ONNX classifier. Output onsets tagged by drum → a drum
pattern the DrumKit / Tracker model can hold, and a percussion `NoteEvent` stream
for the score.

**Done.** (1) `transcribeDrums(mono, {RhythmGrid?}) → List<({double timeMs, String
drum})>`. (2) Synth test: rendered kick/snare/hat pattern → correct labels +
onset-F ≥ 0.9 vs `note_metrics`. (3) A real drum-loop recording → a sensible
pattern in the commit.

---

*Every tier stays behind the frozen `contracts.dart` seam and the shared
`note_metrics.dart` ruler, so engines swap without touching consumers, and every
neural piece is download-on-demand + `!kIsWeb`-guarded with a pure-Dart fallback.*
