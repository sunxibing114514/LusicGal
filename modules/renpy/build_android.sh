#!/usr/bin/env bash
# LusicGal Ren'Py 外板壳模块 staging（Route B，Android arm64）。
#
# 产出（modules/renpy/build-out/，参与 App 构建的 drop-in）：
#   java/rapt/**          rapt 的 renpyandroid Java（PythonSDLActivity/ResourceManager/
#                         AssetExtract/…，真实文件，不含 libsdl 符号链接）
#   java/sdl/**           SDL3 android-project Java（SDLActivity 等）
#   jniLibs/arm64-v8a/librenpython.so
#   assets/private.mp3    tar{ main.py + renpy/ Python 树（无 common）}
#   assets/x-renpy/x-common/**   renpy/common/** 逐段 x- 前缀（loader 反向去前缀）
#
# 依据（renpy-build @ 6121730 精读）：
#   tasks/renpython.py android 链接产物 = librenpython.so（--stop renpython）
#   rapt/buildlib/rapt/build.py::split_renpy / make_assets_tree 的目录语义
#   rapt/prototype/renpyandroid/src/main/java/.../libsdl → SDL3 构建产物
#
# 重（网络 + 编译）：SDL3/Python/ffmpeg 全静态 —— CI 走手动实验 job。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RB="$ROOT/third_party/upstream/renpy-build"       # scripts/fetch_engines.sh renpy-build
RENPY="$ROOT/third_party/upstream/renpy"           # scripts/fetch_engines.sh renpy
OUT="$ROOT/modules/renpy/build-out"

[ -d "$RB" ] || { echo "✗ 缺 renpy-build 源码：scripts/fetch_engines.sh renpy-build"; exit 2; }
[ -d "$RENPY" ] || { echo "✗ 缺 renpy 源码：scripts/fetch_engines.sh renpy"; exit 2; }

echo "== [1/4] librenpython.so（renpy-build，Android arm64，重）=="
# renpy-build 把 renpy 运行时树作为 git 子模块（$RB/renpy）引用；本仓库
# 按 pin 分开浅拉（third_party/upstream/renpy）且不初始化子模块 —— 用
# 软链拼回上游期望的布局（CI 实证：缺它时 uv 报 "Project directory
# `renpy` does not exist"）。
if [ ! -f "$RB/renpy/renpy/main.py" ]; then
  rm -rf "$RB/renpy"
  ln -s "$RENPY" "$RB/renpy"
  echo "  linked $RB/renpy -> $RENPY"
fi
( cd "$RB" && ./build.sh --platform android --arch arm64_v8a --stop renpython )

echo "== [2/4] 定位产物 =="
LIBREN="$(find "$RB/tmp" -name 'librenpython.so' -path '*android*' -type f | head -1 || true)"
[ -n "$LIBREN" ] || { echo "✗ 未找到 librenpython.so（build.sh --stop renpython 产物）"; exit 2; }
SDL_JAVA="$(find "$RB/tmp" -type d -path '*SDL3*android-project/app/src/main/java' | head -1 || true)"
[ -n "$SDL_JAVA" ] || SDL_JAVA="$(find "$RB/tmp" -type d -path '*SDL3-*/android-project/app/src/main/java' | head -1 || true)"
[ -n "$SDL_JAVA" ] || { echo "✗ 未找到 SDL3 android Java（tmp/source/SDL3-*/android-project/...）"; exit 2; }
echo "  librenpython: $LIBREN"
echo "  SDL3 java:    $SDL_JAVA"

echo "== [3/4] staging =="
rm -rf "$OUT"
mkdir -p "$OUT/java/rapt" "$OUT/java/sdl" "$OUT/jniLibs/arm64-v8a" "$OUT/assets"

# rapt Java：真实文件。org/{libsdl,jnius} 是指向 renpy-build 构建产物的
# 符号链接 —— 排除后单独解析（cp -L 遇失效链接会直接失败）。
RAPT_JAVA="$RB/rapt/prototype/renpyandroid/src/main/java"
( cd "$RAPT_JAVA" \
  && tar cf - --exclude='./org/libsdl' --exclude='./org/jnius' . ) \
  | tar xf - -C "$OUT/java/rapt"

resolve_link() {
  # $1=符号链接路径；输出解析后的绝对路径（存在则目录校验通过）。
  [ -L "$1" ] || return 1
  local resolved
  resolved="$(readlink -f "$1" 2>/dev/null || true)"
  [ -n "$resolved" ] && [ -d "$resolved" ] || return 1
  echo "$resolved"
}

# jnius（pyjnius Java）：renpy 在 Android 的 autoclass 依赖。
JNIUS="$(resolve_link "$RAPT_JAVA/org/jnius" || true)"
if [ -z "$JNIUS" ]; then
  JNIUS="$(find "$RB/tmp" -type d -name jnius -path '*pyjnius*' 2>/dev/null | head -1 || true)"
fi
if [ -n "$JNIUS" ]; then
  cp -R "$JNIUS/." "$OUT/java/rapt/org/jnius/"
  echo "  jnius java: $JNIUS"
else
  echo "⚠ 未找到 pyjnius Java（autoclass 受限）"
fi

# SDL android Java：优先 rapt 符号链接（上游意图），回退 tmp 里的 SDL3 源码树。
SDL_RESOLVED="$(resolve_link "$RAPT_JAVA/org/libsdl" || true)"
if [ -n "$SDL_RESOLVED" ]; then
  SDL_JAVA="$SDL_RESOLVED"
fi
echo "  SDL java:   $SDL_JAVA"
cp -R "$SDL_JAVA/." "$OUT/java/sdl/."

cp "$LIBREN" "$OUT/jniLibs/arm64-v8a/librenpython.so"

# private.mp3 = tar{ main.py + renpy/ Python 树（无 common，无 pycache）}
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"
cp "$ROOT/modules/renpy/src/main/python/main.py" "$STAGE/main.py"
tar cf "$OUT/assets/private.mp3" \
    --exclude='common' --exclude='__pycache__' --exclude='*.pyc' \
    -C "$RENPY" renpy \
    -C "$STAGE" main.py
echo "  private.mp3: $(du -h "$OUT/assets/private.mp3" | cut -f1)"

# assets/x-renpy/x-common/**：renpy/common 逐段 x- 前缀（make_assets_tree 语义）
python3 - "$RENPY/renpy/common" "$OUT/assets" <<'PYEOF'
import os, sys, shutil

src_root, dst_root = sys.argv[1], sys.argv[2]
count = 0
for base, dirs, files in os.walk(src_root):
    rel = os.path.relpath(base, src_root)
    parts = [] if rel == "." else rel.split(os.sep)
    xparts = ["x-" + p for p in parts]
    dst_dir = os.path.join(dst_root, "x-renpy", "x-common", *xparts)
    os.makedirs(dst_dir, exist_ok=True)
    for fn in files:
        shutil.copy2(os.path.join(base, fn), os.path.join(dst_dir, "x-" + fn))
        count += 1
print(f"OK   x-common staged: {count} files")
if count == 0:
    sys.exit(1)
PYEOF

touch "$OUT/.ready"
echo "== [4/4] staging 完成（modules/renpy/build-out）=="
du -sh "$OUT"/* || true
echo
echo "下一步：App 构建时 scripts/patch_platform.py 自动 include ':module-renpy'。"
