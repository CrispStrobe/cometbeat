# OMR via pure-Dart ONNX — handover (#4)

**Goal:** run Optical Music Recognition (sheet-music image → tokens → `Score`) on
the **pure-Dart** `onnx_runtime_dart` interpreter, so OMR works with **no native
library — including on web**, alongside today's native ggml path.

**Status:** *not started — blocked on a model asset, not on app code.* Everything
below is the plan; nothing here is wired yet.

## Why it isn't a code task in `mus`

Today's OMR recognizer (`lib/features/games/songs/import/omr_import_io.dart` →
the `crispembed` Flutter plugin, and `crisp_notation_cli/crispembed_omr.dart`)
runs a **GGUF** model (SMT GrandStaff / TrOMR / Flova) through libcrispembed's
ggml backend. `onnx_runtime_dart` cannot load GGUF — it needs an **`.onnx`**
export of an OMR model. Producing that export is a model/training task in the
`crisp_notation` / `CrispEmbed` repos (or upstream), **not** an app change.

## Feasibility (the architecture is already covered)

An SMT/TrOMR/Oemer-class model is a **CNN (or ViT) encoder + CTC or
transformer decoder**. `onnx_runtime_dart` already runs every op family that
needs, parity-validated:

- **Conv / pooling / norm** — `Conv`, `ConvTranspose`, `MaxPool`, `AveragePool`,
  `GlobalAveragePool`, `BatchNormalization` (ResNet18 / MobileNetV2 / SSD at
  parity 1.0).
- **CTC decode** — `LogSoftmax` + greedy/beam over frame logits (FastConformer
  CTC at parity 1.0).
- **Image → text encoder-decoder** — **TrOCR (ViT encoder + text decoder) at
  parity 1.0**, incl. `com.microsoft` fused attention + KV cache — the closest
  analog to a transformer-decoder OMR model.

So once an OMR model is exported to ONNX, no interpreter work is expected;
if an op is missing, add it to `onnx_runtime_dart` (that repo's normal flow).

## The export task (owner: crisp_notation / CrispEmbed model side)

1. Pick the model to export first. **TrOMR (semantic, single-staff)** is the
   simplest target: fixed CNN encoder + transformer decoder, emits the
   `note-…`/`clef-…` semantic dialect we already parse. SMT GrandStaff is the
   higher-value but heavier target (grand staff → two spines).
2. Export to ONNX (opset ≥ 17), **dynamic** image H/W and decode length.
   Fold the image preprocessing (grayscale/resize/normalize) into the graph, or
   document it so the Dart front-end matches it exactly (mismatched
   normalization = silent garbage — see the TabCNN gpfx lesson).
3. Publish to HF (mirror the ggml repos, e.g. `cstr/tromr-onnx`) with the token
   vocab / id→token map alongside.
4. Validate parity on `onnx_runtime_dart` against the ggml output on a few real
   staves **before** wiring the app.

## Where it plugs into the app (small, once the model exists)

The recognizer seam is already there: `recognizeSheetMusic(Uint8List, {download,
onStatus}) → Future<Score?>` (`songs/import/omr_import.dart`, facade over
`_io`/`_stub`), consumed by both GUI surfaces (Song Book import + the
Composition Workshop "Scan sheet music"). Add an **ONNX recognizer** behind the
same seam:

- New `omr_onnx.dart`: decode image (`package:image`) → CQT/greyscale tensor →
  `onnx_runtime_dart` `OnnxModel.run` → logits → CTC/greedy decode → id→token →
  the same `omrDialectOf` router (`scoreFromSemantic` / `bekernToScore` /
  `scoreFromLilyNotes`) that `recognizeSheetMusic` already uses.
- Selection: mirror the transcription backend framework — reuse `Backend`
  (`onnx` vs `crispasr`) and add an OMR step, or a simple "prefer onnx when no
  native lib / on web" fallback inside `recognizeSheetMusic`. On web the
  `_stub` returns unavailable today; the onnx path is what makes web work, so
  route web → onnx.
- `omrAvailable()` should then return true when *either* the native lib **or** a
  downloaded ONNX model is present.

## Acceptance

`dart run` (or a web build) recognises a real staff image → the same `Score`
the ggml path produces, with **no** libcrispembed present. Add it to the
existing OMR parity check (a fixed staff → expected note count).
