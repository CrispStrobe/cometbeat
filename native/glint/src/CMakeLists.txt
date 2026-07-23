# Shared native build for the Flutter FFI plugin (Android/Linux/Windows; Apple
# compiles the same sources via the podspecs). One library, `glint_vorbis`,
# = the minimal glint Ogg-Vorbis decoder (vendored by ../sync_glint.sh) + a
# glint_free shim. Standalone-buildable too (cmake -B build) for verification.
cmake_minimum_required(VERSION 3.10)
project(glint_vorbis_library VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)  # MSVC exports nothing from a DLL otherwise

add_library(glint_vorbis SHARED
  vorbis_c_api.cpp
  vorbis_decoder.cpp
  opus_ogg.cpp
  resample.cpp
  flac_c_api.cpp
  flac_decoder.cpp
  glint_free_shim.cpp
)
# "vorbis_decoder.hpp"/"flac_decoder.hpp" and "glint/glint.h" resolve from src/.
target_include_directories(glint_vorbis PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(glint_vorbis PROPERTIES OUTPUT_NAME "glint_vorbis")
target_compile_definitions(glint_vorbis PUBLIC DART_SHARED_LIB)

if(ANDROID)
  target_link_options(glint_vorbis PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX AND NOT APPLE)
  target_link_libraries(glint_vorbis PRIVATE ${CMAKE_DL_LIBS} m)
endif()
