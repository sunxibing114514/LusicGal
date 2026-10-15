# LusicGal Kirikiri 核心构建：KrKr2-Next（engine_api C ABI）+ LG 适配器。
#
# 入参（build_android.sh 传）：
#   -DKRKR2_DIR=<third_party/upstream/kirikiri-next>
#   -DVCPKG_ROOT=<vcpkg 工具根> -DVCPKG_TARGET_ANDROID=ON
#   -DCMAKE_TOOLCHAIN_FILE=<VCPKG_ROOT>/scripts/buildsystems/vcpkg.cmake
#   -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24
#   -DANDROID_NDK_HOME=<NDK>
#
# 工具链拓扑（与上游 krkr2 根项目 Gradle 路径一致）：
#   入口 toolchain = vcpkg.cmake（manifest：krkr2 根 vcpkg.json）
#     └ VCPKG_CHAINLOAD_TOOLCHAIN_FILE = NDK android.toolchain.cmake
#   vcpkg 自定义 triplet/ports 在 krkr2 的 vcpkg/ 下（overlay 注入）。
# 注意：TOOLCHAIN_FILE/CHAINLOAD 必须在 project() 前生效 —— CMake 在
# project() 后忽略这些变量（krkr2 根 CMakeLists:20-52 同约定；曾因
# project() 后再设导致 manifest 不跑、find_package(FFMPEG) 空）。
# 另：krkr2 根要求 CMake ≥3.28（ubuntu-24.04 CI 自带 3.28+）。
cmake_minimum_required(VERSION 3.22)

if(VCPKG_TARGET_ANDROID)
  if(NOT DEFINED VCPKG_ROOT AND DEFINED ENV{VCPKG_ROOT})
    set(VCPKG_ROOT "$ENV{VCPKG_ROOT}")
  endif()
  if(NOT DEFINED KRKR2_DIR OR NOT DEFINED VCPKG_ROOT)
    message(FATAL_ERROR "KRKR2_DIR / VCPKG_ROOT 未设置")
  endif()
  if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    set(CMAKE_TOOLCHAIN_FILE "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
  endif()
  if(NOT DEFINED ENV{ANDROID_NDK_HOME} AND DEFINED ANDROID_NDK_HOME)
    set(ENV{ANDROID_NDK_HOME} "${ANDROID_NDK_HOME}")
  endif()
  set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE
      "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
      CACHE FILEPATH "" FORCE)
  set(VCPKG_TARGET_TRIPLET "arm64-android" CACHE STRING "" FORCE)
  # overlay triplet 用本目录（release-only 变体，含 krkr2 原版）——
  # 优先级：先本目录，后 krkr2 的 vcpkg/triplets。
  set(VCPKG_OVERLAY_TRIPLETS
      "${CMAKE_CURRENT_SOURCE_DIR}/vcpkg/triplets;${KRKR2_DIR}/vcpkg/triplets"
      CACHE PATH "" FORCE)
  set(VCPKG_OVERLAY_PORTS "${KRKR2_DIR}/vcpkg/ports" CACHE PATH "" FORCE)
  # manifest 用 krkr2 根的 vcpkg.json（适配器目录无 manifest）。
  set(VCPKG_MANIFEST_DIR "${KRKR2_DIR}" CACHE PATH "" FORCE)
endif()

project(lusicgal_kirikiri CXX C)

set(KRKR2_DIR "${KRKR2_DIR}" CACHE PATH "KrKr2-Next 仓库根")
if(NOT EXISTS "${KRKR2_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "KRKR2_DIR 未设置：${KRKR2_DIR}")
endif()

set(BUILD_ENGINE_API ON CACHE BOOL "" FORCE)
set(ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)

# KrKr2-Next 根 CMake（Android 分支：VCPKG_TARGET_ANDROID → arm64-android 三元组）
add_subdirectory(${KRKR2_DIR} krkr2)

# LusicGal 适配器。
add_library(lusicgal_kirikiri SHARED lg_kirikiri.cpp)
set_target_properties(lusicgal_kirikiri PROPERTIES OUTPUT_NAME lusicgal_kirikiri)
target_include_directories(lusicgal_kirikiri PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/include
  ${KRKR2_DIR}/bridge/engine_api/include)
target_link_libraries(lusicgal_kirikiri PRIVATE engine_api log)
