#!/usr/bin/env python3
"""手工 APK 管线：embedding 运行时依赖（精选静态清单）。

空文件不缓存（tmp-then-rename）；缺失类由 d8 阶段自报错补齐。
源：androidx → dl.google.com；io.flutter → download.flutter.io；其余 → central。
"""
import os
import shutil
import urllib.request

OUT = "/tmp/apkbuild/jars"
os.makedirs(OUT, exist_ok=True)
G = "https://dl.google.com/android/maven2"
C = "https://repo1.maven.org/maven2"
F = "https://storage.googleapis.com/download.flutter.io"


def p(g, a, v):
    return f"{g.replace('.', '/')}/{a}/{v}/{a}-{v}.jar"


def base(g):
    if g == "io.flutter":
        return F
    if g.startswith("androidx."):
        return G
    return C


def dl(g, a, v, ext):
    """下载（先本地缓存命中）→ 返回字节或 None。"""
    dst = f"{OUT}/{a}-{v}.{ext}"
    if os.path.exists(dst) and os.path.getsize(dst) > 200:
        return open(dst, "rb").read()
    for b in (base(g), C, G):
        url = f"{b}/{g.replace('.', '/')}/{a}/{v}/{a}-{v}.{ext}"
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = r.read()
            if len(data) < 200:
                raise ValueError("tiny")
            with open(dst, "wb") as f:
                f.write(data)
            return data
        except Exception:
            continue
    return None


def fetch(g, a, v):
    """androidx/relinker 多为 AAR：先 jar 后 aar，展开 classes.jar + res/。"""
    data = dl(g, a, v, "jar")
    if data is not None:
        with open(f"{OUT}/cj_{a}-{v}.jar", "wb") as f:
            f.write(data)
        return True
    data = dl(g, a, v, "aar")
    if data is None:
        print(f"MISS {g}:{a}:{v}")
        return False
    import io, zipfile
    z = zipfile.ZipFile(io.BytesIO(data))
    resd = f"/tmp/apkbuild/aar-res/{a}-{v}"
    os.makedirs(resd, exist_ok=True)
    os.makedirs("/tmp/apkbuild/cjars", exist_ok=True)
    for n in z.namelist():
        if n == "classes.jar":
            open(f"/tmp/apkbuild/cjars/{a}-{v}.jar", "wb").write(z.read(n))
        elif n.startswith("res/") and not n.endswith("/"):
            dst = f"{resd}/{n[len('res/'):]}"
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            open(dst, "wb").write(z.read(n))
    return True


LIST = [
    # embedding POM 直接依赖：
    ("androidx.lifecycle", "lifecycle-common", "2.7.0"),
    ("androidx.lifecycle", "lifecycle-common-java8", "2.7.0"),
    ("androidx.lifecycle", "lifecycle-process", "2.7.0"),
    ("androidx.lifecycle", "lifecycle-runtime", "2.7.0"),
    ("androidx.lifecycle", "lifecycle-viewmodel", "2.7.0"),
    ("androidx.lifecycle", "lifecycle-livedata-core", "2.7.0"),
    ("androidx.fragment", "fragment", "1.7.1"),
    ("androidx.annotation", "annotation", "1.8.1"),
    ("androidx.tracing", "tracing", "1.2.0"),
    ("androidx.core", "core", "1.13.1"),
    ("androidx.window", "window-java", "1.2.0"),
    ("androidx.window", "window", "1.2.0"),
    ("androidx.exifinterface", "exifinterface", "1.4.1"),
    ("com.getkeepsafe.relinker", "relinker", "1.4.5"),
    # 传递（fragment/core/window 触达面）：
    ("androidx.activity", "activity", "1.8.0"),
    ("androidx.annotation", "annotation-experimental", "1.3.1"),
    ("androidx.arch.core", "core-common", "2.2.0"),
    ("androidx.collection", "collection", "1.4.1"),
    ("androidx.customview", "customview-poolingcontainer", "1.0.0"),
    ("androidx.loader", "loader", "1.1.0"),
    ("androidx.savedstate", "savedstate", "1.2.1"),
    ("androidx.startup", "startup-runtime", "1.1.1"),
    ("androidx.versionedparcelable", "versionedparcelable", "1.1.1"),
]

ok = 0
for g, a, v in LIST:
    ok += fetch(g, a, v)
print(f"\n{ok}/{len(LIST)} jars ready in {OUT}")
for f in sorted(os.listdir(OUT)):
    print(" ", f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")
