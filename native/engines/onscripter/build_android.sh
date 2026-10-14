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
if [ ! -f "$SRC/thirdparty/port/SDL2-2.26.3/CMakeLists.txt" ]; then
  echo "== 拉取上游依赖（script/_fetch.sh）=="
  bash "$SRC/script/_fetch.sh" || echo "⚠ _fetch.sh 非零退出（可能是网络），继续"
fi

# 2) SDL Android 取窗补丁（幂等）。
bash "$ROOT/scripts/patch_sdl_android.sh" "$SRC/thirdparty/port/SDL2-2.26.3"

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
DEST="$ROOT/build/cores/onscripter/arm64-v8a"
mkdir -p "$DEST"
for lib in liblusicgal_onscripter.so libonsyuri.so libSDL2.so libSDL2_image.so \
           libSDL2_ttf.so libSDL2_mixer.so liblua.so libbz2.so libc++_shared.so; do
  found="$(find "$BUILD" -name "$lib" -type f | head -1 || true)"
  [ -n "$found" ] && cp "$found" "$DEST/" || echo "⚠ 未找到 $lib"
done
echo "✓ onscripter 核心构建完成：$DEST"
ls -la "$DEST" || true
