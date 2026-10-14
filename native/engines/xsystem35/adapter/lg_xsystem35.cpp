// LusicGal System35（AliceSoft 32bit）核心适配器：lg_xsystem35_* → main()。
//
// 集成模型（调研结论，docs/ENGINE_NOTES.md）：
//  - xsystem35-sdl2 在 ANDROID 分支本就是 add_library(xsystem35 SHARED)，
//    main()（src/xsystem35.c）在库内 —— 适配器在私有线程直接调用。
//  - 参数：-gamedir <path>（__ANDROID__ 语义 = chdir 游戏根，*.ald 从此扫描）
//    + -savedir <save_path>。
//  - SDL2 Android 表面：同 onscripter —— scripts/patch_sdl_android.sh +
//    插件侧 org.libsdl.app.SDLActivity 最小胶水。
//  - 许可 GPL-2.0-or-later → 独立动态库隔离。

#include "lusicgal/engine_abi.h"

#include <SDL.h>
#include <android/native_window.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

namespace {

struct XSysEngine {
  std::string game_path;
  std::string save_path;
  void *host = nullptr;
  lg_event_cb_t cb = nullptr;
  std::atomic_bool running{false};
  std::thread thread;
  std::atomic<void *> window{nullptr};
};

XSysEngine *g_engine = nullptr;

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

} // namespace

extern "C" void *LG_SDL_Window_Override(void) {
  if (g_engine == nullptr) return nullptr;
  return g_engine->window.load(std::memory_order_acquire);
}

extern "C" int main(int argc, char **argv); // xsystem35.c 的入口（库内符号）

namespace {

int xs_thread_main(XSysEngine *e) {
  std::string a0 = "xsystem35";
  std::string gamedir = e->game_path;
  std::string savedir = e->save_path;
  char *argv[] = {
      const_cast<char *>(a0.c_str()),
      const_cast<char *>("-gamedir"), const_cast<char *>(gamedir.c_str()),
      const_cast<char *>("-savedir"), const_cast<char *>(savedir.c_str()),
      const_cast<char *>("-noimagecursor"),
      nullptr,
  };
  int argc = 6;
  int rc = main(argc, argv); // 阻塞直至退出（内部 for(;;) nact_main）
  if (e->cb != nullptr) {
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"type\":\"exit\",\"code\":%d}", rc);
    e->cb(e->host, buf);
  }
  e->running.store(false, std::memory_order_release);
  return rc;
}

} // namespace

extern "C" uint32_t lg_xsystem35_abi_version(void) { return LG_ABI_VERSION; }

extern "C" lg_result_t lg_xsystem35_engine_create(const lg_engine_desc_t *desc,
                                                  lg_engine_t *out) {
  if (desc == nullptr || out == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (desc->game_path == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (g_engine != nullptr) return LG_ERR_INVALID_STATE;
  auto *e = new XSysEngine();
  e->game_path = desc->game_path;
  e->save_path = desc->save_path ? desc->save_path : "";
  e->host = desc->host;
  g_engine = e;
  *out = reinterpret_cast<lg_engine_t>(e);
  return LG_OK;
}

extern "C" lg_result_t lg_xsystem35_engine_start(lg_engine_t engine,
                                                 lg_event_cb_t cb) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
  if (e == nullptr) return LG_ERR_INVALID_ARGUMENT;
  if (e->running.load(std::memory_order_acquire)) return LG_ERR_INVALID_STATE;
  e->cb = cb;
  e->running.store(true, std::memory_order_release);
  try {
    e->thread = std::thread(xs_thread_main, e);
  } catch (...) {
    e->running.store(false, std::memory_order_release);
    return LG_ERR_IO;
  }
  return LG_OK;
}

extern "C" lg_result_t lg_xsystem35_engine_set_surface(lg_engine_t engine,
                                                      void *surface) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
  if (e == nullptr || surface == nullptr) return LG_ERR_INVALID_ARGUMENT;
  auto *win = static_cast<ANativeWindow *>(surface);
  ANativeWindow_acquire(win);
  void *old = e->window.exchange(win, std::memory_order_acq_rel);
  if (old != nullptr) {
    ANativeWindow_release(static_cast<ANativeWindow *>(old));
  }
  return LG_OK;
}

extern "C" lg_result_t lg_xsystem35_engine_push_input(lg_engine_t engine,
                                                      const char *json) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
  if (e == nullptr || json == nullptr) return LG_ERR_INVALID_ARGUMENT;
  std::string type;
  if (!json_get_str(json, "type", type)) return LG_ERR_INVALID_ARGUMENT;
  if (type == "point") {
    std::string phase;
    double x = 0, y = 0;
    json_get_str(json, "phase", phase);
    json_get_num(json, "x", x);
    json_get_num(json, "y", y);
    int wx = static_cast<int>(x * 640); // xsystem35 视口 640x480
    int wy = static_cast<int>(y * 480);
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
    std::string code, state;
    json_get_str(json, "code", code);
    json_get_str(json, "state", state);
    SDL_Keycode key = SDLK_UNKNOWN;
    if (code == "ok" || code == "text" || code == "space") key = SDLK_RETURN;
    else if (code == "cancel" || code == "back") key = SDLK_ESCAPE;
    else if (code == "up") key = SDLK_UP;
    else if (code == "down") key = SDLK_DOWN;
    else if (code == "left") key = SDLK_LEFT;
    else if (code == "right") key = SDLK_RIGHT;
    else if (code == "menu") key = SDLK_F1;
    if (key == SDLK_UNKNOWN) return LG_OK;
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = state == "up" ? SDL_KEYUP : SDL_KEYDOWN;
    ev.key.keysym.scancode = SDL_GetScancodeFromKey(key);
    ev.key.keysym.sym = key;
    SDL_PushEvent(&ev);
  }
  return LG_OK;
}

extern "C" lg_result_t lg_xsystem35_engine_command_json(lg_engine_t engine,
                                                        const char *json) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
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

extern "C" lg_result_t lg_xsystem35_engine_surface_size(lg_engine_t engine,
                                                        int32_t w, int32_t h) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
  if (e == nullptr || w <= 0 || h <= 0) return LG_ERR_INVALID_ARGUMENT;
  return LG_OK; // xsystem35 固定 640x480 视口；宿主缩放呈现。
}

extern "C" lg_result_t lg_xsystem35_engine_destroy(lg_engine_t engine) {
  auto *e = reinterpret_cast<XSysEngine *>(engine);
  if (e == nullptr) return LG_OK;
  SDL_Event ev;
  memset(&ev, 0, sizeof(ev));
  ev.type = SDL_QUIT;
  SDL_PushEvent(&ev);
  if (e->thread.joinable()) {
    e->thread.detach(); // v1：不阻塞宿主退出
  }
  void *old = e->window.exchange(nullptr, std::memory_order_acq_rel);
  if (old != nullptr) {
    ANativeWindow_release(static_cast<ANativeWindow *>(old));
  }
  if (g_engine == e) g_engine = nullptr;
  delete e;
  return LG_OK;
}
