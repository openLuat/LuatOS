

# CMake 最低版本号要求
cmake_minimum_required (VERSION 3.5)

set(CMAKE_BUILD_TYPE "Debug")
set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O2 -Wall")
set(CMAKE_EXE_LINKER_FLAGS "-Wl,-Map=luatos.map")

set(TOPROOT "../..")

# 项目信息
project (luatos)

# 一定一定要先添加本地的头文件
include_directories(./include)

include_directories(${TOPROOT}/lua/include
                    ${TOPROOT}/luat/include
                    ${TOPROOT}/components/freertos/include
                    )
IF (WIN32)
     include_directories(${TOPROOT}/components/freertos/portable/MSVC-MingW)
     aux_source_directory(${TOPROOT}/components/freertos/portable/MSVC-MingW MM_SRCS)
ELSE ()
     include_directories(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix)
     include_directories(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix/utils)
     aux_source_directory(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix MM_SRCS)
     aux_source_directory(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix/utils
                          MM2_SRCS)
ENDIF ()

include_directories(${TOPROOT}/luat/packages/lfs)
include_directories(${TOPROOT}/components/lcd)

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
#aux_source_directory(${TOPROOT}/luat/freertos FTOS_T_SRCS)
aux_source_directory(${TOPROOT}/components/freertos RTOS_SRCS)
aux_source_directory(${TOPROOT}/components/freertos/port RTOS_PORT_SRCS)
aux_source_directory(${TOPROOT}/luat/packages/lua-cjson CJSON_SRCS)

aux_source_directory(${TOPROOT}/components/lcd LCD_SRCS)

add_library(freertos10 ${PORT_SRCS} ${RTOS_SRCS} ${RTOS_PORT_SRCS} ${MM_SRCS} ${MM2_SRCS})
add_library(lua ${LUA_SRCS})
add_library(luatos_msys ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${TOPROOT}/luat/modules/luat_main.c
                 ${TOPROOT}/luat/modules/luat_ota.c
                 ${TOPROOT}/luat/modules/luat_luat_bin.c
                 ${TOPROOT}/luat/modules/luat_lib_rtos.c
                 ${TOPROOT}/luat/modules/luat_lib_timer.c
                 ${TOPROOT}/luat/modules/luat_lib_log.c
                 ${TOPROOT}/luat/modules/luat_lib_gpio.c
                 ${TOPROOT}/luat/modules/luat_lib_spi.c
                 ${TOPROOT}/luat/modules/luat_lib_pack.c
                 ${TOPROOT}/luat/modules/luat_lib_zbuff.c
                 ${TOPROOT}/luat/modules/luat_lib_mqttcore.c
                 ${TOPROOT}/luat/modules/luat_lib_libcoap.c
                 ${TOPROOT}/luat/modules/luat_lib_crypto.c
                 ${TOPROOT}/luat/modules/luat_lib_sfd.c
                 ${TOPROOT}/luat/modules/luat_sfd.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_fs_lfs2.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline.c
                 ${TOPROOT}/luat/packages/lfs/lfs_sfd.c
                 ${TOPROOT}/luat/packages/lfs/lfs_util.c
                 ${TOPROOT}/luat/packages/lfs/lfs.c
                 ${TOPROOT}/luat/packages/lfs/luat_lib_lfs2.c
                 ${LCD_SRCS}
            )

IF (WIN32)
#-----------------------
# LuaFileSystem --> lfs
aux_source_directory(./rock/LuaFileSystem ROCK_LFS_SRCS)
add_library(rock_lfs ${ROCK_LFS_SRCS})
#-----------------------

#------------------------
# librs232 -> rs232
include_directories(./rock/librs232/include)
aux_source_directory(./rock/librs232/src ROCK_LIB_RS232_SRCS)
add_library(rock_librs232 ${ROCK_LIB_RS232_SRCS} ./rock/librs232/bindings/lua/luars232.c)
#------------------------

ENDIF ()

include_directories(${TOPROOT}/luat/packages/fatfs)
add_library(fatfs   ${TOPROOT}/luat/packages/fatfs/ff.c
                    ${TOPROOT}/luat/packages/fatfs/ffsystem.c
                    ${TOPROOT}/luat/packages/fatfs/ffunicode.c
                    ${TOPROOT}/luat/packages/fatfs/diskio_impl.c
                    ${TOPROOT}/luat/packages/fatfs/diskio_ramdisk.c
                    ${TOPROOT}/luat/packages/fatfs/diskio_spitf.c
                    ${TOPROOT}/luat/vfs/luat_fs_fatfs.c
                    ${TOPROOT}/luat/packages/fatfs/luat_lib_fatfs.c)

#-----------------------
# mbedtls
include_directories(${TOPROOT}/components/mbedtls/include)
add_subdirectory(${TOPROOT}/components/mbedtls mbedtls.out)
#-----------------------

#-----------------------
# lvgl
include_directories(${TOPROOT}/components/lvgl)
add_subdirectory(${TOPROOT}/components/lvgl lvgl.out)
#-----------------------

#-----------------------
# lwip
include_directories(${TOPROOT}/components/network/lwip)
add_subdirectory(${TOPROOT}/components/network/lwip lwip.out)
#-----------------------

IF (WIN32)
# 指定生成目标
add_executable(luatos src/main_win32.c)
target_link_libraries(luat freertos10 winmm fatfs lvgl lwip)
target_link_libraries(luatos freertos10 lua luatos_msys luat winmm cjson
                      rock_lfs rock_librs232 mbedtls fatfs lvgl lwip
                      lwipcontribexamples lwipcontribapps lwipcontribaddons 
                      lwipallapps lwipcore lwipcontribportwindows lwipmbedtls)
ELSE ()
add_executable(luatos src/main_posix.c)
target_link_libraries(luat freertos10 pthread fatfs lvgl)
target_link_libraries(luatos freertos10 lua luatos_msys fatfs luat pthread cjson mbedtls lvgl m)
ENDIF ()
