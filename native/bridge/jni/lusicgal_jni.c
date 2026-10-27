/*
 * LusicGal JNI 桥（v2）：Java_com_lusicgal_engines_CoreNative_* → C ABI。
 *
 * 派发方式：运行期 dlsym(RTLD_DEFAULT, "lg_<id>_…")。
 *  - Android：核心以独立 liblusicgal_<id>.so 发布（Kotlin 先 loadLibrary
 *    再 probeCore），桥本身不链接任何核心 —— 核心可拆包/可下载（许可策略
 *    见 docs/LICENSE_NOTES.md）。
 *  - iOS：静态链接（弱 stub 兜底，见 native/stubs），dlsym 同样适用。
 *
 * 会话：单活动会话（v1 约定：一次运行一个游戏；多开在 v0.5 后再议）。
 * 事件：核心线程 → JVM AttachCurrentThread → Kotlin onEvent(String) → 主线程
 * → EventChannel。
 */
#include "lusicgal/engine_abi.h"

#include <dlfcn.h>
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __ANDROID__
#include <android/native_window.h>
#include <android/native_window_jni.h>
#endif

/* ---- 核心 API 运行期解析 -------------------------------------------------- */

/*
 * 核心装载方式（v0.1.11 修正）：
 *  - Kotlin System.loadLibrary 在 bionic 是 RTLD_LOCAL —— 符号不进全局
 *    作用域，桥的 dlsym(RTLD_DEFAULT, "lg_<id>_…") 永远解析不到 →
 *    launch 一律 -3 NOT_SUPPORTED（v0.1.10 现机报障实证；此前被更早的
 *    装载失败掩盖，原生核心从未真正启动过）。
 *  - 修正：Kotlin 改调 loadCoreGlobal(全路径) —— 本桥 dlopen(path,
 *    RTLD_NOW|RTLD_GLOBAL)，核心符号进全局作用域，dlsym(RTLD_DEFAULT)
 *    生效。同库重复 dlopen 由 linker 按路径去重，只提升作用域。
 */

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

/* 最近一次 loadCoreGlobal 的 dlopen 错误原文（coreLoadError 读出）。 */
static char g_last_core_dlerror[512] = {0};

/* 解析核心符号集。返回 1 = abi_version 符号存在（核心已加载）。 */
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

/* ---- 会话 ------------------------------------------------------------------ */

typedef struct {
  char id[32];
  lg_core_api_t api;
  lg_engine_t engine;
  int started;
} lg_session_t;

static lg_session_t g_session;

static int session_alive(void) {
  return g_session.started && g_session.engine != NULL;
}

/* ---- 事件回流：核心线程 → Kotlin ------------------------------------------ */

static JavaVM *g_vm = NULL;
static jobject g_sink_ref = NULL;
static jmethodID g_sink_method = NULL;

jint JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  g_vm = vm;
  return JNI_VERSION_1_6;
}

static void emit_event(void *host, const char *json) {
  (void)host;
  if (g_vm == NULL || g_sink_ref == NULL || g_sink_method == NULL || json == NULL) {
    return;
  }
  JNIEnv *env = NULL;
  int attached = 0;
  if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*g_vm)->AttachCurrentThread(g_vm, (void **)&env, NULL) != JNI_OK) {
      return;
    }
    attached = 1;
  }
  jstring jstr = (*env)->NewStringUTF(env, json);
  if (jstr != NULL) {
    (*env)->CallVoidMethod(env, g_sink_ref, g_sink_method, jstr);
    (*env)->DeleteLocalRef(env, jstr);
  }
  if (attached) {
    (*g_vm)->DetachCurrentThread(g_vm);
  }
}

/* ---- Android 上下文注入（v2） -------------------------------------------- */

static jobject g_context_ref = NULL;

/* 可选核心符号 lg_<id>_set_android_context(java_vm, context)：
 * 供上游音频栈（kira→cpal→Oboe / ndk-context）初始化。launch 前注入。 */
static void inject_android_context(const char *engine_id) {
  if (g_vm == NULL || g_context_ref == NULL || engine_id == NULL) return;
  char buf[96];
  if (snprintf(buf, sizeof(buf), "lg_%s_set_android_context", engine_id) >=
      (int)sizeof(buf)) {
    return;
  }
  void *sym = dlsym(RTLD_DEFAULT, buf);
  if (sym == NULL) return;
  typedef void (*set_ctx_fn)(void *, void *);
  ((set_ctx_fn)sym)((void *)g_vm, (void *)g_context_ref);
}

/* ---- 工具 ------------------------------------------------------------------ */

static char *jstr_dup(JNIEnv *env, jstring s) {
  if (s == NULL) return NULL;
  const char *c = (*env)->GetStringUTFChars(env, s, NULL);
  if (c == NULL) return NULL;
  char *out = strdup(c);
  (*env)->ReleaseStringUTFChars(env, s, c);
  return out;
}

/* ---- JNI 入口 -------------------------------------------------------------- */

