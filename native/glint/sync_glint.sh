#!/usr/bin/env bash
# Vendor the glint source sets the Flutter FFI plugin compiles into the app on
# every platform. Two halves:
#
#   DECODE — Ogg-Vorbis + FLAC (the .sf3 / SFZ sample cases).
#   ENCODE — glint_encode_audio: MP3 / AAC-LC / Ogg-Opus export.
#
# Everything here is copied VERBATIM from the glint repo (MIT) — this plugin
# forks none of glint's codec logic, so re-running this script is always safe.
# The only local sources are opus_file_c_api.cpp (Ogg-Opus -> PCM glue) and
# glint_free_shim.cpp; both are intentionally absent from the copy lists below.
#
# Re-run after glint moves. Source of truth: the glint repo (MIT), path below.
set -euo pipefail
GLINT="${GLINT_DIR:-$HOME/code/glint}"
DST="$(cd "$(dirname "$0")" && pwd)/src"
if [ ! -d "$GLINT/src" ]; then echo "glint repo not found at $GLINT (set GLINT_DIR)"; exit 1; fi

# ---- .cpp compiled into the app -------------------------------------------
# Decode side. decode_audio_c_api.cpp is glint's whole-file, header-detecting
# decoder (MP3 / AAC-LC / Ogg-Opus / Ogg-Vorbis / FLAC in one call) and needs the
# MP3 + AAC decoders with it. Measured cost: +55 KB of dylib. It buys native
# parity with the web/wasm build, which has always had this decoder, and it
# DEFINES glint_flac_decode itself — which is why this plugin no longer carries
# a local flac_c_api.cpp (the two collided; glint's is now the only copy).
CPP=(vorbis_c_api.cpp vorbis_decoder.cpp flac_decoder.cpp opus_ogg.cpp resample.cpp
     decode_audio_c_api.cpp mp3_decoder.cpp aac_decoder.cpp)
# Encode entry point: dispatches to all three codecs, so the link closure is
# much bigger than its include list suggests (see the three groups below).
CPP+=(encode_audio_c_api.cpp)
# MP3 encoder.
CPP+=(encoder.cpp subband.cpp mdct.cpp quantize.cpp huffman.cpp reservoir.cpp
      bitstream.cpp psycho.cpp)
# AAC-LC encoder.
CPP+=(aac_encoder.cpp aac_mdct.cpp aac_coder.cpp aac_psy.cpp aac_tns.cpp)
# Opus: the CELT encoder proper...
CPP+=(opus_celt_encoder.cpp opus_celt_enc_bands.cpp opus_celt_enc_energy.cpp
      opus_celt_enc_vq.cpp opus_celt_bands.cpp opus_celt_energy.cpp
      opus_celt_pitch.cpp opus_celt_rate.cpp opus_ec.cpp opus_mdct.cpp
      opus_cwrs.cpp opus_laplace.cpp opus_analysis.cpp)
# ...plus opus_c_api.cpp, which defines glint_opus_encode_file (what
# encode_audio_c_api.cpp calls for Opus). That file also names OpusDecoder /
# OpusMsDecoder, so taking it verbatim drags in the Opus + SILK DECODER too.
# Measured cost: +97 KB of dylib over hand-copying the ~30-line encode function
# into a local shim. We pay it deliberately — a local copy of glint's muxing
# logic (pre-skip, frame size, packet TOC) would silently drift and emit subtly
# wrong .opus files. Bonus: the app gets native Opus decode symbols for free.
CPP+=(opus_c_api.cpp opus_decoder.cpp opus_ms_decoder.cpp opus_celt_decoder.cpp
      opus_silk_decoder.cpp opus_silk_excitation.cpp opus_silk_indices.cpp
      opus_silk_nlsf.cpp opus_silk_plc.cpp opus_silk_frame.cpp
      opus_silk_stereo.cpp opus_silk_resampler.cpp)

