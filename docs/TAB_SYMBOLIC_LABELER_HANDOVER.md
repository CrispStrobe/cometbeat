# Symbolic tab labeler (score/MIDI → fingering) — worker handover

> ## ✅ DELIVERED (onnx_runtime_dart agent)
> Trained, ONNX-exported, parity-verified on pure-Dart `onnx_runtime_dart`,
> published, and wired behind the seam.
> - **Weights:** `cstr/tab-labeler-onnx` (HF) + `models-v1` release —
>   `tab-labeler.onnx` (~1 MB, 244 k params), sha256
>   `c466b1e4e6bbf2ab87560d2b3197d0d29bf9d91be87d29fdd122c08cb290263f`.
> - **IO:** `input float32[N,49,9,1]` (49 pitch bins × 9-column window; multi-hot
>   MIDI-40..88 presence) → `output float32[N,6,21]` per-string LogSoftmax; class
>   0 = silent, class k = fret k-1; string 0 = high e. Emission score for
>   `(string,fret)` = `output[string][fret+1]`. **Reuses TabCNN's exact contract**
>   so the shipped decoder is unchanged. Pure-Dart parity cosine 1.0, max|Δ| 5.7e-6.
> - **Data:** GuitarSet annotations (CC BY 4.0) — `note→string/fret` labels; held
>   out by guitarist (player 05). Registry `license`: `CC-BY-4.0 (GuitarSet)`.
> - **Provider:** `lib/features/games/composition/tab_labeler.dart` —
>   `TabLabeler implements TabPositionModel` + `TabLabelerModelStore` (HF download /
>   `COMET_TABLABELER_DIR`). Null-on-offline → heuristic fallback.
> - **Acceptance (`test/tab_labeler_accept_test.dart`, store-gated):** on 60
>   held-out GuitarSet songs / 8,715 positions, human-fingering agreement
>   **56.98% (heuristic) → 78.59% (model), +21.6 pts**, at ~equal hand movement.
>   Playability invariants still hold structurally (the DP enforces them).
> - **Repro pipeline:** onnx_runtime_dart `tool/tab_labeler/` (extract/train/
>   parity/export_acceptance + README).

**Mission:** train + export a small model that scores `(string, fret)` placements
for a sequence of note columns, so `arrangeTab`'s Viterbi produces more human-like
fingering than the hand-tuned heuristic. This is the **symbolic arm** of the tab
work — the score→tab side (the audio arm is TabCNN, already shipped). You own the
model; CometBeat owns the DP.

Read first: `docs/TAB_ARRANGER_NEURAL_HANDOFF.md` (the seam + spec) and
`CrispASR/docs/music-transcription/GUITAR_TAB_SPEC.md` §2–§4 (why NOT a DadaGP
autoregressive decoder, and why an emission scorer fits).

## The key constraint — an EMISSION scorer, not a tab generator

The two strong published symbolic systems (MIDI-to-Tab, Fretting-Transformer) are
**autoregressive token decoders** — they emit `TAB<<<string,fret>>>` conditioned
on their own prior tokens, which violates the conditional independence a Viterbi
needs, and both depend on the **unlicensed DadaGP scrape** (spec §2.3 — nothing to
gate on, do NOT ship a derived model). So this is deliberately the **un-run
experiment** (spec §3): the classical guitar-fingering HMM has an empty emission
slot; fill it with a small **sequence labeler** (BiLSTM-CRF or a tiny transformer
over note columns) that emits per-position scores. Our Viterbi + hard constraints
stay the arbiter, so output is always playable.

## The seam you target (already in the tree)

`lib/features/games/composition/tab_arranger.dart`:

```dart
abstract interface class TabPositionModel {
  /// Per column, a score per candidate (string,fret) — higher = more idiomatic.
  /// Null (whole or per-column) → arrangeTab falls back to its heuristic.
  List<Map<(int string, int fret), double>?>? score(
    List<List<int>> columns, Tuning tuning, {int capo, int maxFret});
}
```

`arrangeTab(columns, tuning, {model})` already routes a supplied model's scores
into the LOCAL term while keeping the transition (hand-movement) cost + hard
constraints ours. A fake-model routing test exists (green). Your job is the real
weights behind this + a CometBeat provider that runs them.

## Data — LICENSED only (this is the whole risk)

- ⛔ **NOT DadaGP** (request-gated scrape, no corpus licence).
- ✅ **GuitarSet** (CC BY 4.0) — its tablature annotations give exact
  `(pitch → string, fret)` labels aligned to notes: the cleanest supervised
  signal for "which position did a human pick." Same corpus the audio arm uses.
- ✅ Any GP/MusicXML we can license or that is public-domain (public-domain
  classical guitar editions) — parse with `crisp_notation`'s GPIF/MusicXML
  readers to `(note-column, chosen-string/fret)` pairs.
- Tag the corpus in the model registry `license` field; if it can't be named, it
  doesn't ship (the BTC/DadaGP lesson).

## Model + export

- Input: a window of note columns (each a set of MIDI pitches) + the tuning's
  string MIDIs + capo. Output: per-column, per-candidate-`(string,fret)` scores
  (log-probs). Keep it small (BiLSTM-CRF / tiny transformer — ONNX-exportable,
  runs on `onnx_runtime_dart` pure-Dart like the other models).
- Publish the `.onnx` (+ any vocab) as an `onnx_runtime_dart` `models-v1` release
  asset / HF `cstr/*`, pinned by a `TabLabelerModelStore` (mirror
  `crepe_model_store`).

## CometBeat provider (small, once weights exist)

A `tab_labeler.dart` implementing `TabPositionModel`: build the candidate list
`arrangeTab` would (send it to the model, don't let the model invent an ordering),
run the `.onnx`, return the score map. Gate null-on-offline so the heuristic
Viterbi stays the fallback.

## Acceptance (spec §6–§7 — do NOT build a cross-metric league table)

- **Playability invariants** hold structurally (the decoder enforces one-note-
  per-string, fret range, capo) — not your metric.
- **Quality:** string-assignment agreement vs held-out human tab on a licensed
  set; report it alongside total hand-movement cost vs the heuristic baseline
  (the model should reduce movement / match at lower variance).
- Never put symbolic and audio numbers in one table (they share no metric).

## Coordination

Feature branch + a worktree; no PRs, merge to main; land the CometBeat provider +
a store-gated test, then a real weights swap. The seam is already green — the
model port has a target before any training finishes.
