

# CMake 最低版本号要求
cmake_minimum_required (VERSION 3.12)

set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O2 -Wall")

set(TOPROOT "../..")

# 项目信息
project (luatos)

include_directories(${TOPROOT}/lua/include ${TOPROOT}/luat/include ./freertos/include ./freertos/portable/MSVC-MingW)

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
#aux_source_directory(${TOPROOT}/luat/freertos FTOS_T_SRCS)
aux_source_directory(./freertos RTOS_SRCS)
aux_source_directory(./freertos/port RTOS_PORT_SRCS)
aux_source_directory(./freertos/portable/MSVC-MingW MM_SRCS)
aux_source_directory(${TOPROOT}/luat/packages/lua-cjson CJSON_SRCS)

add_library(freertos10 ${PORT_SRCS} ${RTOS_SRCS} ${RTOS_PORT_SRCS} ${MM_SRCS})
add_library(lua ${LUA_SRCS})
add_library(luatos_msys ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${TOPROOT}/luat/modules/luat_main.c 
                 ${TOPROOT}/luat/modules/luat_luat_bin.c
                 ${TOPROOT}/luat/modules/luat_lib_rtos.c
                 ${TOPROOT}/luat/modules/luat_lib_timer.c
                 ${TOPROOT}/luat/modules/luat_lib_log.c
                 ${TOPROOT}/luat/modules/luat_lib_pack.c
                 ${TOPROOT}/luat/modules/luat_lib_zbuff.c
                 ${TOPROOT}/luat/modules/luat_lib_mqttcore.c
                 ${TOPROOT}/luat/modules/luat_lib_libcoap.c
            )

#-----------------------
aux_source_directory(./rock/LuaFileSystem ROCK_LFS_SRCS)
add_library(rock_lfs ${ROCK_LFS_SRCS})
#-----------------------

# 指定生成目标
add_executable(luatos src/main_win32.c)
target_link_libraries(luat freertos10 winmm)
target_link_libraries(luatos freertos10 lua luatos_msys luat winmm cjson rock_lfs)
