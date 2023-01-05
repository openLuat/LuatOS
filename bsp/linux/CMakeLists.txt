

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
                    )

include_directories(${TOPROOT}/components/lfs)
include_directories(${TOPROOT}/components/qrcode)
include_directories(${TOPROOT}/components/lcd)
include_directories(${TOPROOT}/components/u8g2)
include_directories(${TOPROOT}/components/tjpgd)
include_directories(${TOPROOT}/components/rsa/inc)

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
aux_source_directory(${TOPROOT}/components/lua-cjson CJSON_SRCS)
aux_source_directory(${TOPROOT}/components/rsa/binding RSA_SRCS)

aux_source_directory(${TOPROOT}/components/qrcode QRCODE_SRCS)
aux_source_directory(${TOPROOT}/components/lcd LCD_SRCS)
aux_source_directory(${TOPROOT}/components/u8g2 U8G2_SRCS)
aux_source_directory(${TOPROOT}/components/tjpgd TJPGD_SRCS)

#add_library(lua )
#add_library(luatos_msys ${PORT_SRCS})
#add_library(cjson )
add_library(luat ${PORT_SRCS} ${LUA_SRCS} ${CJSON_SRCS} ${TOPROOT}/luat/modules/luat_main.c
                 ${TOPROOT}/luat/modules/luat_base.c
                 ${TOPROOT}/luat/modules/luat_ota.c
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
                 ${TOPROOT}/components/sfd/luat_sfd_onchip.c
                 ${TOPROOT}/components/sfd/luat_sfd.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_fs_lfs2.c
                 ${TOPROOT}/luat/vfs/luat_fs_inline.c
                 ${TOPROOT}/luat/vfs/luat_fs_romfs.c
                 ${TOPROOT}/luat/vfs/luat_inline_libs_64bit_size32.c
                 ${TOPROOT}/luat/vfs/luat_inline_libs_64bit_size64.c
                 ${TOPROOT}/luat/vfs/luat_luadb_mock.c
                 ${TOPROOT}/components/lfs/lfs_sfd.c
                 ${TOPROOT}/components/lfs/lfs_util.c
                 ${TOPROOT}/components/lfs/lfs.c
                 ${TOPROOT}/components/lfs/luat_lib_lfs2.c
                 ${TOPROOT}/components/crypto/luat_crypto_mbedtls.c
                 ${QRCODE_SRCS}
                 ${LCD_SRCS}
                 ${U8G2_SRCS}
                 ${TJPGD_SRCS}
                 ${RSA_SRCS}
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



add_executable(luatos src/main.c src/lua.c)

#target_link_libraries(luat pthread lua)
target_link_libraries(luatos luat pthread mbedtls m dl readline)
