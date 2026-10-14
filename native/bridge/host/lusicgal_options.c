/*
 * LusicGal 宿主工具：极简 JSON 键值读取（无第三方依赖）。
 * 仅供核心与桥接层解析 options_json / command_json 中的平面键。
 */
#include "lusicgal/engine_abi.h"

#include <stdlib.h>
#include <string.h>

static const char *find_value(const char *json, const char *key, size_t *len) {
  if (json == NULL || key == NULL) return NULL;
  const size_t klen = strlen(key);
  const char *p = json;
  for (;;) {
    const char *k = strstr(p, key);
    if (k == NULL) return NULL;
    /* 确保是完整的键名："key" 之后的冒号 */
    const char *after = k + klen;
    if ((k == json || k[-1] == '"') && after[0] == '"') {
      after++;
      while (*after == ' ' || *after == ':') after++;
      if (*after == '"') {
        const char *v = after + 1;
        const char *e = strchr(v, '"');
        if (e != NULL) {
          *len = (size_t)(e - v);
          return v;
        }
        return NULL;
      }
      const char *e = after;
      while (*e != ',' && *e != '}' && *e != '\0') e++;
      if (*e == '\0') return NULL;
      *len = (size_t)(e - after);
      return after;
    }
    p = after;
  }
}

const char *lg_option_get(const char *json, const char *key, const char *fallback) {
  size_t len = 0;
  const char *v = find_value(json, key, &len);
  const char *src = fallback == NULL ? "" : fallback;
  if (v == NULL) {
    /* 始终返回可释放的拷贝，宿主无需区分来源。 */
    char *out = (char *)malloc(strlen(src) + 1);
    if (out == NULL) return src;
    strcpy(out, src);
    return out;
  }
  char *out = (char *)malloc(len + 1);
  if (out == NULL) return src;
  memcpy(out, v, len);
  out[len] = '\0';
  return out;
}

double lg_option_get_num(const char *json, const char *key, double fallback) {
  size_t len = 0;
  const char *v = find_value(json, key, &len);
  if (v == NULL) return fallback;
  char buf[32];
  if (len >= sizeof(buf)) return fallback;
  memcpy(buf, v, len);
  buf[len] = '\0';
  return strtod(buf, NULL);
}
