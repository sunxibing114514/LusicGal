/*
 * LusicGal iOS 桥：Swift → 统一 C ABI（engine_abi.h）。
 *
 * iOS 核心为静态链接（.a 经 podspec / 构建脚本并入）：
 *  - 有核心：dlsym(RTLD_DEFAULT) 解析其强符号；
 *  - 无核心：native/stubs 的弱 stub 兜底（lg_ios_probe 返回 0）。
 * 单活动会话；事件经 Swift 注册的 C 回调（主队列分发在 Swift 侧）。
 */
#ifndef LUSICGAL_IOS_BRIDGE_H
#define LUSICGAL_IOS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 返回值 = lg_result_t（engine_abi.h）。 */
int32_t lg_ios_launch(const char *engine_id, const char *game_id,
                      const char *game_path, const char *save_path,
                      const char *options_json);
int32_t lg_ios_command(const char *json_utf8);
int32_t lg_ios_push_input(const char *json_utf8);
int32_t lg_ios_surface_size(int32_t w, int32_t h);
/* surface：CAMetalLayer*（渲染核心）或 UIView*（CPU 帧核心自绘）。 */
int32_t lg_ios_attach_surface(void *surface);
int32_t lg_ios_shutdown(void);

/* 探测：1=核心已链接；0=未链接。 */
int32_t lg_ios_probe(const char *engine_id);
int32_t lg_ios_core_abi_version(const char *engine_id);

/* 事件回调：核心线程调用；json 生命周期仅限回调内。 */
typedef void (*lg_ios_event_cb_t)(const char *json_utf8);
void lg_ios_set_event_callback(lg_ios_event_cb_t cb);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* LUSICGAL_IOS_BRIDGE_H */
