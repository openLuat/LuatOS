

# CMake 最低版本号要求
cmake_minimum_required (VERSION 3.5)

set(CMAKE_BUILD_TYPE "Debug")
#set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -Og -Wall -g -ggdb")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O2 -Wall")

set(TOPROOT "../..")

# 项目信息
project (luatos)

# 一定一定要先添加本地的头文件
include_directories(./include)

include_directories(${TOPROOT}/lua/include 
                    ${TOPROOT}/luat/include
                    ${TOPROOT}/components/tjpgd
                    ${TOPROOT}/components/qrcode
                    ${TOPROOT}/components/lcd
                    ${TOPROOT}/components/u8g2
                    ${TOPROOT}/components/ui/sdl2
                    )

aux_source_directory(./port PORT_SRCS)
aux_source_directory(${TOPROOT}/lua/src LUA_SRCS)
aux_source_directory(${TOPROOT}/components/lua-cjson CJSON_SRCS)

aux_source_directory(${TOPROOT}/components/tjpgd TJPGD_SRCS)
aux_source_directory(${TOPROOT}/components/qrcode QRCODE_SRCS)
aux_source_directory(${TOPROOT}/components/lcd LCD_SRCS)
aux_source_directory(${TOPROOT}/components/u8g2 U8G2_SRCS)

aux_source_directory(${TOPROOT}/components/ui/sdl2 UI_SDL2_SRCS)

add_library(lua ${LUA_SRCS})
add_library(luatos_port ${PORT_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(luat ${TOPROOT}/luat/modules/luat_main.c 
                 ${TOPROOT}/luat/modules/luat_base.c
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
                 ${TOPROOT}/luat/modules/luat_lib_gpio.c
                 ${TOPROOT}/luat/modules/luat_lib_i2c.c
                 ${TOPROOT}/luat/modules/luat_lib_spi.c
                 ${TOPROOT}/luat/modules/luat_lib_adc.c
                 ${TOPROOT}/luat/modules/luat_lib_pin.c
                 ${TOPROOT}/luat/modules/luat_lib_wdt.c
                 ${TOPROOT}/luat/modules/luat_lib_uart.c
                 ${TOPROOT}/luat/modules/luat_lib_sensor.c
                 ${TOPROOT}/luat/modules/luat_irq.c
                 ${TOPROOT}/components/crypto/luat_crypto_mbedtls.c
                 ${TOPROOT}/luat/modules/crc.c
                 ${TOPROOT}/luat/vfs/luat_vfs.c
                 ${TOPROOT}/luat/vfs/luat_fs_luadb.c
                 ${TOPROOT}/luat/vfs/luat_fs_posix.c
                 ${TOPROOT}/luat/vfs/luat_luadb_inline.c
                 ${TOPROOT}/luat/vfs/luat_inline_sys.c
                 ${TOPROOT}/luat/vfs/luat_fs_onefile.c
                 ${LCD_SRCS}
                 ${U8G2_SRCS}
                 ${TJPGD_SRCS}
                 ${QRCODE_SRCS}
                 ${UI_SDL2_SRCS}
            )

#-----------------------
# mbedtls
include_directories(${TOPROOT}/components/mbedtls/include)
add_subdirectory(${TOPROOT}/components/mbedtls mbedtls.out)
#-----------------------

#-----------------------
# lvgl
include_directories(${TOPROOT}/components/lvgl)
add_subdirectory(${TOPROOT}/components/lvgl lvgl.out)

if( ${CMAKE_SYSTEM_NAME} MATCHES "Emscripten")
    set(USE_FLAGS "-s INITIAL_MEMORY=134217728 -s USE_SDL=2 -sEXPORTED_RUNTIME_METHODS=ccall,cwrap -fsanitize=address -gsource-map --source-map-base http://127.0.0.1:8000/")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${USE_FLAGS}")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${USE_FLAGS}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${USE_FLAGS}")
    #set(CMAKE_EXECUTABLE_SUFFIX .html)
else()
    find_package(SDL2 REQUIRED)
    find_package(Freetype REQUIRED)
endif()

# 指定生成目标
add_executable(luatos src/main_sysp.c)
#add_library(luatos_wasm src/main_sysp.c)
#target_link_libraries(luat luatos_port lua lvgl SDL2 m)
#target_link_libraries(luatos_port luat lua lvgl SDL2 m)
target_link_libraries(luatos luat lua luatos_port cjson lvgl m mbedtls)
#target_link_libraries(luatos_wasm luat lua luatos_port cjson m)
#target_link_libraries(luatos luat lua luatos_port cjson mbedtls lvgl SDL2 m)
#target_link_libraries(luatos_wasm luat lua luatos_port cjson mbedtls lvgl SDL2 m)
