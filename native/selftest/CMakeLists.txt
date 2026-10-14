cmake_minimum_required(VERSION 3.16)
project(lusicgal_selftest C)

# 宿主自检（engines.yml: c-abi-host，必须绿）：
# 验证 ABI 头 + 选项工具 + 全核心弱 stub 可编译链接运行。
add_executable(lusicgal_selftest
  main.c
  ../stubs/lusicgal_stubs.c
  ../bridge/host/lusicgal_options.c
)
target_include_directories(lusicgal_selftest PRIVATE ../include)
