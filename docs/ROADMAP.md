# ROADMAP

## v0.1（当前 · 本仓库）

- ✅ Flutter 壳：M3 明暗主题、四页导航（书库/存档/引擎/设置）、播放器骨架
- ✅ 引擎识别（8 引擎 + KEY 系细分，含证据链）
- ✅ 游戏库（JSON 原子持久化、导入双通道、重命名/删除、游玩统计）
- ✅ 存档管理（隔离目录、zip 导出/导入、zip-slip 防护）
- ✅ 设置（主题/分辨率缩放/四通道音量/按键映射）
- ✅ 平台桥插件（Kotlin + Swift：probe/launch/命令/事件/PlatformView）
- ✅ C ABI + JNI 桥 + Rust FFI 门面（CI 必须绿）
- ✅ 18 个上游 pin 化（scripts/fetch_engines.sh）与逐项目调研结论（docs/ENGINE_NOTES.md）
- ✅ CI：analyze/test/APK/iOS 全绿 + 引擎实验 job

## v0.2 — 第一个真实核心（ONScripter 移动化）

按 ENGINE_NOTES 选型 OnscripterYuri 为 ONS 核心：
1. `native/engines/onscripter`：NDK 构建（arm64-v8a/armeabi-v7a/x86_64）产出 `liblusicgal_onscripter.so`
2. 合入 ONScripter-zero 的 Android 修复清单（触摸冲突/openslES/后台）为验收用例
3. ABI 包装：SDL 主循环 → `lg_engine_set_surface(ANativeWindow*)`，事件回调对接 EventChannel
4. iOS：yeatse/ONScripter-iOS 的 SDL2 参数 + onscripter-ru Xcode 工程参考
5. 真机验收：月姬/寒蝉 等典型 NScripter 游戏

## v0.3 — Kirikiri + System 3.x

- krkr2 核心（platforms/android + apple 现成），XP3 挂载 + TJS2 跑通
- xsystem35-sdl2 核心（自带 Android Gradle 工程直接适配）
- 引擎"实验 job"逐个转正为必绿

## v0.4 — Rust 三引擎（rfvp / siglus_rs / sena-rs）

- `native/rust/cbridge` 接线三个 staticlib（MPL-2.0）
- 合入 YukiHub rfvp-build 的 12 个 Android 补丁（生产验证过的集合）
- cargo-ndk / cargo-lipo 双平台矩阵

## v0.5 — Ren'Py（官方链）

- renpy-build 容器产出 rapt/renios 静态库
- C 入口包装 + 每游戏独立 Python 环境目录

## v1.0 — Artemis（AetherMinori）与通用化

- AetherMinori 格式文档化后补全 Artemis 自动检测
- 引擎核心商店化（按需下载，进一步规避许可打包问题）
- 手柄/键盘映射外设、云存档、游戏内快进/自动模式面板

## 待解决问题对照（需求文档逐条）

| 待解决 | 本仓库答案 |
|---|---|
| Kirikiri 的 iOS 编译链路 | krkr2 `platforms/apple` + KrKr2-Next(ANGLE/Metal) 双参考 → `native/engines/kirikiri/README.md` |
| Ren'Py iOS 构建（Xcode+Python 整合） | 官方 renpy-build `renios/` 容器化构建 → `native/engines/renpy/README.md` |
| Rust 引擎 FFI 对接 | `native/rust/cbridge` + MPL-2.0 兼容性结论（LICENSE_NOTES） |
| System35 SDL2 移动移植 | xsystem35 自带 Android 工程 + 与 ONS 共用 SDL iOS 链路（BUILD.md） |
| 输入/音频/渲染统一抽象 | `engine_abi.h`（surface 注入 + JSON 命令 + 事件回调），设计源自 AetherKiri `engine_api.h` |
