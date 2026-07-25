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
  add_test(NAME encode_roundtrip COMMAND glint_encode_test)
endif()
