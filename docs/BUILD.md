# BUILD — 构建 / 编译验证

## CI（权威；2026-10-18 起仓库转公有后恢复可用）

仓库推送后由 GitHub Actions 验证。配额历史（2026-10-17~18）：私有仓库
Actions 配额耗尽，run 创建后 runner 拒绝接入（steps=0，本页"本地手工
管线"即该空窗期的补位实证）。**2026-10-18 仓库转 public**（GPL 开源 +
release 公开分发），标准 runner 免配额，engines.yml 四核矩阵恢复为
Rust 核心权威产线；本地 Windows 仅保留 sena 一核实证产物与下述交叉
编译配方（as-is 备档）。

### `.github/workflows/app.yml`

> **iOS 暂不构建**（用户指令）：引擎核心验证只做 Android arm64；
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

## 本地手工 APK 管线（2026-10-17 实证，**550MB 内存 / 550MB APK 上限**）

容器边界（多轮实证，memory.events oom_kill 累计 11 次）：

- cgroup `memory.max=954MB` 与外来服务共享（node/NCM 常驻 ~432MB）
  → 有效余量 ~520MB，只读不可调、无 swap；
- flutter 工具（~82MB）+ gradle daemon（~435MB）共存必超；
- frontend_server 冷编完整框架闭包（即使 stub main）>550MB 被内核
  OOM；gradle/AGP 的 includeBuild Kotlin 编译同为巨物 —— **gradle
  全家在这台容器装不下**。

因此 APK 用**逐阶段窄工具**拼装（每阶段单进程、小内存、可独立验证）：
`flutter assemble`（仅引导内核）→ `kotlinc`（280m heap 实证绿）→
`d8` → `aapt2 compile/link`（分离 res zip，**勿合并 values 文件**）
→ cmake-NDK（桥 .so）→ `zipalign -p` → `apksigner`。

```bash
python3 tool/apk_pipeline/fetch_deps.py     # 依赖闭包预取（AAR→classes.jar+res）
bash tool/make_stub_apk.sh                 # 全管线（可复现记录）
# 产物 build/outputs/apk/debug/LusicGal-stub-debug.apk（402MB < 550MB ✓）
```

实证产物（2026-10-17）：`package=com.lusicgal.lusicgal v1`、
launchable=`io.flutter.embedding.android.FlutterActivity`、
`native-code=arm64-v8a`、apksigner verify 绿、105 entries、
flutter_assets/kernel_blob.bin（引导内核 5.4KB）+ isolate_snapshot_data
+ lg_web_boot.js + libflutter.so（STORED 页对齐，extractNativeLibs=false）
+ classes.dex（embedding + androidx 闭包 + 插件 + GeneratedPluginRegistrant
手写注册表，5.5MB）。

### 内核边界与热换（Kernel Boundary & Hot-swap）

**app.dill（真实业务内核）在本容器不可编** —— `frontend_server` 对
`lib/main.dart`（material 框架闭包）的冷编峰值 >550MB，9+ 次 OOM
实证；工具还强制注入 dart_plugin_registrant（引插件接口→框架闭包）。
已装 APK 携带**引导内核**（`tool/stub_kernel/main.dart`：纯 dart:ui
画说明页，冷编 ~85ms/<200MB —— 本容器唯一可编内核）。

在任意 ≥1GB 空闲内存的机器（或配额恢复后的 CI）产出真实内核后，
对已签 APK 做**单文件热换**：

```bash
# 1) 正常机器：flutter assemble ... -dTargetFile=lib/main.dart
#    （或 flutter build apk --debug 取其 kernel_blob.bin）
# 2) 热换（无需重编/重打包整 APK）：
python3 - << 'EOF'
import zipfile
# 用新 kernel_blob.bin 原地替换 APK 内 assets/flutter_assets/kernel_blob.bin
EOF
zipalign -p -f 4 in.apk out.apk && apksigner sign --ks <ks> out.apk
```

热换不触碰 dex/资源/原生库 —— 插件注册表（GeneratedPluginRegistrant）
已编入 classes.dex，真实内核启动即经 embedding 反射注册
lusicgal/engines 通道；stub→real 仅差 kernel_blob.bin 一个文件。
调试引擎（libflutter.so debug 版 + isolate_snapshot_data + JIT）与
JIT 语义下 kernel_blob 即全量业务逻辑，无 AOT 快照耦合。

