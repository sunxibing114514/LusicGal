/*
 * 宿主自检：验证 ABI 头 + 工具实现 + 全部核心的弱符号在无真实引擎时可链接。
 * CI（engines.yml / c-abi-host）编译并运行本文件 —— 必须绿。
 */
#include "lusicgal/engine_abi.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                          \
  do {                                                                        \
    if (!(cond)) {                                                            \
      printf("FAIL: %s (line %d)\n", #cond, __LINE__);                        \
      failures++;                                                             \
    }                                                                          \
  } while (0)

int main(void) {
  CHECK(lg_onscripter_abi_version() == LG_ABI_VERSION);
  CHECK(lg_kirikiri_abi_version() == LG_ABI_VERSION);
  CHECK(lg_renpy_abi_version() == LG_ABI_VERSION);

  lg_engine_desc_t desc;
  memset(&desc, 0, sizeof(desc));
  desc.struct_size = (uint32_t)sizeof(desc);
  desc.abi_version = LG_ABI_VERSION;
  desc.engine_id = "onscripter";
  desc.game_id = "test-game";
  desc.game_path = "/data/game";
  desc.save_path = "/data/saves";
  desc.cache_path = "/data/cache";
  desc.options_json = "{\"resolutionScale\":1.5,\"volumes\":{\"master\":80}}";

  /* 弱 stub 核心：create 应返回 NOT_SUPPORTED（真实核心未链接）。 */
  lg_engine_t engine = NULL;
  CHECK(lg_onscripter_engine_create(&desc, &engine) == LG_ERR_NOT_SUPPORTED);
  CHECK(lg_rfvp_engine_create(&desc, &engine) == LG_ERR_NOT_SUPPORTED);
  CHECK(lg_siglus_engine_command_json(NULL, "{}") == LG_ERR_NOT_SUPPORTED);

  /* 选项工具。 */
  CHECK(lg_option_get_num(desc.options_json, "resolutionScale", 1.0) == 1.5);
  CHECK(lg_option_get_num(desc.options_json, "missing", 42.0) == 42.0);
  const char *engine_opt = lg_option_get(desc.options_json, "engine", "fallback");
  CHECK(engine_opt != NULL && strcmp(engine_opt, "fallback") == 0);
  free((void *)engine_opt);

  if (failures == 0) {
    printf("{\"selftest\":\"ok\",\"abi\":\"0x%08x\"}\n", LG_ABI_VERSION);
    return 0;
  }
  printf("{\"selftest\":\"FAILED\",\"failures\":%d}\n", failures);
  return 1;
}
