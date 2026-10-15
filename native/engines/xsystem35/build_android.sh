#!/usr/bin/env bash
# System35（xsystem35-sdl2）核心 Android arm64 构建。
# FetchContent 拉 SDL2（构建前打取窗补丁）/freetype/SDL_mixer。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/third_party/upstream/xsystem35-sdl2"
[ -d "$SRC" ] || { echo "✗ 缺源码：scripts/fetch_engines.sh xsystem35-sdl2"; exit 2; }
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[ -z "$NDK" ] && [ -n "${ANDROID_HOME:-}" ] && NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK"; exit 2; }

BUILD="$ROOT/build/cores/xsystem35/cmake"
mkdir -p "$BUILD"
cmake -G Ninja -S "$ROOT/native/engines/xsystem35/adapter" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_shared \
  -DXS35_DIR="$SRC"
cmake --build "$BUILD" --target lusicgal_xsystem35

DEST="$ROOT/build/cores/xsystem35/arm64-v8a"
mkdir -p "$DEST"
# freetype 为静态链入（NDK FetchContent 默认静态）——无 libfreetype.so 产物。
# libwebp/libsharpyuv 为 xsystem35 android 分支自带的 SHARED 依赖（NEEDED）。
for lib in liblusicgal_xsystem35.so libxsystem35.so libSDL2.so \
           libSDL2_mixer.so libwebp.so libsharpyuv.so libc++_shared.so; do
  found="$(find "$BUILD" -name "$lib" -type f | head -1 || true)"
  [ -n "$found" ] && cp "$found" "$DEST/" || echo "⚠ 未找到 $lib"
done
# libc++_shared.so（ANDROID_STL=c++_shared）不在构建树 —— 从 NDK sysroot 取。
if [ ! -f "$DEST/libc++_shared.so" ]; then
  STL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
  [ -f "$STL" ] && cp "$STL" "$DEST/" || echo "⚠ NDK 未找到 libc++_shared.so"
fi
echo "✓ xsystem35 核心构建完成：$DEST"
ls -la "$DEST" || true
