# RVC/SVC Site-B injectable noise — worker handover

**Mission:** make the RVC generator's **Site B** noise injectable on the CometBeat
side, so the three-way bit-exact harness (Python-ref → our Dart offline oracle →
ggml) can feed all three the identical buffer and line up to `max_abs 0`. Site A
is already injectable; Site B is not, and it's genuinely random, so the harness
can't close without it. Needs an ONNX **re-export** + a small `rvc.dart` change —
a shared task (the export owner + CometBeat).

Background: auto-memory `svc-voice-conversion-seam`; the relay came from the
CrispASR RVC determinism proof (three RNG sites: A = `randn_like` z_p latent,
phase = a zeroed `(1,1)` draw, B = SineGen additive noise).

## What's already handled — and the ONE gap

`infer()` draws exactly three RNG sites; our determinism story covers two:

- **Site A** (`rnd`, the flow/`z_p` latent `[1,192,T]`) — **injectable today**:
  `rvcConvert(..., Float32List? rnd)` feeds `'rnd': Tensor.float(noise,[1,192,t])`;
  `rvcSeededNoise(frames, seed:)` is the default (`lib/core/audio/transcription/
  rvc.dart`).
- **SineGen phase** — NOT random for us: `harmonic_num == 0` → a single `(1,1)`
  draw the model's next line zeroes, so **injecting zeros is provably equivalent**
  (bit-identical, proven). Nothing to do; just assert `harmonic_num==0` in any
  guard.
- ⛔ **Site B** — SineGen's **additive noise** `(1, T×upp, 1)`, voicing-dependent
  and genuinely random. **Our ONNX export FOLDS the SineGen source away, so Site
  B is not a graph input** → it can't be injected → the three-way harness can't
  match bit-for-bit. This is the gap.

## The task (two halves)

1. **Re-export the RVC ONNX exposing Site B as a graph input** — like `rnd` is for
   Site A: the SineGen additive-noise buffer becomes a named `float32[1, T×upp, 1]`
   input instead of an internal `randn`. (Export owner / the tooling that produced
   the current `rnd`-exposing graph. Keep `rnd` + phase handling unchanged.)
   Publish the new model to the RVC store's pinned location + sha.
2. **Wire it in `rvc.dart`** (CometBeat) — mirror the Site-A seam:
   - add `Float32List? sourceNoise` to `rvcConvert` (default a seeded draw, e.g.
     `rvcSeededSourceNoise(framesUpsampled, seed:)`), feeding the new input tensor;
   - production `convert()` stays RANDOM (kids' voice transform); the seed/inject
     is a **test affordance only**, exactly like `rnd`.

## Acceptance

The 3-way harness feeds Python-ref, `rvc.dart` (offline oracle), and ggml the
**same** Site-A and Site-B buffers (+ zeroed phase) and gets **bit-identical**
output — `max_abs 0.000e+00` across all three, the same proof already achieved for
Site A alone. Add it to the RVC reference-dumper's stages so it can't regress.

## Notes / traps

- The buffer is `T×upp` long (upsampled by the NSF hop `upp`), **not** `T` — size
  it from the upsample factor, not the frame count.
- Voicing-dependent: the source module gates the additive noise by the UV mask, so
  the injected buffer must be applied at the SAME point (pre-gate) the model does,
  or the values diverge even when the raw draw matches.
- Don't touch the production randomness — `convert()` must stay non-deterministic;
  only the harness/test path injects.

## Coordination

Feature branch + a worktree; the ONNX re-export is the gating half (do it first so
`rvc.dart` has a target); no PRs, merge to main; report the new model sha + the
input tensor name back here + into `svc-voice-conversion-seam`.
