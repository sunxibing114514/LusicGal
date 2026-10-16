# ROADMAP

> 更新：v2 已把八引擎真核全部接线（不再按引擎分期）。剩余工作 =
> 验证与转正（受 CI 配额阻塞）+ 打磨项。

## 已完成（当前 main）

- ✅ Flutter 壳：M3 明暗主题、四页导航（书库/存档/引擎/设置）、播放器
  （自动播放/快进/跳过快捷键、暂停/恢复、游玩统计）
- ✅ 引擎识别（8 引擎 + KEY 系细分，证据链评分）+ 游戏库 + 存档管理
  （隔离目录、zip 导出/导入、zip-slip 防护）
- ✅ **ABI v2**（`0x00020000`，8 符号/核心 + 可选 set_android_context）：
  统一 dlsym 派发桥（Android `liblusicgal_bridge.so` 零核心；iOS C 桥
  `lg_ios_*` 源码就位）
- ✅ **八引擎真核接线**：
  - Kirikiri = KrKr2-Next（tick 驱动 C ABI，NDK+vcpkg 构建）
  - ONScripter = OnscripterYuri（main(argc,argv) + SDL 取窗补丁；argv
    契约逐行核对，`-window` 修正）
  - Ren'Py = **Route B 外板壳**（`modules/renpy/`：官方 `librenpython.so`
    + rapt Java 复用 + argv 注入游戏目录/存档目录；staging 后自动并入）
  - Siglus/RealLive/AVG32/UK2 = siglus_rs（probe 自动判子引擎：
    siglus→wgpu 直渲，其余→CPU 帧 blit；`REALLIVE_SAVE_DIR`）
  - Rfvp = rfvp crate（wgpu 直渲 ANativeWindow）
  - SoftPAL = sena-rs pal-vm（CPU 帧 + generation 变化检测 blit）
  - System 3.x = xsystem35-sdl2（`-gamedir` 前置 chdir 契约验证）
  - Artemis = art3m1s-core（`art3m1s_get_api_v1` 60 字段函数表）
- ✅ **SDL2 真实音频**：`SdlCompat.kt` 完整移植 SDLAudioManager
  （AudioTrack 实时输出、2.26/2.32 双签名兼容、装载后 nativeSetupJNI 引导）
- ✅ **平台条目引擎（引擎 8 → 14）**：
  - Web 跑法：**Tyrano**（TyranoScript/TyranoBuilder，含 app.asar
    Electron 包）与 **RPG Maker MV / MZ** —— 本地 HTTP（127.0.0.1，
    Range + 大小写/资源后缀回退）+ index.html 注入自适应 hook
    （音频生命周期 / 存档桥 / MV·MZ 虚拟手柄 KeyboardEvent 合成）
  - 外板启动条目：**PSP**（PPSSPP 显式 Intent 协议）、**PC**
    （winlator-cn ExternalLaunchActivity extras 协议；容器/驱动/分辨率
    可覆盖）、**Android 应用**（含 GameHub 快捷方式类条目）
  - 导入三通道扩齐（目录 → 镜像文件 → 应用清单选择器）；检测器补
    web/PC/PSP 证据与魔数；条目模型 +options（条目级参数）
  - 许可：移植 YukiHub（GPL-3.0 同许可）架构重写 —— 署名与协议出处
    见 docs/LICENSE_NOTES.md
- ✅ 上游契约逐行核对（Rust 四壳 extern 全量 / argv / SDL JNI —— 见
  ENGINE_NOTES"契约核对记录"）
- ✅ CI 骨架：门禁（selftest/JNI 桥/Rust FFI/pin 校验）+ 真核四矩阵 +
  实验 job（kirikiri/onscripter/xsystem35/renpy-module）
- ✅ 本地门禁复核：selftest `{"selftest":"ok","abi":"0x00020000"}` 绿；
  JNI 桥 10 Java 符号链接绿
