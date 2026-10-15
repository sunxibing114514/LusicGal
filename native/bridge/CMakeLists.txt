cmake_minimum_required(VERSION 3.16)
project(lusicgal_bridge C CXX)

# LusicGal JNI 桥：SHARED 库（liblusicgal_bridge.so）。
# dlsym 运行期派发（见 jni/lusicgal_jni.c）——桥不链接任何核心：
#  - Android：核心 = 独立 liblusicgal_<id>.so（Kotlin loadLibrary 后
#    dlsym(RTLD_DEFAULT) 解析；可拆包/可下载，见 docs/LICENSE_NOTES.md）。
#    因此这里【不】编入 stubs —— 弱 stub 会遮蔽真实核心符号。
#  - iOS：静态链接，stub 弱符号由 pod 提供（见 plugins/lusicgal_engines/ios）。
# 核心适配器子目录（LG_ENG_<id>=ON 时）编译独立 core 目标，不进桥。
add_library(lusicgal_bridge SHARED
  jni/lusicgal_jni.c
  host/lusicgal_options.c
)
target_include_directories(lusicgal_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../include)

find_library(log-lib log)
target_link_libraries(lusicgal_bridge PRIVATE ${log-lib})
target_link_libraries(lusicgal_bridge PRIVATE dl)

# ANativeWindow_fromSurface/_release（attachSurface 注入渲染面）在
# libandroid.so —— 桥必须链接（本地 NDK 构建实证缺此即链接失败）。
find_library(android-lib android)
target_link_libraries(lusicgal_bridge PRIVATE ${android-lib})

# 核心不并入桥（v2 分发模型）：
#   Android —— 各核心独立 liblusicgal_<id>.so，由
#     native/engines/<id>/build_android.sh（C/C++ 核心）或
#     scripts/build_rust_core.sh（Rust 核心）产出，运行期
#     System.loadLibrary + dlsym 派发（docs/BUILD.md §核心分发模型）。
#   iOS —— 静态库 liblusicgal_<id>.a 并入 pod（弱 stub 兜底，
#     plugins/lusicgal_engines/ios）。
