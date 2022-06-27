

# CMake 最低版本号要求
cmake_minimum_required (VERSION 3.5)

set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O3 -Wall")
set(CMAKE_EXE_LINKER_FLAGS "-Wl,-Map=luatos.map")

set(TOPROOT "../..")

# 项目信息
project (luatos)

# 一定一定要先添加本地的头文件
include_directories(./include)

include_directories(${TOPROOT}/lua/include
                    ${TOPROOT}/luat/include
                    ./lv_drivers
                    )

include_directories(${TOPROOT}/components/lfs)
include_directories(${TOPROOT}/components/qrcode)
# include_directories(${TOPROOT}/components/lcd)

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
aux_source_directory(${TOPROOT}/components/lua-cjson CJSON_SRCS)

aux_source_directory(${TOPROOT}/components/qrcode QRCODE_SRCS)
# aux_source_directory(${TOPROOT}/components/lcd LCD_SRCS)

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
                 ${TOPROOT}/luat/modules/luat_lib_vmx.c
                 ${TOPROOT}/luat/modules/luat_lib_uart.c
                 ${TOPROOT}/components/sfd/luat_lib_sfd.c
                 ${TOPROOT}/components/sfd/luat_sfd_mem.c
                 ${TOPROOT}/components/sfd/luat_sfd_w25q.c
                 ${TOPROOT}/components/luf/luat_lib_luf.c
                 ${TOPROOT}/components/luf/luat_luf_dump.c
                 ${TOPROOT}/components/luf/luat_luf_undump.c
                 ${TOPROOT}/components/luf/luat_luf_cmp.c
                 ${TOPROOT}/components/crypto/luat_crypto_mbedtls.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_fs_lfs2.c
                 ${TOPROOT}/luat/vfs/luat_fs_onefile.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline_sys.c
                 ${TOPROOT}/luat/vfs/luat_inline_sys.c
                 ${TOPROOT}/components/lfs/lfs_sfd.c
                 ${TOPROOT}/components/lfs/lfs_util.c
                 ${TOPROOT}/components/lfs/lfs.c
                 ${TOPROOT}/components/lfs/luat_lib_lfs2.c
                 ${TOPROOT}/luat/vfs/luat_inline_libs.c
                 ./lv_drivers/win_drv.c
                 ${QRCODE_SRCS}
               #   ${LCD_SRCS}
            )

include_directories(${TOPROOT}/components/fatfs)
add_library(fatfs   ${TOPROOT}/components/fatfs/ff.c
                    ${TOPROOT}/components/fatfs/ffsystem.c
                    ${TOPROOT}/components/fatfs/ffunicode.c
                    ${TOPROOT}/components/fatfs/diskio_impl.c
                    ${TOPROOT}/components/fatfs/diskio_ramdisk.c
                    ${TOPROOT}/components/fatfs/diskio_spitf.c
                    ${TOPROOT}/luat/vfs/luat_fs_fatfs.c
                    ${TOPROOT}/components/fatfs/luat_lib_fatfs.c)

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
# lvgl v8
# include_directories(${TOPROOT}/components/lvgl_v8)
# add_subdirectory(${TOPROOT}/components/lvgl_v8 lvgl.out)
#-----------------------



# 指定生成目标
add_executable(luatos src/main_win32.c src/lua.c)
#target_link_libraries(luat winmm luatos_msys fatfs lvgl lua)
target_link_libraries(luatos lua luat luatos_msys lua luat lvgl cjson
                      mbedtls fatfs winmm luat lua luatos_msys
                      )