- ✅ **本地实构建（2026-10，NDK r27c arm64；内存约束容器 —— 实证时
  400MB 上限，现行收紧为 300MB）**：
  - 真产物：`liblusicgal_bridge.so`（61KB/10 JNI 符号）、ONScripter 9 件
    （适配器+onsyuri+SDL2 栈+lua/bz2+STL）、xsystem35 7 件（适配器+
    xsystem35+SDL2/mixer+webp/sharpyuv+STL）—— 符号/NEEDED 逐一核验
  - Rust 四壳独立检查（`scripts/rust_local_check.sh`，host+android 双
    目标）全绿；壳 7 类编译/链接 bug 在 CI 首跑前修复（详见 ENGINE_NOTES
    "本地实构建实证记录"）
  - SDL 取窗注入改注册回调形态 `LG_SDL_SetWindowOverride`（反向 extern
    三重死因实证）+ NDK r27 `ALooper_pollAll` 兼容
  - Kirikiri vcpkg 工具链拓扑跑通（入口 vcpkg.cmake 链挂 NDK、
    manifest/overlay 指 krkr2 根、vcpkg 须完整 git 历史、release-only
    overlay triplet；本地推进至 136 buildtree/10 港口缓存，整链因
    spirv-tools -O3 -g 单元超容器内存 OOM —— CI 7GB runner 为场域）
  - 不可行项（实证非遗漏）：Rust 全量上游交叉编译（wgpu 系单 crate
    峰值超 400MB）—— 四壳上游仍以 CI rust-cores 矩阵为准

## 阻塞中（CI 配额）

私有仓库 Actions 分钟配额耗尽 —— 所有 push job 0 步秒死（多轮复核确认）。
配额恢复后第一轮验证顺序：① 门禁四项 ② rust-cores 四矩阵 ③ app
analyze/test/apk ④ Kotlin/Gradle 首次编译修复轮。

## 下一步（配额恢复后）

1. **首编译转正轮**：CI 跑门禁 + Rust 四核矩阵 + app 构建；修
   Kotlin/Gradle/Rust 编译错误（预期存在——本地无 Android 工具链）。
2. **实验 job 逐个转正**：kirikiri-android（NDK+vcpkg）/
   onscripter-android / xsystem35-android / renpy-module staging。
3. **真机验收**：每引擎一款代表游戏跑通：启动→渲染→音频→输入→存档→退出。
4. **打磨**：SDL 手柄（SDLControllerManager 完整移植）、ONScripter-zero
   Android 修复清单合入、xsystem35 playlist 虚拟 CD、Kirikiri
   PSB/layerEx 插件兼容、核心商店化（按需下载）。

## 平台范围（用户指令）

- **iOS 暂不构建**：核心只构建/验证 Android arm64；iOS 侧源码（Swift 插件 /
  C 桥 / stub / podspec）保持就位，未来恢复时按各上游 `platform/apple`、
  `platform/ios` 文档接（见各引擎 README 与 ENGINE_NOTES 范围声明）。

## 待解决问题对照（需求文档逐条）

| 待解决 | 本仓库答案 |
|---|---|
| Kirikiri 移动编译链路 | KrKr2-Next `platforms/android`（NDK+vcpkg，`build_android.sh`）；`platforms/apple` 留作 iOS 恢复用 |
| Ren'Py 移动构建（Xcode+Python 整合） | **Route B**：官方 renpy-build `librenpython.so` + rapt 链路重组（`modules/renpy/`），无需自建 Python 整合 |
| Rust 引擎 FFI 对接 | `native/rust/shells/*` 四壳（MPL-2.0 上游）+ `lg_common`；契约已逐行核对 |
| System35 SDL2 移动移植 | xsystem35-sdl2 + 与 ONS 共用 SDL 取窗/音频胶水（SdlCompat.kt） |
| 输入/音频/渲染统一抽象 | `engine_abi.h` v2（surface 注入 + JSON 输入/命令 + 事件回调），设计源自 AetherKiri `engine_api.h` |
