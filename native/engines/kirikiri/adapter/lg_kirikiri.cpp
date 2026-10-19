// LusicGal Kirikiri 核心适配器：lg_kirikiri_* → KrKr2-Next engine_api.h。
//
// 集成模型（调研结论，docs/ENGINE_NOTES.md）：
//  - KrKr2-Next 提供 tick 驱动的纯 C ABI（bridge/engine_api/include/
//    engine_api.h，ENGINE_API_VERSION 0x01000000）—— 无需窗口事件泵，
//    宿主每帧 engine_tick(delta_ms)。
//  - Android 渲染：engine_set_render_target_surface(h, ANativeWindow*, w, h)
//    → EGL 直渲宿主面；krkr2_android.cpp（经 patch_engines.sh 增补
//    krkr_SetAndroidContext / krkr_SetNativeWindow）承接 JVM/Context 注入。
//  - 存档：engine_create_desc_t.writable_path = 宿主 save_path（原生支持）。
//  - 输入：engine_send_input(engine_input_event_t)——本适配器把 LG JSON
//    解析后经互斥队列转投核心线程。
//
// 许可：KrKr2-Next GPL-3.0 → 独立动态库（GPL 边界隔离）。

#include "lusicgal/engine_abi.h"

#include <android/native_window.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

// KrKr2-Next C ABI（源码树内精确头文件，构建脚本注入 -I）。
#include "engine_api.h"

// LusicGal 补丁新增的宿主注入入口（patch_engines.sh 在上游
// platforms/android/cpp/krkr2_android.cpp 里以 extern "C" 定义；这里
// 补声明 —— 它们不在 engine_api.h 内）。
extern "C" {
void krkr_SetAndroidContext(void *vm, void *context);
void krkr_SetNativeWindow(void *win, uint32_t w, uint32_t h);
}

namespace {

struct KrkrEngine {
  std::string game_path;
  std::string save_path;
  void *host = nullptr;
  lg_event_cb_t cb = nullptr;

  engine_handle_t handle = nullptr;
  std::atomic_bool running{false};
  std::thread thread;

  // 表面（等待 + 重绑检测）。
  std::mutex surf_mu;
  std::condition_variable surf_cv;
  ANativeWindow *window = nullptr; // 持引用
  uint32_t surf_w = 0, surf_h = 0;
  uint64_t surf_gen = 0;
  bool surf_ready = false;

