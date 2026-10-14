# Siglus / KEY 系核心（SiglusEngine · RealLive · AVG32 · UK2）

## 选型

**核心 = xmoezzz/siglus_rs**（Rust，MPL-2.0）—— 一个 crate 系列覆盖 **UK2 / AVG32 / RealLive / SiglusEngine**
四引擎：`game_fs`（文件系统）、`game_launcher`、`siglus_scene_vm`、`siglus_gameexe_ini`、
`siglus_g00_extract`（图片）、`siglus_omv_decoder`（视频）、`theora-rs` 等。

## 检测规则（权威来源）

本仓库 `lib/core/detect/engine_detector.dart` 的 KEY 系规则**逐条移植自上游
`crates/engine-detect/src/lib.rs`**（见该文件头注释）：

| 引擎 | 证据 |
|---|---|
| SiglusEngine | `Scene.pck` 或 `Gameexe.dat` |
| AVG32 | `Gameexe.ini` + `PACL` 封包 `SEEN.TXT` 或 `TPC32` 散装场景 |
| RealLive | `Gameexe.ini` + 10000 条目 `SEEN.TXT`（首场景头 `0x1d0`/`0x1cc`） |
| UK2 | `UK2.CFG` 或 `<< UK2 TEXT Ver1.00 >>` 魔数的 `.MES` |

## 集成路径（v0.4）

`native/rust/cbridge` → `lg_siglus_engine_*`；`game_fs` 直接对接 `game_path`；
Gameexe.ini 编码（auto-detect）进 options_json。

## 许可

MPL-2.0 —— 与 GPL-3.0 兼容。
