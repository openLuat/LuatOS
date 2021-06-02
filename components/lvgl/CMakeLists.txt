
cmake_minimum_required(VERSION 2.8.12)

project("lvgl" C)

file(GLOB_RECURSE SOURCES src/*.c)
file(GLOB_RECURSE SOURCES2 gen/*.c)
add_library(lvgl STATIC ${SOURCES} ${SOURCES2})
