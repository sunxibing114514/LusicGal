/*
 * 核心占位实现：让宿主桥在没有任何真实引擎核心时也可链接、可自测。
 * 真实核心（native/engines/<id>）将定义同名强符号覆盖这些弱实现。
 *
 * v2：push_input / surface_size 也有弱实现（宿主可直接调用无需判空；
 *     ABI 版本协商见 engine_abi.h）。
 */
#include "lusicgal/engine_abi.h"

#include <stddef.h>

static lg_result_t stub_create(const lg_engine_desc_t *desc, lg_engine_t *out) {
  (void)desc;
  (void)out;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_start(lg_engine_t e, lg_event_cb_t cb) {
  (void)e;
  (void)cb;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_command(lg_engine_t e, const char *json) {
  (void)e;
  (void)json;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_surface(lg_engine_t e, void *surface) {
  (void)e;
  (void)surface;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_input(lg_engine_t e, const char *json) {
  (void)e;
  (void)json;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_size(lg_engine_t e, int32_t w, int32_t h) {
  (void)e;
  (void)w;
  (void)h;
  return LG_ERR_NOT_SUPPORTED;
}

static lg_result_t stub_destroy(lg_engine_t e) {
  (void)e;
  return LG_OK;
}

#define LG_STUB_CORE(id)                                                       \
  __attribute__((weak)) uint32_t lg_##id##_abi_version(void) {                 \
    return LG_ABI_VERSION;                                                     \
  }                                                                            \
  __attribute__((weak)) lg_result_t lg_##id##_engine_create(                   \
      const lg_engine_desc_t *desc, lg_engine_t *out) {                        \
    return stub_create(desc, out);                                             \
  }                                                                            \
  __attribute__((weak)) lg_result_t lg_##id##_engine_start(                    \
      lg_engine_t e, lg_event_cb_t cb) { return stub_start(e, cb); }           \
  __attribute__((weak)) lg_result_t lg_##id##_engine_command_json(             \
      lg_engine_t e, const char *json) { return stub_command(e, json); }        \
  __attribute__((weak)) lg_result_t lg_##id##_engine_set_surface(               \
      lg_engine_t e, void *surface) { return stub_surface(e, surface); }        \
  __attribute__((weak)) lg_result_t lg_##id##_engine_push_input(               \
      lg_engine_t e, const char *json) { return stub_input(e, json); }          \
  __attribute__((weak)) lg_result_t lg_##id##_engine_surface_size(             \
      lg_engine_t e, int32_t w, int32_t h) { return stub_size(e, w, h); }       \
  __attribute__((weak)) lg_result_t lg_##id##_engine_destroy(lg_engine_t e) {  \
    return stub_destroy(e);                                                    \
  }

LG_CORE_LIST(LG_STUB_CORE)
