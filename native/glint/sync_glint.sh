#!/usr/bin/env bash
# Vendor the MINIMAL glint Ogg-Vorbis DECODE source set into src/ so the Flutter
# FFI plugin compiles it into the app on every platform. Re-run after glint's
# feature/vorbis-decoder lands on glint main (e.g. floor-0 changes to
# vorbis_decoder.cpp). Source of truth: the glint repo (MIT), path below.
set -euo pipefail
GLINT="${GLINT_DIR:-$HOME/code/glint}"
DST="$(cd "$(dirname "$0")" && pwd)/src"
if [ ! -d "$GLINT/src" ]; then echo "glint repo not found at $GLINT (set GLINT_DIR)"; exit 1; fi

# .cpp compiled into the app (glint_free's real def is entangled with the AAC/MP3
# decoder, so we ship a 2-line shim instead — see glint_free_shim.cpp).
for f in vorbis_c_api.cpp vorbis_decoder.cpp opus_ogg.cpp resample.cpp; do
  cp "$GLINT/src/$f" "$DST/$f"
done
# headers reached src-relative (#include "vorbis_decoder.hpp") + the public ABI.
for h in vorbis_decoder.hpp vorbis_bits.hpp vorbis_imdct.hpp vorbis_ogg.hpp opus_ogg.hpp resample.hpp; do
  cp "$GLINT/src/$h" "$DST/$h"
done
cp "$GLINT/include/glint/glint.h" "$DST/glint/glint.h"
echo "synced glint Vorbis sources → $DST (from $GLINT @ $(git -C "$GLINT" rev-parse --short HEAD))"