  // 输入事件队列（Dart/JNI 线程 → 核心线程）。
  std::mutex in_mu;
  std::deque<engine_input_event_t> inputs;
};

KrkrEngine *g_engine = nullptr;

void emit(KrkrEngine *e, const char *json) {
  if (e != nullptr && e->cb != nullptr) e->cb(e->host, json);
}

bool json_get_str(const char *json, const char *key, std::string &out) {
  std::string pat = std::string("\"") + key + "\"";
  std::string s(json ? json : "");
  auto pos = s.find(pat);
  if (pos == std::string::npos) return false;
  auto colon = s.find(':', pos + pat.size());
  if (colon == std::string::npos) return false;
  auto q1 = s.find('"', colon + 1);
  if (q1 == std::string::npos) return false;
  auto q2 = s.find('"', q1 + 1);
  if (q2 == std::string::npos) return false;
  out = s.substr(q1 + 1, q2 - q1 - 1);
  return true;
}

bool json_get_num(const char *json, const char *key, double &out) {
  std::string pat = std::string("\"") + key + "\"";
  std::string s(json ? json : "");
  auto pos = s.find(pat);
  if (pos == std::string::npos) return false;
  auto colon = s.find(':', pos + pat.size());
  if (colon == std::string::npos) return false;
  out = ::strtod(s.c_str() + colon + 1, nullptr);
  return true;
}

int krkr_thread_main(KrkrEngine *e) {
  // 1) 打开游戏（异步）→ 轮询启动状态。
  engine_result_t rc = engine_open_game_async(
      e->handle, e->game_path.c_str(), nullptr);
  if (rc != ENGINE_RESULT_OK) {
    char buf[160];
    snprintf(buf, sizeof(buf), "{\"type\":\"error\",\"code\":\"OPEN_FAIL\",\"result\":%d}",
             (int)rc);
    emit(e, buf);
    e->running.store(false, std::memory_order_release);
    return 1;
  }
  for (;;) {
    uint32_t state = 0;
    engine_get_startup_state(e->handle, &state);
    char logs[4096];
    uint32_t written = 0;
    while (engine_drain_startup_logs(e->handle, logs, sizeof(logs), &written) ==
               ENGINE_RESULT_OK &&
           written > 0) {
      char ev[4200];
      // 行日志 → 单行 JSON（\n 破坏结构，换 \r 表示）。
      std::string text(logs, written);
      for (auto &c : text) {
        if (c == '\n') c = ' ';
        if (c == '"') c = '\'';
        if (c == '\\') c = '/';
      }
      snprintf(ev, sizeof(ev), "{\"type\":\"log\",\"message\":\"%s\"}", text.c_str());
      emit(e, ev);
    }
    if (state == ENGINE_STARTUP_STATE_SUCCEEDED) {
      emit(e, "{\"type\":\"state\",\"state\":\"running\",\"message\":\"游戏已启动\"}");
      break;
    }
    if (state == ENGINE_STARTUP_STATE_FAILED) {
      emit(e, "{\"type\":\"error\",\"code\":\"STARTUP_FAILED\",\"message\":\"KrKr2 启动失败\"}");
      e->running.store(false, std::memory_order_release);
      return 2;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  // 2) 主循环：等表面 → tick + 输入消费 + 表面重绑。
  {
    std::unique_lock<std::mutex> lock(e->surf_mu);
    e->surf_cv.wait_for(lock, std::chrono::seconds(10),
                        [e] { return e->surf_ready; });
    if (!e->surf_ready) {
      emit(e, "{\"type\":\"error\",\"code\":\"NO_SURFACE\",\"message\":\"10s 内无宿主表面\"}");
    }
  }
  uint64_t last_surf_gen = 0;
  auto last = std::chrono::steady_clock::now();
  while (e->running.load(std::memory_order_acquire)) {
    // 表面变化 → 重新设置渲染目标。
    {
      std::lock_guard<std::mutex> lock(e->surf_mu);
      if (e->surf_ready && e->surf_gen != last_surf_gen) {
        engine_set_render_target_surface(
            e->handle, e->window, e->surf_w, e->surf_h);
        krkr_SetNativeWindow(e->window, e->surf_w, e->surf_h);
        last_surf_gen = e->surf_gen;
      }
    }
    // 消费输入。
    for (int burst = 0; burst < 16; ++burst) {
      engine_input_event_t ev;
      {
        std::lock_guard<std::mutex> lock(e->in_mu);
        if (e->inputs.empty()) break;
        ev = e->inputs.front();
        e->inputs.pop_front();
      }
      engine_send_input(e->handle, &ev);
    }
    auto now = std::chrono::steady_clock::now();
    uint32_t delta = static_cast<uint32_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(now - last)
            .count());
    last = now;
    if (delta > 100) delta = 100; // 卡顿防大步
    engine_tick(e->handle, delta);
    std::this_thread::sleep_for(std::chrono::milliseconds(8));
  }
  emit(e, "{\"type\":\"exit\",\"code\":0}");
  e->running.store(false, std::memory_order_release);
  return 0;
}

} // namespace

// 宿主注入（桥在 launch 前调用；patch_engines.sh 新增的 C 入口）。
extern "C" void krkr_SetAndroidContext(void *vm, void *context);
extern "C" void krkr_SetNativeWindow(void *win, uint32_t w, uint32_t h);

extern "C" void lg_kirikiri_set_android_context(void *vm, void *context) {
  krkr_SetAndroidContext(vm, context);
}

extern "C" uint32_t lg_kirikiri_abi_version(void) { return LG_ABI_VERSION; }

extern "C" lg_result_t lg_kirikiri_engine_create(const lg_engine_desc_t *desc,
                                                lg_engine_t *out) {
  if (desc == nullptr || out == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (desc->game_path == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (g_engine != nullptr) return LG_ERR_INVALID_STATE;
  auto *e = new KrkrEngine();
  e->game_path = desc->game_path;
  e->save_path = desc->save_path ? desc->save_path : "";
  e->host = desc->host;
  engine_create_desc_t cd;
  memset(&cd, 0, sizeof(cd));
  cd.struct_size = (uint32_t)sizeof(cd);
  cd.api_version = ENGINE_API_VERSION;
  cd.writable_path_utf8 = e->save_path.c_str();
  cd.cache_path_utf8 = e->save_path.c_str();
  cd.user_data = nullptr;
  engine_handle_t h = nullptr;
  engine_result_t rc = engine_create(&cd, &h);
  if (rc != ENGINE_RESULT_OK || h == nullptr) {
    delete e;
    return LG_ERR_IO;
  }
  e->handle = h;
  g_engine = e;
  *out = reinterpret_cast<lg_engine_t>(e);
  return LG_OK;
}

extern "C" lg_result_t lg_kirikiri_engine_start(lg_engine_t engine,
                                                lg_event_cb_t cb) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (e->running.load(std::memory_order_acquire)) return LG_ERR_INVALID_STATE;
  e->cb = cb;
  e->running.store(true, std::memory_order_release);
  try {
    e->thread = std::thread(krkr_thread_main, e);
  } catch (...) {
    e->running.store(false, std::memory_order_release);
    return LG_ERR_IO;
  }
  return LG_OK;
}

extern "C" lg_result_t lg_kirikiri_engine_set_surface(lg_engine_t engine,
                                                     void *surface) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr || surface == nullptr) return LG_ERR_INVALID_ARGUMENT;
  auto *win = static_cast<ANativeWindow *>(surface);
  ANativeWindow_acquire(win);
  ANativeWindow *old = nullptr;
  {
    std::lock_guard<std::mutex> lock(e->surf_mu);
    old = e->window;
    e->window = win;
    // 无尺寸信息时用窗口自身尺寸。
    if (e->surf_w == 0) {
      e->surf_w = (uint32_t)ANativeWindow_getWidth(win);
      e->surf_h = (uint32_t)ANativeWindow_getHeight(win);
    }
    e->surf_gen += 1;
    e->surf_ready = true;
  }
  e->surf_cv.notify_all();
  if (old != nullptr) ANativeWindow_release(old);
  return LG_OK;
}

