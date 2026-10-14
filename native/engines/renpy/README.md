# Ren'Py 核心（官方链路）

## 结论（对应需求"待解决问题：Ren'Py 的 iOS 构建需要 Xcode + Python 环境整合"）

Ren'Py 不做重实现：**官方 renpy-build 已内建 rapt/（Android）与 renios/（iOS）**，在 Ubuntu 24.04 容器内产出含嵌入式 Python 的移动静态库/动态库 —— 这就是官方答案，v0.5 直接采用。

三个上游的分工：
- **renpy/renpy**（引擎本体，`renpy/android.py`、`sphinx/source/ios.rst` 官方 iOS 指南）：运行时与 RPA 格式（识别魔数 `RPA-3.0 ` 的出处 `renpy/loader.py`）。
- **renpy/renpy-build**（构建系统）：`prepare.sh + build.sh`、`run_ios.sh`、`test_android.sh / test_ios.sh` —— CI 产物 job 的执行入口。
- **chrismear/renios**（历史）：LGPL-2.1 第三方打包器的经验记录（Python 静态嵌入 iOS 的必然性）；仅作参考。

## 集成路径（v0.5）

1. CI 容器跑 renpy-build 产出 `renios` iOS 静态库与 rapt Android 库。
2. C 入口包装（renpy 官方提供 `renpy_main` C API）→ `lg_renpy_engine_*`。
3. 每游戏独立 Python 环境（`game/` + 编译缓存）置于游戏目录旁。

## 检测特征

`*.rpa`（魔数 `RPA-`，10 分）/ `renpy/` 目录（6 分）/ `*.rpyc`（6 分）。

## 许可

LGPL / MIT 混合（官方）—— 与 GPL-3.0 App 兼容；随附上游 LICENSE。
