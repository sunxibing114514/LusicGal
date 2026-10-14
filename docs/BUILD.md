# BUILD — 构建 / 编译验证

## CI（权威验证方式）

仓库推送后由 GitHub Actions 验证（对应用户要求：**编译验证在私有仓库完成，不在本地进行**）。

### `.github/workflows/app.yml`

| Job | Runner | 步骤 | 产物 |
|---|---|---|---|
| `analyze-test` | ubuntu-latest | `flutter pub get` → `flutter analyze` → `flutter test` | — |
| `build-android` | ubuntu-latest | `flutter create --platforms=android` → 补丁 → `flutter build apk --release` | `app-release.apk`（artifact） |
| `build-ios` | macos-latest | `flutter create --platforms=ios` → 补丁 → `flutter build ios --debug --no-codesign` | 构建通过 |

### `.github/workflows/engines.yml`

| Job | 内容 | 性质 |
|---|---|---|
| `c-abi-host` | gcc 编译 `native/`（ABI 头 + stub + selftest）并运行自检 | **必须绿** |
| `jni-bridge-android` | NDK（arm64-v8a）交叉编译 JNI 桥 | **必须绿** |
| `rust-cbridge` | `cargo check` `native/rust/cbridge`（Rust FFI 门面） | **必须绿** |
| `fetch-upstreams` | `scripts/fetch_engines.sh`（校验 18 个 pin 全部可解析） | **必须绿** |
| `engine-cross-experimental` | 引擎核心真实交叉编译尝试（Yuri/xsystem35/sena…） | `continue-on-error`（非阻塞，逐个转正） |

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

## 常见问题

- **为什么没有 android/ ios/ 目录？** 平台壳由 CI 确定性重建（`flutter create`），自定义原生代码全部在 `plugins/lusicgal_engines` 与 `native/` —— 见 docs/ARCHITECTURE.md §6。
- **iOS 真机调试？** `flutter build ios --no-codesign` 产物 + Xcode 手动签名即可。
- **导入的游戏去哪了？** App Documents `games/<id>/`；iOS 可通过"文件"App 的 LusicGal 目录直接投放（CI 已注入 UIFileSharingEnabled）。
