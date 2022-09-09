
cmake_minimum_required(VERSION 2.8.12)

project("lvgl" C)

include_directories("." "gen/" "binding/" "font/" "sdl2")

file(GLOB_RECURSE SOURCES src/*.c)
file(GLOB_RECURSE SOURCES_GEN gen/*.c)
file(GLOB_RECURSE SOURCES_BINDING binding/*.c)
file(GLOB_RECURSE SOURCES_FONT font/*.c)
file(GLOB_RECURSE SOURCES_EXTS exts/*.c)
file(GLOB_RECURSE SOURCES_SDL2 sdl2/*.c)
add_library(lvgl STATIC ${SOURCES} ${SOURCES_GEN} ${SOURCES_BINDING} ${SOURCES_FONT} ${SOURCES_EXTS} ${SOURCES_SDL2})