extern "C" lg_result_t lg_kirikiri_engine_push_input(lg_engine_t engine,
                                                    const char *json) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr || json == nullptr) return LG_ERR_INVALID_ARGUMENT;
  std::string type;
  if (!json_get_str(json, "type", type)) return LG_ERR_INVALID_ARGUMENT;
  engine_input_event_t ev;
  memset(&ev, 0, sizeof(ev));
  ev.struct_size = (uint32_t)sizeof(ev);
  if (type == "point") {
    std::string phase;
    double x = 0, y = 0;
    json_get_str(json, "phase", phase);
    json_get_num(json, "x", x);
    json_get_num(json, "y", y);
    ev.type = phase == "down" ? ENGINE_INPUT_EVENT_POINTER_DOWN
              : phase == "move" ? ENGINE_INPUT_EVENT_POINTER_MOVE
                                : ENGINE_INPUT_EVENT_POINTER_UP;
    ev.x = x;
    ev.y = y;
    ev.pointer_id = 0;
    ev.button = 0;
  } else if (type == "key") {
    std::string code, state;
    json_get_str(json, "code", code);
    json_get_str(json, "state", state);
    ev.type = state == "up" ? ENGINE_INPUT_EVENT_KEY_UP
                             : ENGINE_INPUT_EVENT_KEY_DOWN;
    // KrKr2 key_code 为 Windows VK 语义（engine_send_input 文档）。
    if (code == "ok" || code == "text" || code == "space") ev.key_code = 13;
    else if (code == "cancel" || code == "back") {
      ev.type = ENGINE_INPUT_EVENT_BACK;
    } else if (code == "up") ev.key_code = 38;
    else if (code == "down") ev.key_code = 40;
    else if (code == "left") ev.key_code = 37;
    else if (code == "right") ev.key_code = 39;
    else if (code == "menu") ev.key_code = 112;
    else if (code == "save") ev.key_code = 113;
    else if (code == "load") ev.key_code = 114;
    else if (code == "skip") ev.key_code = 115;
    else if (code == "auto") ev.key_code = 116;
    else if (code == "speed" || code == "ctrl") ev.key_code = 17;
    else return LG_OK;
  } else if (type == "text") {
    std::string utf8;
    json_get_str(json, "utf8", utf8);
    ev.type = ENGINE_INPUT_EVENT_TEXT_INPUT;
    if (!utf8.empty()) {
      uint32_t cp = (unsigned char)utf8[0];
      if ((cp & 0xE0) == 0xC0 && utf8.size() >= 2)
        cp = ((cp & 0x1F) << 6) | ((unsigned char)utf8[1] & 0x3F);
      else if ((cp & 0xF0) == 0xE0 && utf8.size() >= 3)
        cp = ((cp & 0x0F) << 12) | (((unsigned char)utf8[1] & 0x3F) << 6) |
             ((unsigned char)utf8[2] & 0x3F);
      else if ((cp & 0xF8) == 0xF0 && utf8.size() >= 4)
        cp = ((cp & 0x07) << 18) | (((unsigned char)utf8[1] & 0x3F) << 12) |
             (((unsigned char)utf8[2] & 0x3F) << 6) | ((unsigned char)utf8[3] & 0x3F);
      ev.unicode_codepoint = cp;
    }
  } else {
    return LG_OK;
  }
  {
    std::lock_guard<std::mutex> lock(e->in_mu);
    e->inputs.push_back(ev);
  }
  return LG_OK;
}

