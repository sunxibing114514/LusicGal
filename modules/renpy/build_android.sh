#!/usr/bin/env bash
# LusicGal Ren'Py 外板壳模块 staging（Route B，Android arm64）。
#
# 产出（modules/renpy/build-out/，参与 App 构建的 drop-in）：
#   java/rapt/**          rapt 的 renpyandroid Java（PythonSDLActivity/ResourceManager/
#                         AssetExtract/…，真实文件，不含 libsdl 符号链接）
#   jniLibs/arm64-v8a/librenpython.so
#   assets/private.mp3    tar{ main.py + renpy/ Python 树（无 common）}
#   assets/x-renpy/x-common/**   renpy/common/** 逐段 x- 前缀（loader 反向去前缀）
#
# org.libsdl.app Java 不在此 staging：由 plugins/lusicgal_engines 统一提供
#（SDL3 android-project 全套 + SDL2 兼容音频面；round-8 前模块自带副本曾致
#  :app:mergeDexRelease "defined multiple times"）。
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

# renpy-build 的 toolchain 任务直接 `unzip tars/android-ndk-r29-linux.zip`
# （不自己下载 NDK）—— 先把 zip 备进 tars/（CI 实证缺它必死）。
NDKZIP="$RB/tars/android-ndk-r29-linux.zip"
if [ ! -f "$NDKZIP" ]; then
  mkdir -p "$RB/tars"
  echo "  downloading android-ndk-r29-linux.zip → tars/（~700MB）"
  curl -L --fail -o "$NDKZIP" https://dl.google.com/android/repository/android-ndk-r29-linux.zip
fi

# renpybuild llvm() 的约定（run.py:42 实读）：CC=ccache clang-22、
# CXX=clang++-22、AR=llvm-ar-22 …（Ubuntu LLVM 版本化名，suffix="-22"），
# PATH 直接继承 build.sh 进程环境 —— NDK bin 只有裸名。预解包后全套
# 布符号链接 + PATH 注入（CI 实证 nasm.host 死于 "C compiler cannot
# create executables"；早前 -type f 漏掉符号链接形态的 bin/clang）。
NDKUN="$RB/tmp/cross.android"
if [ ! -d "$NDKUN/toolchains" ] && [ ! -d "$NDKUN/android-ndk-r29/toolchains" ]; then
  mkdir -p "$NDKUN"
  ( cd "$NDKUN" && unzip -q "$NDKZIP" )
fi
CLANG_BIN="$(find "$NDKUN" \( -type f -o -type l \) -path '*/prebuilt/*/bin/clang' 2>/dev/null | head -1 || true)"
[ -z "$CLANG_BIN" ] && CLANG_BIN="$(find "$NDKUN" \( -type f -o -type l \) -name clang 2>/dev/null | grep -E '/bin/clang$' | head -1 || true)"
if [ -n "$CLANG_BIN" ]; then
  NDKBIN="$(dirname "$CLANG_BIN")"
  for tool in clang clang++ llvm-ar llvm-ranlib llvm-strip llvm-nm \
              llvm-readelf llvm-install-name-tool; do
    [ -e "$NDKBIN/$tool" ] && [ ! -e "$NDKBIN/$tool-22" ] && \
      ln -s "$tool" "$NDKBIN/$tool-22"
  done
  export PATH="$NDKBIN:$PATH"
  echo "  llvm-22 套件 → $NDKBIN（PATH 注入）"
else
  echo "  ⚠ 未定位 NDK clang（find 输出如下，供诊断）"
  find "$NDKUN" -maxdepth 7 -name 'clang*' 2>/dev/null | head -10
fi

# renpy/gl2/live2dmodel.pyx 编译期 #include "Live2DCubismCore.h"（运行时
# 经 SDL_LoadObject 动态载入 Core —— live2dcsm.c 实读，无链接期依赖）。
# renpy-build 的 live2d 任务要求 tars/CubismSdkForNative-5-r.5.zip（本仓
# 不 vendor 官方 SDK），但缺 zip 时静默跳过 → 只补头文件：用 kirikiri 上
# 游树内 vendored 的 Core 头布进全部三态 install 目录
# （context.py 实读：host/cross.android-arm64_v8a/install.android-arm64_v8a）。
KRKR_HDR="$ROOT/third_party/upstream/kirikiri-next/cpp/plugins/cubism/Core/include/Live2DCubismCore.h"
if [ -f "$KRKR_HDR" ]; then
  for d in "$RB/tmp/host" "$RB/tmp/cross.android-arm64_v8a" \
           "$RB/tmp/install.android-arm64_v8a"; do
    mkdir -p "$d/cubism/Core/include"
    cp "$KRKR_HDR" "$d/cubism/Core/include/Live2DCubismCore.h"
  done
  echo "  Live2DCubismCore.h → 三态 install（编译期头，运行时 dlopen）"
else
  echo "  ⚠ 缺 kirikiri 树内 Cubism 头（fetch kirikiri-next 后重试）"
fi

( cd "$RB" && ./build.sh --platform android --arch arm64_v8a --stop renpython )

echo "== [2/4] 定位产物 =="
LIBREN="$(find "$RB/tmp" -name 'librenpython.so' -path '*android*' -type f | head -1 || true)"
[ -n "$LIBREN" ] || { echo "✗ 未找到 librenpython.so（build.sh --stop renpython 产物）"; exit 2; }
echo "  librenpython: $LIBREN"
# 注：org.libsdl.app Java 不再随本模块 staging —— 插件
# plugins/lusicgal_engines 是唯一提供方（SDL3 android-project 全套 +
# SDL2 兼容音频面，合并文件）。两处同 FQCN 会让 :app:mergeDexRelease
# 报 "defined multiple times"（CI round-7 实证）。

echo "== [3/4] staging =="
rm -rf "$OUT"
mkdir -p "$OUT/java/rapt" "$OUT/jniLibs/arm64-v8a" "$OUT/assets"

# rapt Java：真实文件。org/{libsdl,jnius} 是指向 renpy-build 构建产物的
# 符号链接 —— 排除后单独解析（cp -L 遇失效链接会直接失败）。
RAPT_JAVA="$RB/rapt/prototype/renpyandroid/src/main/java"
( cd "$RAPT_JAVA" \
  && tar cf - --exclude='./org/libsdl' --exclude='./org/jnius' . ) \
  | tar xf - -C "$OUT/java/rapt"

# rapt res：RenPyFileProvider 引 R.xml.file_paths —— 不随带 res 则模块
# 无 R 包，javac "package R does not exist"（CI 实证）。
RAPT_RES="$RB/rapt/prototype/renpyandroid/src/main/res"
if [ -d "$RAPT_RES/xml" ]; then
  mkdir -p "$OUT/res/xml"
  cp -R "$RAPT_RES/xml/." "$OUT/res/xml/"
  echo "  rapt res/xml staged"
else
  echo "⚠ 未找到 rapt res/xml（RenPyFileProvider 会编译失败）"
fi

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

# SDL org/libsdl Java：已并入插件（plugins/lusicgal_engines/android/src/main/
# java/org/libsdl/app），本模块经 implementation project(':lusicgal_engines')
# 编译引用 —— 不再本地 staging（round-8 修复）。

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