## 本地（可选，CI 均已覆盖；手工 APK 管线见上）

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
（历史实证 400MB；现行用户上限为 **550MB**，见上），四壳上游交叉编译
以 CI rust-cores 矩阵为准。

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
的环境直接验证 —— 容器内存约束下可行（现行看护 **550MB**；2026-10-17
实测 import_flow 10/10、detector 15/15、gameentry 6/6 全绿）：

```bash
# Dart SDK 任意 ≥3.x（dart-sdk/bin 在 PATH）
dart tool/detector_harness_check.dart    # 检测器新规则 + 回归（15 项）
dart tool/gameentry_harness_check.dart   # GameEntry options 序列化往返（6 项）
dart --packages=/tmp/alt_packages.json \
  tool/import_flow_harness_check.dart    # 导入流 10 项（目录入沙盒/tyrano
                                         # web 入库/散装 xp3/纯 exe 原样退回）
node plugins/lusicgal_engines/android/src/main/assets/lg_web_boot.js  # 语法检查
# node 冒烟（音频生命周期 / 按键合成 / Tyrano 存档桥）见 ENGINE_NOTES
```

- **import_flow harness 的 foundation 桩**：LibraryStore imports
  `package:flutter/foundation.dart`（传递依赖 dart:ui，纯 VM 编不动）
  → 最小桩（ChangeNotifier / protected / visibleForTesting，
  入仓于 `tool/fbstub/`）+ 替换包表（/tmp/alt_packages.json 指向它）。

- harness 直跑真实源码（`lib/core/…` 相对导入），非副本；`tool/**`
  已排除静态分析（print/exit 汇报）。
- **flutter 工具链为容器边界（2026-10-16/17 实证，550MB 看护）**：
  - flutter 3.47.7 stable 可装可用（pub get 绿；assemble 引导内核 85ms 绿）；
  - `flutter analyze`：LSP 分析服务器交换完 capabilities 后峰值超看护
    被杀（-9）—— 全包图（含 flutter 框架闭包）撑不下；
  - app.dill 冷编（frontend_server）：550MB 看护与裸跑均被 cgroup OOM
    （memory.events oom_kill 累计 11）；工具强注 registrant 无法剥离；
  - gradle/AGP 管线：daemon（435MB）+ includeBuild Kotlin 编译超
    cgroup 余量（~520MB）—— 手工窄工具管线（见上）替代；
  - 检测器/条目逻辑以纯 Dart harness 等价覆盖（同批断言）；Kotlin 侧
    以 kotlinc（JDK17 + android.jar + embedding jar，280m heap）全量编译绿 +
    WebServer/Asar JVM 功能实测 17/17 替代。CI 恢复后 flutter
    analyze/test 归 app job。

## Windows 本地管线实录（2026-10-18，真内核 APK 落地）

容器内核 OOM 无法翻越的 app.dill 冷编，在 Windows（1.9GB RAM + 页文件 +
DSH 沙箱）上完成闭环。沙箱约束与对策（全部实证）：

- **PowerShell 全域 ConstrainedLanguage**：`[System.IO.*]`、方法调用
  一律拒 —— 文件操作走 cmdlet/`tar`/文件工具；flutter 自带
  `update_engine_version.ps1`/`update_dart_sdk.ps1`（共享 bat 每次必调）
  置为 `exit 0` 桩 —— zip 自带 `engine.stamp`/`flutter_tools.snapshot`
  全齐，桩后不触发任何重建。
- **子进程管道 stdio 被禁**（EPERM/CreateFile failed 5）：`dart`/
  frontend_server/`tar`/`node` 直跑全部可行；一切"工具套工具"
  （flutter.bat 套 git、gradle、sdkmanager）不可行 → 全程绕开 flutter 命令行。
- **curl.exe schannel 被掐**（SEC_E_NO_CREDENTIALS）→ node fetch
  流式下载器 `.toolchain/dl.js`（OpenSSL 栈）。
- pub 缓存/临时目录重定向到工作区（systemprofile AppData 拒绝访问）；
  MinGit + `GIT_CONFIG_GLOBAL`（必须 UTF-8；`[safe] directory = *`）。

四步真内核管线（脚本均入仓 `tool/apk_pipeline/`）：

