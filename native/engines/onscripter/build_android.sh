#!/usr/bin/env bash
# ONScripter（OnscripterYuri）核心 Android arm64 构建。
# 依赖上游 script/_fetch.sh 拉取的 SDL 栈 → patch_sdl_android.sh → CMake。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/third_party/upstream/onscripter-yuri"
[ -d "$SRC" ] || { echo "✗ 缺源码：scripts/fetch_engines.sh onscripter-yuri"; exit 2; }
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[ -z "$NDK" ] && [ -n "${ANDROID_HOME:-}" ] && NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK"; exit 2; }

# 1) 上游依赖（best-effort：已存在则跳过）。
#    上游 script/_fetch.sh 只「定义」fetch_* 函数并不自跑，且其 mkdir
#    前导用未引号的 $CMAKELISTS_PATH —— 空值时 mkdir /thirdparty 撞
#    Permission denied（CI round-7 日志实证，曾长期误判为网络问题）。
#    故显式 source + 按序调用，并设 CMAKELISTS_PATH=源码根。
if [ ! -f "$SRC/thirdparty/port/SDL2-2.26.3/CMakeLists.txt" ]; then
  echo "== 拉取上游依赖（_fetch.sh 函数显式调用）=="
  (
    export CMAKELISTS_PATH="$SRC"
    # shellcheck disable=SC1091
    source "$SRC/script/_fetch.sh"
    # github releases 优先（CI 可达性最好），余源殿后 —— 任一失败即中止
    # 子壳走兜底（外层 || 捕获），已下成功者保留供下次增量。
    fetch_sdl2
    fetch_sdl2_image
    fetch_sdl2_ttf
    fetch_sdl2_mixer
    fetch_bz2
    fetch_lua
    fetch_jpeg
  ) || echo "⚠ 依赖拉取非零退出（可能是网络），继续"
fi

# 2) SDL Android 取窗补丁（幂等）。
bash "$ROOT/scripts/patch_sdl_android.sh" "$SRC/thirdparty/port/SDL2-2.26.3"

# 2.5) external/jpeg 补齐：SDL_image 2.6.3 官方 release tarball 不含
#      external/* 子模块（本地 tar 实证 432 成员全无 jpeg）—— 而上游
#      onsyuri/本 adapter 的 JPEG_DIR 接法（add_subdirectory(external/jpeg)）
#      依赖它。按 SDL_image release-2.6.3 官方钉的子模块版本拉齐：
#      libsdl-org/jpeg @ bc27d050625f126dcba73ae5b731272de1a89dc1。
#      （历史上唯一活过的 onsyuri = 本地 NDK 实构建产物，彼时树里恰有
#      external/jpeg —— CI 的 tarball 路线从未成功过。）
JPEGM="$SRC/thirdparty/port/SDL2_image-2.6.3/external/jpeg"
if [ ! -f "$JPEGM/CMakeLists.txt" ]; then
  echo "== 补齐 external/jpeg（SDL_image 子模块 libsdl-org/jpeg@bc27d05）=="
  ok=""
  for i in 1 2 3 4 5; do
    rm -rf /tmp/lg-jpeg.tar.gz /tmp/jpeg-bc27d05*
    if curl -fsSL -o /tmp/lg-jpeg.tar.gz \
       https://github.com/libsdl-org/jpeg/archive/bc27d050625f126dcba73ae5b731272de1a89dc1.tar.gz \
       && tar zxf /tmp/lg-jpeg.tar.gz -C /tmp \
       && mkdir -p "$JPEGM" \
       && cp -r /tmp/jpeg-bc27d05*/. "$JPEGM/"; then
      ok=1; break
    fi
    echo "⚠ external/jpeg 拉取重试 $i/5"; sleep 10
  done
  rm -rf /tmp/lg-jpeg.tar.gz /tmp/jpeg-bc27d05*
  [ -n "$ok" ] || { echo "✗ external/jpeg 补齐失败（onsyuri 构建必败，主动红灯）"; exit 2; }
fi

# 3) CMake（NDK 工具链）。
BUILD="$ROOT/build/cores/onscripter/cmake"
mkdir -p "$BUILD"
cmake -G Ninja -S "$ROOT/native/engines/onscripter/adapter" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_shared \
  -DONSYURI_DIR="$SRC"
cmake --build "$BUILD" --target lusicgal_onscripter

# 4) 产物收集（含运行时依赖 libonsyuri.so / liblusicgal_onscripter.so）。
#    libjpeg.so：libonsyuri 的 DT_NEEDED 实证依赖（fetch_jpeg 构建的共享
#    版）—— 此前漏拷 → 现机 dlopen "library libjpeg.so not found"。
DEST="$ROOT/build/cores/onscripter/arm64-v8a"
mkdir -p "$DEST"
for lib in liblusicgal_onscripter.so libonsyuri.so libSDL2.so libSDL2_image.so \
           libSDL2_ttf.so libSDL2_mixer.so liblua.so libbz2.so libjpeg.so \
           libc++_shared.so; do
  found="$(find "$BUILD" -name "$lib" -type f | head -1 || true)"
  [ -n "$found" ] && cp "$found" "$DEST/" || echo "⚠ 未找到 $lib"
done
# libc++_shared.so（ANDROID_STL=c++_shared）不在构建树 —— 从 NDK sysroot 取。
if [ ! -f "$DEST/libc++_shared.so" ]; then
  STL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
  [ -f "$STL" ] && cp "$STL" "$DEST/" || echo "⚠ NDK 未找到 libc++_shared.so"
fi
echo "✓ onscripter 核心构建完成：$DEST"
ls -la "$DEST" || true
