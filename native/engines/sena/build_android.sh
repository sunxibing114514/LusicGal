#!/usr/bin/env bash
# 实验性（engines.yml continue-on-error）：sena-rs（pal-vm）→ Android aarch64。
# cargo check 交叉目标：验证 Rust 核心在 Android 目标可编译。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/third_party/upstream/sena-rs"
[ -d "$SRC" ] || { echo "✗ 缺少源码：先运行 scripts/fetch_engines.sh"; exit 2; }
command -v cargo >/dev/null || { echo "✗ 需要 Rust 工具链"; exit 2; }

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  if [ -n "${ANDROID_HOME:-}" ]; then
    NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK"; exit 2; }

TARGET="${ANDROID_TARGET:-aarch64-linux-android}"
PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$PREBUILT" ]; then
  # 其他宿主命名差异（如 macOS）兜底。
  PREBUILT="$(dirname "$(dirname "$(find "$NDK/toolchains/llvm" -name clang -type f | head -1)")")"
fi
export ANDROID_NDK_HOME="$NDK"
export PATH="$PREBUILT/bin:$PATH"
export CC_aarch64_linux_android="$PREBUILT/bin/aarch64-linux-android24-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$PREBUILT/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$PREBUILT/bin/aarch64-linux-android24-clang"
rustup target add "$TARGET"
echo "== sena-rs → $TARGET（NDK: $NDK）=="
cargo check --manifest-path "$SRC/Cargo.toml" -p pal-vm --target "$TARGET"
echo "✓ sena-rs Android 目标检查通过"
