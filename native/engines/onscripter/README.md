# ONScripter / NScripter 核心

## 选型（docs/ENGINE_NOTES.md §ONScripter）

**v1 核心 = OnscripterYuri**（CMake + vcpkg，上游自带 android(arm|arm64) CI 与 `script/cross_android.sh`）。
其余 5 个上游 fork 的用途：
- **ONScripter-zero**：Android 修复清单（触摸冲突 / openslES / 后台黑屏 / 后台崩溃 / HiDPI）→ 合入为验收用例与移动补丁来源。
- **ONScripter-EN**：桌面基线 + `test/` 回归样例。
- **onscripter-insani**：便携性谱系（历史 iPhone Makefile）确认无平台假设代码。
- **onscripter-ru**：iOS Xcode 工程参数 + BSD 许可文件（可作 iOS 胶水）。
- **yeatse/ONScripter-iOS**：SDL2 iOS 交叉编译参数（`build_libraries.sh` + `SDL2-patch.diff`）。

## Android（v2 实装：`adapter/lg_onscripter.cpp`）

```bash
bash scripts/fetch_engines.sh onscripter-yuri
bash native/engines/onscripter/build_android.sh   # 需要 ANDROID_NDK_HOME
```

链路（build_android.sh 自动执行）：
1. 上游 `script/_fetch.sh` 拉取 SDL 栈（`thirdparty/port/SDL2-2.26.3` 等）。
2. `scripts/patch_sdl_android.sh`：给 `SDL_android.c` 的
   `Android_JNI_GetNativeWindow()` 加宿主窗口覆盖
   （`LG_SDL_Window_Override()` —— SDL2 Android **没有** `SDL_CreateWindowFrom`，
   这是无 SDLActivity 嵌入的取窗路径）。
3. 适配器 CMake 镜像上游 `src/onsyuri_android/app/cpp/CMakeLists.txt` 依赖编排
   → `add_subdirectory(仓库根)` 得 `libonsyuri.so`，再链出
   `liblusicgal_onscripter.so`。

运行期：`lg_onscripter_engine_start` 在私有线程调上游 `main(argc, argv)`：
`-r <game_dir> --save-dir <save_dir> --width/--height <options>`；
输入 JSON → `SDL_PushEvent`（触摸→鼠标合成，键名→SDL keycode）；
stop → `SDL_QUIT`。SDL 的 Java 侧生命周期由插件内
`org.libsdl.app`（SDL3 android-project 全套 + SDL2 音频兼容面，
`plugins/lusicgal_engines/android/src/main/java/org/libsdl/app/`）
承接：SDLAudioManager 合并了 2.26.3 `(IIII)[I` 与 2.32.10 `(IIIII)[I`
双 audioOpen 签名及采集空实现，`ensureCore` 装载核心后调用
`nativeSetupJNI()` 缓存 C 侧回调方法表 → AudioTrack 实时音频。
采集（capture*）为安全空实现（ONS 不采集）。

## iOS

**暂不构建**（用户指令；核心只构建验证 Android arm64）。源码参考留存：

yeatse/ONScripter-iOS 的 `build_libraries.sh` 参数（SDL/SDL_mixer/SDL_ttf/lua/smpeg）
+ onscripter-ru 的 Xcode 工程配置（`platform/ios`），静态库符号前缀 `lg_onscripter_*`。

## 检测特征（lib/core/detect/engine_detector.dart）

`nscript.dat`（10 分）/ `arc*.nsa`（8 分，魔数 `NSA\0`）/ `0.txt`·`00.txt`（6 分）/ `*.sar`（5 分）。

## 许可

GPL-2.0（Ogapee 血统）。分发改动需随附原始 COPYING 与修改声明；分发策略见 docs/LICENSE_NOTES.md。
