#!/usr/bin/env bash
# tool/bundle_macos_tts.sh
#
# Collect libcrispasr + ALL its non-system dependencies (the ggml dylibs and the
# Homebrew opus/ogg dylibs) into ONE self-contained directory with @loader_path-
# relative install names, so the set loads on a machine that has neither the
# CrispASR build tree nor Homebrew — a mini `dylibbundler` (which isn't installed
# here) in pure `install_name_tool` + `codesign`.
#
# Two uses:
#   • DEV desktop build — target ~/.cache/crispasr (the default): CometBeat's
#     KokoroModelStore cascade then finds `libcrispasr.dylib` there and neural TTS
#     works in `flutter run macos`, no Xcode changes.
#   • RELEASE — target a staging dir, then copy its contents into the signed
#     `.app`'s Contents/Frameworks via an Xcode "Copy Files" / Podfile hook
#     (see docs/TTS_MACOS.md) and re-sign with your Developer ID.
#
# Usage:
#   tool/bundle_macos_tts.sh [SRC_DYLIB] [TARGET_DIR]
#     SRC_DYLIB   default: ../CrispASR/build/src/libcrispasr.dylib
#     TARGET_DIR  default: $HOME/.cache/crispasr
set -euo pipefail

SRC="${1:-../CrispASR/build/src/libcrispasr.dylib}"
DEST="${2:-$HOME/.cache/crispasr}"

[[ -f "$SRC" ]] || { echo "✗ source dylib not found: $SRC" >&2; exit 1; }
mkdir -p "$DEST"

# Resolve a dylib reference (an otool -L line's path) to a real file. @rpath refs
# are looked up against the root's LC_RPATH entries; absolute paths are used as-is.
declare -a RPATHS
_load_rpaths() {
  while IFS= read -r p; do RPATHS+=("$p"); done < <(
    otool -l "$1" 2>/dev/null | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}'
  )
}

_resolve() { # $1 = dep ref
  local ref="$1"
  case "$ref" in
    @rpath/*)
      local leaf="${ref#@rpath/}"
      for rp in "${RPATHS[@]}"; do
        [[ -f "$rp/$leaf" ]] && { echo "$rp/$leaf"; return; }
      done
      return 1 ;;
    /System/*|/usr/lib/*) return 1 ;;   # system — never bundle
    /*) [[ -f "$ref" ]] && echo "$ref" ;;
    *) return 1 ;;
  esac
}

# BFS over the dependency graph. CRUCIAL: copy each dep under the exact basename
# it is REFERENCED by (e.g. libggml.0.dylib), not the symlink-resolved versioned
# name (libggml.0.10.2.dylib) — otherwise the rewritten @rpath refs won't match.
# bash 3.2 (macOS default) — no associative arrays; queue holds "refname|realpath".
SEEN=" "
declare -a QUEUE

# Every dependency is bundled under a "crispasr-" prefixed name (the root keeps
# its own). WHY: another plugin in the same app ships its OWN ggml under the
# same install names — CrispEmbed's libggml.0.dylib / libggml-base.0.dylib,
# linked at launch. dyld then hands libcrispasr the already-loaded copy of
# that NAME, and dlopen fails ("Symbol not found: _ggml_prec_set_acc") — or
# worse, binds to an ABI-mismatched ggml. Distinct install names make them
# distinct images; macOS's two-level namespace keeps each library bound to its
# own copy. The root is not renamed: callers look for libcrispasr.dylib.
_bundled() { # $1 = referenced basename → name it is stored + referenced as
  if [[ "$1" == "$ROOT_REF" ]]; then echo "$1"; else echo "crispasr-$1"; fi
}
_seen()   { case "$SEEN" in *" $1 "*) return 0;; *) return 1;; esac; }
_mark()   { SEEN="$SEEN$1 "; }
_enqueue() { QUEUE+=("$1"); }

# Root: reference name = its own install-name id basename (libcrispasr.1.dylib).
ROOT_REAL="$(readlink -f "$SRC" 2>/dev/null || echo "$SRC")"
ROOT_ID="$(otool -D "$ROOT_REAL" 2>/dev/null | tail -1)"
ROOT_REF="$(basename "${ROOT_ID:-$SRC}")"
_enqueue "$ROOT_REF|$ROOT_REAL"

echo "→ collecting into $DEST"
while ((${#QUEUE[@]})); do
  cur="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}")
  refname="${cur%%|*}"; real="${cur#*|}"
  _seen "$refname" && continue
  _mark "$refname"
  out="$(_bundled "$refname")"
  cp -f "$real" "$DEST/$out"; chmod u+w "$DEST/$out"
  echo "  + $out"
  _load_rpaths "$real"
  while IFS= read -r dep; do
    r="$(_resolve "$dep" || true)"
    [[ -n "$r" ]] && _enqueue "$(basename "$dep")|$r"
  done < <(otool -L "$real" | tail -n +2 | awk '{print $1}')
done

# Rewrite every collected lib: id + inter-deps → @rpath/<refname>; strip ALL
# foreign LC_RPATHs and leave only @loader_path, so the loader can ONLY find the
# deps inside this dir (true self-containment).
echo "→ rewriting install names + rpaths"
for f in "$DEST"/*.dylib; do
  base="$(basename "$f")"
  install_name_tool -id "@rpath/$base" "$f" 2>/dev/null || true
  while IFS= read -r dep; do
    db="$(basename "$dep")"
    if _seen "$db"; then
      install_name_tool -change "$dep" "@rpath/$(_bundled "$db")" "$f" 2>/dev/null || true
    fi
  done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
  # Drop every existing rpath, then add just @loader_path.
  while IFS= read -r rp; do
    install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
  done < <(otool -l "$f" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}')
  install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
done

# Unversioned convenience name the store looks for, + ad-hoc sign everything.
ln -sf "$ROOT_REF" "$DEST/libcrispasr.dylib"
echo "→ codesigning (ad-hoc)"
for f in "$DEST"/*.dylib; do codesign --force -s - "$f" 2>/dev/null || true; done

# Static self-containment check: no LC_RPATH may point outside the bundle, and
# every @rpath dependency must have a matching file here.
echo "→ verifying self-containment"
fail=0
for f in "$DEST"/*.dylib; do
  while IFS= read -r rp; do
    [[ "$rp" == "@loader_path" ]] || { echo "  ✗ $(basename "$f"): foreign rpath $rp"; fail=1; }
  done < <(otool -l "$f" | awk '/LC_RPATH/{r=1} r&&/path /{print $2; r=0}')
  while IFS= read -r dep; do
    case "$dep" in
      @rpath/*) [[ -f "$DEST/${dep#@rpath/}" ]] || { echo "  ✗ $(basename "$f"): missing dep $dep"; fail=1; } ;;
      /opt/homebrew/*|/Volumes/*) echo "  ✗ $(basename "$f"): external dep $dep"; fail=1 ;;
    esac
  done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
done
((fail==0)) && echo "  ✓ self-contained" || { echo "✗ bundle is NOT self-contained"; exit 1; }

echo "✓ bundled $(ls "$DEST"/*.dylib | grep -vc 'libcrispasr.dylib$') dylibs → $DEST"
echo "  dev: neural TTS now loads in \`flutter run macos\`."
echo "  release: copy $DEST/*.dylib into <App>.app/Contents/Frameworks + re-sign."
