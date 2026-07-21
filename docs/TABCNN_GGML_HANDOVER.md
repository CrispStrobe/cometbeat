# TabCNN native ggml `--tab` — worker handover (CrispASR agent)

**Mission:** add a `--tab` task to CrispASR that runs the TabCNN GGUF natively
(ggml, GPU-capable) and emits the frozen audio→tab contract over the C ABI, so
CometBeat can use a fast native path alongside the pure-Dart-onnx one it already
ships. The GGUF is already published (`cstr/tabcnn-GGUF`). You own the C++
backend + ABI; CometBeat owns the DP + the FFI provider.

This is the **native twin** of the pure-Dart audio arm — same contract, faster
runtime. Read first: `docs/TABCNN_ONNX_HANDOVER.md` (the shipped onnx path),
`CrispASR/docs/music-transcription/GUITAR_TAB_SPEC.md` §9 (packaging), and the
CometBeat consumer `lib/features/games/composition/tab_emission_decoder.dart`.

## The frozen contract (identical to the onnx path — do NOT diverge)

- **Output = `[T, 6, 21]` log-probabilities** (`log_softmax` per string), NOT
  softmax / logits. Row-major (frame, string, class).
- **Class layout:** class 0 = string **silent** ("closed"); class `k ≥ 1` = fret
  `k−1` (class 1 = open, class 20 = fret 19). (The gpfx GGUF's native
  `class 20 = silence` head is already remapped to this in the export — keep it.)
- **Input:** per frame a `9 × 192` CQT context window (`[N,192,9,1]`, bins ×
  context × 1). `N` = a batch of windows.
- **Frame hop = 512 / 22050 = 0.023220 s** — return it so the caller aligns to
  its grid.

## ⚠ TWO variants, TWO front-ends (the #1 correctness risk — from the HF card)

Both GGUFs share the CQT geometry (sr 22050, hop 512, n_bins 192,
bins_per_octave 24, fmin C1) and start from the raw magnitude `|CQT|/√length`
(the `tabcnn-cqt.bin` blob's `mean`/`std` are 0/1, unused), but the post-CQT
normalization DIFFERS:

- **gpfx** (GuitarProFX, the DEFAULT — electric-robust, EGSet12 F1 ≈ 0.77): per-
  clip `librosa.amplitude_to_db(ref=max, top_db=80)` → min-max to `[0,1]`.
- **vanilla** (GuitarSet, clean/acoustic, ~0.45): raw magnitude, no log.

Feeding the wrong normalization is a silent quality loss (the BTC 152× scale-bug
class). Assert **median per-bin magnitude ratio ≈ 1** in the CQT parity check,
not just cosine.

## Packaging (mirror `--pitch`/`--chords`, spec §9)

- `CAP_TAB` bit in **both** capability-name tables in `crispasr_backend.cpp`.
- `examples/cli/crispasr_tab_cli.{h,cpp}` early dispatcher, called from
  `crispasr_run_backend()` **and** `cli.cpp` before the transcribe backends.
- redirect shim `crispasr_backend_tabcnn.cpp` so `--list-backends` sees it.
- **both** detect passes: `crispasr_backend.cpp` *and*
  `crispasr_detect_backend_from_gguf()` in `src/crispasr_c_api.cpp`.
- session C ABI `crispasr_session_tab*`: a run call returning a frame count, an
  `n_*` accessor, and a **flat all-float view** of the `[T,6,21]` log-probs (a
  mixed int/float struct read through a float view misreads the int lanes).
- registry entry with a **`license` field** — `CC-BY-4.0 (GuitarSet; GuitarProFX
  = Pedroza et al. DAFx-24, Zenodo 11406378)`. Attribution required.
- `python tools/gen-feature-matrix.py` (never hand-edit) +
  `tools/check-backend-wiring.py`.

## Acceptance (bytes are NOT the target — tab is a preference)

1. **CQT parity** — the C++ front-end vs `librosa.cqt` at the GGUF's variant:
   cosine **and** median magnitude ratio (both, per §1's trap).
2. **Per-stage diff** — `crispasr-diff tabcnn` vs a dumped reference, registered
   in `crispasr_diff_main.cpp`. A reference dumper with no C++ consumer is dead
   code that looks like coverage — wire both halves.
3. **Round-trip** — feed the `[T,6,21]` log-probs to CometBeat's
   `decodeTabEmissions()` on a known clip; assert the decoded frets match.
4. **Report EGSet12 zero-shot** (not just the flattering GuitarSet training fold).

## CometBeat side (a follow-up once your ABI lands)

CometBeat writes a `crispasr_ffi_tab.dart` provider implementing
`TabEmissionModel` (mirrors `crispasr_ffi_pitch.dart`): audio → your session ABI
→ `TabEmissionFrames`. It slots behind the same seam the onnx `TabCnnEmitter`
already fills, auto-ordered native > onnx > offline. Hand back: the session ABI
signatures + the exact input tensor layout you expect.

## Coordination

Feature branch + a worktree; verify with the repo's own build/diff harness; no
PRs, merge to main; report the ABI + CQT-variant handling back here when done.
