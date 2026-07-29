#!/usr/bin/env bash
#
# pregate — the two-minute check to run BEFORE you push.
#
# Not a replacement for the full suite. It exists because the full suite takes
# 15–30 minutes on this shared box and is routinely killed under load, so people
# skip it — and then a red lands on whichever lane happens to push next.
#
# In one evening this repo took FIVE shared CI reds. Four were the same shape: a
# feature shipped without the cross-cutting file it implies.
#
#   * a game added to `game_registry` with no `concept_map` entry
#     -> `curriculum_coverage_test` ("every game should be placed")
#   * a field added to `TabColumn` with no codec entry — which was DATA LOSS,
#     not just a red: a saved barre was silently dropped
#     -> `tab_document_codec_test` ("the codec knows about every field")
#   * a choice-typed FX param added with no entry in the inventory
#     -> `fx_params_test` ("nothing else claims to be a choice")
#   * a missing trailing comma in a NEW TEST FILE — `require_trailing_commas` is
#     error-level here, so Analyze failed and every push behind it inherited red
#     -> `flutter analyze`, over the WHOLE project including `test/`
#
# ⚠️ Every one of those was already caught by a test that EXISTED. The tests are
# not the gap. Running them before pushing is. That is the whole point of this
# script: make the cheap 5% of the suite that catches the cross-cutting class
# something you can afford to run every time.
#
# ⚠️ `dart format` does NOT fix a missing trailing comma — measured, because I
# assumed otherwise. Formatting is not a substitute for analyzing.
#
# Usage:  tool/pregate.sh
# Then:   the full suite, when the box is quiet enough to finish one.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
step() { printf '\n=== %s\n' "$1"; }

step 'format (FIRST — it can introduce trailing-comma lints)'
if ! dart format lib test tool >/dev/null; then
  echo 'FAILED: dart format'
  fail=1
fi

step 'analyze (WHOLE project, test/ included — LAST of the static checks)'
# `test/` is where this bites: `expect(..., reason: ...)` calls are what wrap,
# so analyzing `lib/` alone is exactly the blind spot that produced two of the
# five reds.
# Run it ONCE and reuse the output; analyze is ~40s and calling it twice to
# print and then to check doubled the whole gate's cost.
analyze_out="$(flutter analyze 2>&1)"
echo "$analyze_out" | tail -2
if echo "$analyze_out" | grep -qE '^\s+(error|warning|info) •'; then
  echo 'FAILED: analyze reported issues — INFO counts here, the CI gate is'
  echo '        error-level, and `require_trailing_commas` arrives as info.'
  echo "$analyze_out" | grep -E '^\s+(error|warning|info) •' | head -5
  fail=1
fi

step 'inventory tests (the cross-cutting couplings, ~25s)'
# Deliberately only the PURE ones. `live_flow_test` boots the whole app and
# `tracker_midi_record_test` builds a screen; together they take this from two
# minutes to nine, and a gate nobody runs catches nothing.
if ! flutter test --concurrency=4 \
  test/curriculum_coverage_test.dart \
  test/effect_numbering_table_test.dart \
  test/fx_params_test.dart \
  test/tab_document_codec_test.dart \
  test/mod_note_table_test.dart \
  test/consistency_test.dart \
  test/transcribe_engines_test.dart 2>&1 | tail -2; then
  echo 'FAILED: an inventory test — read its message, it names the file to update'
  fail=1
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo 'pregate PASSED — the cross-cutting class is clear.'
  echo 'Still run the full suite before you push if you can get one to finish.'
else
  echo 'pregate FAILED — do not push.'
fi
exit "$fail"
