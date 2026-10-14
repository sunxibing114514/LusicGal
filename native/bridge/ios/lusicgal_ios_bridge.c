/*
 * LusicGal iOS 桥实现（会话派发，与 Android JNI 桥同构）。
 * 详注见 include/lusicgal_ios_bridge.h 与 jni/lusicgal_jni.c。
 */
#include "lusicgal/engine_abi.h"
#include "lusicgal_ios_bridge.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct lg_core_api {
  uint32_t (*abi_version)(void);
  lg_result_t (*create)(const lg_engine_desc_t *, lg_engine_t *);
  lg_result_t (*start)(lg_engine_t, lg_event_cb_t);
  lg_result_t (*command_json)(lg_engine_t, const char *);
  lg_result_t (*set_surface)(lg_engine_t, void *);
  lg_result_t (*push_input)(lg_engine_t, const char *);
  lg_result_t (*surface_size)(lg_engine_t, int32_t, int32_t);
  lg_result_t (*destroy)(lg_engine_t);
} lg_core_api_t;

static void lg_resolve_sym(void **slot, const char *engine_id,
                           const char *suffix) {
  char buf[96];
  if (snprintf(buf, sizeof(buf), "lg_%s_%s", engine_id, suffix) >=
      (int)sizeof(buf)) {
    *slot = NULL;
    return;
  }
  *slot = dlsym(RTLD_DEFAULT, buf);
}

static int lg_resolve(const char *engine_id, lg_core_api_t *api) {
  memset(api, 0, sizeof(*api));
  if (engine_id == NULL) return 0;
  lg_resolve_sym((void **)&api->abi_version, engine_id, "abi_version");
  if (api->abi_version == NULL) return 0;
  lg_resolve_sym((void **)&api->create, engine_id, "engine_create");
  lg_resolve_sym((void **)&api->start, engine_id, "engine_start");
  lg_resolve_sym((void **)&api->command_json, engine_id, "engine_command_json");
  lg_resolve_sym((void **)&api->set_surface, engine_id, "engine_set_surface");
  lg_resolve_sym((void **)&api->push_input, engine_id, "engine_push_input");
  lg_resolve_sym((void **)&api->surface_size, engine_id, "engine_surface_size");
  lg_resolve_sym((void **)&api->destroy, engine_id, "engine_destroy");
  return 1;
}

static struct {
  char id[32];
  lg_core_api_t api;
  lg_engine_t engine;
  int started;
} g_session;

static lg_ios_event_cb_t g_event_cb = NULL;

static void emit_event(void *host, const char *json) {
  (void)host;
  if (g_event_cb != NULL && json != NULL) {
    g_event_cb(json);
  }
}

static int session_alive(void) {
  return g_session.started && g_session.engine != NULL;
}

int32_t lg_ios_probe(const char *engine_id) {
  if (engine_id == NULL) return 0;
  lg_core_api_t api;
  return lg_resolve(engine_id, &api) ? 1 : 0;
}

int32_t lg_ios_core_abi_version(const char *engine_id) {
  if (engine_id == NULL) return 0;
  lg_core_api_t api;
  if (!lg_resolve(engine_id, &api) || api.abi_version == NULL) return 0;
  return (int32_t)api.abi_version();
}

int32_t lg_ios_launch(const char *engine_id, const char *game_id,
                      const char *game_path, const char *save_path,
                      const char *options_json) {
  if (session_alive()) return LG_ERR_INVALID_STATE;
  if (engine_id == NULL || game_path == NULL) return LG_ERR_INVALID_ARGUMENT;
  lg_core_api_t api;
  if (!lg_resolve(engine_id, &api) || api.create == NULL) {
    return LG_ERR_NOT_SUPPORTED;
  }
  lg_engine_desc_t desc;
  memset(&desc, 0, sizeof(desc));
  desc.struct_size = (uint32_t)sizeof(desc);
  desc.abi_version = LG_ABI_VERSION;
  desc.engine_id = engine_id;
  desc.game_id = game_id;
  desc.game_path = game_path;
  desc.save_path = save_path ? save_path : game_path;
  desc.cache_path = save_path ? save_path : game_path;
  desc.options_json = options_json;
  desc.host = NULL;

  lg_engine_t engine = NULL;
  lg_result_t rc = api.create(&desc, &engine);
  if (rc == LG_OK && engine != NULL && api.start != NULL) {
    rc = api.start(engine, emit_event);
    if (rc == LG_OK) {
      memset(&g_session, 0, sizeof(g_session));
      snprintf(g_session.id, sizeof(g_session.id), "%s", engine_id);
      g_session.api = api;
      g_session.engine = engine;
      g_session.started = 1;
    } else if (api.destroy != NULL) {
      api.destroy(engine);
    }
  } else if (rc == LG_OK && engine != NULL && api.destroy != NULL) {
    api.destroy(engine);
    rc = LG_ERR_NOT_SUPPORTED;
  }
  return rc;
}

int32_t lg_ios_command(const char *json_utf8) {
  if (!session_alive() || json_utf8 == NULL) return LG_ERR_INVALID_STATE;
  if (g_session.api.command_json == NULL) return LG_ERR_NOT_SUPPORTED;
  return g_session.api.command_json(g_session.engine, json_utf8);
}

int32_t lg_ios_push_input(const char *json_utf8) {
  if (!session_alive() || json_utf8 == NULL) return LG_ERR_INVALID_STATE;
  if (g_session.api.push_input != NULL) {
    return g_session.api.push_input(g_session.engine, json_utf8);
  }
  if (g_session.api.command_json == NULL) return LG_ERR_NOT_SUPPORTED;
  size_t n = strlen(json_utf8) + 32;
  char *wrap = (char *)malloc(n);
  if (wrap == NULL) return LG_ERR_IO;
  snprintf(wrap, n, "{\"command\":\"input\",\"event\":%s}", json_utf8);
  lg_result_t rc = g_session.api.command_json(g_session.engine, wrap);
  free(wrap);
  return rc;
}

int32_t lg_ios_surface_size(int32_t w, int32_t h) {
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  if (w <= 0 || h <= 0) return LG_ERR_INVALID_ARGUMENT;
  if (g_session.api.surface_size == NULL) return LG_ERR_NOT_SUPPORTED;
  return g_session.api.surface_size(g_session.engine, w, h);
}

int32_t lg_ios_attach_surface(void *surface) {
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  if (surface == NULL) return LG_ERR_INVALID_ARGUMENT;
  if (g_session.api.set_surface == NULL) return LG_ERR_NOT_SUPPORTED;
  return g_session.api.set_surface(g_session.engine, surface);
}

int32_t lg_ios_shutdown(void) {
  if (!session_alive()) return LG_OK;
  if (g_session.api.command_json != NULL) {
    g_session.api.command_json(g_session.engine, "{\"command\":\"stop\"}");
  }
  lg_result_t rc = LG_OK;
  if (g_session.api.destroy != NULL) {
    rc = g_session.api.destroy(g_session.engine);
  }
  memset(&g_session, 0, sizeof(g_session));
  return rc;
}

void lg_ios_set_event_callback(lg_ios_event_cb_t cb) {
  g_event_cb = cb;
}
