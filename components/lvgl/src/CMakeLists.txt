
cmake_minimum_required(VERSION 2.8.12)

project("lvgl_src" C)

add_subdirectory(lv_core)
add_subdirectory(lv_draw)
add_subdirectory(lv_font)
add_subdirectory(lv_gpu)
add_subdirectory(lv_hal)
add_subdirectory(lv_misc)
add_subdirectory(lv_themes)
add_subdirectory(lv_widgets)
