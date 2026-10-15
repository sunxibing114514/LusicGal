#!/usr/bin/env bash
# SDL2 Android 源码补丁（onscripter / xsystem35 共用），多 hunk 各自幂等：
#
# 1) 取窗注入（注册回调形态）：SDL2 Android 视频驱动不支持
#    SDL_CreateWindowFrom（实测 2.26/2.32 均无），官方路径是 Java
#    SDLActivity.getNativeSurface() → JNI Android_JNI_GetNativeWindow()。
#    本补丁让 SDL 导出 LG_SDL_SetWindowOverride(fn)：适配器（
#    lg_<id>_engine_set_surface）正向注册回调；取窗时先咨询，未注册/NULL
#    则回退官方 Java 路径。
#    为什么不反向 extern（旧版做法）：适配器 .so 是 SDL 的"加载者"，
#    SDL 重定位在先 —— bionic 无惰性绑定，弱未定义符号会永久解析为 NULL；
#    且 -Wl,--no-undefined 下 SDL 直接链不过（本地 NDK 实构建发现）。
# 2) NDK r27 兼容：r27 sysroot 把 ALooper_pollAll 标记 unavailable
#    （硬错）。SDL_androidsensor.c:174 用的正是它 —— 与 SDL3 的演进一致，
#    换成签名兼容、单次轮询语义相同的 ALooper_pollOnce。
#
# 用法：patch_sdl_android.sh <SDL2 源码目录>
set -euo pipefail
SDL_SRC="${1:?用法：patch_sdl_android.sh <SDL2 源码目录>}"

# ---- hunk 1：取窗注入（注册回调）------------------------------------------
F="$SDL_SRC/src/core/android/SDL_android.c"
[ -f "$F" ] || { echo "✗ 未找到 $F"; exit 2; }

python3 - "$F" <<'PYEOF'
import sys, re
f = sys.argv[1]
src = open(f, encoding="utf-8").read()

SETTER_DEF = """/* LusicGal 宿主窗口注入注册（docs/ARCHITECTURE.md）：
 * 适配器（lg_<id>_engine_set_surface）正向调用本 setter 注册回调；
 * 未注册时 Android_JNI_GetNativeWindow 走官方 Java 路径。
 * visibility("default")：SDL 全库 -fvisibility=hidden，不加则导不出
 * （本地 NDK 实构建发现：.o 全局 T、.so 动态表 0）。 */
static void* (*LG_Window_Override_Impl)(void) = NULL;
__attribute__((visibility("default")))
void LG_SDL_SetWindowOverride(void* (*fn)(void)) { LG_Window_Override_Impl = fn; }

"""
CALL_NEW = """    /* LusicGal 宿主表面注入：适配器经 LG_SDL_SetWindowOverride 注册回调。 */
    if (LG_Window_Override_Impl) {
        void* lg_window = LG_Window_Override_Impl();
        if (lg_window) {
            return (ANativeWindow*)lg_window;
        }
    }
"""
CALL_OLD = """    /* LusicGal 宿主表面注入（docs/ARCHITECTURE.md）：
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

if 'LG_SDL_SetWindowOverride(void* (*fn)(void)) __attribute__((visibility("default")))' in src or \
   '__attribute__((visibility("default")))\nvoid LG_SDL_SetWindowOverride' in src:
    print("OK   SDL_android.c 取窗注入（注册回调）已在（跳过）")
    sys.exit(0)

# 升级路径 2：v2 setter（无 visibility 属性）→ 补属性。
OLD_SETTER = "void LG_SDL_SetWindowOverride(void* (*fn)(void)) { LG_Window_Override_Impl = fn; }"
NEW_SETTER = ('__attribute__((visibility("default")))\n'
              "void LG_SDL_SetWindowOverride(void* (*fn)(void)) { LG_Window_Override_Impl = fn; }")
if OLD_SETTER in src:
    src = src.replace(OLD_SETTER, NEW_SETTER, 1)
    open(f, "w", encoding="utf-8").write(src)
    print("OK   SDL_android.c setter 已补 visibility 属性")
    sys.exit(0)

m = re.search(r"ANativeWindow\s*\*\s*Android_JNI_GetNativeWindow\(void\)\s*\{", src)
if not m:
    print("✗ 函数头未命中（SDL 版本漂移？）")
    sys.exit(1)

if CALL_OLD in src:
    # 旧版（反向 extern）就地升级为注册回调形态。
    src = src.replace(CALL_OLD, CALL_NEW)
    src = src[:m.start()] + SETTER_DEF + src[m.start():]
    print("OK   SDL_android.c 取窗注入已升级：注册回调形态")
else:
    insert_at = m.end()
    src = src[:m.start()] + SETTER_DEF + src[m.start():]
    m2 = re.search(r"ANativeWindow\s*\*\s*Android_JNI_GetNativeWindow\(void\)\s*\{", src)
    src = src[:m2.end()] + CALL_NEW + src[m2.end():]
    print("OK   SDL_android.c 取窗注入（注册回调）已应用")

open(f, "w", encoding="utf-8").write(src)
PYEOF

# ---- hunk 2：NDK r27 ALooper_pollAll → pollOnce ----------------------------
# SDL 2.32+ 上游已自带 pollOnce（含空格风格变体）——已含即 OK。
S="$SDL_SRC/src/sensor/android/SDL_androidsensor.c"
if [ -f "$S" ]; then
  if grep -q 'ALooper_pollOnce' "$S"; then
    echo "OK   SDL_androidsensor.c 已用 pollOnce（上游或补丁，跳过）"
  elif grep -q 'ALooper_pollAll(0, NULL, &events, (void \*\*)&source)' "$S"; then
    python3 - "$S" <<'PYEOF'
import sys
f = sys.argv[1]
src = open(f, encoding="utf-8").read()
old = "ALooper_pollAll(0, NULL, &events, (void**)&source)"
new = "ALooper_pollOnce(0, NULL, &events, (void**)&source) /* LusicGal: NDK r27 unavailable */"
if src.count(old) != 1:
    print("✗ ALooper_pollAll 命中非 1 次")
    sys.exit(1)
open(f, "w", encoding="utf-8").write(src.replace(old, new))
print("OK   SDL_androidsensor.c pollOnce 补丁已应用")
PYEOF
  else
    echo "✗ SDL_androidsensor.c 锚文本未命中（版本漂移？）"; exit 2
  fi
else
  echo "OK   无 SDL_androidsensor.c（该 SDL 版本无 sensor 目录，跳过）"
fi

echo "✓ SDL Android 补丁完成：注册回调取窗 + sensor pollOnce。"
