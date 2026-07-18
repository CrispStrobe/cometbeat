# Flutter FFI plugin (linux) — delegates to the shared native build under ../src.
cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "glint_vorbis")
project(${PROJECT_NAME} LANGUAGES CXX)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
set(glint_vorbis_bundled_libraries $<TARGET_FILE:glint_vorbis> PARENT_SCOPE)
