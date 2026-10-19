#!/usr/bin/env bash
# Rust 四壳本地检查（无 NDK/无 Android 工具链也可跑）：
#
#   scripts/rust_local_check.sh              # 四壳 host + aarch64-android check
#   scripts/rust_local_check.sh sena rfvp    # 只查指定壳
#
# 原理：壳只消费上游的 no_mangle C 符号（extern "C" 声明），不 import 其
# Rust item —— 临时剥离 Cargo.toml 的上游 path 依赖后，壳可独立编译检查。
# 这覆盖壳的全部自有代码（ABI 导出/线程模型/输入解析/cfg 分支），
# 不覆盖上游 crate 本身（那需要 CI 全量构建）。
#
# 前置：PATH 有 cargo + rustc；aarch64-linux-android rust-std（可选，
# 缺失时跳过 android 目标并提示）。
#
# 变更面：临时改 Cargo.toml（结束即 git restore）；
# Cargo.lock 若生成会在结束时删除（不入库）。CARGO_TARGET_DIR 默认 /tmp。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/rust-target}"

SHELLS=("$@")
[ ${#SHELLS[@]} -eq 0 ] && SHELLS=(sena rfvp siglus artemis)

command -v cargo >/dev/null || { echo "✗ 需要 cargo"; exit 2; }

# 上游依赖块探测：从 "[dependencies.<name>]" 行起删到下一个 "[" 节前。
strip_upstream() {
  python3 - "$1" <<'PYEOF'
import re, sys
p = sys.argv[1]
src = open(p, encoding="utf-8").read()
# 删除 [dependencies.pal-vm]/[dependencies.rfvp]/[dependencies.game_launcher]/[dependencies.art3m1s-core]
pat = re.compile(
    r'\n#(?!\[)[^\n]*\n+'                       # 前导注释行（含空行）
    r'|(?=\n)\n+\[dependencies\.(?:pal-vm|rfvp|game_launcher|art3m1s-core)\][^\[]*',
    re.X)
# 上面组合不可靠 —— 逐块处理更稳：
blocks = src.split("\n[")
out = blocks[0]
removed = False
for b in blocks[1:]:
    name = b.split("]", 1)[0]
    if name.startswith("dependencies.") and name.split(".", 1)[1] in (
            "pal-vm", "rfvp", "game_launcher", "art3m1s-core"):
        removed = True
        continue  # 丢弃该块
    out += "\n[" + b
# 顺带丢弃紧邻的注释段（“# 上游核心”说明行）：
out = re.sub(r"\n# 上游核心（[^\n]*\n(# [^\n]*\n)*", "\n", out)
open(p, "w", encoding="utf-8").write(out)
if not removed:
    print(f"warn: {p}: 未发现上游依赖块（可能已剥离）", file=sys.stderr)
PYEOF
}

ANDROID_OK=1
if [ -d "$(rustc --print sysroot 2>/dev/null || true)/lib/rustlib/aarch64-linux-android" ]; then
  :
else
  ANDROID_OK=0
  echo "!! 未装 aarch64-linux-android rust-std —— 跳过 android 目标检查"
fi

FAIL=0
for s in "${SHELLS[@]}"; do
  d="$ROOT/native/rust/shells/$s"
  [ -f "$d/Cargo.toml" ] || { echo "✗ 未知壳：$s"; FAIL=1; continue; }
  echo "== $s：剥离上游依赖 → host check"
  strip_upstream "$d/Cargo.toml"
  lock="$d/Cargo.lock"
  if ( cd "$d" && cargo check 2>&1 | grep -E '^(error|warning: unused)' ) ; then
    echo "✗ $s host check 有诊断输出（见上）"
    ( cd "$d" && cargo check >/dev/null 2>&1 ) || FAIL=1
  else
    ( cd "$d" && cargo check >/dev/null 2>&1 ) || FAIL=1 \
      && echo "OK   $s host check"
  fi
  if [ "$ANDROID_OK" = 1 ] && [ "$FAIL" = 0 ]; then
    echo "== $s：aarch64-linux-android check（cfg(android) 路径 + extern 块）"
    ( cd "$d" && cargo check --target aarch64-linux-android >/dev/null 2>&1 ) \
      && echo "OK   $s android check" \
      || { echo "✗ $s android check 失败"; FAIL=1; }
  fi
  git -C "$ROOT" checkout -- "$d/Cargo.toml"
  rm -f "$lock"
  [ "$FAIL" = 1 ] && break
done

# cbridge 顺带全检（无上游依赖）。
if [ "$FAIL" = 0 ]; then
  echo "== cbridge（含测试）"
  ( cd "$ROOT/native/rust/cbridge" && cargo check --tests >/dev/null 2>&1 ) \
    && echo "OK   cbridge check" || { echo "✗ cbridge check 失败"; FAIL=1; }
  rm -f "$ROOT/native/rust/cbridge/Cargo.lock"
fi

[ "$FAIL" = 0 ] && echo "全部通过。" || { echo "存在失败项。"; exit 1; }
