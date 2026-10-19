#!/usr/bin/env bash
# 上游核心存档目录注入补丁（幂等，锚文本精确匹配）。
#
# LusicGal 的 SaveManager 为每个游戏分配独立存档目录（save_path），经
# desc.save_path → 壳设置 LUSICGAL_SAVE_DIR 环境变量 → 下列补丁让上游
# 尊重该变量（原实现写游戏目录旁）。
#
#   scripts/patch_engines.sh            # 全部
#   scripts/patch_engines.sh sena rfvp  # 指定引擎
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP="$ROOT/third_party/upstream"

FILTERS=("$@")
matches() {
  [ ${#FILTERS[@]} -eq 0 ] && return 0
  local f
  for f in "${FILTERS[@]}"; do
    case "$1" in
      *"$f"*) return 0 ;;
    esac
  done
  return 1
}

# patch_file <engine> <file> <锚-已打标> <python 替换体（heredoc 传入 vars:
#   ANCHOR=精确既有文本，REPLACEMENT=替换为）>
patch_file() {
  local engine="$1" file="$2" mark="$3" body="$4"
  matches "$engine" || return 0
  local target="$UP/$engine/$file"
  [ -f "$target" ] || { echo "✗ patch($engine): 缺 $file"; return 2; }
  if grep -q "$mark" "$target"; then
    echo "OK   patch($engine) 已应用（跳过）"
    return 0
  fi
  if python3 - "$target" "$body" <<'PYEOF'
import sys
target, body = sys.argv[1], sys.argv[2]
ns = {}
exec(body, ns)
anchor, replacement = ns["ANCHOR"], ns["REPLACEMENT"]
src = open(target, encoding="utf-8").read()
if anchor not in src:
    print(f"✗ 锚文本未命中：{target}")
    sys.exit(1)
open(target, "w", encoding="utf-8").write(src.replace(anchor, replacement, 1))
print(f"OK   patch applied: {target}")
PYEOF
  then :; else
    echo "✗ patch($engine) 失败"
    return 2
  fi
}

# ---- siglus_rs：original_save.rs::save_dir → LUSICGAL_SAVE_DIR 优先 ---------
# （reallive 的 save.rs 原生支持 REALLIVE_SAVE_DIR，无需补丁）
patch_file siglus-rs "crates/siglus_scene_vm/src/original_save.rs" \
  'LUSICGAL_SAVE_DIR' '
ANCHOR = """pub fn save_dir(project_dir: &Path) -> PathBuf {
    project_dir.join("savedata")
}"""
REPLACEMENT = """pub fn save_dir(project_dir: &Path) -> PathBuf {
    if let Some(dir) = std::env::var_os("LUSICGAL_SAVE_DIR") {
        return std::path::PathBuf::from(dir);
    }
    project_dir.join("savedata")
}"""
'

# ---- sena-rs：runtime.rs::portable_save_dir → LUSICGAL_SAVE_DIR 优先 -------
patch_file sena-rs "crates/pal-vm/src/runtime.rs" \
  'LUSICGAL_SAVE_DIR' '
ANCHOR = """fn portable_save_dir(root: &Path) -> PathBuf {
    root.join("save").join("sena_rs")
}"""
REPLACEMENT = """fn portable_save_dir(root: &Path) -> PathBuf {
    if let Some(dir) = std::env::var_os("LUSICGAL_SAVE_DIR") {
        return PathBuf::from(dir);
    }
    root.join("save").join("sena_rs")
}"""
'

# ---- rfvp：utils/file.rs::desktop_storage → LUSICGAL_SAVE_DIR 优先 ---------
# 原实现把存档放 app_base_path()（= 游戏目录）下的 save/。
patch_file rfvp "crates/rfvp/src/utils/file.rs" \
  'LUSICGAL_SAVE_DIR' '
ANCHOR = """pub fn desktop_storage() -> std::sync::Arc<dyn crate::host_api::RfvpStorage> {
    std::sync::Arc::new(crate::host_api::std_fs::StdDir::new(
        app_base_path().get_path().clone(),
    ))
}"""
REPLACEMENT = """pub fn desktop_storage() -> std::sync::Arc<dyn crate::host_api::RfvpStorage> {
    let base = std::env::var_os("LUSICGAL_SAVE_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| app_base_path().get_path().clone());
    std::sync::Arc::new(crate::host_api::std_fs::StdDir::new(base))
}"""
'

# ---- rfvp：YukiHub 生产补丁集（vendored，pin 709b6ba 逐脚本实测）----------
# 来源 xm486/YukiHub rfvp-build/（GPL-3.0，Android 生产验证）。实测结论：
#   ✓ APPLIES（真实改码）：text_patch（YHFVP-TEXTPATCH-1.0 汉化查表）、
#     android_log（android_logger + wgpu 噪音压制）、text_click（点击补全 +
#     TextResume 保护）。
#   ✓ NO-OP 回归护栏（上游 pin 已含等效修复，脚本幂等检测后空转）：
#     additive_blend（上游 ffc73809 已入）、mask_dissolve（上游 e95f275a
#     已入 —— crates/rfvp/src/rendering/mask_dissolve.rs 已是 git 跟踪文件）。
#   ✗ 不 vendor：wmv_decoder（上游重构为 exponent_pow_tab_index + 单测，
#     负数下标防护已在）、movie/audio_fix（上游 videoplayer 整体重写为
#     symphonia 版 threaded/inline 双实现，声道校验 + SampleBuffer 按需
#     分配俱在）、text_scale（psx cfg 重构致 3 锚点漂移，字号缩放为
#     附加功能，待再锚定）、probe（YukiHub 诊断工具）。
# 脚本按 __file__ 所在目录解析仓库根 —— 须先拷进 rfvp 根（同 YukiHub CI）。
if matches rfvp; then
  RFVP_ROOT="$UP/rfvp"
  [ -d "$RFVP_ROOT" ] || { echo "✗ patch(rfvp): 缺上游源码"; exit 2; }
  for py in apply_text_patch.py apply_android_log_patch.py \
            apply_text_click_patch.py apply_fvp_additive_blend_patch.py \
            apply_fvp_mask_dissolve_patch.py; do
    src="$ROOT/native/engines/rfvp/patches/yukihub/$py"
    [ -f "$src" ] || { echo "✗ patch(rfvp): 缺 $py"; exit 2; }
    cp "$src" "$RFVP_ROOT/$py"
    ( cd "$RFVP_ROOT" && python3 "$py" ) || {
      echo "✗ patch(rfvp): $py 失败（锚点漂移？）"; exit 2; }
    rm -f "$RFVP_ROOT/$py"
  done
  echo "OK   patch(rfvp) YukiHub 生产补丁集完成（3 实改 + 2 护栏）"
fi

# ---- KrKr2-Next：导出 C setter（宿主注入 JVM/Context/窗口）-----------------
# 原实现只有 Kotlin 类绑定的 JNI 命名 setter（org.github.krkr2...），
# LusicGal 不复用其 Flutter 插件 —— 注入经本补丁新增的纯 C 入口。
patch_file kirikiri-next "platforms/android/cpp/krkr2_android.cpp" \
  'krkr_SetAndroidContext' '
ANCHOR = """ANativeWindow* krkr_GetNativeWindow() {"""
REPLACEMENT = """// LusicGal 宿主注入入口（补丁新增）：桥在 launch 前调用。
// vm=JavaVM*，context=jobject（Activity Application Context）。
extern "C" void krkr_SetAndroidContext(void* vm, void* context) {
    if (vm) {
        std::lock_guard<std::mutex> lock(g_jvm_mutex);
        g_javaVM = reinterpret_cast<JavaVM*>(vm);
        krkr::JniHelper::setJavaVM(reinterpret_cast<JavaVM*>(vm));
    }
    if (context) {
        JNIEnv* env = nullptr;
        JavaVM* jvm = krkr_GetJavaVM();
        if (jvm && jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            std::lock_guard<std::mutex> lock(g_context_mutex);
            if (g_app_context) {
                env->DeleteGlobalRef(g_app_context);
            }
            g_app_context = env->NewGlobalRef(reinterpret_cast<jobject>(context));
        }
    }
}

// LusicGal 宿主渲染面注入（补丁新增）：win=ANativeWindow*。
extern "C" void krkr_SetNativeWindow(void* win, uint32_t w, uint32_t h) {
    std::lock_guard<std::mutex> lock(g_surface_mutex);
    if (g_native_window) {
        ANativeWindow_release(g_native_window);
        g_native_window = nullptr;
    }
    g_native_window = reinterpret_cast<ANativeWindow*>(win);
    if (g_native_window) {
        ANativeWindow_acquire(g_native_window);
    }
    g_surface_width = w;
    g_surface_height = h;
}

ANativeWindow* krkr_GetNativeWindow() {"""
'

echo "补丁流程完成。"
