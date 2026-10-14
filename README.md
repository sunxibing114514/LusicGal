# LusicGal

**多引擎视觉小说 / ADV 游戏移动端运行器**（iOS / Android）—— 一个 App 管理 + 运行多种引擎的成品游戏包，无需对游戏重新打包。

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-3DDC84">
  <img alt="framework" src="https://img.shields.io/badge/UI-Flutter%20Material%203-02569B">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-blue">
</p>

## 支持的引擎

| 引擎 | 典型游戏文件 | 参考上游 | 移动端方案 | 当前状态 |
|---|---|---|---|---|
| **Kirikiri / KAG (krkr2)** | `*.xp3`（含 `data.xp3`）、`startup.tjs` | krkr2 / LauncherC / KrKr2-Next | C++ + CMake，Android Gradle + apple 平台目录（上游已含） | 检测 ✅ 核心 ⏳ |
| **ONScripter / NScripter** | `nscript.dat`、`arc*.nsa`、`0.txt` | ONScripter-EN / insani / ru / iOS / Yuri / zero | C/C++（SDL 系），Yuri 有 CMake+Android CI，zero 有大量 Android 修复 | 检测 ✅ 核心 ⏳ |
| **Ren'Py** | `game/scripts.rpa`（`RPA-3.0` 魔数）、`*.rpyc`、`renpy/` | renpy / renios / renpy-build | 官方 rapt/renios 构建链（见 docs/ENGINE_NOTES.md §Ren'Py） | 检测 ✅ 核心 ⏳ |
| **KEY 系（Siglus / RealLive / AVG32 / UK2）** | `Scene.pck`、`Gameexe.dat`、`Gameexe.ini`+`SEEN.TXT` | siglus_rs（Rust） | Rust `staticlib/cdylib` + cargo-ndk / iOS `a`（上游平台层已含） | 检测 ✅ 核心 ⏳ |
| **Rfvp（FVP 引擎）** | `*.hcb`、`*.nvsg` | rfvp（Rust） | Rust，上游自带 android/ios 构建文档 | 检测 ✅ 核心 ⏳ |
| **Sena（SoftPAL）** | `*.pac`（Koikake） | sena-rs（Rust） | Rust，上游支持 iOS arm64 / Android arm64-v8a | 检测 ✅ 核心 ⏳ |
| **System 3.x（AliceSoft）** | `*.ald` | xsystem35-sdl2 | C + SDL2，上游自带完整 Android Gradle 工程 | 检测 ✅ 核心 ⏳ |
| **Artemis（minori 系）** | 待 AetherMinori 格式文档化 | AetherKiri / AetherMinori | 参考 AetherKiri 多运行时 ABI | 检测 ⏳（可手动指定） |

> **检测 ✅ 核心 ⏳** = 游戏导入/识别/库管理/存档/设置已完整可用；引擎核心以"可选编译模块"方式接入（LGPL/GPL/MPL 许可与主 App 解耦，见 docs/LICENSE_NOTES.md）。核心的交叉编译脚本与 CI 已就位（`.github/workflows/engines.yml`），但尚未打包进正式产物。

## 功能

- 📂 **游戏导入**：扫描 App 专属目录 / 系统文件选择器双通道，自动递归复制入库
- 🧭 **引擎识别**：纯文件特征识别（魔数 + 文件名规则，规则参考 siglus_rs `engine-detect`），带置信度与证据链
- 🎮 **游戏库**：Material 3 网格/列表、重命名、删除（保留或删除文件）、游玩时长统计
- 💾 **存档管理**：按游戏隔离的存档目录、一键导出 zip / 导入 zip（含 zip-slip 防护）
- 🎛 **设置**：分辨率缩放、四通道音量（主/BGM/SE/Voice）、按键映射、明暗主题（Material 3 dark / light / system）
- 🔍 **引擎状态页**：实时探测已打包的引擎核心（JNI/dlsym 探测），核心缺失时给出构建指引

## 技术架构（摘要）

```
┌──────────────── Flutter (Material 3, 明暗主题) ────────────────┐
│ lib/ui          书库/存档/引擎/设置 四页 + 播放器               │
│ lib/core        识别 · 库(JSON) · 存档 · 设置 · 导入            │
│ lib/engine      EngineHost 门面（会话/事件/命令）               │
├──────────────── plugins/lusicgal_engines（平台桥）──────────────┤
│ MethodChannel lusicgal/engines  · EventChannel lusicgal/engineEvents
│ Android: Kotlin(JNI 核心探测) + PlatformView    iOS: Swift + dlsym
├──────────────── native/（引擎核心层，C ABI）────────────────────┤
│ native/include/lusicgal/engine_abi.h   统一引擎 ABI（学 krkr2/AetherKiri）
│ native/bridge/jni  JNI 适配        native/rust/cbridge  Rust FFI 门面
│ scripts/fetch_engines.sh  按 pin 拉取 16 个上游仓库
└──────────────────────────────────────────────────────────────────┘
```

完整设计见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，逐项目调研与"挑选可用代码"结论见 [docs/ENGINE_NOTES.md](docs/ENGINE_NOTES.md)。

## 编译验证（GitHub Actions）

平台壳（android/、ios/）不入库，由 CI 确定性生成（`flutter create`），保证任何 Flutter 稳定版可直接构建：

| Workflow | 内容 |
|---|---|
| `app` | `flutter analyze` + `flutter test` + `flutter build apk --release`（Ubuntu）+ `flutter build ios --debug --no-codesign`（macOS） |
| `engines` | C ABI 宿主自检 · JNI 桥 NDK 交叉编译 · Rust cbridge `cargo check` · 上游 pin 校验 · 引擎核心交叉编译实验（非阻塞） |

## 目录结构

```
├── lib/                     # Flutter UI + 业务层
├── plugins/lusicgal_engines/ # 平台桥插件（Kotlin/Swift/Dart）
├── native/                  # 引擎 ABI、JNI 桥、Rust 门面、各引擎集成方案
├── scripts/                  # 上游拉取 / 平台壳补丁脚本
├── docs/                     # ARCHITECTURE / ENGINE_NOTES / BUILD / ROADMAP / LICENSE_NOTES
└── .github/workflows/        # app.yml + engines.yml
```

## 许可

GPL-3.0（引擎核心各自的 GPL-2 / MPL-2 许可分析见 [docs/LICENSE_NOTES.md](docs/LICENSE_NOTES.md)）。
