#!/usr/bin/env bash
# Kirikiri（KrKr2-Next）核心 Android arm64 构建（实验性，CI continue-on-error）。
# 依赖：vcpkg（VCPKG_ROOT）+ NDK。补丁：scripts/patch_engines.sh kirikiri-next
# 注入 krkr_SetAndroidContext / krkr_SetNativeWindow。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/third_party/upstream/kirikiri-next"
[ -d "$SRC" ] || { echo "✗ 缺源码：scripts/fetch_engines.sh kirikiri-next"; exit 2; }
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[ -z "$NDK" ] && [ -n "${ANDROID_HOME:-}" ] && NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK"; exit 2; }

# vcpkg：仓库自带子目录则用之，否则要求 VCPKG_ROOT。
VCPKG="${VCPKG_ROOT:-}"
if [ -z "$VCPKG" ] && [ -d "$SRC/vcpkg/vcpkg" ]; then VCPKG="$SRC/vcpkg/vcpkg"; fi
[ -n "$VCPKG" ] && [ -x "$VCPKG/vcpkg" ] || {
  echo "✗ 未找到 vcpkg（VCPKG_ROOT 或 $SRC/vcpkg/vcpkg）"; exit 2;
}
export VCPKG_ROOT="$VCPKG"

# 上游补丁（幂等）：krkr_SetAndroidContext / krkr_SetNativeWindow。
bash "$ROOT/scripts/patch_engines.sh" kirikiri-next

BUILD="$ROOT/build/cores/kirikiri/cmake"
mkdir -p "$BUILD"
# 入口工具链 = vcpkg.cmake（manifest 模式，链挂 NDK）—— 见适配器
# CMakeLists 的工具链拓扑说明（NDK 工具链经 VCPKG_CHAINLOAD 注入）。
# krkr2 根要求 CMake ≥3.28。
cmake -G Ninja -S "$ROOT/native/engines/kirikiri/adapter" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_shared \
  -DKRKR2_DIR="$SRC" \
  -DANDROID_NDK_HOME="$NDK" \
  -DVCPKG_ROOT="$VCPKG" \
  -DVCPKG_TARGET_ANDROID=ON \
  -DVCPKG_TARGET_TRIPLET=arm64-android
cmake --build "$BUILD" --target lusicgal_kirikiri

DEST="$ROOT/build/cores/kirikiri/arm64-v8a"
mkdir -p "$DEST"
for lib in liblusicgal_kirikiri.so libengine_api.so libc++_shared.so; do
  found="$(find "$BUILD" -name "$lib" -type f | head -1 || true)"
  [ -n "$found" ] && cp "$found" "$DEST/" || echo "⚠ 未找到 $lib"
done
# libc++_shared.so（ANDROID_STL=c++_shared）不在构建树 —— 从 NDK sysroot 取。
if [ ! -f "$DEST/libc++_shared.so" ]; then
  STL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
  [ -f "$STL" ] && cp "$STL" "$DEST/" || echo "⚠ NDK 未找到 libc++_shared.so"
fi
echo "✓ kirikiri 核心构建完成：$DEST"
ls -la "$DEST" || true
