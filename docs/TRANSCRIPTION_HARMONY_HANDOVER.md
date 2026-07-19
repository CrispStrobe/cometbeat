# W-HARMONY handover — neural chord recognition (BTC) in pure Dart

**Status: FEASIBILITY PROVEN.** The BTC chord model (MIT) exports to ONNX and
**runs end-to-end on `onnx_runtime_dart`**, producing chord logits. The only
substantial remaining work is a Dart **CQT front-end**. This is the cleanest of
the remaining ONNX asks (cleaner than RMVPE) — a small MIT transformer that runs
faster than real-time.

This is a standalone brief for a fresh agent to ship neural chord/key estimation.

---

## 1 · Model + licence

- **[BTC-ISMIR19](https://github.com/jayg996/BTC-ISMIR19)** — "A Bi-Directional
  Transformer for Musical Chord Recognition" (Park, ISMIR 2019). **MIT
  licensed**, and the pretrained checkpoints are bundled in the repo:
  `test/btc_model.pt` (maj/min, **25 classes**) and
  `test/btc_model_large_voca.pt` (**170 classes**). Clean to ship with NOTICE.
- Architecture: bidirectional self-attention transformer (small). Input a CQT
  segment `[1, 108, 144]`; output chord logits `[1, 108, num_chords]`.

## 2 · Feasibility — PROVEN (this session)

Exported the maj/min core (`self_attn_layers → output_layer`, `probs_out=True`)
to ONNX and ran it on `onnx_runtime_dart` (AOT `tool/bench.dart`):

- Export: `cqt[1,108,144] → chord[1,108,25]`, **13 MB**, opset 17.
- Ops present, all supported: `MatMul`×106, `Softmax`×16, `ReduceMean`×78
  (LayerNorm), `Conv`×32, `Relu`×32, plus Add/Mul/Reshape/Transpose glue.
- **Ran clean** → `output chord [1,108,25]`, ~2.5 s/segment (108 frames ≈ 10 s
  of audio at hop 2048) **on a machine at load ~90** ⇒ comfortably faster than
  real-time idle. A 3-min song ≈ 18 segments ≈ ~45 s under load, ~10–15 s idle.

Export gotchas (numpy/pyyaml are old in the repo): patch before importing —
`np.float=float; np.int=int; np.bool=bool` and
`yaml.load = lambda f,*a,**k: _orig(f, Loader=yaml.FullLoader)`. Load with
`torch.load(..., weights_only=False)['model']`.

## 3 · Remaining build (the real work)

1. **Dart CQT front-end — the crux.** BTC trained on librosa CQT:
   `n_bins=144, bins_per_octave=24, hop_length=2048` (⇒ 6 octaves), then
   `feature.T`, then per-song `(feature - mean) / std` normalisation
   (see BTC `test.py` / `utils/mir_eval_modules.audio_file_to_features`). The
   app has FFT/spectral DSP in `lib/core/audio/crisp_dsp/`, but a constant-Q
   transform is log-frequency and must MATCH librosa's CQT closely or the model
   degrades. **Budget real parity work here** (compare Dart CQT vs librosa CQT
   on a test tone/chirp to a tight tolerance, like the CREPE decoder parity).
   Confirm the sample rate BTC expects (librosa default 22050) and resample.
2. **Export both checkpoints** to ONNX (25 and 170 class); host as release
   assets (mirror the CREPE `models-v1` pattern on `onnx_runtime_dart`) —
   **not** in the pub package. `harmony_model_store.dart` (native,
   download-on-demand, `!kIsWeb`), mirror `crepe_model_store.dart`.
3. **Segment + run:** pad the CQT to a multiple of 108 frames, run each 108-frame
   segment through the model, concat logits.
4. **Decode:** argmax per frame → chord index → label via BTC's `idx2chord` /
   `idx2voca_chord` (25 = `N` + 12 maj + 12 min; 170 = large vocab). Merge
   consecutive equal frames → chord events with start/end times
   (`frame × hop / sr`).
5. **Additive seam (contracts.dart is FROZEN):** add a `ChordEvent`
   (`{String label, int rootPc, String quality, double onMs, double offMs}`) in
   a NEW file, and surface a `List<ChordEvent>` on the transcription result /
   a `harmony.dart` `estimateChords(mono) → List<ChordEvent>`. Fall back to the
   existing Krumhansl key estimate + chroda-template when no model.
6. **Web-safe split** exactly like CREPE: pure `harmony.dart` (takes a preloaded
   `OnnxModel`, no dart:io) + native `harmony_model_store.dart`.
7. **Tests:** deterministic decode test (hand-built logits → expected chords);
   CQT parity vs librosa fixture; model-gated (skip-if-absent) end-to-end on a
   synth C–G–Am–F progression → the right chord labels; a CLI
   `bin/transcribe_chords.dart`.

## 4 · Reproduce the feasibility proof

```bash
cd <scratch> && git clone --depth 1 https://github.com/jayg996/BTC-ISMIR19
# in onnx_runtime_dart: uv pip install --python .venv-crepe/bin/python pyyaml
# export test/btc_model.pt (self_attn_layers→output_layer, probs_out=True,
#   input [1,108,144]) → btc.onnx  (apply the numpy/yaml patches above)
dart run tool/bench.dart btc.onnx --iters 3   # → chord [1,108,25], runs clean
```

## 5 · Value + relation to RMVPE

Chord symbols (maj/min or large vocab) over the staff — useful for the Song
Book / Workshop / learning flows; the app currently has key detection
(Krumhansl) and chord-aware *engraving* but no chord *classifier*. This is a
distinct goal from **RMVPE** (vocal F0 from a mix — the separate "b" ask, MIT
but heavier: U-Net + GRU + mel front end). BTC is the higher-confidence build.

**Work in your own git worktree** (concurrent agents share the mus checkout).
