# ONScripter / NScripter 核心

## 选型（docs/ENGINE_NOTES.md §ONScripter）

**v1 核心 = OnscripterYuri**（CMake + vcpkg，上游自带 android(arm|arm64) CI 与 `script/cross_android.sh`）。
其余 5 个上游 fork 的用途：
- **ONScripter-zero**：Android 修复清单（触摸冲突 / openslES / 后台黑屏 / 后台崩溃 / HiDPI）→ 合入为验收用例与移动补丁来源。
- **ONScripter-EN**：桌面基线 + `test/` 回归样例。
- **onscripter-insani**：便携性谱系（历史 iPhone Makefile）确认无平台假设代码。
- **onscripter-ru**：iOS Xcode 工程参数 + BSD 许可文件（可作 iOS 胶水）。
- **yeatse/ONScripter-iOS**：SDL2 iOS 交叉编译参数（`build_libraries.sh` + `SDL2-patch.diff`）。

## Android（实验脚本）

```bash
bash scripts/fetch_engines.sh
bash native/engines/onscripter/build_android.sh   # 需要 ANDROID_NDK_HOME，vcpkg 依赖自动解析
```

产物并入 `liblusicgal_onscripter.so`（engine_abi.h 包装 SDL 主循环 →
`lg_onscripter_engine_set_surface(ANativeWindow*)`）。

## iOS

yeatse/ONScripter-iOS 的 `build_libraries.sh` 参数（SDL/SDL_mixer/SDL_ttf/lua/smpeg）
+ onscripter-ru 的 Xcode 工程配置（`platform/ios`），静态库符号前缀 `lg_onscripter_*`。

## 检测特征（lib/core/detect/engine_detector.dart）

`nscript.dat`（10 分）/ `arc*.nsa`（8 分，魔数 `NSA\0`）/ `0.txt`·`00.txt`（6 分）/ `*.sar`（5 分）。

## 许可

GPL-2.0（Ogapee 血统）。分发改动需随附原始 COPYING 与修改声明；分发策略见 docs/LICENSE_NOTES.md。
