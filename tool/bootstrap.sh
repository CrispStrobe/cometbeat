#!/usr/bin/env bash
#
# bootstrap — make a fresh clone buildable.
#
# pubspec.yaml resolves three packages by RELATIVE PATH, from repositories that
# must sit next to this one:
#
#     ../crisp_notation       notation model, codecs and score widgets
#     ../CrispEmbed           ggml engine behind the OMR Flutter plugin
#     ../onnx_runtime_dart    pure-Dart ONNX runtime (neural transcription)
#
# They are path dependencies on purpose — they are developed alongside the app
# and consumed from `main` ahead of their published releases — but that means
# `flutter pub get` fails on a clone that does not have them, with an error
# that names a path rather than a fix. CI lays them out the same way (see the
# checkout steps in .github/workflows/ci.yml); this script does it locally.
#
# It only ever CLONES what is missing. A sibling that already exists is left
# exactly as it is — never fetched, reset or switched — because it may be your
# working copy. Its branch and commit are printed so a mismatch is visible.
#
# Usage:  tool/bootstrap.sh            clone what is missing, then pub get
#         tool/bootstrap.sh --check    report only; exit 1 if one is missing

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# name | repository | the path pubspec.yaml points into
SIBLINGS=(
  "crisp_notation|https://github.com/CrispStrobe/crisp_notation|packages/crisp_notation/pubspec.yaml"
  "CrispEmbed|https://github.com/CrispStrobe/CrispEmbed|flutter/crispembed/pubspec.yaml"
  "onnx_runtime_dart|https://github.com/CrispStrobe/onnx_runtime_dart|pubspec.yaml"
)

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

missing=0
for entry in "${SIBLINGS[@]}"; do
  IFS='|' read -r name repo marker <<<"$entry"
  dir="../$name"
  if [ -f "$dir/$marker" ]; then
    where="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    sha="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout')"
    printf 'ok       %-18s %s @ %s\n' "$name" "$where" "$sha"
  elif [ -e "$dir" ]; then
    # Something is there but it is not the package: do not guess, do not touch.
    printf 'BROKEN   %-18s %s exists but has no %s\n' "$name" "$dir" "$marker"
    missing=1
  elif [ "$check_only" = 1 ]; then
    printf 'MISSING  %-18s expected at %s\n' "$name" "$dir"
    missing=1
  else
    printf 'cloning  %-18s %s\n' "$name" "$repo"
    if ! git clone --depth 1 "$repo" "$dir"; then
      printf 'FAILED   %-18s could not clone %s\n' "$name" "$repo"
      missing=1
    fi
  fi
done

if [ "$missing" = 1 ]; then
  echo
  echo 'Not buildable yet: fix the entries above, then run this again.'
  exit 1
fi
[ "$check_only" = 1 ] && exit 0

echo
if command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo 'flutter is not on PATH — install it (CI uses the version pinned in'
  echo '.github/workflows/ci.yml), then run: flutter pub get'
  exit 1
fi
