

# CMake 最低版本号要求
cmake_minimum_required (VERSION 3.5)

set(CMAKE_BUILD_TYPE "Debug")
set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O2 -Wall")

set(TOPROOT "../..")

# 项目信息
project (luatos)

# 一定一定要先添加本地的头文件
include_directories(./include)

include_directories(${TOPROOT}/lua/include 
                    ${TOPROOT}/luat/include 
                    )

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
aux_source_directory(${TOPROOT}/luat/packages/lua-cjson CJSON_SRCS)

add_library(lua ${LUA_SRCS})
add_library(luatos_port ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${TOPROOT}/luat/modules/luat_main.c 
                 ${TOPROOT}/luat/modules/luat_sysp.c
                 ${TOPROOT}/luat/modules/luat_ota.c
                 ${TOPROOT}/luat/modules/luat_luat_bin.c
                 ${TOPROOT}/luat/modules/luat_lib_rtos.c
                 ${TOPROOT}/luat/modules/luat_lib_timer.c
                 ${TOPROOT}/luat/modules/luat_lib_log.c
                 ${TOPROOT}/luat/modules/luat_lib_pack.c
                 ${TOPROOT}/luat/modules/luat_lib_zbuff.c
                 ${TOPROOT}/luat/modules/luat_lib_mqttcore.c
                 ${TOPROOT}/luat/modules/luat_lib_libcoap.c
                 ${TOPROOT}/luat/modules/luat_lib_crypto.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline.c
            )

#-----------------------
# mbedtls
include_directories(${TOPROOT}/components/mbedtls/include)
add_subdirectory(${TOPROOT}/components/mbedtls mbedtls.out)
#-----------------------

# 指定生成目标
add_executable(luatos src/main_sysp.c)
target_link_libraries(luat luatos_port lua)
target_link_libraries(luatos_port luat lua)
target_link_libraries(luatos luat lua luatos_port cjson mbedtls)
