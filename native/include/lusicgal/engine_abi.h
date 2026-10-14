/*
 * LusicGal 统一引擎 ABI（v1）。
 *
 * 设计参考：
 *  - AetherKiri/abi/include/engine_api.h（Godot 宿主多运行时 ABI，源头为 krkr2）
 *  - KrKr2-Next 的 Flutter 壳 + C++ 核心分层
 *
 * 约定：
 *  - 所有结构体首字段 struct_size，尾部保留 reserved[]，ABI 可演化。
 *  - 核心不透明句柄 lg_engine_t；错误码统一 lg_result_t。
 *  - 渲染面由宿主注入（Android: ANativeWindow* / iOS: CALayer*）。
 *  - 输入/存档/音量等一切动态配置走 JSON 字符串（options_json / command_json），
 *    事件经回调以 JSON 返回 —— 这让 C ABI 无需为每个引擎的配置项扩展字段。
 *  - 每个核心一组带前缀的符号（iOS 静态链接必需），由 LG_CORE_API 生成。
 */
#ifndef LUSICGAL_ENGINE_ABI_H
#define LUSICGAL_ENGINE_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LG_ABI_VERSION 0x00010000u

#define LG_ABI_MAKE_VERSION(major, minor, patch) \
  (((uint32_t)(major) << 24) | ((uint32_t)(minor) << 16) | (uint32_t)(patch))

typedef enum lg_result {
  LG_OK = 0,
  LG_ERR_INVALID_ARGUMENT = -1,
  LG_ERR_INVALID_STATE = -2,
  LG_ERR_NOT_SUPPORTED = -3,
  LG_ERR_IO = -4,
  LG_ERR_CORE = -5,
} lg_result_t;

typedef struct lg_engine_s *lg_engine_t;

/* 事件回调：JSON（{"type":"log|state|exit", ...}）。回调线程由核心定义。 */
typedef void (*lg_event_cb_t)(void *host, const char *json_utf8);

typedef struct lg_engine_desc {
  uint32_t struct_size; /* = sizeof(lg_engine_desc_t) */
  uint32_t abi_version; /* 宿主 LG_ABI_VERSION */
  const char *engine_id; /* "onscripter" 等，见 lib/core/models/engine_id.dart */
  const char *game_id;   /* 书库条目 id（存档隔离键） */
  const char *game_path; /* UTF-8 游戏文件目录 */
  const char *save_path; /* UTF-8 存档写入目录（已由宿主创建） */
  const char *cache_path; /* UTF-8 缓存目录（可空） */
  const char *options_json; /* 启动选项 JSON（分辨率缩放/音量/按键映射） */
  void *host;             /* 回调 host 透传 */
  void *reserved_ptr[8];
  uint64_t reserved_u64[8];
} lg_engine_desc_t;

/*
 * 每核心符号集：lg_<id>_abi_version / _engine_create / _engine_start /
 * _engine_command_json / _engine_set_surface / _engine_destroy。
 *
 * 宿主按前缀 dlsym/System.loadLibrary 探测（见平台桥插件）。
 */
#define LG_CORE_API(id)                                                        \
  uint32_t lg_##id##_abi_version(void);                                        \
  lg_result_t lg_##id##_engine_create(const lg_engine_desc_t *desc,            \
                                      lg_engine_t *out);                       \
  lg_result_t lg_##id##_engine_start(lg_engine_t engine, lg_event_cb_t cb);    \
  lg_result_t lg_##id##_engine_command_json(lg_engine_t engine,               \
                                             const char *json_utf8);           \
  lg_result_t lg_##id##_engine_set_surface(lg_engine_t engine, void *surface); \
  lg_result_t lg_##id##_engine_destroy(lg_engine_t engine);

/* LusicGal 当前支持的全部核心。 */
#define LG_CORE_LIST(X)                                                        \
  X(kirikiri)                                                                  \
  X(onscripter)                                                                \
  X(renpy)                                                                     \
  X(siglus)                                                                    \
  X(rfvp)                                                                      \
  X(sena)                                                                      \
  X(xsystem35)                                                                 \
  X(artemis)

#define LG_DECLARE_ALL_CORES() LG_CORE_LIST(LG_CORE_API)

LG_DECLARE_ALL_CORES()

/* 宿主侧工具：从 options_json 中读取字符串/数值键（bridge 实现）。 */
const char *lg_option_get(const char *json_utf8, const char *key, const char *fallback);
double lg_option_get_num(const char *json_utf8, const char *key, double fallback);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* LUSICGAL_ENGINE_ABI_H */
