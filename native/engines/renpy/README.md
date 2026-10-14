# Ren'Py 核心（Route B：官方产物外板壳）

## 结论

Ren'Py 不做重实现、也**不经 LusicGal ABI 桥**：`librenpython.so` 自带完整
Python 运行时 + SDL3 生命周期，塞进 dlsym 桥会丢功能。采用 **Route B 外板壳**：
官方 rapt 链路的重组，全部落在 `modules/renpy/`（见该目录 README 的机制表）。

三个上游的分工：
- **renpy/renpy**（pin 80edccb）：运行时 Python 树（`renpy/`）+ `renpy/common`
  （打进 APK 资产 `x-renpy/x-common`）+ RPA 识别魔数出处。
- **renpy/renpy-build**（pin 6121730）：`build.sh --platform android --arch
  arm64_v8a --stop renpython` 产出 `librenpython.so`；rapt Java
  （PythonSDLActivity/ResourceManager/AssetExtract）原样复用。
- **chrismear/renios**（历史）：仅参考。

## 集成路径（v2 已实装）

1. `modules/renpy/build_android.sh` staging（librenpython.so + rapt/SDL3 Java +
   `private.mp3` 运行时 tar + `x-common` 资产）。
2. `scripts/patch_platform.py` 检测 `build-out/.ready` → App 并入 `:module-renpy`。
3. 启动：桥 `RenpyLauncher` → 显式 Intent → `RenpyGameActivity`
   （extends PythonSDLActivity）→ `getArguments() = [gamePath, "--savedir", savePath]`。
4. **iOS**：renios 链路（`run_ios.sh`）后续同型接入（独立 pod 子规范），v1 不做。

## 检测特征

`*.rpa`（魔数 `RPA-`，10 分）/ `renpy/` 目录（6 分）/ `*.rpyc`（6 分）。

## 许可

LGPL / MIT 混合（官方产物内含完整组件许可清单）—— 原样动态分发 + 源码指针
（renpy-build 仓库）；`main.py` / `RenpyGameActivity` 为 LusicGal 自有 GPL-3.0
代码。见 docs/LICENSE_NOTES.md 与 modules/renpy/README.md。
