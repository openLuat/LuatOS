
cmake_minimum_required(VERSION 2.8.12)

project("lvgl" C)

include_directories("." "gen/" "binding")

file(GLOB_RECURSE SOURCES src/*.c)
file(GLOB_RECURSE SOURCES_GEN gen/*.c)
file(GLOB_RECURSE SOURCES_BINDING binding/*.c)
add_library(lvgl STATIC ${SOURCES} ${SOURCES_GEN} ${SOURCES_BINDING})
