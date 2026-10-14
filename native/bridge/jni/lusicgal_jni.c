/*
 * LusicGal JNI 桥：Java_com_lusicgal_engines_CoreNative_* → C ABI。
 *
 * 核心符号以弱引用接入（__attribute__((weak))）：核心未打包/未链接时
 * 桥仍然可编译链接，运行时返回 LG_ERR_NOT_SUPPORTED。
 * 真实核心由 native/engines/<id> 的构建脚本产出 liblusicgal_<id>.so，
 * 由宿主 Gradle（后续版本）链接进 APK。
 */
#include "lusicgal/engine_abi.h"

#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 弱引用声明：核心存在则由动态库提供，否则为 NULL。 */
#define LG_WEAK_CORE(id)                                                       \
  extern uint32_t lg_##id##_abi_version(void) __attribute__((weak));           \
  extern lg_result_t lg_##id##_engine_create(                                  \
      const lg_engine_desc_t *, lg_engine_t *) __attribute__((weak));          \
  extern lg_result_t lg_##id##_engine_start(lg_engine_t, lg_event_cb_t)        \
      __attribute__((weak));                                                  \
  extern lg_result_t lg_##id##_engine_command_json(lg_engine_t,                \
                                                   const char *)              \
      __attribute__((weak));                                                  \
  extern lg_result_t lg_##id##_engine_destroy(lg_engine_t) __attribute__((weak));

LG_CORE_LIST(LG_WEAK_CORE)

typedef struct {
  const char *id;
  lg_engine_t engine;
  int started;
} lg_session_t;

static lg_session_t g_session;

static char *jstr_dup(JNIEnv *env, jstring s) {
  if (s == NULL) return NULL;
  const char *c = (*env)->GetStringUTFChars(env, s, NULL);
  if (c == NULL) return NULL;
  char *out = strdup(c);
  (*env)->ReleaseStringUTFChars(env, s, c);
  return out;
}

static void emit_event(void *host, const char *json) {
  (void)host;
  (void)json;
  /* v1：事件经 EventChannel 由宿主轮询/桥接；真实核心接入时由
   * 平台桥（Kotlin）通过 JNI 回调把 JSON 事件推送到 EventChannel。 */
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_launch(JNIEnv *env, jclass clazz,
                                            jstring engine_id, jstring game_id,
                                            jstring game_path, jstring save_path,
                                            jstring options_json) {
  (void)clazz;
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

  lg_result_t rc = LG_ERR_NOT_SUPPORTED;
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

#define LG_TRY_CORE(id_)                                                       \
  do {                                                                         \
    if (lg_##id_##_engine_create != NULL && strcmp(id, #id_) == 0) {           \
      rc = lg_##id_##_engine_create(&desc, &engine);                           \
    }                                                                          \
  } while (0);
  LG_CORE_LIST(LG_TRY_CORE)
#undef LG_TRY_CORE

  if (rc == LG_OK && engine != NULL) {
#define LG_START_CORE(id_)                                                     \
  do {                                                                         \
    if (lg_##id_##_engine_start != NULL && strcmp(id, #id_) == 0) {            \
      rc = lg_##id_##_engine_start(engine, emit_event);                        \
    }                                                                          \
  } while (0);
    LG_CORE_LIST(LG_START_CORE)
#undef LG_START_CORE
    if (rc == LG_OK) {
      free(g_session.id);
      g_session.id = strdup(id);
      g_session.engine = engine;
      g_session.started = 1;
    } else {
      /* 启动失败：销毁半成品实例，避免泄漏。 */
#define LG_DESTROY_CORE(id_)                                                   \
  do {                                                                         \
    if (lg_##id_##_engine_destroy != NULL && strcmp(id, #id_) == 0) {          \
      lg_##id_##_engine_destroy(engine);                                        \
    }                                                                          \
  } while (0);
      LG_CORE_LIST(LG_DESTROY_CORE)
#undef LG_DESTROY_CORE
    }
  }

  /* desc 的字符串所有权交由核心（按 ABI 约定核心在 create 内复制）。 */
  return (jint)rc;
}

JNIEXPORT jint JNICALL
Java_com_lusicgal_engines_CoreNative_command(JNIEnv *env, jclass clazz,
                                             jstring engine_id, jstring command,
                                             jstring args_json) {
  (void)clazz;
  (void)engine_id;
  if (!g_session.started || g_session.engine == NULL) return LG_ERR_INVALID_STATE;
  if (command == NULL) return LG_ERR_INVALID_ARGUMENT;
  char *cmd = jstr_dup(env, command);
  char *args = jstr_dup(env, args_json);
  if (cmd == NULL) {
    free(args);
    return LG_ERR_INVALID_ARGUMENT;
  }
  size_t n = strlen(cmd) + (args ? strlen(args) : 0) + 64;
  char *json = (char *)malloc(n);
  lg_result_t rc = LG_ERR_NOT_SUPPORTED;
  if (json != NULL) {
    if (args != NULL) {
      snprintf(json, n, "{\"command\":\"%s\",\"args\":%s}", cmd, args);
    } else {
      snprintf(json, n, "{\"command\":\"%s\"}", cmd);
    }
#define LG_CMD_CORE(id_)                                                       \
  do {                                                                         \
    if (lg_##id_##_engine_command_json != NULL && g_session.id != NULL &&       \
        strcmp(g_session.id, #id_) == 0) {                                      \
      rc = lg_##id_##_engine_command_json(g_session.engine, json);              \
    }                                                                          \
  } while (0);
    LG_CORE_LIST(LG_CMD_CORE)
#undef LG_CMD_CORE
    free(json);
  }
  free(cmd);
  free(args);
  return (jint)rc;
}