# ---- headers reached src-relative (#include "encoder.hpp") -----------------
# This is the transitive closure of the .cpp list above, computed with
#   clang++ -std=c++17 -MM -I include -I src src/<each>.cpp
# Re-derive it that way after adding sources; do not guess.
HDR=(vorbis_decoder.hpp vorbis_bits.hpp vorbis_imdct.hpp vorbis_ogg.hpp
     flac_decoder.hpp opus_ogg.hpp resample.hpp mp3_decoder.hpp aac_decoder.hpp
     encoder.hpp subband.hpp mdct.hpp quantize.hpp huffman.hpp reservoir.hpp
     bitstream.hpp psycho.hpp tables.hpp simd.hpp fixedpoint.hpp intmath.hpp
     aac_coder.hpp aac_coder_types_fwd.hpp aac_mdct.hpp aac_psy.hpp
     aac_tns.hpp aac_tables.hpp
     opus_celt_encoder.hpp opus_celt_enc_bands.hpp opus_celt_enc_energy.hpp
     opus_celt_enc_vq.hpp opus_celt_bands.hpp opus_celt_energy.hpp
     opus_celt_pitch.hpp opus_celt_rate.hpp opus_celt_tables.hpp
     opus_celt_decoder.hpp opus_ec.hpp opus_mdct.hpp opus_cwrs.hpp
     opus_laplace.hpp opus_analysis.hpp opus_decoder.hpp opus_ms_decoder.hpp
     opus_silk_decoder.hpp opus_silk_excitation.hpp opus_silk_indices.hpp
     opus_silk_nlsf.hpp opus_silk_plc.hpp opus_silk_frame.hpp
     opus_silk_stereo.hpp opus_silk_resampler.hpp opus_silk_math.hpp
     opus_silk_tables.hpp)

for f in "${CPP[@]}" "${HDR[@]}"; do
  cp "$GLINT/src/$f" "$DST/$f"
done
cp "$GLINT/include/glint/glint.h" "$DST/glint/glint.h"
echo "synced ${#CPP[@]} sources + ${#HDR[@]} headers → $DST"
echo "  (from $GLINT @ $(git -C "$GLINT" rev-parse --short HEAD))"

# ---- regenerate the per-platform source lists ------------------------------
# Every .cpp in src/ is meant to be compiled: the vendored set above plus our
# two local files (flac_c_api.cpp, glint_free_shim.cpp). Generating these lists
# instead of hand-maintaining them is the whole point — a source that is
# vendored but missing from one platform's list is a link error found only on
# that platform, days later.
ROOT="$(cd "$(dirname "$0")" && pwd)"
ALL_CPP=()
for p in "$DST"/*.cpp; do ALL_CPP+=("$(basename "$p")"); done

# 1. CMake list (Android / Linux / Windows), included by src/CMakeLists.txt.
{
  echo "# GENERATED by ../sync_glint.sh — do not edit."
  echo "# Every .cpp under src/: the vendored glint set + our local wrappers."
  echo "set(GLINT_NATIVE_SOURCES"
  for f in "${ALL_CPP[@]}"; do echo "  \${CMAKE_CURRENT_SOURCE_DIR}/$f"; done
  echo ")"
} > "$DST/glint_sources.cmake"

# 2. Apple forwarders: a podspec cannot reference sources outside its own dir,
#    so each platform gets a one-line file that relatively #includes ../../src.
for plat in macos ios; do
  cls="$ROOT/$plat/Classes"
  mkdir -p "$cls"
  rm -f "$cls"/*.cpp
  for f in "${ALL_CPP[@]}"; do
    {
      echo "// GENERATED by ../../sync_glint.sh — do not edit."
      echo "// Forwarder: podspecs cannot reference sources outside their dir, so this"
      echo "// relatively includes the shared glint source. See ../glint_vorbis.podspec."
      echo "#include \"../../src/$f\""
    } > "$cls/$f"
  done
done
echo "regenerated src/glint_sources.cmake + macos/ios Classes forwarders (${#ALL_CPP[@]} .cpp)"
