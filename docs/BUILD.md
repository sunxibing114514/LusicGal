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

### `.github/workflows/engines.yml`

四个必绿门禁合并为单一 ubuntu job `gates`（省去重复 setup 与分钟开销）：

| Step（job `gates`） | 内容 | 性质 |
|---|---|---|
| C ABI selftest | gcc 编译 `native/`（ABI 头 + stub + selftest）并运行自检 | **必须绿** |
| JNI bridge ×NDK | NDK（arm64-v8a）交叉编译 JNI 桥 | **必须绿** |
| Rust FFI gate | `cargo check`/`test` `native/rust/cbridge` | **必须绿** |
| 上游 pin 校验 | `scripts/fetch_engines.sh --verify`（18 个 pin 全部可解析） | **必须绿** |
| `onscripter-android` / `sena-android`（手动） | 引擎核心真实交叉编译尝试 | `continue-on-error`（非阻塞，逐个转正） |

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

## 引擎核心构建（实验，非阻塞）

```bash
bash scripts/fetch_engines.sh              # 按 pin 浅拉取 18 个上游 → third_party/upstream/
bash native/engines/onscripter/build_android.sh   # 例：Yuri NDK 交叉编译
```

各引擎的具体链路（vcpkg triplet / SDL iOS 参数 / cargo-ndk…）见各 `native/engines/<id>/README.md` 与 `docs/ENGINE_NOTES.md`。

## widget 测试契约（避免死锁）

- `testWidgets` body 运行于 fake-async zone：`scheduleMicrotask` 被拦截。**一切真实 IO（文件读写、临时目录）必须包进 `tester.runAsync`**，否则 IO 完成回调停在 fake 队列，body 永久挂起（超时堆栈为 `dart:isolate _RawReceivePort._handleMessage`）。
- 未 mock 的平台通道回复永不完成：测试里用 `setMockMethodCallHandler` 返回 `null`，让 `EngineHost` 走"核心未打包"分支（真实生产行为）。
- 泵送用有界 `pump(Duration)` + 显式 `timeout`，不用无限期 `pumpAndSettle`。
- 范例见 `test/widget_test.dart`（完整壳）与 `test/lean_shell_test.dart`（精简壳）。

## 常见问题

- **为什么没有 android/ ios/ 目录？** 平台壳由 CI 确定性重建（`flutter create`），自定义原生代码全部在 `plugins/lusicgal_engines` 与 `native/` —— 见 docs/ARCHITECTURE.md §6。
- **iOS 真机调试？** `flutter build ios --no-codesign` 产物 + Xcode 手动签名即可。
- **导入的游戏去哪了？** App Documents `games/<id>/`；iOS 可通过"文件"App 的 LusicGal 目录直接投放（CI 已注入 UIFileSharingEnabled）。
