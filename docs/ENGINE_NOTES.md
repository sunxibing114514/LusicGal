# ENGINE_NOTES — 参考项目调研与"挑选可用代码"结论

> 调研方式：GitHub API 实测（元数据 / 目录树 / README / 关键源码），调研时间见 git 历史。
> 每个条目标注：**定位**（pinned commit）、**许可**、**移动端方案**、**LusicGal 采纳点**（我们具体拿了什么 / 学了什么）。
> 文末"v2 真核集成结论"= 各引擎当前实际接线方式（native/engines/* 与 native/rust/shells/*）。

## 总表

| # | 项目 | 语言 | 许可 | 移动端 | LusicGal 用途 |
|---|---|---|---|---|---|
| 1 | 2468785842/krkr2 | C++ | NOASSERTION（见下） | ✅ Android Gradle + apple 平台 | Kirikiri 核心基底 |
| 2 | xiaocongyu66/KiriKiri-LauncherC | C++ | 同 krkr2（fork） | ✅ 同上 | KrKr2 工程化参考 |
| 3 | reAAAq/KrKr2-Next | C++/Flutter | GPL-3.0（badge） | ✅ iOS(ANGLE/Metal) + Android | Flutter + C++ 双层架构同构参考 |
| 4 | Galladite27/ONScripter-EN | C | GPL-2.0 | 桌面为主 | ONS 基线（最活跃 EN fork） |
| 5 | insani-org/onscripter-insani | C++ | GPL-2.0 | Makefile.iPhone（历史 iOS） | ONS 便携性参考 |
| 6 | Serentty/onscripter-ru | C++ | BSD + GPLv2 双许可 | Xcode 工程（iOS） | iOS 构建 + 高级特性参考 |
| 7 | yeatse/ONScripter-iOS | C++ | （未声明，ONS GPL-2 系） | ✅ SDL2 iOS 补丁 + build_libraries.sh | iOS SDL 移植直接参考 |
| 8 | YuriSizuku/OnscripterYuri | C++ | GPL-2.0 | ✅ CMake+vcpkg，Android CI | **首选 ONS 移动核心** |
| 9 | zeromake/ONScripter-zero | C++ | GPL-2.0 | ✅ xmake，大量 Android 修复 | Android 修复清单移植 |
| 10 | renpy/renpy | Python/C | LGPL/MIT 混合 | ✅ 官方 rapt/renios | Ren'Py 运行时本体 |
| 11 | chrismear/renios | Python | LGPL-2.1 | ✅（已停更） | 历史 iOS 打包链参考 |
| 12 | renpy/renpy-build | C/Python | 同 renpy 系 | ✅ 含 rapt/renios 目录 | Ren'Py 移动产物构建系统 |
| 13 | xmoezzz/rfvp | Rust | MPL-2.0 | ✅ platform/android + ios + IPA/APK 文档 | FVP 核心 |
| 14 | xmoezzz/siglus_rs | Rust | MPL-2.0 | ✅ 多平台 | KEY 系核心 + **engine-detect 规则** |
| 15 | xmoezzz/sena-rs | Rust | MPL-2.0 | ✅ iOS arm64 / Android arm64-v8a | SoftPAL 核心 |
| 16 | kichikuou/xsystem35-sdl2 | C | GPL-2.0 | ✅ 完整 Android Gradle 工程 | System 3.x 核心 |
| 17 | AetherKiri/Aether（原 AetherKiri，Artemis 参考） | C++/GDScript | GPL-3.0 | ✅ iOS/Android CI | 多运行时 ABI + AetherMinori |
| 18 | xm486/YukiHub（同类参考） | Java | GPL-3.0 | ✅ Android 原生 | 管理端交互 + rfvp-build 补丁集 |
| 19 | Alphaly2K/art3m1s-core | Rust | MPL-2.0 | ✅ Android(Vulkan)+iOS | **Artemis 真核**（minori 引擎重实现） |

Pinned commits（`scripts/fetch_engines.sh` 使用同一批 pin）：

| 项目 | HEAD pin |
|---|---|
| krkr2 | `dca7264572a63e753c1b07ca7053513d1751ce70` |
| KiriKiri-LauncherC | `df997312a8a3af9f9b529adb02f5b6cc7f5733d1` |
| KrKr2-Next | `1abd1ed4e8aec7abd5d2524c3a9ad7886880602f` |
| ONScripter-EN | `3854ae86c19337991722059d2bed07cbcc847f6f` |
| onscripter-insani | `c64bd7dfbc6501e23560599240b906ba806f3705` |
| onscripter-ru | `360b733cfb3674557bf3465133779429a8ae67a9` |
| ONScripter-iOS | `67531a432cb13df514019bc53733bf235e8ed791` |
| OnscripterYuri | `08f744b31cc1907b66a15f0402e62321a131ed81` |
| ONScripter-zero | `66cd50004fa79a7cca679e3a445543f5ae7c0fd1` |
| renpy | `80edccb125734ec9851b60b2f2b14d3f1f24eca6` |
| renios | `8eed53054fb4361eecb09e3c0eb3e26fd76d0cf0` |
| renpy-build | `612173094583e6fc2c5a92df438849757e0d3656` |
| rfvp | `709b6ba2f9ae4ba9f34c56df82a044eb958ff329` |
| siglus_rs | `5f358ef1360b0439e92aed2b749e8f25d8721954` |
| sena-rs | `f99db788421f2b724f1c57bc0a7c00debbd3624a` |
| xsystem35-sdl2 | `741a96e40733ba2b51eac3f9b57022b7c5015073` |
| AetherKiri | `a7453781f4a753a8d933e49aaa3c2960f1a823e7` |
| YukiHub | `35d12c0bb3d693646a3296bfe805561439b9f47c` |
| art3m1s-core | `ad90a62cb192b119b7cf8589aa7f87a94bd747c8` |

---

## 1. Kirikiri 家族

### 2468785842/krkr2 —— Kirikiri 核心基底
- 现代化 KrKr2 模拟器：`cpp/core`（TJS2/KAG 运行时、XP3/ZIP/TAR/7z 归档、软件渲染 + GLES + Vulkan）、`cpp/plugins`（Kirikiroid 兼容补丁、PSB/PSD、layerEx…）、**`platforms/android`（完整 Gradle 工程）+ `platforms/apple`（iOS/macOS）**、CMakePresets + vcpkg overlay triplets 交叉编译。
- CI badge 显示 Linux/Windows/Android 三平台构建流水线 —— 我们直接复用其 CMake preset + vcpkg triplet 思路。
- **采纳**：作为 LusicGal 的 Kirikiri 核心（`native/engines/kirikiri`）。其 `platforms/android` 证明 Android 可编译；iOS 走 `platforms/apple`。vcpkg overlay port 方案进入 `native/engines/kirikiri/build_android.sh`。

### xiaocongyu66/KiriKiri-LauncherC —— KrKr2 工程化参考
- krkr2 的 fork：模块化（`cpp/core` / `cpp/plugins` / `platforms`），Android 接入 Cocos2d-x/SDL 平台层、Breakpad、Dobby hook、oneTBB、mimalloc、per-game 偏好配置。
- **采纳**：per-game 偏好配置 → LusicGal `SettingsController` 的 per-game 覆盖；崩溃日志/移动端输入的模块划分方式 → native/bridge 的回调表设计。

### reAAAq/KrKr2-Next —— 架构同构参考（Flutter + C++）
- **Flutter 壳 + C++ 引擎 + ANGLE（Metal/Vulkan/GLES）**，五平台含 iOS。这证明"Flutter UI + C ABI 引擎核心"路线在 iOS 上可行（ANGLE 翻译 GLES → Metal）。
- **采纳**：Flutter↔C++ 分层（与我们一致）；iOS Metal 走 ANGLE 而非裸 GLES 的结论写入 ROADMAP；其 GPL-3.0 选择支持我们对主 App 采用 GPL-3.0。

## 2. ONScripter 家族（6 个）

### Galladite27/ONScripter-EN —— 基线
- 最活跃的英文向 ONS 维护（2024 仍在更新），autotools + `extlib`、`Makefile.extlibs`、单测 `Makefile.unittest`。
- **采纳**：作为桌面端行为基线与回归对比对象；其 `test/` 用于我们的兼容性测试样例来源。

### insani-org/onscripter-insani —— 便携性谱系
- 历史上支持 iPhone（`Makefile.iPhone`）、PSP、GP2X、WinCE 等 —— ONS 本身就是"为便携而写"。
- **采纳**：确认 ONS 无平台假设代码；其 `nscriptdecode/nsaconv/sarconv` 工具链 → 我们的存档/资源工具形态参考。

### Serentty/onscripter-ru —— 高级特性 + iOS Xcode 工程
- umineko-project 的 PS3 版海猫引擎（ONScripter 深度强化：h264/theora、着色器、多语言）。
- 许可为 **BSD + GPLv2 双许可**（部分文件 BSD），提供 `ONScripter.xcodeproj`。
- **采纳**：iOS Xcode 工程参数（签名/架构/SDL 集成）→ native/engines/onscripter iOS podspec 参考；BSD 部分文件可作为宽松许可的 iOS 平台胶水代码来源。

### yeatse/ONScripter-iOS —— iOS SDL 移植直接参考
- `SDL2-patch.diff` + `build_libraries.sh`（SDL/SDL_image/SDL_mixer/SDL_ttf/lua/smpeg 全套 iOS 编译脚本）+ `dev_iPhoneOS.sh`。
- **采纳**：`build_libraries.sh` 的 SDL iOS 交叉编译参数直接移植进 `native/engines/onscripter/build_ios.sh`。

### YuriSizuku/OnscripterYuri —— **首选 ONS 移动核心**
- CMake + vcpkg，CI 已跑 **android(arm|arm64)**、web(wasm)、win、linux、darwin —— 六平台构建流水线齐全，855 星，最活跃。
- 提供 `script/cross_android.sh`（NDK 交叉编译脚本）与 CMake presets。
- **采纳**：**LusicGal 的 ONScripter 核心以此为准**。`script/cross_android.sh` → `native/engines/onscripter/build_android.sh` 主体；其 `CMakeLists.txt` 的 vcpkg android triplet（freetype/sdl/ogg/vorbis）→ 引擎 CI 的依赖清单。

### zeromake/ONScripter-zero —— Android 修复清单移植
- ONScripter-Jh fork，README 是一份完整的 **Android 修复清单**：触摸(finger/mouse 冲突)、openslES 音频驱动、后台黑屏、后台崩溃、HiDPI 渲染模糊、存档路径 win 风格转换……
- **采纳**：该清单逐条转化为 LusicGal 移动核心的验收用例（docs/ROADMAP.md）；其 finger 事件→鼠标模拟的取舍结论直接指导桥接层输入映射。

## 3. Ren'Py 家族

### renpy/renpy —— 运行时本体
- 官方引擎（Python + C 加速模块 `src/`，`renpy/` 含 android/ios/web 平台胶水），移动支持是**一等公民**（`renpy/android.py`、ios 打包在 `sphinx/source/ios.rst` 官方文档）。
- **采纳**：LusicGal 的 Ren'Py 支持不做"重实现"，走官方移动产物路线（见下）。识别规则（`RPA-3.0` 魔数）来自其 `renpy/loader.py`。

### renpy/renpy-build —— 移动产物构建系统
- 官方构建系统（Ubuntu 24.04 容器，64GB 磁盘），内含 **`rapt/`（Android）与 `renios/`（iOS）** 目录、`run_ios.sh`、`test_android.sh`、`test_ios.sh`。
- **采纳**：引擎 CI 的 Ren'Py 产物 job 直接按其 `prepare.sh + build.sh` 流程产出 `libpy*`/`librenpy*` 静态库；这是"整合 Xcode + Python 环境"待决问题的官方答案。

### chrismear/renios —— 历史 iOS 打包链参考
- 2012 年的第三方 Ren'Py iOS 打包器（LGPL-2.1，已停更），证明 iOS 需要 Python 解释器静态嵌入 —— 与 renpy-build 内置 renios 一致。
- **采纳**：仅作历史参考与许可（LGPL-2.1 组件兼容性）记录；实际构建用官方 renpy-build。

**Ren'Py 集成结论**（对应"待解决问题：Ren'Py 的 iOS 构建需要 Xcode + Python 环境整合"）：
1. 官方链路：Ubuntu 24.04 容器内 `renpy-build` 产出 `renios` 的 iOS 静态库（内嵌 Python）→ Xcode 链接。
2. LusicGal 的接入点：Ren'Py 核心作为**独立可选核心模块**（体积大，含 Python），通过 `engine_abi.h` 包装 `renpy.main` 启动（C 入口 `renpy.h: renpy_main`）。
3. v1 不打包，检测/库管理先就绪 —— ROADMAP 中列出完整流水线。

## 4. Rust 三引擎（xmoezzz 系）

### xmoezzz/rfvp —— FVP 引擎（fate/hollow 系）
- Rust 重实现，crates 含 `rfvp`（引擎）、`rfvp-staticlib`（**静态库形态**！）、`nvsg_pack`（游戏 NVSG 封包）、`rfvp-bitmap`、`hcb2lua_decompiler/lua2hcb_compiler`（HCB 脚本）；`platform/android` + `platform/ios` + `setsumei/HOW-TO-BUILD.ios.md / android-apk.md`。
- 游戏文件特征：`*.hcb`（脚本）、`*.nvsg`（封包）、可选 `font/` 目录 —— 全部进入检测器。
- **采纳**：核心 = `rfvp-staticlib`（crate-type 已满足 FFI）；其 platform/android 的 NDK 构建参数进入 `native/engines/rfvp/build_android.sh`。

### xmoezzz/siglus_rs —— KEY 系四引擎 + 权威识别规则
- Rust 重实现 **SiglusEngine / RealLive / AVG32 / UK2**；crates 含 `game_fs`、`game_launcher`、`siglus_scene_vm`、`siglus_gameexe_ini`、`g00_extract`、`omv_decoder`，以及 **`engine-detect`（目录即引擎识别）**。
- **采纳**（最重要）：
  - `engine-detect/src/lib.rs` 的识别表 **逐条移植为 Dart 检测规则**（本仓库 `lib/core/detect/engine_detector.dart` 顶部注释标注证据来源）：
    - SiglusEngine ← `Scene.pck` 或 `Gameexe.dat`
    - AVG32 ← `Gameexe.ini` + `PACL` 魔数 `SEEN.TXT` 或 `TPC32` 散装场景
    - RealLive ← `Gameexe.ini` + 10000 条目 `SEEN.TXT`（`0x1d0`/`0x1cc` 头）
    - UK2 ← `UK2.CFG` 或 `<< UK2 TEXT Ver1.00 >>` 魔数的 `.MES`
  - 核心 = 其 engine crate `staticlib/cdylib` 产物（MPL-2.0，文件级许可，与 GPL-3 App 共存方式见 LICENSE_NOTES）。

### xmoezzz/sena-rs —— SoftPAL（Koikake）
- Rust 实现，**官方支持 iOS arm64/simulator 与 Android arm64-v8a/x86_64**（README 平台表），`platform/android` + `platform/ios` 目录现成；crates 含 `pal-vm`（入口 bin `sena`）、`pal-pac-unpacker`（**PAC 封包**）、`pal-script`。
- 启动样例：`cargo run -p pal-vm --release --bin sena -- /path/to/game --nls sjis` —— 命令行参数即我们的 `engine_abi.h` desc 字段。
- **采纳**：核心 + `*.pac` 检测特征；其 iOS/Android 平台目录证明两端 FFI 均已打通。

## 5. System 3.x —— kichikuou/xsystem35-sdl2
- C + SDL2，GPL-2.0；**仓库自带完整 Android Gradle 工程**（`android/app`、`android/README.md`）—— 在 NDK 下编译 `SDL2 + xsystem35` 的现成范本。
- 游戏文件特征：`*.ald` 封包（AliceSoft）+ 可选 `playlist.txt` 虚拟 CD。
- **采纳**：核心；`android/` Gradle 工程参数（SDL2 源码内嵌编译方式）→ `native/engines/xsystem35/build_android.sh`；iOS 通过 SDL2 iOS 支持编译（与 ONS 的 SDL 链路共用，见 BUILD.md）。

## 6. Artemis —— AetherKiri/AetherKiri
- **Godot 4 作为渲染层的多运行时视觉小说平台**（与 LusicGal 目标同构，可作为整体参照系）：`abi/`（**统一引擎 ABI：`engine_api.h` / `engine_gpu_bridge.h` / `engine_options.h` / `engine_runtime_provider.h`**）+ `packages/`（AetherKrkr、AetherSiglus、AetherSoftPal、OnscripterYuri、rfvp、**AetherMinori**…，以 submodule 挂载各运行时）。
- AetherMinori 的 Artemis 运行时为**私有仓库**（AetherInternal 404、SSH submodule）——不可作为 LusicGal 上游。
- **采纳**（关键）：
  1. **`engine_api.h` 的 ABI 设计**（`struct_size` 版本化、`reserved[]` 字段、handle 型指针、`engine_result_t` 错误码、key/value option 表）→ `native/include/lusicgal/engine_abi.h` 直接借鉴这套模式；
  2. `packages/*` 的"宿主 + 运行时包"组织方式 → LusicGal `native/engines/*` 的目录协议。

### Alphaly2K/art3m1s-core —— **Artemis 真核**（v2 采纳）
- Rust 实现的 minori 引擎（Artemis）运行时，MPL-2.0，v0.4.0，edition 2024（Rust ≥1.85）。
- FFI：`src/ffi/api.rs` 的 `art3m1s_get_api_v1(&mut usize) -> *const Art3m1sApiV1` **函数表**
  （60 字段、`abi_version=1`、magic `0x415254334D314150` "ART3M1AP"、前缀稳定）：
  `runtime_set_external_surface(rt, kind=1=ANativeWindow, win, w,h)`、`runtime_load_project(rt, path, platform)`、
  `runtime_feed_touch(rt, pointer, phase, x, y)`（phase 0=began/1=moved/2=ended/3=cancel = LG ABI 同构）、
  `runtime_feed_key(rt, vk, down)`、`runtime_advance_and_present(rt, dt)`、`resources_set_save_dir`、
  `runtime_set_reported_os` 等；宿主事件队列线缆 = 24B 小端头 [0..4]ver / [4..8]kind(1=log 2=media 3=ui) / [8..16]seq / [16..20]payload_len / [20..24]aux + payload。
- Android 默认 Vulkan 后端；工程目录（dir）或 `.pfs` 封包挂载。
- **采纳**：Artemis 核心本体（`native/rust/shells/artemis`，`vulkan-backend` feature；事件转 JSON `{"type":"artemis_log|artemis_media|artemis_ui","aux":N,"payload":…}`）。

## 7. 同类管理端参考 —— xm486/YukiHub
- Android 原生（Java/Gradle）的 Galgame 管理与启动器（GPL-3.0，528 星）：本地游戏扫描、外部模拟器入口、游玩记录同步。
- 其 **`rfvp-build/` 目录是 rfvp 的 Android 生产化补丁集**（`ENGINE_PATCHES.md` + 12 个 patch 脚本：Android 日志、音频修复、加法混合、mask dissolve、WMV 解码器、文本缩放……）。
- **采纳**：
  1. 管理端交互（扫描→列表→启动记录）→ 书库页信息结构（标题/引擎徽标/游玩时长/上次游玩）；
  2. **rfvp Android 补丁集**（YukiHub 已在生产验证）→ LusicGal 集成 rfvp 时的必合入清单（`native/engines/rfvp/patches-README`）。

---

## 引擎 → 核心选型速查（v2 实际接线）

| 引擎 | v2 核心来源 | 接线方式 |
|---|---|---|
| Kirikiri | **KrKr2-Next**（GPL-3.0，tick 驱动 C ABI `engine_api.h`） | `native/engines/kirikiri/adapter/lg_kirikiri.cpp`：`engine_open_game_async` → 状态轮询 → `engine_tick` 主循环；渲染 = `engine_set_render_target_surface`；`patch_engines.sh` 注入 `krkr_SetAndroidContext/krkr_SetNativeWindow` |
| ONScripter | **OnscripterYuri**（GPL-2.0，Android SHARED） | `lg_onscripter.cpp`：私有线程调上游 `main(argc,argv)`（`-r <dir> --save-dir <dir> --width/--height`）；SDL2 取窗 = `scripts/patch_sdl_android.sh` + `org.libsdl.app` 最小胶水；输入 → `SDL_PushEvent` |
| Ren'Py | renpy-build `librenpython.so`（官方产物，LGPL 系） | **Route B 外板壳**：独立模块 `com.lusicgal.renpy`（Activity 继承上游 `PythonSDLActivity`），LusicGal 桥只做 `RenpyLauncher` 转发（`plugins/.../RenpyLauncher.kt`）——不经 ABI 桥 |
| Siglus/RealLive/AVG32/UK2 | **siglus_rs game_launcher**（MPL-2.0） | `native/rust/shells/siglus`：`game_probe_json` 自动判子引擎（"siglus"→`siglus_android_*` wgpu 路径，其余→`game_fb_*` CPU 帧路径 blit）；`REALLIVE_SAVE_DIR` + `LUSICGAL_SAVE_DIR` 双环境变量 |
| FVP | **rfvp crate**（MPL-2.0） | `native/rust/shells/rfvp`：`rfvp_android_create/step/render`（wgpu）；触摸 phase 与 LG ABI 逐字相同（0/1/2/3） |
| SoftPAL | **sena-rs pal-vm**（MPL-2.0） | `native/rust/shells/sena`：`sena_host_create(game_root, nls, w,h)` + `sena_host_step`（0=run 1=end 2=error）+ CPU 帧 `sena_host_frame_generation` 变化检测 → `lg_common::blit` |
| System 3.x | **xsystem35-sdl2**（GPL-2.0，Android SHARED） | `lg_xsystem35.cpp`：私有线程 `main(6, argv)`（`-gamedir <dir> -savedir <dir> -noimagecursor`）；同 onscripter 的 SDL 取窗/胶水链路 |
| Artemis | **art3m1s-core**（MPL-2.0） | `native/rust/shells/artemis`：`art3m1s_get_api_v1` 函数表全量镜像（60 字段 size/version/magic 校验）→ `runtime_set_external_surface(kind=1)` + `runtime_load_project` + `runtime_advance_and_present` + 24B 头事件泵 → JSON 事件 |

通用约定：
- 核心全部为**独立动态库** `liblusicgal_<id>.so`（Android）/ `liblusicgal_<id>.a`（iOS 静态并入 pod）——GPL 边界隔离 + 按需分发。
- 桥 `liblusicgal_bridge.so` 零核心：`dlsym(RTLD_DEFAULT, "lg_<id>_<symbol>")` 运行期派发（JNI 侧 `EngineHost.ensureCore` 先 `System.loadLibrary("lusicgal_<id>")`）。
- 输入统一 JSON（`engine_abi.h` v2）：point/key/text；键名→各核心码表映射在壳内（VK 基准在 `lg_common::input::vk_code`）。
- 存档统一 `desc.save_path` → 壳设 `LUSICGAL_SAVE_DIR` → `scripts/patch_engines.sh` 的上游补丁消费（siglus/sena/rfvp；reallive 原生 `REALLIVE_SAVE_DIR`；KrKr2 原生 `writable_path`）。
