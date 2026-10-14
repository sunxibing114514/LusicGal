#!/usr/bin/env bash
# 实验性（engines.yml continue-on-error）：ONScripter（OnscripterYuri）→ Android。
# 上游：YuriSizuku/OnscripterYuri @ 08f744b（CMake + vcpkg，自带 Android CI）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/third_party/upstream/onscripter-yuri"
[ -d "$SRC" ] || { echo "✗ 缺少源码：先运行 scripts/fetch_engines.sh"; exit 2; }
command -v cmake >/dev/null || { echo "✗ 需要 cmake"; exit 2; }

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  if [ -n "${ANDROID_HOME:-}" ]; then
    NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK（ANDROID_NDK_HOME / ANDROID_HOME/ndk/*）"; exit 2; }

ABI="${ANDROID_ABI:-arm64-v8a}"
BUILD="$ROOT/build/engines/onscripter-$ABI"
echo "== OnscripterYuri → $ABI（toolchain: $NDK）=="
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" -j"$(nproc)"
echo "✓ 构建目录：$BUILD（ABI 包装后并入 liblusicgal_onscripter.so）"