1. **工具链还原**：flutter_windows_3.47.7-stable.zip + MinGit +
   JDK17（Temurin）+ build-tools_r34 直下解压（均经 dl.js）；磁盘吃紧时
   删 `artifacts/engine/*`（仅留 `common`（flutter_patched_sdk）与
   `windows-x64`（frontend_server），内核编译只需此四件套）。
2. **包还原 `restore_pkgs.js`**：按迁移来的 `.dart_tool/package_config.json`
   从 `pub.dev/api/archives/<name>-<version>.tar.gz` 拉全 64 个 hosted
   包（纯 node gunzip + tar 解析，零 spawn），SDK 包指向
   `.toolchain/flutter/packages/*`，重写包表（Linux 原表备份 `.linux.bak`）。
3. **手动 frontend_server 冷编**（即 Linux OOM 九连处）：

   ```
   dartaotruntime.exe artifacts\engine\windows-x64\frontend_server_aot.dart.snapshot
     --sdk-root artifacts\engine\common\flutter_patched_sdk
     --target flutter --no-print-incremental-dependencies
     -Ddart.vm.profile=false -Ddart.vm.product=false
     --enable-asserts --track-widget-creation --no-link-platform
     --packages C:\LusicGal\.dart_tool\package_config.json
     --output-dill build\win_kernel\app.dill --depfile build\win_kernel\app.d
     C:\LusicGal\lib\main.dart
   ```

   产物 55,943,464 B，errorCount 0。页文件扛峰（Linux 侧为
   memory.swap.max=0 硬墙，Windows 无此墙）。dart 侧 registrant 未注：
   Android 运行时插件注册由 Java `GeneratedPluginRegistrant`（classes.dex
   内）负责，dart registrant 仅服务桌面嵌入器/测试。
4. **热换 + 对齐 + 签名**：`swap_kernel.js`（仅动
   `assets/flutter_assets/*`，95 条目字节级原样保留含 STORED 的
   libflutter.so/resources.arsc 与 `assets/lg_web_boot.js`）→
   `zipalign -p -f 4` → `apksigner sign`（Windows 新生成的 debug
   keystore：SHA-256 `07eb78cf…6433889`；与 Linux 侧签名不同，覆盖安装
   需先卸载）。

产物 `build/outputs/apk/debug/LusicGal-debug.apk`：419,173,478 B
（**419MB ≤ 550MB 上限**），105 条目，kernel_blob.bin = 55,943,464 B
真内核，apksigner verify 通过。

**引擎核心 .so 注入（`add_libs.js` + `strip_sigblock.js`）**：Linux 侧
已编成的核心（onscripter 全家桶：SDL2/image/ttf/mixer、lua、bz2、
onsyuri；xsystem35 全家桶：webp、sharpyuv；两核心共用 libc++_shared
与一套 SDL2/mixer —— 取 xsystem35 构建，SDL2 soname ABI 兼容）以
STORED 追加进 `lib/arm64-v8a/`；zip 手术要点：数据区与旧 CD 记录
原样保留、新 CD = 旧记录 + 新记录、EOCD 的 size/offset 字段易写反
（两次实测踩坑）；随后 `zipalign -p -f 4` + apksigner 重签。签名基座
若只剩已签 APK，用 `strip_sigblock.js` 剥 v2/v3 块还原未签名态。
终版 **420.0MB，118 条目，15 个 .so 全 STORED**，apksigner verify 通过。

- **renpy 自建模块（open source 原生，非 web）**：renpy-build 需要
  bash + Linux NDK 工具链路径，Windows 无 WSL 不可本地原生复现；
  上游 pin（renpy-build@6121730 + renpy@80edccb）与 Linux 侧已完成的
  33 项任务记录见 `docs/ENGINE_NOTES.md` / ROADMAP；恢复路径为
  Linux/CI 环境（hostpython3.host 失败点续查）或装 WSL 后原样重放。

## Windows Rust 核心交叉编译实录（2026-10-18；sena 成、其余转 CI）

目标：无 rustup/VS/MSYS 安装器、schannel 被掐、管道 stdio 被禁的
DSH 沙箱里，从官方 dist 组件手工组装 Rust 交叉编译环境（x86_64-pc-windows-gnu
宿主 → aarch64-linux-android）。**sena 核心全绿**（619KB
`liblusicgal_sena.so`）；wgpu 系大 crate（naga/ash/siglus_scene_vm）
实测撞物理内存承诺上限（见尾），其余三核转 CI。

