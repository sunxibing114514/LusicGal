# Kirikiri / KAG 核心

## 选型（v2 定案）

**核心 = reAAAq/KrKr2-Next**（GPL-3.0，pin `1abd1ed4`）—— 而非早期候选
`2468785842/krkr2`。理由：KrKr2-Next 提供 **tick 驱动的纯 C ABI**
（`bridge/engine_api/include/engine_api.h`，`ENGINE_API_VERSION 0x01000000`）：

- `engine_create(engine_create_desc_t{writable_path, cache_path})`
- `engine_open_game_async(h, game_root, startup_script)` + 启动状态轮询 + 日志排水
- `engine_tick(h, delta_ms)` —— 无窗口事件泵，宿主每帧驱动
- `engine_send_input(h, engine_input_event_t)` —— 指针/键/文本/BACK 四类
- `engine_set_render_target_surface(h, ANativeWindow*, w, h)` —— Android EGL 直渲宿主面
- `engine_set_surface_size` / `engine_pause` / `engine_resume` / `engine_destroy`

存档 = `writable_path`（原生支持，无需补丁）。krkr2 / LauncherC 仍保留在调研
矩阵中（工程化与 per-game 偏好参考，见 docs/ENGINE_NOTES.md §Kirikiri）。

## 集成路径（v2，`adapter/lg_kirikiri.cpp`）

1. `scripts/fetch_engines.sh kirikiri-next` 拉取源码。
2. `scripts/patch_engines.sh kirikiri-next` —— 给 `platforms/android/cpp/krkr2_android.cpp`
   增补纯 C 注入入口 `krkr_SetAndroidContext(vm, ctx)` / `krkr_SetNativeWindow(win, w, h)`
   （原实现只有绑定其自家 Kotlin 插件的 JNI 命名 setter）。
3. `native/engines/kirikiri/build_android.sh`：NDK 工具链 + `VCPKG_TARGET_ANDROID=ON`
   （arm64-android 三元组）构建 `libengine_api.so` + `liblusicgal_kirikiri.so`。
4. 运行期：桥 dlsym 派发；`lg_kirikiri_set_android_context` 在 launch 前注入 JVM/Context。

适配器主循环：open_game_async → 轮询 `engine_get_startup_state`（SUCCEEDED/FAILED，
日志经 `engine_drain_startup_logs` → log 事件）→ 等表面（condvar，10s）→
tick 循环（表面重绑 gen 检测 + 输入队列消费 + `engine_tick(≤100ms)`）。

## 检测特征

`*.xp3`（魔数 `XP3\r\n\x1a\x8a`，10 分）/ `startup.tjs`（5 分）/ `*.tjs`（3 分）。

## 许可

GPL-3.0（badge）—— 与主 App 同许可；独立 `liblusicgal_kirikiri.so` 分发，
随附上游 LICENSE + `patch_engines.sh` diff 声明（docs/LICENSE_NOTES.md）。
