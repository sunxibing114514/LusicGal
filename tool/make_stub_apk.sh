#!/usr/bin/env bash
# LusicGal 手工 APK 管线（窄工具版）
# ---------------------------------------------------------------------------
# 背景：本仓库的常规构建（flutter build apk → gradle）在开发容器内不可行：
#   - flutter 工具 + gradle daemon 共存 > 容器 cgroup 余量（~520MB，只读）；
#   - frontend_server 冷编完整框架闭包 >550MB，被内核 OOM（memory.events
#     oom_kill 递增实证）；
#   - gradle/AGP/Kotlin 三 JVM 同样装不下。
# 因此 APK 用「逐阶段窄工具」手工拼装（aapt2 / kotlinc / d8 / cmake-NDK /
# zipalign / apksigner 均为单进程小内存工具）。本脚本 = 该管线的可复现记录。
#
# 前提（容器内一次性就位）：
#   - JDK17 / kotlinc / android-sdk(platform-36, build-tools 36.0.0,
#     cmake 3.22.1, NDK 27.2.12479018) / flutter-sdk 均在 /tmp 下；
#   - 本脚本自身跑在 ≥1GB 空闲内存的机器上同样成立。
#
# 产物：build/outputs/apk/debug/LusicGal-stub-debug.apk
#   - 引导内核（tool/stub_kernel/main.dart，纯 dart:ui）；
#   - 真实业务内核热换：assets/flutter_assets/kernel_blob.bin 单文件替换
#     + zipalign + apksigner 重签（详见 docs/BUILD.md「内核边界与热换」）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="${LG_APKBUILD:-/tmp/apkbuild}"   # 工作目录（含已下载依赖缓存）
FLUTTER="${FLUTTER_SDK:-/tmp/flutter-sdk}"
SDK="${ANDROID_HOME:-/tmp/android-sdk}"
BT="$SDK/build-tools/36.0.0"
PLATFORM="$SDK/platforms/android-36/android.jar"
JDK17="${JAVA_HOME:-/tmp/jdk17}"

export PATH="$JDK17/bin:$PATH"

mkdir -p "$B" && cd "$B"

# ── ① flutter_assets（引导内核 + isolate 快照）───────────────────────────
# stub 闭包 ≈ dart:ui，冷编 <100ms / <200MB —— 唯一在本容器可编的内核。
# 注意：pubspec 需处于「仅 flutter + lusicgal_engines」形态（registrant 为空；
# 完整依赖形态下工具强制注入 registrant → 框架闭包 → OOM）。见 BUILD.md。
cd "$ROOT" && export PATH="$FLUTTER/bin:$PATH" HOME="${HOME:-/tmp}" CI=true
flutter assemble --no-version-check \
  --depfile build/app/intermediates/flutter/debug/flutter_build.d \
  --output build/app/intermediates/flutter/debug \
  -dTargetFile=tool/stub_kernel/main.dart -dTargetPlatform=android \
  -dBuildMode=debug -dTrackWidgetCreation=true \
  -dAndroidArchs=android-arm64 -dMinSdkVersion=21 debug_android_application
cd "$B"

