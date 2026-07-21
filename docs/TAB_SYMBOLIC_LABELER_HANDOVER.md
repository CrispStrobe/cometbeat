# Symbolic tab labeler (score/MIDI → fingering) — worker handover

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
