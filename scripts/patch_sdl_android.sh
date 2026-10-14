#!/usr/bin/env bash
# SDL2 Android 取窗注入补丁（onscripter / xsystem35 共用）。
#
# SDL2 Android 视频驱动不支持 SDL_CreateWindowFrom（实测 2.26/2.32 均无），
# 官方路径是 Java SDLActivity.getNativeSurface() → JNI
# Android_JNI_GetNativeWindow()。本补丁让后者先咨询适配器导出的
# LG_SDL_Window_Override()（lg_<id>_engine_set_surface 注入的 ANativeWindow）。
# 幂等：已含 LG_SDL_Window_Override 即跳过。
#
# 用法：patch_sdl_android.sh <SDL2 源码目录>
set -euo pipefail
SDL_SRC="${1:?用法：patch_sdl_android.sh <SDL2 源码目录>}"
F="$SDL_SRC/src/core/android/SDL_android.c"
[ -f "$F" ] || { echo "✗ 未找到 $F"; exit 2; }

grep -q 'LG_SDL_Window_Override' "$F" && { echo "OK   SDL_android.c 已打补丁（跳过）"; exit 0; }

python3 - "$F" <<'PYEOF'
import sys
f = sys.argv[1]
src = open(f, encoding="utf-8").read()

anchor = "ANativeWindow* Android_JNI_GetNativeWindow(void)"
if anchor not in src:
    print("✗ 锚文本未命中（SDL 版本漂移？）")
    sys.exit(1)

# 在函数体开头插入宿主窗口覆盖逻辑。
old = """ANativeWindow* Android_JNI_GetNativeWindow(void)
{
    ANativeWindow *anw;*/
"""
# 注：不同版本函数体首行可能带注释，逐行探测真实函数头。
import re
m = re.search(
    r"ANativeWindow\* Android_JNI_GetNativeWindow\(void\)\s*\{",
    src,
)
if not m:
    print("✗ 函数头未命中")
    sys.exit(1)
insert_at = m.end()
injection = """
    /* LusicGal 宿主表面注入（docs/ARCHITECTURE.md）：
     * 非 SDLActivity 环境下由引擎适配器（lg_<id>_engine_set_surface）
     * 提供窗口；返回 NULL 则回退官方 Java 路径。 */
    {
        extern void* LG_SDL_Window_Override(void);
        void* lg_window = LG_SDL_Window_Override();
        if (lg_window) {
            return (ANativeWindow*)lg_window;
        }
    }
"""
src = src[:insert_at] + injection + src[insert_at:]
open(f, "w", encoding="utf-8").write(src)
print("OK   SDL_android.c 取窗注入补丁已应用")
PYEOF
echo "✓ 补丁完成：Android_JNI_GetNativeWindow 将优先使用宿主注入窗口。"
