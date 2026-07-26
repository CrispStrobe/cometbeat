# Shared native build for the Flutter FFI plugin (Android/Linux/Windows; Apple
# compiles the same sources via the podspecs). One library, `glint_vorbis`,
# = the vendored glint DECODE set (Ogg-Vorbis, FLAC) + the ENCODE set
# (glint_encode_audio → MP3 / AAC-LC / Ogg-Opus) + a glint_free shim.
# Vendored by ../sync_glint.sh, which also generates glint_sources.cmake.
# Standalone-buildable too (cmake -B build) for verification.
cmake_minimum_required(VERSION 3.10)
project(glint_vorbis_library VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)  # MSVC exports nothing from a DLL otherwise

# GLINT_NATIVE_SOURCES = every .cpp in this dir, generated so the list cannot
# drift from what sync_glint.sh actually vendored.
include(${CMAKE_CURRENT_SOURCE_DIR}/glint_sources.cmake)

add_library(glint_vorbis SHARED ${GLINT_NATIVE_SOURCES})
# "vorbis_decoder.hpp"/"encoder.hpp" and "glint/glint.h" resolve from src/.
target_include_directories(glint_vorbis PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(glint_vorbis PROPERTIES OUTPUT_NAME "glint_vorbis")
target_compile_definitions(glint_vorbis PUBLIC DART_SHARED_LIB)

if(WIN32)
  # M_PI and friends are NOT in MSVC's <cmath> unless this is defined before it
  # is included — a -D on the command line satisfies that for the whole TU.
  # Five vendored files use M_PI (opus_analysis, opus_celt_bands, resample,
  # vorbis_decoder, vorbis_imdct.hpp); without this the Windows build fails to
  # compile. Fixed HERE rather than in the sources, because everything under
  # src/ except our three local files is copied VERBATIM from glint and
  # sync_glint.sh would overwrite any edit on the next re-vendor.
  #
  # Guarded on WIN32, not MSVC: MinGW hides M_PI too under a strict -std=c++17
  # (rather than gnu++17), which is how this was reproduced and the fix proven
  # without an MSVC machine. Harmless where M_PI is already visible.
  target_compile_definitions(glint_vorbis PRIVATE _USE_MATH_DEFINES)
endif()

if(ANDROID)
  target_link_options(glint_vorbis PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX AND NOT APPLE)
  target_link_libraries(glint_vorbis PRIVATE ${CMAKE_DL_LIBS} m)
endif()

# ---- verification harness (host only; not built by the Flutter platforms) ---
# `cmake -B build -DGLINT_BUILD_TESTS=ON && cmake --build build && ctest`
# runs the native encode→decode round-trip in ../test.
option(GLINT_BUILD_TESTS "Build the native round-trip test" OFF)
if(GLINT_BUILD_TESTS)
  enable_testing()
  add_executable(glint_encode_test ${CMAKE_CURRENT_SOURCE_DIR}/../test/encode_roundtrip_test.cpp)
  target_link_libraries(glint_encode_test PRIVATE glint_vorbis)
  target_include_directories(glint_encode_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  if(WIN32)
    # GetProcessMemoryInfo, for the leak check's peak-RSS reading.
    target_link_libraries(glint_encode_test PRIVATE psapi)
  endif()
  add_test(NAME encode_roundtrip COMMAND glint_encode_test)
endif()
