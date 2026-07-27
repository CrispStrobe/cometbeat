#!/usr/bin/env bash
# Whole-suite line coverage that routes around the collection bug.
#
# `flutter test --coverage` aborts the ENTIRE run with "Cannot add event while
# adding stream" as soon as one test spawns an isolate/process. A handful of our
# tests do (CLI round-trips, live-audio, procedural streamers). This harness
# excludes the known spawners, runs the rest in batches under coverage, and if a
# batch still aborts (an unknown spawner) falls back to per-file so only that one
# file is lost — then tool/coverage/merge.py merges the parts and reports.
#
# Usage:  bash tool/coverage/run.sh        # from the repo root
#         python3 tool/coverage/merge.py   # then merge + report
#
# On this Mac, wrap with the broken-Ruby env (see CLAUDE.md) if pod/xcode run:
#   PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
#     bash tool/coverage/run.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

PARTS="$ROOT/coverage/parts"
LOG="$ROOT/coverage/harness.log"
mkdir -p "$PARTS"
rm -f "$PARTS"/*.info "$PARTS"/failed.txt "$LOG"

# Known isolate/process spawners that break --coverage collection. The per-file
# fallback catches any not listed here (they land in coverage/parts/failed.txt).
SPAWNERS="test/dawedit_cli_test.dart test/flac_glint_live_test.dart \
test/fxproc_cli_test.dart test/module_wild_test.dart \
test/mp3_decode_roundtrip_test.dart test/rendersong_cli_test.dart \
test/stream_export_test.dart test/tracker_audio_regression_test.dart \
test/streaming_procedural_test.dart"

is_spawner() { case " $SPAWNERS " in *" $1 "*) return 0;; *) return 1;; esac; }

SAFE=()
while IFS= read -r f; do
  is_spawner "$f" || SAFE+=("$f")
done < <(find test -name '*_test.dart' | sort)

echo "$(date +%T) safe test files: ${#SAFE[@]}" | tee -a "$LOG"

run_cov() { # $1=outfile ; rest=test files
  local out="$1"; shift
  flutter test --coverage --coverage-path="$out" "$@" >/dev/null 2>&1
  [ -s "$out" ]
}

BATCH="${COVERAGE_BATCH:-40}"
n=0
batch=()
flush() {
  [ ${#batch[@]} -eq 0 ] && return
  local out
  out="$PARTS/batch_$(printf '%02d' $n).info"
  echo "$(date +%T) batch $n: ${#batch[@]} files" | tee -a "$LOG"
  if run_cov "$out" "${batch[@]}"; then
    echo "  ok" | tee -a "$LOG"
  else
    echo "  batch aborted -> per-file fallback" | tee -a "$LOG"
    rm -f "$out"
    for f in "${batch[@]}"; do
      local base; base=$(basename "$f" .dart)
      if run_cov "$PARTS/f_${base}.info" "$f"; then
        echo "    ok  $f" | tee -a "$LOG"
      else
        echo "    FAIL $f" | tee -a "$LOG"
        echo "$f" >> "$PARTS/failed.txt"
      fi
    done
  fi
  n=$((n+1))
  batch=()
}

for f in "${SAFE[@]}"; do
  batch+=("$f")
  [ ${#batch[@]} -ge "$BATCH" ] && flush
done
flush

echo "$(date +%T) DONE. parts: $(ls "$PARTS"/*.info 2>/dev/null | wc -l), failed: $(wc -l < "$PARTS/failed.txt" 2>/dev/null || echo 0)" | tee -a "$LOG"
echo "Now run:  python3 tool/coverage/merge.py"