/*
 * dlopen 核心库到全局作用域（Kotlin 侧装载入口，替代 System.loadLibrary
 * —— 后者 RTLD_LOCAL，符号对 dlsym(RTLD_DEFAULT) 不可见）。
 * path = liblusicgal_<id>.so 的绝对路径（nativeLibraryDir 下）。
 * 返回 0 成功；非 0 = 失败，原文见 coreLoadError()。
 */
JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_loadCoreGlobal(JNIEnv *env,
                                                     jclass clazz,
                                                     jstring path) {
  (void)clazz;
  const char *cpath = (*env)->GetStringUTFChars(env, path, NULL);
  if (cpath == NULL) return -1;
  dlerror();
  void *h = dlopen(cpath, RTLD_NOW | RTLD_GLOBAL);
  const char *err = dlerror();
  if (h == NULL) {
    snprintf(g_last_core_dlerror, sizeof(g_last_core_dlerror), "%s: %s",
             cpath, (err && *err) ? err : "dlopen failed");
    (*env)->ReleaseStringUTFChars(env, path, cpath);
    return -1;
  }
  g_last_core_dlerror[0] = '\0';
  (*env)->ReleaseStringUTFChars(env, path, cpath);
  return 0;
}

JNIEXPORT jstring JNICALL
Java_com_lusicgal_engines_CoreNative_coreLoadError(JNIEnv *env,
                                                   jclass clazz) {
  (void)clazz;
  return (*env)->NewStringUTF(env, g_last_core_dlerror[0]
                                        ? g_last_core_dlerror : "");
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_probeCore(JNIEnv *env, jclass clazz,
                                               jstring engine_id) {
  (void)clazz;
  char *id = jstr_dup(env, engine_id);
  if (id == NULL) return 0;
  lg_core_api_t api;
  int found = lg_resolve(id, &api);
  free(id);
  return found;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_coreAbiVersion(JNIEnv *env, jclass clazz,
                                                    jstring engine_id) {
  (void)clazz;
  char *id = jstr_dup(env, engine_id);
  if (id == NULL) return 0;
  lg_core_api_t api;
  jint v = 0;
  if (lg_resolve(id, &api) && api.abi_version != NULL) {
    v = (jint)api.abi_version();
  }
  free(id);
  return v;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_launch(JNIEnv *env, jclass clazz,
                                            jstring engine_id, jstring game_id,
                                            jstring game_path,
                                            jstring save_path,
                                            jstring options_json) {
  (void)clazz;
  if (session_alive()) return LG_ERR_INVALID_STATE;
  if (engine_id == NULL || game_path == NULL) return LG_ERR_INVALID_ARGUMENT;

  char *id = jstr_dup(env, engine_id);
  char *gid = jstr_dup(env, game_id);
  char *gpath = jstr_dup(env, game_path);
  char *spath = jstr_dup(env, save_path);
  char *opts = jstr_dup(env, options_json);
  if (id == NULL || gpath == NULL) {
    free(id);
    free(gid);
    free(gpath);
    free(spath);
    free(opts);
    return LG_ERR_INVALID_ARGUMENT;
  }

  lg_core_api_t api;
  if (!lg_resolve(id, &api) || api.create == NULL) {
    free(id);
    free(gid);
    free(gpath);
    free(spath);
    free(opts);
    return LG_ERR_NOT_SUPPORTED;
  }
  /* 核心可先拿到 JVM/Context（音频初始化需要，见 inject_android_context）。 */
  inject_android_context(id);

  lg_result_t rc;
  lg_engine_desc_t desc;
  memset(&desc, 0, sizeof(desc));
  desc.struct_size = (uint32_t)sizeof(desc);
  desc.abi_version = LG_ABI_VERSION;
  desc.engine_id = id;
  desc.game_id = gid;
  desc.game_path = gpath;
  desc.save_path = spath;
  desc.cache_path = spath;
  desc.options_json = opts;
  desc.host = NULL;

  lg_engine_t engine = NULL;
  rc = api.create(&desc, &engine);
  if (rc == LG_OK && engine != NULL && api.start != NULL) {
    rc = api.start(engine, emit_event);
    if (rc == LG_OK) {
      memset(&g_session, 0, sizeof(g_session));
      snprintf(g_session.id, sizeof(g_session.id), "%s", id);
      g_session.api = api;
      g_session.engine = engine;
      g_session.started = 1;
    } else if (api.destroy != NULL) {
      api.destroy(engine);
    }
  } else if (rc == LG_OK && engine != NULL && api.destroy != NULL) {
    /* 无 start 入口：销毁半成品。 */
    api.destroy(engine);
    rc = LG_ERR_NOT_SUPPORTED;
  }

  free(id);
  free(gid);
  free(gpath);
  free(spath);
  free(opts);
  return (jint)rc;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_command(JNIEnv *env, jclass clazz,
                                             jstring engine_id, jstring command,
                                             jstring args_json) {
  (void)clazz;
  (void)engine_id;
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  if (command == NULL) return LG_ERR_INVALID_ARGUMENT;
  char *cmd = jstr_dup(env, command);
  char *args = jstr_dup(env, args_json);
  if (cmd == NULL) {
    free(args);
    return LG_ERR_INVALID_ARGUMENT;
  }
  lg_result_t rc = LG_ERR_NOT_SUPPORTED;
  if (g_session.api.command_json != NULL) {
    size_t n = strlen(cmd) + (args ? strlen(args) : 0) + 64;
    char *json = (char *)malloc(n);
    if (json != NULL) {
      if (args != NULL) {
        snprintf(json, n, "{\"command\":\"%s\",\"args\":%s}", cmd, args);
      } else {
        snprintf(json, n, "{\"command\":\"%s\"}", cmd);
      }
      rc = g_session.api.command_json(g_session.engine, json);
      free(json);
    } else {
      rc = LG_ERR_IO;
    }
  }
  free(cmd);
  free(args);
  return (jint)rc;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_pushInput(JNIEnv *env, jclass clazz,
                                               jstring json) {
  (void)clazz;
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  char *input = jstr_dup(env, json);
  if (input == NULL) return LG_ERR_INVALID_ARGUMENT;
  lg_result_t rc = LG_ERR_NOT_SUPPORTED;
  if (g_session.api.push_input != NULL) {
    rc = g_session.api.push_input(g_session.engine, input);
  } else if (g_session.api.command_json != NULL) {
    /* v1 核心回退：command_json {"command":"input","event":…}。 */
    size_t n = strlen(input) + 32;
    char *wrap = (char *)malloc(n);
    if (wrap != NULL) {
      snprintf(wrap, n, "{\"command\":\"input\",\"event\":%s}", input);
      rc = g_session.api.command_json(g_session.engine, wrap);
      free(wrap);
    } else {
      rc = LG_ERR_IO;
    }
  }
  free(input);
  return (jint)rc;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_surfaceSize(JNIEnv *env, jclass clazz,
                                                 jint w, jint h) {
  (void)env;
  (void)clazz;
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  if (w <= 0 || h <= 0) return LG_ERR_INVALID_ARGUMENT;
  if (g_session.api.surface_size == NULL) return LG_ERR_NOT_SUPPORTED;
  return (jint)g_session.api.surface_size(g_session.engine, (int32_t)w,
                                         (int32_t)h);
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_attachSurface(JNIEnv *env, jclass clazz,
                                                   jobject surface) {
  (void)clazz;
  if (!session_alive()) return LG_ERR_INVALID_STATE;
  if (surface == NULL) return LG_ERR_INVALID_ARGUMENT;
  if (g_session.api.set_surface == NULL) return LG_ERR_NOT_SUPPORTED;
#ifdef __ANDROID__
  ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
  if (window == NULL) return LG_ERR_INVALID_ARGUMENT;
  lg_result_t rc = g_session.api.set_surface(g_session.engine, (void *)window);
  if (rc != LG_OK) {
    ANativeWindow_release(window);
  }
  return (jint)rc;
#else
  (void)surface;
  return LG_ERR_NOT_SUPPORTED;
#endif
}

/* v2：注册应用上下文（onAttachedToEngine 调一次；launch 前注入核心）。 */
JNIEXPORT void JNICALL
Java_com_lusicgal_engines_CoreNative_initAndroid(JNIEnv *env, jclass clazz,
                                                 jobject context) {
  (void)clazz;
  if (g_context_ref != NULL) {
    (*env)->DeleteGlobalRef(env, g_context_ref);
    g_context_ref = NULL;
  }
  if (context != NULL) {
    g_context_ref = (*env)->NewGlobalRef(env, context);
  }
}

/* 会话结束（核心回调 exit 事件或 Dart 调 stop 后调用；幂等）。 */
JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_shutdown(JNIEnv *env, jclass clazz) {
  (void)env;
  (void)clazz;
  if (!session_alive()) return LG_OK;
  lg_result_t rc = LG_OK;
  if (g_session.api.command_json != NULL) {
    g_session.api.command_json(g_session.engine, "{\"command\":\"stop\"}");
  }
  if (g_session.api.destroy != NULL) {
    rc = g_session.api.destroy(g_session.engine);
  }
  memset(&g_session, 0, sizeof(g_session));
  return (jint)rc;
}

JNIEXPORT void JNICALL
Java_com_lusicgal_engines_CoreNative_setEventSink(JNIEnv *env, jclass clazz,
                                                 jobject sink) {
  (void)clazz;
  if (g_sink_ref != NULL) {
    (*env)->DeleteGlobalRef(env, g_sink_ref);
    g_sink_ref = NULL;
    g_sink_method = NULL;
  }
  if (sink == NULL) return;
  g_sink_ref = (*env)->NewGlobalRef(env, sink);
  if (g_sink_ref == NULL) return;
  jclass klass = (*env)->GetObjectClass(env, g_sink_ref);
  if (klass == NULL) {
    (*env)->DeleteGlobalRef(env, g_sink_ref);
    g_sink_ref = NULL;
    return;
  }
  g_sink_method =
      (*env)->GetMethodID(env, klass, "onEvent", "(Ljava/lang/String;)V");
  (*env)->DeleteLocalRef(env, klass);
  if (g_sink_method == NULL) {
    (*env)->DeleteGlobalRef(env, g_sink_ref);
    g_sink_ref = NULL;
  }
}
