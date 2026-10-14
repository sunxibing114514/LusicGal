# LusicGal Kirikiri 核心构建：KrKr2-Next（engine_api C ABI）+ LG 适配器。
#
# 入参（build_android.sh 传）：
#   -DKRKR2_DIR=<third_party/upstream/kirikiri-next>
#   -DVCPKG_ROOT=<vcpkg 根>（ KrKr2 依赖经 vcpkg manifest 安装）
# NDK 工具链由调用方提供（-DCMAKE_TOOLCHAIN_FILE）。
#
# 说明：KrKr2-Next 的 Android 官方路径 = Gradle externalNativeBuild +
# vcpkg_android.cmake（cmake/vcpkg_android.cmake）。此处直接以 NDK 工具链
# 驱动其根 CMakeLists（VCPKG_TARGET_ANDROID=ON）并叠加适配器目标；
# 重依赖（highway/freetype/...）首次构建 20~40min —— CI 走 continue-on-error
# + rust-cache 式缓存（vcpkg 二进制缓存在 CI 层做）。
cmake_minimum_required(VERSION 3.22)
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
