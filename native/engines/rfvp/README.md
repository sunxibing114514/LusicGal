# Rfvp（FVP 引擎，fate 系）核心

## 选型

**核心 = xmoezzz/rfvp**（Rust，MPL-2.0）。crates 中已有 `rfvp-staticlib`（静态库形态，FFI 就绪）、
`nvsg_pack`（游戏封包）、`rfvp-bitmap`、`hcb2lua_decompiler / lua2hcb_compiler`（HCB 脚本）。
上游自带 `platform/android` + `platform/ios` 与 `setsumei/HOW-TO-BUILD.ios.md / android-apk.md`。

## 生产化补丁（必合入）

**YukiHub 的 `rfvp-build/` 是 rfvp 的 Android 生产验证补丁集**（GPL-3.0 项目，直接引用其
`ENGINE_PATCHES.md` 与 patch 脚本适配到本仓库 `patches/`）：
- `apply_android_log_patch.py` —— Android 日志
- `apply_audio_fix_patch.py` —— 音频修复
- `apply_fvp_additive_blend_patch.py` / `apply_fvp_mask_dissolve_patch.py` —— 渲染
- `apply_movie_patch.py` / `apply_wmv_decoder_patch.py`（+ `video-sys-cpu-read.patch`）—— 视频链路
- `apply_text_*_patch.py` —— 文本（缩放/点击）

## 集成路径（v0.4）

1. `rfvp-staticlib`（crate-type staticlib/cdylib）经 `native/rust/cbridge` 接线，
   导出 `lg_rfvp_engine_*`（engine_abi.h）。
2. Android：cargo-ndk（arm64-v8a / armeabi-v7a / x86_64）。
3. iOS：**暂不构建**（用户指令；上游平台表含 iOS，未来需要时按上游文档接）。

## 检测特征

`*.hcb`（8 分）/ `*.nvsg`（10 分）。编码切换（Nls：UTF-8 / GBK）在 options_json 透传。

## 许可

MPL-2.0（文件级）—— 与 GPL-3.0 App 组合的经典兼容形态；YukiHub 补丁按 GPL-3 合入并在文件头注明。
