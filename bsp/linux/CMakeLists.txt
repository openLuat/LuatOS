

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
# 
# include_directories(
# /usr/include/gtk-3.0 
# /usr/include/at-spi2-atk/2.0 
# /usr/include/at-spi-2.0 
# /usr/include/dbus-1.0 
# /usr/lib/arm-linux-gnueabihf/dbus-1.0/include 
# /usr/include/gtk-3.0 
# /usr/include/gio-unix-2.0 
# /usr/include/cairo 
# /usr/include/pango-1.0 
# /usr/include/harfbuzz 
# /usr/include/pango-1.0 
# /usr/include/fribidi 
# /usr/include/atk-1.0 
# /usr/include/cairo 
# /usr/include/pixman-1 
# /usr/include/freetype2 
# /usr/include/libpng16 
# /usr/include/gdk-pixbuf-2.0 
# /usr/include/libmount 
# /usr/include/blkid 
# /usr/include/uuid 
# /usr/include/glib-2.0 
# /usr/lib/arm-linux-gnueabihf/glib-2.0/include
# )

include_directories(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix)
include_directories(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix/utils)
aux_source_directory(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix MM_SRCS)
aux_source_directory(${TOPROOT}/components/freertos/portable/ThirdParty/GCC/Posix/utils MM2_SRCS)

include_directories(${TOPROOT}/luat/packages/lfs)
include_directories(${TOPROOT}/components/qrcode)
include_directories(${TOPROOT}/components/lcd)
include_directories(${TOPROOT}/luat/packages/u8g2)

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
#aux_source_directory(${TOPROOT}/luat/freertos FTOS_T_SRCS)
aux_source_directory(${TOPROOT}/components/freertos RTOS_SRCS)
aux_source_directory(${TOPROOT}/components/freertos/port RTOS_PORT_SRCS)
aux_source_directory(${TOPROOT}/luat/packages/lua-cjson CJSON_SRCS)

aux_source_directory(${TOPROOT}/components/qrcode QRCODE_SRCS)
aux_source_directory(${TOPROOT}/components/lcd LCD_SRCS)
aux_source_directory(${TOPROOT}/components/u8g2 U8G2_SRCS)

add_library(freertos10 ${PORT_SRCS} ${RTOS_SRCS} ${RTOS_PORT_SRCS} ${MM_SRCS} ${MM2_SRCS})
add_library(lua ${LUA_SRCS})
add_library(luatos_msys ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${TOPROOT}/luat/modules/luat_main.c
                 ${TOPROOT}/luat/modules/luat_base.c
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
                 ${TOPROOT}/components/sfd/luat_lib_sfd.c
                 ${TOPROOT}/components/sfd/luat_sfd_mem.c
                 ${TOPROOT}/components/sfd/luat_sfd_w25q.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_fs_lfs2.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline_sys.c
                 ${TOPROOT}/luat/vfs/luat_inline_sys.c
                 ${TOPROOT}/luat/packages/lfs/lfs_sfd.c
                 ${TOPROOT}/luat/packages/lfs/lfs_util.c
                 ${TOPROOT}/luat/packages/lfs/lfs.c
                 ${TOPROOT}/luat/packages/lfs/luat_lib_lfs2.c
                 ${QRCODE_SRCS}
                 ${LCD_SRCS}
                 ${U8G2_SRCS}
            )

#-----------------------
# mbedtls
include_directories(${TOPROOT}/components/mbedtls/include)
add_subdirectory(${TOPROOT}/components/mbedtls mbedtls.out)
#-----------------------

#-----------------------
# lvgl
# include_directories(${TOPROOT}/components/lvgl)
# add_subdirectory(${TOPROOT}/components/lvgl lvgl.out)
#-----------------------

#-----------------------
# luat_rtos
include_directories(${TOPROOT}/components/rtos/posix/include)
aux_source_directory(${TOPROOT}/components/rtos/posix RTOS_POSIX_SRCS)
add_library(luat_rtos ${RTOS_POSIX_SRCS})
#-----------------------

#-----------------------
# luat_network_libtcpip
include_directories(${TOPROOT}/components/network/libtcpip/)
include_directories(${TOPROOT}/components/network/libtcpip/protocol/mqtt)
aux_source_directory(${TOPROOT}/components/network/libtcpip/port LIBTCPIP_SRCS)
aux_source_directory(${TOPROOT}/components/network/libtcpip/protocol/mqtt LIBTCPIP_SRCS2)
add_library(luat_network_libtcpip ${LIBTCPIP_SRCS} ${LIBTCPIP_SRCS2})
#-----------------------


add_executable(luatos src/main.c src/lua.c)

target_link_libraries(luat freertos10 pthread luat_rtos luat_network_libtcpip lua)
target_link_libraries(luatos freertos10 lua luatos_msys luat pthread cjson mbedtls m dl readline luat_rtos luat_network_libtcpip)