# ── ② 插件 Kotlin（含 web 运行页）+ SDL Java 集合 ─────────────────────────
# SDL java（org.libsdl.app，SDL3 全套 + SDL2 音频兼容面）先经 javac 成
# class（kotlinc 对命令行 .java 仅做解析不做编译产出，故分两步）。
rm -rf jav-out ktl-out && mkdir jav-out ktl-out
find "$ROOT"/plugins/lusicgal_engines/android/src/main/java -name '*.java' > jav-sources.txt
javac -encoding UTF-8 -cp "$PLATFORM" -d jav-out @jav-sources.txt
"${LG_KOTLINC:-/tmp/kotlinc/bin/kotlinc}" \
  -cp "$PLATFORM:jav-out:${LG_EMBEDDING_JAR:-/tmp/embedding.jar}" \
  -d ktl-out \
  "$ROOT"/plugins/lusicgal_engines/android/src/main/kotlin/com/lusicgal/engines/*.kt \
  "$ROOT"/plugins/lusicgal_engines/android/src/main/kotlin/com/lusicgal/engines/web/*.kt

# ── ③ GeneratedPluginRegistrant（平时由 flutter gradle 插件生成）──────────
mkdir -p genout gen
cp "$ROOT/tool/apk_pipeline/GeneratedPluginRegistrant.java" gen/ 2>/dev/null || true
javac -encoding UTF-8 \
  -cp "${LG_EMBEDDING_JAR:-/tmp/embedding.jar}:ktl-out:$PLATFORM" \
  -d genout gen/GeneratedPluginRegistrant.java

# ── ④ d8（embedding + androidx 闭包 + kotlin-stdlib + 插件 + registrant）──
# 依赖闭包由 tool/apk_pipeline/fetch_deps.py 预取（AAR→classes.jar+res 展开）。
rm -rf dexout && mkdir dexout
CJ="$(ls cjars/*.jar | tr '\n' ' ')"
"$BT/d8" --release --min-api 21 --lib "$PLATFORM" --output dexout \
  "${LG_EMBEDDING_JAR:-/tmp/embedding.jar}" "${LG_KOTLINC:-/tmp/kotlinc}/lib/kotlin-stdlib.jar" \
  $CJ $(find genout jav-out -name '*.class') $(find ktl-out -name '*.class')

# ── ⑤ 资源（app res + 各 AAR res 分链：勿合并 values —— 节点级合并会被
#      aapt2 静默弃置；分离编译 + 多 zip link 实证可靠）───────────────────────
"$BT/aapt2" compile --dir "$ROOT/android/app/src/main/res" -o appres.zip
for d in aar-res/*/; do
  [ -d "$d" ] && [ -n "$(find "$d" -type f)" ] || continue
  n=$(basename "$d"); "$BT/aapt2" compile --dir "$d" -o "r-$n.zip"
done

# ── ⑥ 基包链接（assets = flutter_assets + 插件 lg_web_boot.js）─────────────
rm -rf allassets && mkdir allassets
cp -r "$ROOT/build/app/intermediates/flutter/debug/." allassets/
cp "$ROOT/plugins/lusicgal_engines/android/src/main/assets/lg_web_boot.js" allassets/
rm -f base.apk
"$BT/aapt2" link -o base.apk -I "$PLATFORM" \
  --manifest "$ROOT/tool/apk_pipeline/AndroidManifest.xml" \
  --min-sdk-version 21 --target-sdk-version 36 \
  --version-code 1 --version-name 0.1.0 \
  -A allassets appres.zip r-*.zip

# ── ⑦ dex + 原生库入库（.so STORED —— extractNativeLibs=false 直 mmap）────
rm -rf libs && mkdir -p libs/lib/arm64-v8a
unzip -o -q "$FLUTTER/bin/cache/artifacts/engine/android-arm64/flutter.jar" \
  'lib/arm64-v8a/libflutter.so' -d libs
cmake -S "$ROOT/native/bridge" -B "$ROOT/build/bridge-arm64" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SDK/ndk/27.2.12479018/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 \
  -DANDROID_STL=none -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/build/bridge-arm64"
cp "$ROOT/build/bridge-arm64/liblusicgal_bridge.so" libs/lib/arm64-v8a/
python3 - "$B" << 'EOF'
import sys, zipfile
b = sys.argv[1]
def add(apk, path, arc, stored):
    with zipfile.ZipFile(apk, 'a') as z:
        zi = zipfile.ZipInfo(arc)
        zi.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        z.writestr(zi, open(path, 'rb').read())
add(f'{b}/base.apk', f'{b}/libs/lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libflutter.so', True)
add(f'{b}/base.apk', f'{b}/libs/lib/arm64-v8a/liblusicgal_bridge.so', 'lib/arm64-v8a/liblusicgal_bridge.so', True)
add(f'{b}/base.apk', f'{b}/dexout/classes.dex', 'classes.dex', False)
EOF

# ── ⑧ 对齐 + 签名（-p：.so 页对齐）────────────────────────────────────────
rm -f aligned.apk lg.keystore
"$BT/zipalign" -p -f 4 base.apk aligned.apk
keytool -genkeypair -keystore lg.keystore -storepass lusicgal -keypass lusicgal \
  -alias lgdebug -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=LusicGal Debug, OU=LusicGal, O=LusicGal, L=Local, S=Local, C=CN" >/dev/null
"$BT/apksigner" sign --ks lg.keystore --ks-pass pass:lusicgal \
  --key-pass pass:lusicgal --out LusicGal-stub-debug.apk aligned.apk
"$BT/apksigner" verify LusicGal-stub-debug.apk

mkdir -p "$ROOT/build/outputs/apk/debug"
cp LusicGal-stub-debug.apk "$ROOT/build/outputs/apk/debug/"
echo "OK: build/outputs/apk/debug/LusicGal-stub-debug.apk"
