# System 3.x（AliceSoft）核心

## 选型

**核心 = kichikuou/xsystem35-sdl2**（C + SDL2，GPL-2.0）。上游**自带完整 Android Gradle 工程**
（`android/app`、`android/README.md`）—— NDK 内嵌编译 SDL2 + 引擎本体的现成范本。

## 集成路径（v2 实装：`adapter/lg_xsystem35.cpp`）

1. CMake 镜像上游 `android/app/jni/CMakeLists.txt` 依赖编排：
   FetchContent SDL2-2.32.10（**构建前经 `scripts/patch_sdl_android.sh` 打取窗补丁**
   —— 与 ONScripter 共用 `LG_SDL_Window_Override()` 机制）+ freetype（自带光栅器）
   + SDL2_mixer 2.8.0 → `add_subdirectory(仓库根)` 得 `libxsystem35.so`（上游
   ANDROID 分支本就是 SHARED 目标，内含 `main()`），再链出 `liblusicgal_xsystem35.so`。
2. 运行期：`lg_xsystem35_engine_start` 私有线程调 `main(6, argv)`：
   `-gamedir <game_dir> -savedir <save_dir> -noimagecursor`
   （`-gamedir` 在 `__ANDROID__` 下 = chdir 游戏根，`*.ald` 从此扫描）。
3. 输入 JSON → `SDL_PushEvent`（视口 640×480 归一化换算）；stop → `SDL_QUIT`。
   SDL Java 侧生命周期与实时音频同 ONScripter（插件内 `org.libsdl.app`
   合并类集：SDL3 全套 + SDL2 音频兼容面，装载核心后 `nativeSetupJNI()` 引导）。
4. `playlist.txt` 虚拟 CD 与字体参数经 options_json 透传（后续）。

构建：`bash native/engines/xsystem35/build_android.sh`（需 ANDROID_NDK_HOME）。

## 检测特征

`*.ald`（10 分，AliceSoft ALD 封包）。

## 许可

GPL-2.0 —— 分发策略同 ONScripter（docs/LICENSE_NOTES.md）。