- **工具链组装**（rustup 全家不可用：`rustup-init` 注册表访问被拒 +
  schannel 下载静默卡死）：rsproxy.cn/dist 拉官方 tar 组件
  `rustc + rust-std(host) + rust-std(aarch64-linux-android) + cargo +
  rust-mingw`，按 `<ver>/<component>/` 两层目录解到
  `.toolchain/rust/`，host std 并入 `rustc/lib/rustlib/…`。
- **宿主链接**（build script/proc-macro 单元）：无 MinGW 安装器 ——
  `rust-lld`（rustc 自带）+ msys2 TUNA 镜像抽包（`mingw-w64-ucrt-x86_64-
  {crt,winpthreads,gcc}` 的 .a/.o 原样拷进 rustlib `…/lib/self-contained/`；
  **gcc 包才有真 libgcc/libgcc_eh（_Unwind_* 符号），空壳 stub 无效**）。
  rustc 默认宿主链接器名 `x86_64-w64-mingw32-gcc` → **NDK clang.exe 硬链
  改名顶替** + `CCC_OVERRIDE_OPTIONS="^--target=x86_64-w64-mingw32
  ^-L<self-contained>"`（分隔符是空格；`^`=前插；android 包装脚本自带
  --target 后插胜出，不受污染——cc-rs 探测的 CC 除外）。dlltool 硬链
  自 llvm-dlltool（windows-sys build 在 gnu target_env 下必调）。
- **android 链接**：`-L` 泄漏会毒化 android 链接（拾到 mingw
  libm/liblog）→ 自制 `.toolchain/ndkwrap/aarch64-linux-android26-clang.cmd`
  先 `set "CCC_OVERRIDE_OPTIONS="` 再调真 NDK 包装；API26 而非 24
  （cpal/oboe 需 libaaudio）。RUSTFLAGS 保持为空：它不进宿主单元、且
  `-C link-self-contained` 在 android 目标被拒。
- **cargo 注册表**：cargo 走 schannel 必死 → `tool/apk_pipeline/
  lg_cargo_proxy.js` 本地 HTTP 桥（:9999）：sparse 索引透传
  rsproxy.cn/index，crate 下载走 `…/api/v1/crates/…/download`，
  `config.json` 的 dl 改指回本桥；`CARGO_HOME/config.toml` 里
  `[source.crates-io] replace-with="lg-sparse"`。
- **bat/cmd 必须 CRLF**（LF 会被 cmd 逐行错切）；`.toolchain/rustenv.bat`
  承载上述全部环境。
- **`-j 1` 必须**：naga 并行编译即异常退出。
- **实证内存天花板（决定性）**：本机 1.9GB RAM + **768MB 固定页文件**
  （AutomaticManagedPagefile=False，改配要重启，不可行）。Rust 线程栈
  Windows 上整块一次 commit，rustc 按 CGU 起工作线程；wgpu 系大
  crate 编 LLVM 峰值即触 `ERROR_COMMITMENT_LIMIT(1455)`
  （"页面文件太小"）→ 表现为 `failed to spawn work thread` ICE 或
  无诊断 0xc0000409（fastfail，勿被名字 STATUS_STACK_BUFFER_OVERRUN
  误导——非栈溢出）。已排除并实测无效的路径：RUST_MIN_STACK=64MB
  （反而加速撞顶，降到 8MB）、opt-level=1+codegen-units=1+incremental=0
  （naga 仍 "Allocation failed"）、rustc PE 主线程栈预留 2MB→512MB
  补丁（`tool/apk_pipeline/patch_rustc_stack.js`，排除主线程栈疑点）、
  rustc 1.88/1.90 降版（其 std 临时目录走 GetTempPath2W→系统上下文
  固定解析 C:\Windows\SystemTemp，沙箱拒访，1.99.1 恰好不涉）。
  **结论：该配置下 wgpu 系核心本地不可编，sena（619KB）是实际上限；
  rfvp/siglus/artemis 以 CI rust-cores 矩阵为产线。**
- **磁盘纪律**：页文件随内存压力吃盘（ENOSDC 反复出现）——每个核心
  harvest 后删 `target/`，NDK 只留 arm64 sysroot，删 sources/ 与
  shader-tools/simpleperf，cargo 注册表缓存保留（后续构建复用）。
