cmake_minimum_required(VERSION 3.16)
project(lusicgal_bridge C)

# JNI 桥 + 宿主工具 + 核心 stub（engines.yml: jni-bridge-android 用 NDK 编译，
# 产出 liblusicgal_bridge.a；真实核心接入后由宿主 Gradle 合并进 liblusicgal_<id>.so）。
add_library(lusicgal_bridge STATIC
  jni/lusicgal_jni.c
  host/lusicgal_options.c
  stubs/lusicgal_stubs.c
)
target_include_directories(lusicgal_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../include)
