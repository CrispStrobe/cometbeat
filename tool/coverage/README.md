# Coverage harness

`flutter test --coverage` aborts the **entire** run with
`Cannot add event while adding stream` the moment one test spawns an
isolate/process (our CLI round-trips, live-audio, procedural streamers). That
made a whole-suite coverage number impossible to collect directly.

`run.sh` routes around it: it excludes the known spawners, runs the rest in
batches under coverage, and if a batch still aborts (an unknown spawner) falls
back to per-file so only that one file is lost. `merge.py` then merges the lcov
parts (DA + BRDA by max hit) into `coverage/merged.info` and prints the worst-
covered files and the files no test loads.

```bash
# from the repo root (wrap with the broken-Ruby env from CLAUDE.md if needed)
bash tool/coverage/run.sh          # ~45-75 min: writes coverage/parts/*.info
python3 tool/coverage/merge.py     # merges + reports; writes coverage/merged.info
```

Add `--branch-coverage` inside `run.sh`'s `run_cov` to also collect BRDA (branch)
records; `merge.py` already merges them.

## Baseline (2026-07-27)

Whole-`lib/` line coverage was **80.0%** (61,890 / 77,385 lines, 532 / 601
files loaded). The worst-covered files are almost all FFI / native-transcription
/ ONNX-model-store / plugin wrappers (integration-tested, not unit-testable) and
platform export-shell barrels; the pure-logic gaps the map surfaced were closed
to 100% file-by-file (rhythm_quantize, reading_hint, chord_progression,
module_doc DocCell, xm/s3m/it structs, source_registry, module_flow_timeline).

`coverage/` itself is gitignored; only this tooling is tracked.
