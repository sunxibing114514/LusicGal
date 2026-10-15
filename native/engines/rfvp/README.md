# Rfvp（FVP 引擎，fate 系）核心

## 选型

**核心 = xmoezzz/rfvp**（Rust，MPL-2.0）。crates 中已有 `rfvp-staticlib`（静态库形态，FFI 就绪）、
`nvsg_pack`（游戏封包）、`rfvp-bitmap`、`hcb2lua_decompiler / lua2hcb_compiler`（HCB 脚本）。
上游自带 `platform/android` + `platform/ios` 与 `setsumei/HOW-TO-BUILD.ios.md / android-apk.md`。

## 生产化补丁（YukiHub rfvp-build，逐脚本实测于 pin 709b6ba）

**已 vendor**（`patches/yukihub/`，`scripts/patch_engines.sh rfvp` 自动应用；
GPL-3.0，来源 pin 35d12c0b 文件头注明）：
- `apply_text_patch.py` —— **YHFVP-TEXTPATCH-1.0 外部文本替换表**（Windows
  注入式汉化的安卓化：按脚本字节偏移查表，hcb 零改动）—— 实改 ✓
- `apply_android_log_patch.py` —— android_logger + wgpu 噪音压制 —— 实改 ✓
- `apply_text_click_patch.py` —— 点击补全点字动画 + TextResume 状态保护 —— 实改 ✓
- `apply_fvp_additive_blend_patch.py` / `apply_fvp_mask_dissolve_patch.py` ——
  渲染修复（上游 ffc73809/e95f275a 已入本 pin；脚本幂等检测后空转 =
  **回归护栏**：若未来重 pin 旧版自动补上）

**不 vendor（上游已吸收等效实现，逐行核实）**：
- wmv_decoder 负数下标防护 → 上游重构为 `exponent_pow_tab_index` + 单测
  （decoder.rs:38-42/1635）
- movie/audio_fix → 上游 videoplayer 整体重写为 symphonia 版
  （`videoplayer/{mod,inline,threaded}.rs`，声道校验 + SampleBuffer 容量 0
  按需分配俱在）
- text_scale（全局字号缩放 + `rfvp_android_set_text_scale`）→ 3 锚点因
  上游 psx cfg 重构漂移，**待再锚定**（附加功能，不阻塞游戏正确性）
- probe → YukiHub 诊断工具，不取

## 集成路径（v2 已实装）

1. 壳 crate `native/rust/shells/rfvp`（`lg_rfvp_engine_*`，对上游
   `rfvp_android_*` 9 符号逐签名核对通过）。
2. Android：`scripts/build_rust_core.sh rfvp`（aarch64-linux-android）。
3. 存档：`LUSICGAL_SAVE_DIR` 环境变量（`utils/file.rs::desktop_storage`
   补丁；Android 活路径 `with_vfs → desktop_storage` 已核实）。
4. iOS：**暂不构建**（用户指令；上游平台表含 iOS，未来需要时按上游文档接）。

## 检测特征

`*.hcb`（8 分）/ `*.nvsg`（10 分）。编码切换（Nls：UTF-8 / GBK）在 options_json 透传。

## 许可

MPL-2.0（文件级）—— 与 GPL-3.0 App 组合的经典兼容形态；YukiHub 补丁按 GPL-3 合入并在文件头注明。
