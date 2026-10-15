# LusicGal overlay triplet：krkr2 的 arm64-android 自包含镜像 + release-only。
#
# 为什么自包含：vcpkg 求 triplet 时无 KRKR2_DIR 等外部变量（实测 include
# 解析成 /vcpkg/triplets/... 失败）；CMAKE_CURRENT_LIST_DIR 指向本目录，
# android-dynamic-libs.cmake 一并镜像。
# 为什么 release-only：vcpkg manifest 默认 dbg+rel 双构建 —— DBG（-O0 +
# 完整 -g）对模板重库（spirv-tools diff.cpp 等）单进程内存超小容器上限
# （实测 SIGKILL 137，cgroup OOM 含页缓存）。RELEASE-only：内存峰值更低
# + 构建量减半，CI 同样受益（dbg 产物从未被使用）。
# 若上游 krkr2 的 triplet 改动，此处需同步（pin 见 third_party/fetch 清单）。
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
set(VCPKG_CMAKE_SYSTEM_VERSION 24)

include(${CMAKE_CURRENT_LIST_DIR}/android-dynamic-libs.cmake)

set(VCPKG_BUILD_TYPE release)
