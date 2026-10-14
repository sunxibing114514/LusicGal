# ARCHITECTURE — LusicGal 分层设计

## 总览

```
┌─────────────────────────── Flutter（lib/） ────────────────────────────┐
│  ui/            书库 · 存档 · 引擎状态 · 设置 · 播放器（M3 明暗主题）    │
│  core/          detect（识别） · library（库/导入） · saves · settings   │
│  engine/        EngineHost 门面：会话生命周期 / 事件流 / 命令           │
└───────────────────────────────┬────────────────────────────────────────┘
                MethodChannel `lusicgal/engines`
                EventChannel   `lusicgal/engineEvents`
                PlatformView   `lusicgal-engine-view`
┌─────────────────────── plugins/lusicgal_engines（桥）──────────────────┐
│  Dart   lusicgal_engines.dart   probe/launch/command/events + 视图参数 │
│  Android(Kotlin)  核心探测(System.loadLibrary) · PlatformView · JNI 声明 │
│  iOS(Swift)       核心探测(dlsym) · PlatformView · 事件通道              │
└───────────────────────────────┬────────────────────────────────────────┘
                     C ABI（native/include/lusicgal/engine_abi.h）
┌───────────────────────────────┴────────────────────────────────────────┐
│ native/bridge/jni   JNI 实现（Java_com_lusicgal_engines_* → C ABI）      │
│ native/rust/cbridge  Rust FFI 门面（rfvp/siglus/sena 的静态库从这里接线） │
│ native/engines/<id>  每引擎的拉取/补丁/交叉编译脚本 + 上游 pin            │
└─────────────────────────────────────────────────────────────────────────┘
```

分层动机：**Flutter 壳永不因引擎编译失败而挂**（核心缺失 = probe 返回不可用，UI 照常工作并给出指引）；**引擎核心永不感知 Flutter**（只见 C ABI + 平台 surface），与 KrKr2-Next（Flutter+ANGLE）、AetherKiri（Godot 宿主+ABI 包）两个上游验证过的同构路线一致。

## 1. UI 层（lib/ui）

- `home_shell.dart`：`NavigationBar` 四页（书库/存档/引擎/设置），`MaterialApp.router` 不引入 —— 保持普通 Navigator，减少依赖。
- M3 主题：`core/theme.dart`，`ColorScheme.fromSeed(seedColor: 0xFF7C5CFF)`，`theme` / `darkTheme` / `themeMode`（system/light/dark 由设置驱动）。
- 播放器 `player/player_screen.dart`：`AndroidView`/`UiKitView`（viewType `lusicgal-engine-view`）承载引擎 surface；顶部条（返回/标题/时长），底部快捷面板（暂停/恢复/音量/存档/读档/按键映射入口）。核心未打包时原生侧直接渲染占位说明 —— 走的是与未来真实引擎完全相同的 PlatformView 通道。

## 2. 业务层（lib/core）

- **detect/engine_detector.dart**：纯文件特征识别。规则（含魔数）：
  - Kirikiri：`*.xp3`（魔数 `58 50 33 0D 0A 1A 8A`）／`startup.tjs`
  - ONScripter：`nscript.dat`／`arc*.nsa`／`0.txt`
  - Ren'Py：`*.rpa`（魔数 `RPA-3.0 ` 等）／`renpy/` 目录／`*.rpyc`
  - KEY 系（源自 siglus_rs `engine-detect`）：`Scene.pck`｜`Gameexe.dat` → Siglus；`Gameexe.ini`+`PACL`/`TPC32` → AVG32；`Gameexe.ini`+10000 条 `SEEN.TXT` → RealLive；`UK2.CFG`／`<< UK2 TEXT Ver1.00 >>` → UK2
  - FVP：`*.hcb`／`*.nvsg`；SoftPAL：`*.pac`；System3.x：`*.ald`
  - 输出 `DetectResult{engine, detail, evidence[]}`（证据链可解释）
- **library/library_store.dart**：JSON 持久化（原子写：tmp+rename），`ChangeNotifier`；库条目含 id/标题/引擎/路径/添加时间/游玩统计。
- **library/import_service.dart**：双通道导入 —— ①扫描 App 专属外部目录（`Android/data/com.lusicgal/files/` 与 App Documents，用户 USB/文件 App 放入）②系统选择器选单文件（`.xp3/.rpa/.nsa...`）。优先 `rename` 跨分区退化为递归 copy。
- **saves/save_manager.dart**：`<docs>/saves/<gameId>/<engine>/` 按游戏隔离；导出 zip（`<docs>/export/`，iOS 文件 App 可达）；导入 zip 带 zip-slip 防护。
- **settings/settings_controller.dart**：主题模式/分辨率缩放(0.5–2.0)/四通道音量/按键映射（动作→手势），全部进 launch options map 传给核心。

