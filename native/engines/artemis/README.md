# Artemis（minori 系）核心

## 参考项目

**AetherKiri/AetherKiri**（GPL-3.0）：Godot 4 宿主的多运行时视觉小说平台 ——
与 LusicGal 同构的参照系。其 `packages/AetherMinori`（submodule）即 **Artemis（minori 引擎）**
实现；`abi/include/engine_api.h` 是本仓库 `native/include/lusicgal/engine_abi.h` 的设计蓝本。

## v1 状态

- **检测**：待 AetherMinori 的文件格式文档化后补全规则（v1 提供手动指定引擎 —— 书库详情面板"指定引擎"）。
- **核心**：接入 AetherMinori（其上游许可与构建方式以 submodule 内实际文件为准）。

## 许可

GPL-3.0（AetherKiri 系）—— 与主 App 兼容。
