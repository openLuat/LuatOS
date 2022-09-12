

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
                    ${TOPROOT}/components/peripheral/onchip/inc
                    ${TOPROOT}/components/network/ota
                    ./lv_drivers
                    ${TOPROOT}/components/fs/lfs 
                    ${TOPROOT}/components/crypto/inc 
                    ${TOPROOT}/components/ui/qrcode
                    ${TOPROOT}/components/ui/lcd
                    ${TOPROOT}/components/ui/luatfonts
                    ${TOPROOT}/components/ui/lvgl/src/lv_font
                    ${TOPROOT}/components/serialization/miniz
                    ${TOPROOT}/components/mempool/tlsf
                    ${TOPROOT}/components/serialization/protobuf
                    ${TOPROOT}/components/tools/zbuff
                    ${TOPROOT}/components/fs/luadb
                    ${TOPROOT}/components/tools/pack
                    )

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
aux_source_directory(${TOPROOT}/luat/modules LUAT_SRCS)
aux_source_directory(${TOPROOT}/components/serialization/lua-cjson CJSON_SRCS)
aux_source_directory(${TOPROOT}/components/serialization/miniz MINIZ_SRCS)
aux_source_directory(${TOPROOT}/components/ui/qrcode QRCODE_SRCS)
# aux_source_directory(${TOPROOT}/components/ui/lcd LCD_SRCS)
aux_source_directory(./components/tools/iotauth IOTAUTH_SRCS)
aux_source_directory(./components/mempool/tlsf TLSF_SRCS)
aux_source_directory(${TOPROOT}/components/serialization/protobuf PB_SRCS)
aux_source_directory(${TOPROOT}/components/fs/vfs VFS_SRCS)
aux_source_directory(${TOPROOT}/components/fs/lfs LFS_SRCS)
aux_source_directory(${TOPROOT}/components/crypto/src CRYPTO_SRCS)
aux_source_directory(${TOPROOT}/components/tools/zbuff ZBUFF_SRCS)
aux_source_directory(${TOPROOT}/components/tools/libcoap LIBCOAP_SRCS)
aux_source_directory(${TOPROOT}/components/tools/mqttcore MQTTCORE_SRCS)

aux_source_directory(${TOPROOT}/components/peripheral/onchip/src ONCHIP_SRC)
aux_source_directory(${TOPROOT}/components/tools/pack PACK_SRC)
aux_source_directory(${TOPROOT}/components/peripheral/sfd SFD_SRC)
aux_source_directory(${TOPROOT}/components/mempool/bget BGET_SRC)

add_library(lua ${LUA_SRCS})
add_library(luatos_msys ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${LUAT_SRCS}
                 ${ONCHIP_SRC}
                 ${CRYPTO_SRCS}
                 ${ZBUFF_SRCS}
                 ${LIBCOAP_SRCS}
                 ${MQTTCORE_SRCS}
                 ${TOPROOT}/components/crypto/src/luat_crypto_mbedtls.c
                 ${VFS_SRCS}
                 ${LFS_SRCS}
                 ${TOPROOT}/components/tools/iotauth/luat_lib_iotauth.c
                 ./lv_drivers/win_drv.c
                 ${QRCODE_SRCS}
                 ${MINIZ_SRCS}
                 #${LCD_SRCS}
                 ${PB_SRCS}
                 ${PACK_SRC}
                 ${SFD_SRC}
                 ${BGET_SRC}
            )

include_directories(${TOPROOT}/components/fs/fatfs)
add_library(fatfs   ${TOPROOT}/components/fs/fatfs/ff.c
                    ${TOPROOT}/components/fs/fatfs/ffsystem.c
                    ${TOPROOT}/components/fs/fatfs/ffunicode.c
                    ${TOPROOT}/components/fs/fatfs/diskio_impl.c
                    ${TOPROOT}/components/fs/fatfs/diskio_ramdisk.c
                    ${TOPROOT}/components/fs/fatfs/diskio_spitf.c
                    ${TOPROOT}/components/fs/fatfs/luat_lib_fatfs.c
                    )

#-----------------------
# mbedtls
include_directories(${TOPROOT}/components/mbedtls/include)
add_subdirectory(${TOPROOT}/components/mbedtls mbedtls.out)
#-----------------------

#-----------------------
# lvgl
include_directories(${TOPROOT}/components/ui/lvgl)
add_subdirectory(${TOPROOT}/components/ui/lvgl lvgl.out)


# 指定生成目标
add_executable(luatos src/main_win32.c src/lua.c)
target_link_libraries(luat gdi32 lvgl winmm luatos_msys fatfs  lua)
target_link_libraries(luatos gdi32 winmm lua luat luatos_msys lua luat  cjson lvgl
                      mbedtls fatfs winmm luat lua luatos_msys
                      )
