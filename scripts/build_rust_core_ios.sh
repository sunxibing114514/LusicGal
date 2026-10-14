#!/usr/bin/env bash
# Rust 核心 iOS 构建：壳 crate（native/rust/shells/<id>）→ liblusicgal_<id>.a。
#
#   scripts/build_rust_core_ios.sh sena           # aarch64-apple-ios release .a
#   scripts/build_rust_core_ios.sh rfvp siglus artemis
#
# 前置：scripts/fetch_engines.sh 已拉上游；Rust stable + Xcode（macOS 主机/CI）。
# 产物并入 pod：plugins/lusicgal_engines/ios（vendored_libraries 注入说明见
# docs/BUILD.md）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/build/cores}"
TARGET="aarch64-apple-ios"

case_map() {
  case "$1" in
    sena)    echo "sena|sena-rs" ;;
    rfvp)    echo "rfvp|rfvp" ;;
    siglus)  echo "siglus|siglus-rs" ;;
    artemis) echo "artemis|art3m1s-core" ;;
    *) echo "✗ 未知 Rust 核心：$1" >&2; return 2 ;;
  esac
}

[ $# -ge 1 ] || { echo "用法：build_rust_core_ios.sh <sena|rfvp|siglus|artemis>…" >&2; exit 2; }

command -v cargo >/dev/null || { echo "✗ 需要 Rust 工具链"; exit 2; }
command -v xcrun >/dev/null || { echo "✗ 需要 Xcode 工具链（macOS 主机/CI）"; exit 2; }
rustup target add "$TARGET" >/dev/null

# iOS 静态库由 Xcode clang 链接；wgpu（rfvp/siglus Android 路径）在 iOS 用
# Metal 后端 —— 壳的 feature 由各 Cargo.toml 自身决定（与 Android 共用）。
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-14.0}"

for id in "$@"; do
  IFS='|' read -r shell upstream <<< "$(case_map "$id")"
  SRC="$ROOT/third_party/upstream/$upstream"
  [ -d "$SRC" ] || { echo "✗ 缺少上游源码（先 scripts/fetch_engines.sh $upstream）：$id"; exit 2; }
  echo "== $id：壳构建（上游 $upstream，$TARGET）=="

  bash "$ROOT/scripts/patch_engines.sh" "$upstream" >/dev/null || {
    echo "✗ patch_engines.sh $upstream 失败"; exit 2; }

  MANIFEST="$ROOT/native/rust/shells/$shell/Cargo.toml"
  [ -f "$MANIFEST" ] || { echo "✗ 缺壳 crate：$MANIFEST"; exit 2; }
  cargo build --release --manifest-path "$MANIFEST" \
    -p "lusicgal_${id}_ffi" --target "$TARGET"

  BUILT="$ROOT/native/rust/shells/$shell/target/$TARGET/release/liblusicgal_${id}_ffi.a"
  DEST="$OUT_DIR/$id/ios"
  mkdir -p "$DEST"
  cp "$BUILT" "$DEST/liblusicgal_${id}.a"
  echo "✓ $id → $DEST/liblusicgal_${id}.a ($(du -h "$DEST/liblusicgal_${id}.a" | cut -f1))"
done
echo "完成。产物目录：$OUT_DIR（iOS 并入 pod 的步骤见 plugins/lusicgal_engines/ios/lusicgal_engines.podspec 注释）。"
