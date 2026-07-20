# CrispASR-side status — reply to the transcription handovers

Written from the CrispASR repo, 2026-07-20. Corrects stale status in
`TRANSCRIPTION_SOTA_HANDOFF.md` and redirects one worker away from work that is
already done on our side.

**Read §2 before starting W-SEP.** It is the one item here that changes what a
worker should build.

---

## 1 · W-CREPE — COMPLETE, including the surfaces listed as pending

`TRANSCRIPTION_SOTA_HANDOFF.md` says *"Only their Dart FFI + WASM surfaces are
pending (their explicit 'Next')."* **That is now out of date — both landed.**

Shipped on CrispASR `main`:

- `src/crepe.{h,cpp}` — ggml runtime, cos = 1.0 vs `torchcrepe`, tiny RTF 0.28 on
  M1 Metal.
- `--pitch` CLI (mirrors `--separate`), `--pitch-format text|json`,
  `--pitch-hop-ms`.
- Session C ABI `crispasr_session_pitch*`, and **GGUF arch auto-detect now
  recognises `crepe`**, so a plain session open works — the earlier caveat about
  needing an explicit backend name is fixed.
- **Dart FFI: `CrispasrSession.pitch()`** → `PitchFrame` records, published as
  **`crispasr 0.8.16` on pub.dev**. Verified live against a 440 Hz tone
  (reads 440.397) and 220 Hz (220.883).
- **WASM**: `sessionPitch` / `sessionPitchSampleRate` embind exports.
- Full diff-harness (`crispasr-diff crepe`), live test, quantize rules.

⚠️ The Dart binding reads the flat `const float*` via `Float32List`, deliberately
**not** an FFI `Struct` with `Double` fields — the C side is 32-bit `float`, so a
`Double` struct read returns garbage rather than failing. Worth knowing if you
write a second binding.

### Which GGUF to ship — q4_k has a real caveat

Measured per-frame against each model's own f16 (`cos_min` · fraction of frames
whose **argmax pitch bin** is unchanged):

| | f16 | q8_0 | q4_k |
|---|---|---|---|
| tiny | 0.999999 · 100% | 0.999807 · 98.5% | **0.961643 · 85.2%** |
| full | 1.000000 · 100% | 0.999937 · 99.5% | **0.992563 · 91.4%** |

**Use tiny-f16 (0.93 MB) or tiny-q8_0 (0.50 MB). Avoid q4_k** — at tiny, roughly
1 frame in 7 lands on a different pitch bin. The card on `cstr/crepe-GGUF` now
documents this.

### Accuracy on real music — tiny is fine, and the domain limits are real

10 monophonic instrumental recordings (violin arco + pizz, piano, glock,
carillon, cello, flute, three folk melodies, brass):

| | tiny | full |
|---|---|---|
| in-tessitura (voiced_prob ≥ 0.5) | 89.6% | 89.0% |
| octave disagreement tiny-vs-full | 2.3% | — |

`tiny` is **not** meaningfully worse than `full` despite being ~38× cheaper.
Two domain limits shared by both, worth designing around:

- **Plucked / percussive attacks** (violin pizzicato: ~50% in-tessitura) — fast
  decay means most frames carry no sustained pitch.
- **Inharmonic sources** (a carillon clip marked only 39/1501 frames voiced) —
  the model correctly *abstains* rather than inventing pitch. Gate on
  `voicedProb` and this is a feature, not a failure.

Caveat: tessitura bounds were hand-chosen, so absolute percentages are soft; the
tiny-vs-full comparison is the robust part.

---

## 2 · W-SEP — **stop; do not export Open-Unmix**

`TRANSCRIPTION_SEP_HANDOVER.md` proposes fixing the Open-Unmix ONNX export
(`nb_frames` baked into broadcast constants), adding a Dart STFT/iSTFT, and
building `separate_model_store.dart` — and it concedes umxhq quality is
*"mediocre (vocals SDR ~5–6 dB); fine for isolate-vocal→CREPE, not clean stems."*

**CrispASR already ships two separators, at higher quality, today:**

| model | stems | status |
|---|---|---|
| **HTDemucs** (`cstr/htdemucs-GGUF`) | drums / bass / other / vocals, 44.1 kHz stereo | full per-stage parity, Q4_K ~38 MB |
| **Mel-Band RoFormer** (`cstr/mel-band-roformer-vocals-GGUF`) | vocals / instrumental | waveform bit-exact, 2.4e-7 |

Both have auto-download, a `--separate` CLI, the session C ABI, and Python
`Session.separate()`. There is **no ONNX export problem to solve** — that entire
class of work (baked dynamic axes, fixed-`T` chunking, Dart STFT/iSTFT,
overlap-add) disappears.

Your own "highest-value slice first: vocals-only → run `crepeF0` on the stem" is
buildable now with zero export work: **mel-band-roformer is exactly a
vocals/instrumental split**, and CREPE is already wired behind the same session
API. That is the compelling demo, available immediately.

**The one real gap on our side:** `crispasr_session_separate*` is **not yet bound
in the Dart package** (only the CLI, C ABI, and Python have it). That is a small,
well-understood addition mirroring `pitch()` — much smaller than the Open-Unmix
path. Ask and we will add it.

---

## 3 · What CrispASR does NOT have (accurate as of 2026-07-20)

- **Basic Pitch** — claimed under our §250, not yet landed.
- **RMVPE** — absent. Good ggml candidate: your vet correction is right that the
  shipped ONNX is a pure conv U-Net with no recurrent layer, so it ports cleanly,
  and its 360-bin output reuses the CREPE decode we already have. On our side the
  128-bin mel front-end is nearly free (`core/mel.h` has Slaney/librosa
  filterbanks). 361 MB f32 → roughly 90 MB at q4_k, ~180 MB at q8_0.
- **BTC harmony** — absent, and blocked on the same thing you are: **a CQT**. You
  correctly call the Dart CQT "the crux"; we have no CQT either. If we build
  `core/cqt.h` with librosa parity, that unblocks BTC on the CrispASR side and
  the parity fixtures would be reusable as your Dart oracle.
- **MT3** — untouched; still needs the T5X/JAX checkpoint-conversion feasibility
  memo before any C++.

## 4 · Contract alignment

`crepe_frame { float time_ms; float f0_hz; float voiced_prob; }` was laid out to
match your frozen `PitchFrame = ({double timeMs, double f0Hz, double voicedProb})`
field-for-field, so the seam is a read rather than a marshal. `contracts.dart`
was not edited and does not need to be.
