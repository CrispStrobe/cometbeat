# Stem separation (CrispASR) — models, measurements, and where it is used

CometBeat splits audio into stems with CrispASR's ggml separators, through one
entry point: `separateStereoCrispasr` in
`lib/core/audio/transcription/crispasr_ffi_separate_io.dart`. It runs off the
UI isolate (separating a song takes roughly as long as the song) and returns
**stereo** stems at the model's rate (44.1 kHz).

## Where it is used

| Consumer | What it does with the stems |
|---|---|
| **Practise with your song** (`features/games/practice/`) | Plays every stem on its own SoLoud voice: mute, solo, level, one-tap "Without &lt;part&gt;". "Sing the melody" transcribes the voice stem and opens the note highway over the song minus its voice. |
| **Transcribe → whole song** | Mono stems → one part per stem (`stems.dart`). |

`crispasrBeatGrid` (beat-this, MIT, ~41 MB) adds the beat grid: the practice
screen's tempo, the sing-along chart's beat lines, and whole-song
transcription's beats and bar length. Bar *phase* is not taken from it yet:
moving bar 1 onto the first downbeat would need pickup handling the score
builder does not have.

## The models

All three are MIT and run through the same `CrispasrSession.separate` call; the
choice is `TranscriptionEngineConfig.crispasrSeparatorModel` (Settings →
Transcription → Separation model).

| Model | Stems | Download | Notes |
|---|---|---|---|
| `htdemucs` (**auto**) | vocals, drums, bass, other | ~38 MB (q4_k) | GPU (Metal). Best drums. |
| `mini-bs-roformer` | vocals, drums, bass, other | ~50 MB (q8_0) | **CPU only for now** — see below. Best vocals of the 4-stem models. |
| `mel-band-roformer` | vocals, other | ~436 MB (f16) | Vocal splitter: the practice screen's "Voice only (karaoke)". |

Name the stems by what the separator returns, never by a fixed list:
mel-band-roformer's second stem is `other` (or `instrumental`, depending on
the GGUF).

## Measurements — `bin/stem_quality.dart`

Ground truth is exact: every Loop Mixer track (drums, bass, chords, melody) is
rendered **alone**, and their sum is the mix. `--voice v.wav` adds a recorded
voice as a real `vocals` stem (here: 14.6 s of macOS `say`, which is speech, not
singing). The score is SDR, 10·log10(‖s‖²/‖s−ŝ‖²) in dB, higher is better;
`other` is scored against chords + melody.

```sh
COMET_CRISPASR_LIB=~/.cache/crispasr/libcrispasr.dylib \
  dart run bin/stem_quality.dart --voice v.wav [--consistent] [--download]
```

⚠ These are our own synth voices, not recorded instruments. The numbers
**rank** the models on clean, well-separated parts. They are not MUSDB scores
and must not be quoted as such.

With a voice in the mix (three grooves: default / four / chill):

| Model | vocals | drums | bass | other |
|---|---|---|---|---|
| htdemucs (GPU) | 14.3 / 12.1 / 15.4 | 4.1 / 9.1 / 10.9 | 2.9 / 3.1 / 8.8 | 0.5 / −1.0 / 4.1 |
| mini-bs-roformer (**CPU**) | 20.5 / 18.6 / 21.9 | 6.1 / 6.0 / 6.0 | 9.1 / 0.5 / 6.5 | 5.7 / −3.8 / 2.1 |
| mel-band-roformer | 22.3 / 21.0 / 24.3 | accompaniment 25.5 / 24.3 / 26.5 | | |

Reading: mel-band-roformer is the vocal splitter; of the 4-stem models,
Mini-BS-RoFormer has clearly better vocals (+6 dB) and htdemucs is better on
drums in two of three grooves. `auto` stays htdemucs: it runs on the GPU and
drums are the stem a "minus one" learner most often removes.

Timings were recorded but are **not usable**: the machine's load average was
9–43 from other jobs throughout, and the same separation varied by 30×.

### Mini-BS-RoFormer's GPU path is broken (CrispASR #568)

On Metal, `mini-bs-roformer` returns a **silent vocals stem** and loses most of
the signal: on plain speech (input RMS 0.1552), GPU vocals RMS 0.0000 vs CPU
0.1544; GPU vocals SDR ~0.4 dB vs 18.6–21.9 dB on the CPU. CrispASR's own
qualification ran on the CPU only. `CrispasrSeparatorModel.cpuOnly` opens this
model with `openWithParams(useGpu: false)` until the GPU path is fixed — then
drop it and re-measure with `--voice`.

## Mixture consistency

A masking separator estimates each stem independently, and nothing forces the
stems to add back up to the song. With every stem on, the learner must hear
the song they loaded, so the practice screen runs `mixtureConsistent`: it
splits `mix − Σ stems` equally among the stems. That is the least-squares
projection onto "stems that sum to the mix", the smallest change that
achieves it. Measured on a click + tone, the raw stems reconstruct the mix to
15.2 dB (htdemucs) and 40.2 dB (Mini-BS-RoFormer on the CPU; ~4 dB on the
broken GPU path), and to > 60 dB after projection. htdemucs's 15 dB is the
case that matters: audible as a duller song. The cost to separation quality (`--consistent`)
is small: htdemucs ±0.3 dB.

## Tests

- `test/practice/practice_mix_test.dart`, `song_audio_test.dart`: the pure
  logic (mute/solo, windows, the sing-along chart's timing invariant, the
  projection, decoding, persistence).
- `test/practice/crispasr_stems_live_test.dart`: the real libcrispasr
  separators and beat-this through the app's wrappers. Each test skips itself
  when the lib or the model is absent (CI, web).
- `test/transcription/stems_test.dart`: a tracked beat grid sets the bar
  length.
