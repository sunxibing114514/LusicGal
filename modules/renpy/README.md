# Ren'Py 外板壳模块（Route B）

## 设计

Ren'Py 不经 LusicGal ABI 桥 —— `librenpython.so`（renpy-build 官方产物：
SDL3 3.4.8 + Python 3.12 + ffmpeg 全静态）自带完整运行时与生命周期，
硬塞进 dlsym 桥只会丢功能（Python 环境、资产管理、IAP…）。

本模块是**官方 rapt 链路的重组**（依据 renpy/renpy-build @ pin 精读）：

| rapt 官方语义 | 本模块的等价物 |
|---|---|
| `rapt/prototype/renpyandroid` Java（PythonSDLActivity/ResourceManager/AssetExtract…） | staging 原样拷贝（`build-out/java/rapt`） |
| `libsdl` 符号链接 → SDL3 android-project Java | `build-out/java/sdl`（tmp 产物或符号链接解析） |
| `librenpython.so`（tasks/renpython.py android 链接） | `build-out/jniLibs/arm64-v8a/` |
| `private.mp3` tar（build.py::split_renpy → main.py + renpy/ 无 common） | 自行组装：`main.py`（本模块模板）+ renpy 仓 `renpy/` Python 树 |
| `assets/x-renpy/x-common/**`（make_assets_tree 逐段 x- 前缀） | 自行组装：renpy 仓 `renpy/common/**` |
| 游戏打进 APK（assets/x-game） | **改为 argv 注入**：`RenpyGameActivity.getArguments()` → `[<gamePath>, "--savedir", <savePath>]` |

**为什么 argv 注入可行**（renpy/renpy @ 80edccb 精读）：
- `renpy/bootstrap.py`：位置参数 `basedir` → `basedir = os.path.abspath(args.basedir)`，
  Android 下缺失 `game/` 自动 `mkdir`；
- `renpy/loader.py::find_apks`：`renpy_base != basedir` 时**跳过** `assets/x-game/`
  的 APK 内游戏读取 → 游戏目录完全走文件系统（LusicGal 导入目录）；
- `renpy/arguments.py`：`--savedir DIRECTORY` 官方参数 → LusicGal per-game 存档目录；
- SDL3 `SDLActivity.getArguments()` → `nativeRunMain` argv。

## 文件

```
modules/renpy/
├── build.gradle                    # com.android.library；srcDirs = 模板 + staged Java
├── consumer-rules.pro              # keep rapt/SDL/LusicGal 类
├── src/main/AndroidManifest.xml    # RenpyGameActivity 声明（exported=false）
├── src/main/res/values/strings.xml # private_version（bump 触发重解包）
├── src/main/python/main.py         # private tar 的 Python 启动脚本
├── src/main/java/.../RenpyGameActivity.java
└── build_android.sh                # staging（重：renpy-build 完整 Android 产物链）
```

## 使用

```bash
bash scripts/fetch_engines.sh renpy-build
bash scripts/fetch_engines.sh renpy
bash modules/renpy/build_android.sh   # staging → build-out/.ready
# 之后任意 App 构建（CI/本地）经 scripts/patch_platform.py 自动并入 ':module-renpy'
```

运行期：书库启动 renpy 游戏 → 桥 `RenpyLauncher`（plugins/.../RenpyLauncher.kt）
显式 Intent → `com.lusicgal.renpy.RenpyGameActivity`。

## 许可（docs/LICENSE_NOTES.md）

librenpython.so / rapt Java / renpy Python 树**原样分发**（LGPL + Python 软件基金会
+ MIT/Zlib 组件清单在 renpy 发行物内），不修改不静态并入 LusicGal 壳 —— 动态模块
边界即许可边界。`main.py` 与 `RenpyGameActivity` 为 LusicGal 自有代码（GPL-3.0）。
