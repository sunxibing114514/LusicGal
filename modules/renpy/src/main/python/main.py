#!/usr/bin/env python
# LusicGal Ren'Py 外板壳的 Python 启动脚本（打进 private.mp3，随
# PythonSDLActivity.unpackData 解到 ANDROID_PRIVATE）。
#
# 与官方发行包 <game>.py 同构（renpy.py main() 的精简版）：
#  1. renpy_base = ANDROID_PRIVATE（解包出的 renpy/ Python 树所在处）；
#  2. bootstrap(renpy_base) —— sys.argv 由 SDL3 getArguments() 注入：
#     argv[1] = <gamePath>（bootstrap 位置参数 basedir，renpy/arguments.py）
#     argv[2:] = ["--savedir", <savePath>]（LusicGal per-game 存档目录）
#  3. renpy/bootstrap.py: basedir != renpy_base → loader.find_apks 跳过
#     assets/x-game 的 APK 内游戏数据 → 游戏目录完全走文件系统。
import os
import sys

renpy_base = os.environ.get("ANDROID_PRIVATE",
                            os.path.dirname(os.path.abspath(sys.argv[0] or ".")))
sys.path.insert(0, renpy_base)

import renpy.bootstrap  # noqa: E402

renpy.bootstrap.bootstrap(renpy_base)
