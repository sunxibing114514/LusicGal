# LICENSE_NOTES — 许可与分发策略

## 主 App

**GPL-3.0**（与 KrKr2-Next / AetherKiri / YukiHub 同选）。

## 引擎核心许可矩阵

| 核心 | 上游许可 | 与 GPL-3.0 App 共存方式 |
|---|---|---|
| KrKr2-Next（Kirikiri 真核） | GPL-3.0（badge） | **直接兼容**；核心以独立 `liblusicgal_kirikiri.so` 交付，随附上游 LICENSE + `scripts/patch_engines.sh` 的 diff 声明（krkr2 原仓 NOASSERTION，血统自有许可 —— 未用作核心，仅调研记录） |
| ONScripter 系（OnscripterYuri） | GPL-2.0（Ogapee 原始）；onscripter-ru 部分 BSD | **GPL-2-only 风险点**：不与 GPL-3 静态混链。策略：核心以独立 native 库交付（Android 动态库天然分离；iOS 以独立 Framework + 文档说明），或整包以"GPL-2+GPL-3 双许可并列"发布 |
| Ren'Py（librenpython.so） | LGPL-3.0 / MIT 混合（官方产物内含完整许可清单） | **Route B 外板壳**：`librenpython.so` **原样分发、不修改不静态并入**（独立模块 `com.lusicgal.renpy`，Activity 继承上游 `PythonSDLActivity`）→ LGPL 动态链接边界清晰；随附 renpy 自带 LICENSE 与源码指针（`renpy-build` 官方仓库） |
| rfvp / siglus_rs / sena-rs | MPL-2.0（文件级弱 copyleft） | **兼容**：MPL 文件保持独立来源标注即可与 GPL-3 组合（经典共存组合）；补丁（存档目录注入）以文件级声明随附 |
| art3m1s-core（Artemis 真核） | MPL-2.0 | 同上（MPL 文件级共存）；`vulkan-backend` feature 原样使用，无修改 |
| xsystem35-sdl2 | GPL-2.0 | 同 ONScripter 的 GPL-2 策略 |
| AetherKiri / AetherMinori | GPL-3.0 / 私有运行时（AetherMinori 为私有仓库 → 未用作核心） | AetherKiri 仅作 ABI 设计参照（未链接其代码）；其 Artemis 运行时不可再分发 —— LusicGal 改用 art3m1s-core |
| SDL2 | Zlib | 宽松；`scripts/patch_sdl_android.sh` 的取窗补丁 diff 随附（Zlib 允许修改） |
| freetype | FreeType/FTL | 宽松 |

## Web 引擎（2026-10 形态；外板条目已移除）

| 组件 | 来源与许可 | 说明 |
|---|---|---|
| Web 跑法（LocalWebServer / AsarArchive / WebGameActivity / lg_web_boot.js） | 移植 + 重写自 **xm486/YukiHub（GPL-3.0）** `tyrano/TyranoActivity.java`、`tyrano/AsarArchive.java`、`assets/__tyrano__.js` | 本 App 为 GPL-3.0，同许可移植自洽；本地 HTTP + index.html 注入 + app.asar 解析 + 音频暂停表思路源自 YukiHub，代码已按 LusicGal 架构重写（Kotlin、Range 支持、RPG MV/MZ 自适应 hook、虚拟手柄为新增设计） |

> **外板启动协议行已移除（2026-10 用户指令）**：PSP（PPSSPP
> Intent）/ PC（winlator-cn extras）/ 应用条目
> （getLaunchIntentForPackage）三行连同其实现
> （`ExternalLaunchers.kt` / GamesProvider / 导入入口）一并删除
> —— 历史许可考据见 git 历史（提交 0a7a27e 及此前）。

## 分发形态（对应上述约束）

1. **Android**：引擎核心均为 `liblusicgal_<id>.so`，运行时 `System.loadLibrary("lusicgal_<id>")` 探测加载 —— 核心与壳进程内动态共存，缺失任意核心不影响 App（这正是 `probeEngines` 的设计动机之一）。桥 `liblusicgal_bridge.so` 本身零核心代码（dlsym 派发），不构成 GPL 组合。
2. **iOS**：静态链接不可避免，策略 = 核心 `liblusicgal_<id>.a` 以独立 Framework/静态库注入 pod，App 以 GPL-3 为主体、对 GPL-2-only 组件（ONScripter/xsystem35）提供"同源并列许可"声明；发布前必须复检上游 COPYING 全文。
3. **v1 APK 不捆绑任何核心**：所有核心经 CI artifact（`lusicgal-core-<id>-arm64`）产出，用户/发行版按需以 `jniLibs` drop-in 并入 —— 许可义务在核心实际分发时生效；接入每个核心前必须 ① 随附上游 LICENSE 原文 ② 列出补丁 diff（`scripts/patch_engines.sh` / `patch_sdl_android.sh` / YukiHub rfvp 补丁集）。
4. **renpy Route B 例外**：`librenpython.so` 与 rapt Java 树在外板壳模块内原样携带（LGPL §4d 静态链接替代方案不触发 —— 我们不修改；动态分发 + 源指针满足义务）。

> 本文件是工程决策记录，不构成法律意见。
