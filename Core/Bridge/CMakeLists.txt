# Clamshell bridge: melonDS core + C facade, built as static libraries.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Built by Scripts/build-core.sh; not intended to be configured by hand.

cmake_minimum_required(VERSION 3.24)
project(ClamshellBridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# melonDS options. These are hard requirements (see app-store-compliance skill), so they are
# forced into the cache before melonDS reads them.
set(ENABLE_JIT OFF CACHE BOOL "" FORCE)
set(ENABLE_JIT_PROFILING OFF CACHE BOOL "" FORCE)
set(BUILD_QT_SDL OFF CACHE BOOL "" FORCE)
set(ENABLE_OGLRENDERER OFF CACHE BOOL "" FORCE)
set(ENABLE_GDBSTUB OFF CACHE BOOL "" FORCE)
set(USE_VCPKG OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
# LTO would put LLVM bitcode in the archives, which is fragile inside a prebuilt XCFramework.
set(ENABLE_LTO_RELEASE OFF CACHE BOOL "" FORCE)
set(ENABLE_LTO OFF CACHE BOOL "" FORCE)

set(MELONDS_DIR "${CMAKE_CURRENT_LIST_DIR}/../../Vendor/melonDS" CACHE PATH "melonDS checkout")
add_subdirectory("${MELONDS_DIR}" melonDS EXCLUDE_FROM_ALL)

add_library(ClamshellBridge STATIC
    src/Bridge.cpp
    src/Platform.cpp
)
target_include_directories(ClamshellBridge PUBLIC include PRIVATE src)
target_link_libraries(ClamshellBridge PRIVATE core)
target_compile_options(ClamshellBridge PRIVATE -Wall -Wextra -Wno-unused-parameter)
