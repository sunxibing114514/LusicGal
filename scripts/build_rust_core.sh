#!/usr/bin/env bash
# Rust 核心统一构建：壳 crate（native/rust/shells/<id>）→ liblusicgal_<id>.so。
#
#   scripts/build_rust_core.sh sena           # Android arm64 release .so
#   scripts/build_rust_core.sh rfvp siglus artemis
#   OUT_DIR=... scripts/build_rust_core.sh sena   # 产物复制到 OUT_DIR/<id>/
#
# 前置：scripts/fetch_engines.sh 已拉上游；Rust stable + NDK。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/build/cores}"

# id → (shell crate, 上游 fetch 名, 上游目录名)
case_map() {
  case "$1" in
    sena)    echo "sena|sena-rs" ;;
    rfvp)    echo "rfvp|rfvp" ;;
    siglus)  echo "siglus|siglus-rs" ;;
    artemis) echo "artemis|art3m1s-core" ;;
    *) echo "✗ 未知 Rust 核心：$1" >&2; return 2 ;;
  esac
}

[ $# -ge 1 ] || { echo "用法：build_rust_core.sh <sena|rfvp|siglus|artemis>…" >&2; exit 2; }

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  if [ -n "${ANDROID_HOME:-}" ]; then
    NDK="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "✗ 未找到 Android NDK"; exit 2; }

TARGET="${ANDROID_TARGET:-aarch64-linux-android}"
# API26（Android 8）而非 24：cpal/oboe 音频栈链接 -laudio/-laaudio，
# 两者在 API24 sysroot 缺失（本地实测 "unable to find library -laaudio"）。
API="${ANDROID_API:-26}"
PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$PREBUILT" ]; then
  PREBUILT="$(dirname "$(dirname "$(find "$NDK/toolchains/llvm" -name clang -type f | head -1)")")"
fi
export ANDROID_NDK_HOME="$NDK"
export PATH="$PREBUILT/bin:$PATH"
export CC_aarch64_linux_android="$PREBUILT/bin/aarch64-linux-android${API}-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$PREBUILT/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$PREBUILT/bin/aarch64-linux-android${API}-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="${CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS:-} -C link-arg=-landroid"
command -v cargo >/dev/null || { echo "✗ 需要 Rust 工具链"; exit 2; }
rustup target add "$TARGET" >/dev/null

for id in "$@"; do
  IFS='|' read -r shell upstream <<< "$(case_map "$id")"
  SRC="$ROOT/third_party/upstream/$upstream"
  [ -d "$SRC" ] || { echo "✗ 缺少上游源码（先 scripts/fetch_engines.sh $upstream）：$id"; exit 2; }
  echo "== $id：壳构建（上游 $upstream，$TARGET，NDK $(basename "$NDK")）=="

  # 存档注入补丁（幂等）。
  bash "$ROOT/scripts/patch_engines.sh" "$upstream" >/dev/null || {
    echo "✗ patch_engines.sh $upstream 失败"; exit 2; }

  MANIFEST="$ROOT/native/rust/shells/$shell/Cargo.toml"
  [ -f "$MANIFEST" ] || { echo "✗ 缺壳 crate：$MANIFEST"; exit 2; }
  cargo build --release --manifest-path "$MANIFEST" \
    -p "lusicgal_${id}_ffi" --target "$TARGET"

  BUILT="$ROOT/native/rust/shells/$shell/target/$TARGET/release/liblusicgal_${id}_ffi.so"
  DEST="$OUT_DIR/$id/arm64-v8a"
  mkdir -p "$DEST"
  cp "$BUILT" "$DEST/liblusicgal_${id}.so"
  echo "✓ $id → $DEST/liblusicgal_${id}.so ($(du -h "$DEST/liblusicgal_${id}.so" | cut -f1))"
done
echo "完成。产物目录：$OUT_DIR"
