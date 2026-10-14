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
rustup target add "$TARGET"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
echo "== sena-rs → $TARGET（NDK: $NDK）=="
cargo check --manifest-path "$SRC/Cargo.toml" -p pal-vm --target "$TARGET"
echo "✓ sena-rs Android 目标检查通过"
