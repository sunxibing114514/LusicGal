# BUILD — 构建 / 编译验证

## CI（权威验证方式）

仓库推送后由 GitHub Actions 验证（对应用户要求：**编译验证在私有仓库完成，不在本地进行**）。

### `.github/workflows/app.yml`

> 配额说明：私有仓库 Actions 按分钟计费（macOS runner ×10）。默认 push 只跑
> ubuntu job。**iOS 暂不构建**（用户指令）：引擎核心验证只做 Android arm64；
> iOS 侧源码（桥/插件/stub）保持就位但不构建、不进 CI。

| Job | Runner | 步骤 | 产物 |
|---|---|---|---|
| `verify` | ubuntu-latest | `pub get` → `analyze` → `test` → `flutter create --platforms=android` → 补丁 → `flutter build apk --release` | `app-release.apk`（artifact） |
| `build-ios`（手动） | macos-latest | `flutter create --platforms=ios` → 补丁 → `flutter build ios --debug --simulator` | 构建通过 |

### `.github/workflows/engines.yml`（v2）

必绿门禁合并为单一 ubuntu job `gates`；**真核 Rust 四核每次 push 交叉编译产出 `.so` artifact**；C/C++ 实验核心仅手动触发：

| Job | 内容 | 性质 |
|---|---|---|
| `gates` | C ABI selftest v2（0x00020000）/ JNI 桥 ×NDK（dlsym 版）/ Rust FFI 门禁（`native/rust/cbridge`，复用 `lg_common`）/ 19 个上游 pin 校验 | **必须绿** |
| `rust-cores`（matrix: sena/rfvp/siglus/artemis） | `scripts/build_rust_core.sh` 交叉编译 `liblusicgal_<id>.so`（arm64-v8a）→ artifact `lusicgal-core-<id>-arm64` | **push 即跑**（rust-cache 缓存重依赖） |
| `onscripter-android` / `xsystem35-android` / `kirikiri-android` / `renpy-module`（手动） | C/C++ 核心交叉编译与 Ren'Py 外板壳 staging 尝试 | `continue-on-error`（非阻塞，逐个转正） |

## 本地（可选，CI 均已覆盖；2026-10 本地实构建实证见下）

```bash
flutter pub get
flutter analyze
flutter test

# 平台壳（已 .gitignore，按需生成）
flutter create --platforms=android --org com.lusicgal --project-name lusicgal .
python3 scripts/patch_platform.py           # 注入 Android largeHeap / 重建校验
flutter build apk --release
```

### 本地实构建实证（NDK r27c / Rust 1.99 / 400MB 内存约束容器）

无需 Android Studio/SDK 全家桶 —— 只要 NDK（zip 解包）+（Rust 核心另需 rustc
tarball 手动装，rustup 全组件解压在小内存容器会 OOM）：

```bash
export ANDROID_NDK_HOME=<ndk>; export PATH=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

# JNI 桥（CI gates job 等价物；产物 liblusicgal_bridge.so）
cmake -S native/bridge -B build-bridge -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DCMAKE_BUILD_TYPE=Release
cmake --build build-bridge

# ONScripter / xsystem35（依赖上游 script/_fetch.sh 或 FetchContent，均自动拉）
bash native/engines/onscripter/build_android.sh    # 9 件 .so
bash native/engines/xsystem35/build_android.sh    # 7 件 .so

# Kirikiri：需 vcpkg 工具（clone + bootstrap + 完整历史 —— manifest 版本
# 解析要 git show 旧提交）+ CMake ≥3.28；工具链拓扑见其 adapter/CMakeLists.txt
# （入口 toolchain = vcpkg.cmake，链挂 NDK，manifest/overlay 指向 krkr2 根）。
# 注意：整链（angle/ffmpeg/opencv4 等港口风暴）需 ~GB 级内存 —— CI 7GB
# runner 为场域；本地小容器实测在 spirv-tools（-O3 -g 模板重单元）OOM。

# Rust 壳独立检查（无需上游 crate 编译 —— 剥离 path 依赖，覆盖壳全部自有代码）
bash scripts/rust_local_check.sh                  # host + aarch64-android 双目标
```

实证结论（本仓库代码面）：桥/ONS/xsystem35 全链可产 arm64 真产物；Rust 四壳
独立检查全绿；Rust 全量上游编译（wgpu 系单 crate 编译峰值）超内存上限
（历史实证 400MB；现行用户上限已收紧为 **300MB**，见下），
不可行 —— 四壳上游交叉编译仍以 CI rust-cores 矩阵为准。

## 引擎核心构建（v2 核心分发模型）

每个核心 = 独立 `liblusicgal_<id>.so`（Android）/ `liblusicgal_<id>.a`（iOS 静态并入
pod）。App 的 `liblusicgal_bridge.so` 不链接任何核心 —— 运行期 `dlsym` 派发
（Kotlin 先 `System.loadLibrary("lusicgal_<id>")` 再经桥 `probeCore`）。
缺核心 = 探测报告不可用，App 其余功能不受影响。

