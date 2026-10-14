# LICENSE_NOTES — 许可与分发策略

## 主 App

**GPL-3.0**（与 KrKr2-Next / AetherKiri / YukiHub 同选）。

## 引擎核心许可矩阵

| 核心 | 上游许可 | 与 GPL-3.0 App 共存方式 |
|---|---|---|
| KrKr2 系 | 仓库标记 NOASSERTION（KrKiri 血统为作者自有许可，fork 多以 GPL-3 处理，如 KrKr2-Next） | 以**独立可再分发模块**接入；分发时随附其原始 LICENSE 与修改声明 |
| ONScripter 系 | GPL-2.0（Ogapee 原始）；onscripter-ru 部分 BSD | **GPL-2-only 风险点**：不与 GPL-3 静态混链。策略：核心以独立 native 库交付（Android 动态库天然分离；iOS 以独立 Framework + 文档说明），或整包以"GPL-2+GPL-3 双许可并列"发布（v1 阶段核心尚未打包，无即时冲突） |
| Ren'Py 系 | LGPL / MIT 混合（官方） | 宽松，可直接链接；随附 renpy 的 LICENSE 文件 |
| rfvp / siglus_rs / sena-rs | MPL-2.0（文件级弱 copyleft） | **兼容**：MPL 文件保持独立来源标注即可与 GPL-3 组合（经典共存组合） |
| xsystem35-sdl2 | GPL-2.0 | 同 ONScripter 的 GPL-2 策略 |
| AetherMinori(Artemis) / AetherKiri 系 | GPL-3.0 | 直接兼容 |
| SDL2 | Zlib | 宽松 |
| freetype | FreeType/FTL | 宽松 |

## 分发形态（对应上述约束）

1. **Android**：引擎核心均为 `liblusicgal_<id>.so`，运行时 `System.loadLibrary` 探测加载 —— 核心与壳进程内动态共存，缺失任意核心不影响 App（这正是 `probeEngines` 的设计动机之一）。
2. **iOS**：静态链接不可避免，策略 = 核心以独立 Framework/静态库注入，App 以 GPL-3 为主体、对 GPL-2-only 组件（ONScripter/xsystem35）提供"同源并列许可"声明；发布前必须复检上游 COPYING 全文。
3. **引擎核心不打包（当前状态）**：所有许可义务暂为文档级；接入每个核心前必须 ① 随附上游 LICENSE 原文 ② 列出补丁 diff（如 YukiHub rfvp 补丁集）。

> 本文件是工程决策记录，不构成法律意见。