## 3. 桥（plugins/lusicgal_engines）

- **probe（v2 dlsym 模型）**：Android 先 `System.loadLibrary("lusicgal_<id>")`（try/catch）再经桥 `CoreNative.probeCore`（`dlsym(RTLD_DEFAULT, "lg_<id>_abi_version")`）；iOS `lg_ios_probe`（同 dlsym，静态符号）。探测失败的引擎在"引擎"页显示为"核心未打包"并附构建指引，而非崩溃。
- **launch**：`{engineId, gameId, gamePath, savePath, options{...}}` → 桥先注入 JVM/Context（`lg_<id>_set_android_context`，可选符号）→ `engine_create` + `engine_start(emit_event)`；核心缺失同步失败 + 事件 `core_missing`。renpy 例外：Route B 外板壳 Activity（`RenpyLauncher`）。
- **输入（v2）**：`EngineSurfaceView` 触摸 → `CoreNative.pushInput`（归一化坐标 JSON）→ `lg_<id>_engine_push_input`；键/文本经 method channel `pushInput`。核心无 push_input 符号时桥自动包装为 `{"command":"input","event":…}`。
- **事件流**：核心线程 → C `emit_event` → JNI `AttachCurrentThread` → 主 Handler → `EventChannel` 推送 `log/state/exit/core_missing`（+ art3m1s 的 `artemis_log/artemis_media/artemis_ui`）。
- **PlatformView**：creationParams `{engineId, gameId}`；Android `EngineSurfaceView`（SurfaceView → `attachSurface`+`surfaceSize`），iOS v1 占位面（真实 Metal/CAMetalLayer 接线见 ROADMAP）。

## 4. C ABI（native/include/lusicgal/engine_abi.h，v2 = 0x00020000）

设计借鉴 AetherKiri `abi/include/engine_api.h`（其源头是 krkr2）：
- `struct_size` 首字段版本化 + `reserved[]` 尾部保留（ABI 可演化）
- `lg_engine_t` 不透明句柄；`lg_result_t` 错误码（OK/ARG/STATE/NOT_SUPPORTED/IO/CORE）
- 生命周期：`lg_<id>_engine_create(desc) → start(event_cb) → command_json() → destroy()`
- **v2 新增**：`lg_<id>_engine_push_input(engine, json)`（point/key/text，坐标归一化 0~1）与 `lg_<id>_engine_surface_size(engine, w, h)`；可选符号 `lg_<id>_set_android_context(java_vm, context)`（桥 dlsym 探测后调）
- 渲染面：`lg_<id>_engine_set_surface(handle, ANativeWindow* / CAMetalLayer*)`
- 事件回调：`void (*lg_event_cb)(void* host, const char* json_utf8)`
- 每核心前缀宏 `LG_CORE(id)` 展开 8 个 `lg_<id>_*` 符号；核心 = 独立 `liblusicgal_<id>.so`（Android）/ `.a`（iOS），桥零核心、纯 dlsym 派发 —— GPL/许可边界即库边界

## 5. 引擎核心层（native/engines）

每引擎目录协议（对齐 AetherKiri `packages/` 思路）：

```
native/engines/<id>/
├── README.md          上游 pin、选型理由、集成状态（对应 docs/ENGINE_NOTES.md）
├── build_android.sh   NDK 交叉编译（上游脚本适配）
├── build_ios.sh       iOS 交叉编译（必要时）
└── patches/           按需（如 YukiHub rfvp 补丁集的再适配）
```

源码本体不入库：`scripts/fetch_engines.sh` 按 ENGINE_NOTES.md 的 pin 表做浅拉取（`git init → fetch <sha> --depth 1 → checkout`），CI 与本地一致。

## 6. 平台壳策略（重要）

`android/`、`ios/` **不提交**（.gitignore 忽略）。CI 在构建前运行 `flutter create --platforms=... --org com.lusicgal .` 确定性生成，随后 `scripts/patch_platform.py` 注入增量（iOS：`UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`/显示名；Android：`largeHeap` 等）。所有自定义原生代码都位于插件与 native/，不受 `flutter create` 影响 —— 任何 Flutter 稳定版可复现构建，升级零冲突。