```bash
bash scripts/fetch_engines.sh              # 按 pin 浅拉取 19 个上游 → third_party/upstream/
bash scripts/patch_engines.sh              # 存档目录注入（siglus/sena/rfvp/krkr2）
bash scripts/build_rust_core.sh sena       # Rust 核心：sena / rfvp / siglus / artemis
bash native/engines/onscripter/build_android.sh    # C++ 核心（需上游 script/_fetch.sh）
bash native/engines/xsystem35/build_android.sh     # C++ 核心（FetchContent 自拉 SDL2）
bash native/engines/kirikiri/build_android.sh      # C++ 核心（vcpkg + patch_engines.sh）
```

核心产物在 `build/cores/<id>/arm64-v8a/`；作为 `jniLibs` 放入任意 APK 即被
`EngineHost.probe` 识别（见 docs/ARCHITECTURE.md §核心分发）。renpy 例外 ——
Route B 外板壳模块 `modules/renpy/`（`RenpyGameActivity` 承载官方 `librenpython.so`，
不经 ABI 桥）：

```bash
bash modules/renpy/build_android.sh   # staging：renpy-build 产物 + Java + 运行时资产
# staging 后任意 App 构建自动并入 :module-renpy（scripts/patch_platform.py 检测 .ready）
```

各引擎的具体链路（vcpkg triplet / SDL 取窗补丁 / cargo 交叉…）见各
`native/engines/<id>/README.md` 与 `docs/ENGINE_NOTES.md`。

## widget 测试契约（避免死锁）

- `testWidgets` body 运行于 fake-async zone：`scheduleMicrotask` 被拦截。**一切真实 IO（文件读写、临时目录）必须包进 `tester.runAsync`**，否则 IO 完成回调停在 fake 队列，body 永久挂起（超时堆栈为 `dart:isolate _RawReceivePort._handleMessage`）。
- 未 mock 的平台通道回复永不完成：测试里用 `setMockMethodCallHandler` 返回 `null`，让 `EngineHost` 走"核心未打包"分支（真实生产行为）。
- 泵送用有界 `pump(Duration)` + 显式 `timeout`，不用无限期 `pumpAndSettle`。
- 范例见 `test/widget_test.dart`（完整壳）与 `test/lean_shell_test.dart`（精简壳）。

## 常见问题

- **为什么没有 android/ ios/ 目录？** 平台壳由 CI 确定性重建（`flutter create`），自定义原生代码全部在 `plugins/lusicgal_engines` 与 `native/` —— 见 docs/ARCHITECTURE.md §6。
- **iOS 真机调试？** `flutter build ios --no-codesign` 产物 + Xcode 手动签名即可。
- **导入的游戏去哪了？** App Documents `games/<id>/`；iOS 可通过"文件"App 的 LusicGal 目录直接投放（CI 已注入 UIFileSharingEnabled）。

## 本地验证 harness（无 Flutter 工具链也可跑）

纯 Dart 逻辑（检测器 / 条目模型）与 Web hook（JS）可在无 Flutter/Android SDK
的环境直接验证 —— 容器内存约束下可行（现行上限 **300MB**；历史 400MB
实证记录保留）：

```bash
# Dart SDK 任意 ≥3.x（dart-sdk/bin 在 PATH）
dart tool/detector_harness_check.dart    # 检测器新规则 + 回归（20 项）
dart tool/gameentry_harness_check.dart   # GameEntry options 序列化往返（6 项）
dart --packages=/tmp/alt_packages.json \
  tool/import_flow_harness_check.dart    # 导入流 13 项（PC 原位/挑 exe/
                                         # PSP 入库/应用条目/核心回归）
node plugins/lusicgal_engines/android/src/main/assets/lg_web_boot.js  # 语法检查
# node 冒烟（音频生命周期 / 按键合成 / Tyrano 存档桥）见 ENGINE_NOTES
```

- **import_flow harness 的 foundation 桩**：LibraryStore imports
  `package:flutter/foundation.dart`（传递依赖 dart:ui，纯 VM 编不动）
  → 最小桩（ChangeNotifier / protected / visibleForTesting 三符号，
  /tmp/fbstub）+ 替换包表（/tmp/alt_packages.json）。该 harness 已抓
  两个真 bug：const 构造含字符串插值（CI analyze 必红）与子目录 exe
  双重前缀 —— 真源码级验证的价值实证。

- harness 直跑真实源码（`lib/core/…` 相对导入），非副本；`tool/**`
  已排除静态分析（print/exit 汇报）。
- **flutter 工具链为容器边界（2026-10-16 实证，300MB 现行上限）**：
  - flutter 3.47.7 stable 可装可用（工具自身峰 RSS ≈ 97MB；pub get 绿）；
  - `flutter analyze`：LSP 分析服务器交换完 capabilities 后峰值超 400MB
    看护被杀（-9）——全包图（含 flutter 框架闭包）撑不下；
  - `flutter test`：frontend 编译器（tool 82MB + compiler）47 秒被
    cgroup OOM 击杀（"The Dart compiler exited unexpectedly"），无看护
    直跑同结果 —— 与 Rust wgpu 系同类资源边界，非遗漏；
  - 检测器/条目逻辑以纯 Dart harness 等价覆盖（同批断言）；Kotlin 侧
    以 kotlinc（JDK17 + android-34 + embedding jar）全量编译绿 +
    WebServer/Asar JVM 功能实测 17/17 替代。CI 恢复后 flutter
    analyze/test 归 app job。
