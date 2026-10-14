# BUILD — 构建 / 编译验证

## CI（权威验证方式）

仓库推送后由 GitHub Actions 验证（对应用户要求：**编译验证在私有仓库完成，不在本地进行**）。

### `.github/workflows/app.yml`

> 配额说明：私有仓库 Actions 按分钟计费（macOS runner ×10）。默认 push 只跑
> ubuntu job；iOS 构建为 **workflow_dispatch 手动触发**（已在本仓验证绿：
> simulator 目标等效编译验证，且不涉签名）。

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

## 本地（可选，CI 均已覆盖）

```bash
flutter pub get
flutter analyze
flutter test

# 平台壳（已 .gitignore，按需生成）
flutter create --platforms=android,ios --org com.lusicgal --project-name lusicgal .
python3 scripts/patch_platform.py           # 注入 iOS 文件共享 / Android largeHeap 等
flutter build apk --release
flutter build ios --debug --no-codesign
```

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
