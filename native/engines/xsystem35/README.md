# System 3.x（AliceSoft）核心

## 选型

**核心 = kichikuou/xsystem35-sdl2**（C + SDL2，GPL-2.0）。上游**自带完整 Android Gradle 工程**
（`android/app`、`android/README.md`）—— NDK 内嵌编译 SDL2 + 引擎本体的现成范本。

## 集成路径（v0.3）

1. 复用上游 `android/` Gradle 工程参数 → `liblusicgal_xsystem35.so`。
2. SDL2 与 ONScripter 的 iOS SDL 链路共用（见 native/engines/onscripter）。
3. ABI 包装：xsystem35 主循环 → `lg_xsystem35_engine_set_surface`；
   `playlist.txt` 虚拟 CD 特性透传 options_json。

## 检测特征

`*.ald`（10 分，AliceSoft ALD 封包）。

## 许可

GPL-2.0 —— 分发策略同 ONScripter（docs/LICENSE_NOTES.md）。
