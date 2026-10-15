# LusicGal System35 核心构建：镜像 xsystem35-sdl2 的 android/app/jni
# 依赖编排（FetchContent SDL2/freetype/SDL_mixer + 仓库根）+ LG 适配器。
#
# 入参（build_android.sh 传）：
#   -DXS35_DIR=<third_party/upstream/xsystem35-sdl2>
cmake_minimum_required(VERSION 3.22)
project(lusicgal_xsystem35 CXX C)

set(XS35_DIR "${XS35_DIR}" CACHE PATH "xsystem35-sdl2 仓库根")
if(NOT EXISTS "${XS35_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "XS35_DIR 未设置：${XS35_DIR}")
endif()

set(LG_PATCH_SDL "${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/patch_sdl_android.sh")

include(FetchContent)
FetchContent_Declare(
  SDL
  URL https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz
  URL_HASH SHA1=ce98fa93e31836a751feca374ab28a0770b63c16
)
FetchContent_Declare(
  freetype
  URL https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.gz
      https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.gz
  URL_HASH SHA1=a911f65c6355ddcf7aaba46e250dbc00f67e1678
)
FetchContent_Declare(
  SDL_mixer
  URL https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.8.0/SDL2_mixer-2.8.0.tar.gz
  URL_HASH SHA1=a58c69f9d00e44833b9e00e1adb58d85759ca499
)

# 仅 FreeType 自带光栅器。
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(SDL2MIXER_OPUS OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_FLAC OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MOD  OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_WAVPACK OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_INSTALL OFF CACHE BOOL "" FORCE)

# SDL 先 Populate → 打 LG 取窗补丁 → 再 add_subdirectory（MakeAvailable 无法中间补丁）。
FetchContent_GetProperties(SDL)
if(NOT SDL_POPULATED)
  FetchContent_Populate(SDL)
  message(STATUS "打 SDL Android 取窗补丁（${sdl_SOURCE_DIR}）")
  execute_process(
    COMMAND bash "${LG_PATCH_SDL}" "${sdl_SOURCE_DIR}"
    RESULT_VARIABLE patch_rc)
  if(NOT patch_rc EQUAL 0)
    message(FATAL_ERROR "SDL 取窗补丁失败（${patch_rc}）")
  endif()
  add_subdirectory(${sdl_SOURCE_DIR} ${sdl_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

FetchContent_MakeAvailable(freetype SDL_mixer)

# xsystem35 仓库根（ANDROID 分支：add_library(xsystem35 SHARED) + webp + midi.android.c）。
add_subdirectory(${XS35_DIR} xsystem35)

# LusicGal 适配器。
add_library(lusicgal_xsystem35 SHARED lg_xsystem35.cpp)
set_target_properties(lusicgal_xsystem35 PROPERTIES OUTPUT_NAME lusicgal_xsystem35)
target_include_directories(lusicgal_xsystem35 PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/include)
# android = ANativeWindow_acquire/_release（set_surface）。
target_link_libraries(lusicgal_xsystem35 PRIVATE xsystem35 SDL2 log android)
