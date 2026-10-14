# Sena（SoftPAL 引擎，Koikake）核心

## 选型

**核心 = xmoezzz/sena-rs**（Rust，MPL-2.0）。README 平台表**官方支持 iOS arm64/simulator 与
Android arm64-v8a/x86_64**，`platform/android` + `platform/ios` 现成。
入口 crate：`pal-vm`（bin `sena`，`--nls sjis` 参数与 engine_abi.h 的 options_json 直接对应）。

## 集成路径（v0.4）

`native/rust/cbridge` → `lg_sena_engine_*`；启动参数：
`game_path` + options（`nls` 编码）→ pal-vm。存档写 `save_path`。

## 检测特征

`*.pac`（6 分，SoftPAL PAC 封包，crate `pal-pac-unpacker`）。
注：`.pac` 在其他引擎中也有使用，故分数偏低、置信度不足时 UI 让用户确认。

## 许可

MPL-2.0 —— 与 GPL-3.0 兼容。