extern "C" lg_result_t lg_kirikiri_engine_command_json(lg_engine_t engine,
                                                      const char *json) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr || json == nullptr) return LG_ERR_INVALID_ARGUMENT;
  std::string cmd;
  json_get_str(json, "command", cmd);
  if (cmd == "pause") engine_pause(e->handle);
  if (cmd == "resume") engine_resume(e->handle);
  if (cmd == "stop") e->running.store(false, std::memory_order_release);
  return LG_OK;
}

extern "C" lg_result_t lg_kirikiri_engine_surface_size(lg_engine_t engine,
                                                      int32_t w, int32_t h) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr || w <= 0 || h <= 0) return LG_ERR_INVALID_ARGUMENT;
  engine_result_t rc = engine_set_surface_size(e->handle, (uint32_t)w, (uint32_t)h);
  {
    std::lock_guard<std::mutex> lock(e->surf_mu);
    e->surf_w = (uint32_t)w;
    e->surf_h = (uint32_t)h;
    e->surf_gen += 1;
  }
  e->surf_cv.notify_all();
  return rc == ENGINE_RESULT_OK ? LG_OK : LG_ERR_INVALID_STATE;
}

extern "C" lg_result_t lg_kirikiri_engine_destroy(lg_engine_t engine) {
  auto *e = reinterpret_cast<KrkrEngine *>(engine);
  if (e == nullptr) return LG_OK;
  e->running.store(false, std::memory_order_release);
  e->surf_cv.notify_all();
  if (e->thread.joinable()) e->thread.join();
  if (e->handle != nullptr) engine_destroy(e->handle);
  ANativeWindow *old = nullptr;
  {
    std::lock_guard<std::mutex> lock(e->surf_mu);
    old = e->window;
    e->window = nullptr;
  }
  if (old != nullptr) ANativeWindow_release(old);
  if (g_engine == e) g_engine = nullptr;
  delete e;
  return LG_OK;
}
