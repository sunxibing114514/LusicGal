// LusicGal ONScripter 核心适配器：lg_onscripter_* → OnscripterYuri main()。
//
// 集成模型（调研结论，docs/ENGINE_NOTES.md）：
//  - OnscripterYuri 在 Android 构建里本就是 add_library(onsyuri SHARED)，
//    main() 存在于库内 —— 适配器在私有线程直接调用 main(argc, argv)。
//  - SDL2 Android 无 SDL_CreateWindowFrom —— 表面经 scripts/patch_sdl_android.sh
//    补丁（Android_JNI_GetNativeWindow 优先咨询 LG_SDL_Window_Override）。
//  - SDLActivity 生命周期依赖由插件侧 org.libsdl.app.SDLActivity 最小胶水
//    （plugins/.../src/main/kotlin/org/libsdl/app/）承接。
//  - 参数：-r <game_path> --save-dir <save_path>（上游 parseOption 语义）。
//  - 输入：JSON → SDL_PushEvent（触摸合成 SDL_MOUSEBUTTONDOWN/MOTIONBUTTONUP +
//    key）；停止：SDL_QUIT。
//
// 许可：OnscripterYuri GPL-2.0-or-later → 本核心独立动态库（GPL 边界隔离）。

#include "lusicgal/engine_abi.h"

#include <SDL.h>
#include <android/native_window.h>

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

namespace {

struct OnsEngine {
  std::string game_path;
  std::string save_path;
  std::string options_json;
  void *host = nullptr;
  lg_event_cb_t cb = nullptr;
  std::atomic_bool running{false};
  std::thread thread;
  // 宿主注入窗口（SDL 补丁经 LG_SDL_Window_Override 读取）。
  std::atomic<void *> window{nullptr};
};

OnsEngine *g_engine = nullptr;

} // namespace

// SDL_android.c 补丁咨询点：返回宿主注入窗口或 NULL。
extern "C" void *LG_SDL_Window_Override(void) {
  if (g_engine == nullptr) return nullptr;
  return g_engine->window.load(std::memory_order_acquire);
}

extern "C" int main(int argc, char **argv); // onsyuri 的入口（库内符号）

namespace {

int ons_thread_main(OnsEngine *e) {
  std::string a0 = "onscripter";
  std::string root = e->game_path;
  std::string save = e->save_path;
  std::string width = "1280";
  std::string height = "720";
  // options_json 的极简键值读取（width/height）。
  auto opt_num = [&](const char *key, const char *fallback) -> std::string {
    std::string pat = std::string("\"") + key + "\"";
    auto pos = e->options_json.find(pat);
    if (pos == std::string::npos) return fallback;
    auto colon = e->options_json.find(':', pos + pat.size());
    if (colon == std::string::npos) return fallback;
    size_t i = colon + 1;
    while (i < e->options_json.size() &&
           (e->options_json[i] == ' ' || e->options_json[i] == '"')) i++;
    size_t start = i;
    while (i < e->options_json.size() &&
           (e->options_json[i] >= '0' && e->options_json[i] <= '9')) i++;
    if (i == start) return fallback;
    return e->options_json.substr(start, i - start);
  };
  width = opt_num("width", "1280");
  height = opt_num("height", "720");

  char *argv[] = {
      const_cast<char *>(a0.c_str()),
      const_cast<char *>("-r"), const_cast<char *>(root.c_str()),
      const_cast<char *>("--save-dir"), const_cast<char *>(save.c_str()),
      const_cast<char *>("--width"), const_cast<char *>(width.c_str()),
      const_cast<char *>("--height"), const_cast<char *>(height.c_str()),
      const_cast<char *>("--fullscreen"), const_cast<char *>("0"),
      nullptr,
  };
  int argc = 11;
  // 上游阻塞主循环直到退出；返回码经事件回宿主。
  int rc = main(argc, argv);
  if (e->cb != nullptr) {
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"type\":\"exit\",\"code\":%d}", rc);
    e->cb(e->host, buf);
  }
  e->running.store(false, std::memory_order_release);
  return rc;
}

// 极简 JSON 字段提取（字符串键）。
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
  out = strtod(s.c_str() + colon + 1, nullptr);
  return true;
}

} // namespace

extern "C" uint32_t lg_onscripter_abi_version(void) { return LG_ABI_VERSION; }

