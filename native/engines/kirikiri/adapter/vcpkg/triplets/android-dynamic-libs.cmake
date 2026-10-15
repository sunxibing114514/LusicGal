# 镜像 krkr2 的 vcpkg/triplets/android-dynamic-libs.cmake（pin 1abd1ed）。
# 自包含原因：vcpkg 对 triplet 求值时 CMAKE_CURRENT_LIST_DIR 指向本目录，
# krkr2 原版用相对 include —— 若上游改动，此处需同步。
set(DYNAMIC_LIBRARIES sdl2)

if(PORT IN_LIST DYNAMIC_LIBRARIES)
    set(VCPKG_LIBRARY_LINKAGE dynamic)
endif ()
