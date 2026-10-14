#!/usr/bin/env bash
# 按 docs/ENGINE_NOTES.md 的 pin 表拉取上游引擎源码。
#
#   scripts/fetch_engines.sh                 # 浅拉取全部 18 个仓库
#   scripts/fetch_engines.sh onscripter-yuri # 只拉名称匹配的仓库
#   scripts/fetch_engines.sh --verify        # 仅用 GitHub API 校验 pin 可解析（CI）
#
# 目标：third_party/upstream/<name>（已 .gitignore，不入库）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/third_party/upstream"

# name|repo|pinned sha（调研时间点的默认分支 HEAD，见 docs/ENGINE_NOTES.md）
PINNED=(
  "kirikiri2|2468785842/krkr2|dca7264572a63e753c1b07ca7053513d1751ce70"
  "kirikiri-launcherc|xiaocongyu66/KiriKiri-LauncherC|df997312a8a3af9f9b529adb02f5b6cc7f5733d1"
  "kirikiri-next|reAAAq/KrKr2-Next|1abd1ed4e8aec7abd5d2524c3a9ad7886880602f"
  "onscripter-en|Galladite27/ONScripter-EN|3854ae86c19337991722059d2bed07cbcc847f6f"
  "onscripter-insani|insani-org/onscripter-insani|c64bd7dfbc6501e23560599240b906ba806f3705"
  "onscripter-ru|Serentty/onscripter-ru|360b733cfb3674557bf3465133779429a8ae67a9"
  "onscripter-ios|yeatse/ONScripter-iOS|67531a432cb13df514019bc53733bf235e8ed791"
  "onscripter-yuri|YuriSizuku/OnscripterYuri|08f744b31cc1907b66a15f0402e62321a131ed81"
  "onscripter-zero|zeromake/ONScripter-zero|66cd50004fa79a7cca679e3a445543f5ae7c0fd1"
  "renpy|renpy/renpy|80edccb125734ec9851b60b2f2b14d3f1f24eca6"
  "renios|chrismear/renios|8eed53054fb4361eecb09e3c0eb3e26fd76d0cf0"
  "renpy-build|renpy/renpy-build|612173094583e6fc2c5a92df438849757e0d3656"
  "rfvp|xmoezzz/rfvp|709b6ba2f9ae4ba9f34c56df82a044eb958ff329"
  "siglus-rs|xmoezzz/siglus_rs|5f358ef1360b0439e92aed2b749e8f25d8721954"
  "sena-rs|xmoezzz/sena-rs|f99db788421f2b724f1c57bc0a7c00debbd3624a"
  "xsystem35-sdl2|kichikuou/xsystem35-sdl2|741a96e40733ba2b51eac3f9b57022b7c5015073"
  "aether|AetherKiri/AetherKiri|a7453781f4a753a8d933e49aaa3c2960f1a823e7"
  "yukihub|xm486/YukiHub|35d12c0bb3d693646a3296bfe805561439b9f47c"
)

VERIFY=0
FILTERS=()
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    *) FILTERS+=("$arg") ;;
  esac
done

matches() {
  local name="$1"
  [ "${#FILTERS[@]}" -eq 0 ] && return 0
  local f
  for f in "${FILTERS[@]}"; do
    case "$name" in
      *"$f"*) return 0 ;;
    esac
  done
  return 1
}

if [ "$VERIFY" -eq 1 ]; then
  # ---- 校验模式：只确认 pin 指向的提交可解析（避免浅拉 renpy-build ~557MB）。
  AUTH=()
  if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
    AUTH=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}")
  fi
  fail=0
  for entry in "${PINNED[@]}"; do
    IFS='|' read -r name repo sha <<< "$entry"
    matches "$name" || continue
    code="$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
      "https://api.github.com/repos/$repo/commits/$sha")"
    if [ "$code" = "200" ]; then
      echo "OK   $name @ ${sha:0:12}"
    else
      echo "FAIL $name @ ${sha:0:12} (HTTP $code)"
      fail=1
    fi
  done
  if [ "$fail" -ne 0 ]; then
    echo "存在无法解析的 pin。" >&2
    exit 1
  fi
  echo "全部 pin 校验通过。"
  exit 0
fi

# ---- 拉取模式。
mkdir -p "$DEST"
fetch_one() {
  local name="$1" repo="$2" sha="$3"
  local dir="$DEST/$name"
  if [ -e "$dir/.lusicgal-pin" ] && [ "$(cat "$dir/.lusicgal-pin")" = "$sha" ]; then
    echo "OK   $name @ ${sha:0:12}（已缓存）"
    return 0
  fi
  echo "拉取 $name ($repo @ ${sha:0:12}) ..."
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "https://github.com/$repo.git"
  git -C "$dir" fetch -q --depth 1 origin "$sha"
  git -C "$dir" checkout -q FETCH_HEAD
  echo "$sha" > "$dir/.lusicgal-pin"
  echo "OK   $name @ ${sha:0:12}"
}

total=0
for entry in "${PINNED[@]}"; do
  IFS='|' read -r name repo sha <<< "$entry"
  matches "$name" || continue
  fetch_one "$name" "$repo" "$sha"
  total=$((total + 1))
done
echo ""
echo "完成：$total 个仓库已就位（third_party/upstream/）。"
