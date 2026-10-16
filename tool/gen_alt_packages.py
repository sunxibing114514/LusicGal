#!/usr/bin/env python3
"""生成 import_flow harness 的替换包表（flutter → tool/fbstub 最小桩）。

用法：python3 tool/gen_alt_packages.py [输出路径]
默认输出 /tmp/alt_packages.json。随后：

    dart --packages=/tmp/alt_packages.json tool/import_flow_harness_check.dart

背景：LibraryStore imports package:flutter/foundation.dart，其传递依赖
dart:ui 在纯 Dart VM 不可编 —— 桩只提供 ChangeNotifier / protected /
visibleForTesting 三符号（真运行期仍由 Flutter 提供）。
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STUB = (ROOT / "tool" / "fbstub").resolve()
SRC = ROOT / ".dart_tool" / "package_config.json"

out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/alt_packages.json")

if not SRC.exists():
    sys.exit("缺 .dart_tool/package_config.json —— 先 flutter pub get")

cfg = json.loads(SRC.read_text())
pkgs = []
for p in cfg["packages"]:
    if p["name"] == "flutter":
        p = dict(p)
        p["rootUri"] = STUB.as_uri()
        p["packageUri"] = "flutter/lib/"
    pkgs.append(p)

out_path.write_text(json.dumps({"configVersion": 2, "packages": pkgs}))
print(f"ok: {len(pkgs)} packages, flutter -> {STUB}, out={out_path}")