extern "C" lg_result_t lg_onscripter_engine_create(const lg_engine_desc_t *desc,
                                                   lg_engine_t *out) {
  if (desc == nullptr || out == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (desc->game_path == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (g_engine != nullptr) return LG_ERR_INVALID_STATE; // 单实例（v1 约定）
  auto *e = new OnsEngine();
  e->game_path = desc->game_path;
  e->save_path = desc->save_path ? desc->save_path : "";
  e->options_json = desc->options_json ? desc->options_json : "";
  e->host = desc->host;
  g_engine = e;
  *out = reinterpret_cast<lg_engine_t>(e);
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_start(lg_engine_t engine,
                                                  lg_event_cb_t cb) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (e->running.load(std::memory_order_acquire)) return LG_ERR_INVALID_STATE;
  e->cb = cb;
  e->running.store(true, std::memory_order_release);
  try {
    e->thread = std::thread(ons_thread_main, e);
  } catch (...) {
    e->running.store(false, std::memory_order_release);
    return LG_ERR_IO;
  }
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_set_surface(lg_engine_t engine,
                                                       void *surface) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr || surface == nullptr) return LG_ERR_INVALID_ARGUMENT;
  auto *win = static_cast<ANativeWindow *>(surface);
  ANativeWindow_acquire(win);
  void *old = e->window.exchange(win, std::memory_order_acq_rel);
  if (old != nullptr) {
    ANativeWindow_release(static_cast<ANativeWindow *>(old));
  }
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_push_input(lg_engine_t engine,
                                                       const char *json) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr || json == nullptr) return LG_ERR_INVALID_ARGUMENT;
  std::string type;
  if (!json_get_str(json, "type", type)) return LG_ERR_INVALID_ARGUMENT;
  if (type == "point") {
    std::string phase;
    double x = 0, y = 0;
    json_get_str(json, "phase", phase);
    json_get_num(json, "x", x);
    json_get_num(json, "y", y);
    // ONS 视口即游戏窗口（1280x720 或参数宽度）—— 坐标按 SDL 窗口系换算。
    int wx = static_cast<int>(x * 1280);
    int wy = static_cast<int>(y * 720);
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    if (phase == "down") {
      ev.type = SDL_MOUSEBUTTONDOWN;
      ev.button.button = SDL_BUTTON_LEFT;
      ev.button.x = wx;
      ev.button.y = wy;
    } else if (phase == "move") {
      ev.type = SDL_MOUSEMOTION;
      ev.motion.x = wx;
      ev.motion.y = wy;
    } else {
      ev.type = SDL_MOUSEBUTTONUP;
      ev.button.button = SDL_BUTTON_LEFT;
      ev.button.x = wx;
      ev.button.y = wy;
    }
    SDL_PushEvent(&ev);
    return LG_OK;
  }
  if (type == "key") {
    std::string code;
    std::string state;
    json_get_str(json, "code", code);
    json_get_str(json, "state", state);
    SDL_Keycode key = SDLK_UNKNOWN;
    SDL_Scancode sc = SDL_SCANCODE_UNKNOWN;
    if (code == "ok" || code == "text" || code == "space") key = SDLK_RETURN;
    else if (code == "cancel" || code == "back") key = SDLK_ESCAPE;
    else if (code == "up") key = SDLK_UP;
    else if (code == "down") key = SDLK_DOWN;
    else if (code == "left") key = SDLK_LEFT;
    else if (code == "right") key = SDLK_RIGHT;
    else if (code == "speed" || code == "ctrl") key = SDLK_LCTRL;
    else if (code == "menu") key = SDLK_F1;
    else if (code == "save") key = SDLK_F2;
    else if (code == "load") key = SDLK_F3;
    else if (code == "skip") key = SDLK_F4;
    else if (code == "auto") key = SDLK_F5;
    if (key == SDLK_UNKNOWN) return LG_OK;
    sc = SDL_GetScancodeFromKey(key);
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = state == "up" ? SDL_KEYUP : SDL_KEYDOWN;
    ev.key.keysym.scancode = sc;
    ev.key.keysym.sym = key;
    SDL_PushEvent(&ev);
    return LG_OK;
  }
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_command_json(lg_engine_t engine,
                                                         const char *json) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr || json == nullptr) return LG_ERR_INVALID_ARGUMENT;
  std::string cmd;
  json_get_str(json, "command", cmd);
  if (cmd == "stop" || cmd == "quit") {
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_QUIT;
    SDL_PushEvent(&ev);
  }
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_surface_size(lg_engine_t engine,
                                                         int32_t w, int32_t h) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr || w <= 0 || h <= 0) return LG_ERR_INVALID_ARGUMENT;
  // ONS 内部分辨率经启动参数固定；呈现由宿主缩放 —— 记录即可。
  return LG_OK;
}

extern "C" lg_result_t lg_onscripter_engine_destroy(lg_engine_t engine) {
  auto *e = reinterpret_cast<OnsEngine *>(engine);
  if (e == nullptr) return LG_OK;
  SDL_Event ev;
  memset(&ev, 0, sizeof(ev));
  ev.type = SDL_QUIT;
  SDL_PushEvent(&ev);
  if (e->thread.joinable()) {
    // ONS 主循环可能正在 SDL_WaitEvent —— 上限等待防挂。
    e->thread.detach(); // v1：不阻塞宿主退出（进程级会话单实例）
  }
  void *old = e->window.exchange(nullptr, std::memory_order_acq_rel);
  if (old != nullptr) {
    ANativeWindow_release(static_cast<ANativeWindow *>(old));
  }
  if (g_engine == e) g_engine = nullptr;
  delete e;
  return LG_OK;
}
