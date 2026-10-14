# Kirikiri / KAG 核心（krkr2 家族）

## 选型

**核心基底 = 2468785842/krkr2**（`platforms/android` 完整 Gradle 工程 + `platforms/apple` iOS/macOS；CMakePresets + vcpkg overlay triplets）。该工程已被两个下游验证：
- **KiriKiri-LauncherC**（fork）：模块化工程化 + per-game 偏好配置 + Breakpad/Dobby/oneTBB/mimalloc 的移动端接入清单。
- **KrKr2-Next**：Flutter + ANGLE 路线（证明 iOS 走 ANGLE→Metal，而非裸 GLES）。

## 集成路径（v0.3，docs/ROADMAP.md）

1. `scripts/fetch_engines.sh` 拉取 `kirikiri2`（pin `dca7264`）。
2. Android：复用其 `platforms/android` 工程参数构建 `liblusicgal_kirikiri.so`。
3. iOS：`platforms/apple` + ANGLE（学 KrKr2-Next）。
4. ABI 包装：TJS2 主循环 → `lg_kirikiri_engine_set_surface`，XP3 自动挂载（`data.xp3` 等）。

## 检测特征

`*.xp3`（魔数 `XP3\r\n\x1a\x8a`，10 分）/ `startup.tjs`（5 分）/ `*.tjs`（3 分）。

## 许可

仓库标 NOASSERTION（血统为 KrKr 私有许可声明，fork 群按 GPL-3 处理）。分发前必须复检其 LICENSE 原文 —— 见 docs/LICENSE_NOTES.md。
