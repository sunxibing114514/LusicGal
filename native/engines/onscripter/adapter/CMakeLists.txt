# LusicGal ONScripter 核心构建：镜像 onsyuri 的 Android 依赖编排（v0.8.9
# 时代的 src/onsyuri_android/app/cpp/CMakeLists.txt）+ LG 适配器目标。
#
# 入参（build_android.sh 传）：
#   -DONSYURI_DIR=<third_party/upstream/onscripter-yuri>
# NDK 工具链由调用方（-DCMAKE_TOOLCHAIN_FILE）提供。
cmake_minimum_required(VERSION 3.22)
project(lusicgal_onscripter CXX C)

set(ONSYURI_DIR "${ONSYURI_DIR}" CACHE PATH "OnscripterYuri 仓库根")
if(NOT EXISTS "${ONSYURI_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "ONSYURI_DIR 未设置或无 CMakeLists：${ONSYURI_DIR}")
endif()

set(THIRDPARTY_PORT "${ONSYURI_DIR}/thirdparty/port")
set(SDL2_DIR ${THIRDPARTY_PORT}/SDL2-2.26.3)
set(SDL2IMAGE_DIR ${THIRDPARTY_PORT}/SDL2_image-2.6.3)
set(SDL2TTF_DIR ${THIRDPARTY_PORT}/SDL2_ttf-2.20.2)
set(SDL2MIXER_DIR ${THIRDPARTY_PORT}/SDL2_mixer-2.6.3)
set(JPEG_DIR ${THIRDPARTY_PORT}/SDL2_image-2.6.3/external/jpeg)
set(LUA_DIR ${THIRDPARTY_PORT}/lua-5.4.4)
set(BZ2_DIR ${THIRDPARTY_PORT}/bzip2-1.0.8)

if(NOT EXISTS "${SDL2_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "缺 SDL2 源码：先运行上游 script/_fetch.sh（见 build_android.sh）")
endif()

# ---- SDL 栈（镜像上游，含 LG 取窗补丁校验）-----------------------------
set(ANDROID TRUE)
set(CMAKE_SYSTEM_NAME Linux)
add_subdirectory(${SDL2_DIR} ${CMAKE_BINARY_DIR}/thirdparty/sdl2)
target_link_options(SDL2 PRIVATE "-Wl,-z,max-page-size=16384")

set(SDL2IMAGE_INSTALL off)
set(SDL2IMAGE_SAMPLES off)
add_subdirectory(${SDL2IMAGE_DIR} ${CMAKE_BINARY_DIR}/thirdparty/sdl2image)
target_link_options(SDL2_image PRIVATE "-Wl,-z,max-page-size=16384")

set(SDL2TTF_SAMPLES off)
set(SDL2TTF_INSTALL off)
set(SDL2TTF_VENDORED on)
add_subdirectory(${SDL2TTF_DIR} ${CMAKE_BINARY_DIR}/thirdparty/sdl2ttf)
target_link_options(SDL2_ttf PRIVATE "-Wl,-z,max-page-size=16384")

set(SDL2MIXER_SAMPLES off)
set(SDL2MIXER_INSTALL off)
set(SDL2MIXER_OPUS off)
set(SDL2MIXER_FLAC off)
set(SDL2MIXER_MOD off)
set(SDL2MIXER_VORBIS_STB on)
set(SDL2MIXER_VENDORED on)
add_subdirectory(${SDL2MIXER_DIR} ${CMAKE_BINARY_DIR}/thirdparty/sdl2mixer)
target_link_options(SDL2_mixer PRIVATE "-Wl,-z,max-page-size=16384")

add_subdirectory(${JPEG_DIR} ${CMAKE_BINARY_DIR}/thirdparty/jpeg)
target_link_options(jpeg PRIVATE "-Wl,-z,max-page-size=16384")

set(LUASRC_DIR ${LUA_DIR}/src)
set(LUA_CODE
    ${LUASRC_DIR}/lapi.c  ${LUASRC_DIR}/lcode.c ${LUASRC_DIR}/lctype.c ${LUASRC_DIR}/ldebug.c ${LUASRC_DIR}/ldo.c
    ${LUASRC_DIR}/ldump.c ${LUASRC_DIR}/lfunc.c ${LUASRC_DIR}/lgc.c    ${LUASRC_DIR}/llex.c  ${LUASRC_DIR}/lmem.c
    ${LUASRC_DIR}/lobject.c ${LUASRC_DIR}/lopcodes.c ${LUASRC_DIR}/lparser.c ${LUASRC_DIR}/lstate.c ${LUASRC_DIR}/lstring.c
    ${LUASRC_DIR}/ltable.c ${LUASRC_DIR}/ltm.c  ${LUASRC_DIR}/lundump.c ${LUASRC_DIR}/lvm.c   ${LUASRC_DIR}/lzio.c
    ${LUASRC_DIR}/lauxlib.c ${LUASRC_DIR}/lbaselib.c ${LUASRC_DIR}/lcorolib.c ${LUASRC_DIR}/ldblib.c ${LUASRC_DIR}/liolib.c
    ${LUASRC_DIR}/lmathlib.c ${LUASRC_DIR}/loadlib.c ${LUASRC_DIR}/loslib.c  ${LUASRC_DIR}/lstrlib.c
    ${LUASRC_DIR}/ltablib.c ${LUASRC_DIR}/lutf8lib.c ${LUASRC_DIR}/linit.c
)
add_library(lua SHARED ${LUA_CODE})
target_compile_options(lua PRIVATE -D_FILE_OFFSET_BITS=64)
target_link_options(lua PRIVATE "-Wl,-z,max-page-size=16384")

# 上游做法（src/onsyuri_android/app/cpp/CMakeLists.txt:65-73）：bz2 tarball
# 无 CMakeLists —— 直接列 7 个源文件成库（SHARED，产出 libbz2.so）。
set(BZ2_CODE
    ${BZ2_DIR}/blocksort.c ${BZ2_DIR}/huffman.c ${BZ2_DIR}/crctable.c ${BZ2_DIR}/randtable.c
    ${BZ2_DIR}/compress.c  ${BZ2_DIR}/decompress.c ${BZ2_DIR}/bzlib.c
)
add_library(bz2 SHARED ${BZ2_CODE})
target_compile_options(bz2 PRIVATE -D_FILE_OFFSET_BITS=64)

# ---- onsyuri 核心（上游根 CMake 的 Android 分支 = add_library(onsyuri SHARED)）
set(CMAKE_SYSTEM_NAME Android)
include_directories(${BZ2_DIR} ${LUASRC_DIR})
add_subdirectory(${ONSYURI_DIR} ${CMAKE_BINARY_DIR}/onsyuri)
target_link_options(onsyuri PRIVATE "-Wl,-z,max-page-size=16384")

# ---- LusicGal 适配器 ------------------------------------------------------
add_library(lusicgal_onscripter SHARED lg_onscripter.cpp)
set_target_properties(lusicgal_onscripter PROPERTIES OUTPUT_NAME lusicgal_onscripter)
target_include_directories(lusicgal_onscripter PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/include)
# android = ANativeWindow_acquire/_release（set_surface）。
target_link_libraries(lusicgal_onscripter PRIVATE onsyuri SDL2 log android)
