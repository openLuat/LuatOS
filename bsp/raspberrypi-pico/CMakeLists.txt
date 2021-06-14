cmake_minimum_required(VERSION 3.12)

# initialize the SDK based on PICO_SDK_PATH
# note: this must happen before project()
include(pico_sdk_import.cmake)
include(${PICO_SDK_PATH}/pico_sdk_init.cmake)
project(pico-luatos)

# initialize the Pico SDK
pico_sdk_init()

set(LUATOS_ROOT ../../)
set(FreeRTOS ../../components/freertos)

add_library(FreeRTOS STATIC ${FreeRTOS}/croutine.c
${FreeRTOS}/event_groups.c
${FreeRTOS}/list.c
${FreeRTOS}/queue.c
${FreeRTOS}/stream_buffer.c
${FreeRTOS}/tasks.c
${FreeRTOS}/timers.c 
${FreeRTOS}/portable/GCC/ARM_CM0/port.c 
${FreeRTOS}/heap_4.c 
src/FreeRTOS_Support_Files/IdleMemory.c)
target_include_directories(FreeRTOS PUBLIC include/ ${FreeRTOS}/portable/GCC/ARM_CM0)

include_directories(port)
include_directories(${LUATOS_ROOT}/luat/include)
include_directories(${LUATOS_ROOT}/lua/include)
include_directories(${LUATOS_ROOT}/luat/packages/lfs)

aux_source_directory(src DIR_SRCS)
aux_source_directory(port PORT_SRCS)
aux_source_directory(${LUATOS_ROOT}/lua/src LUA_SRCS)
aux_source_directory(${LUATOS_ROOT}/luat/packages/lua-cjson CJSON_SRCS)
aux_source_directory(${LUATOS_ROOT}/luat/packages/lfs LFS_SRCS)
aux_source_directory(${LUATOS_ROOT}/luat/modules MODULES_SRCS)

add_library(port ${PORT_SRCS})
add_library(lua ${LUA_SRCS})
add_library(cjson ${CJSON_SRCS})
add_library(lfs ${LFS_SRCS})
add_library(luat ${MODULES_SRCS}
                ${LUATOS_ROOT}/luat/packages/lfs/lfs_sfd.c
                ${LUATOS_ROOT}/luat/packages/lfs/lfs_util.c
                ${LUATOS_ROOT}/luat/packages/lfs/lfs.c
                ${LUATOS_ROOT}/luat/packages/lfs/luat_lib_lfs2.c
                )

add_executable(pico-luatos ${DIR_SRCS})

# Add pico_stdlib library which aggregates commonly used features
target_link_libraries(pico-luatos pico_stdlib)

# create map/bin/hex/uf2 file in addition to ELF.
pico_add_extra_outputs(pico-luatos)

target_link_libraries(port pico_stdlib hardware_pio hardware_flash FreeRTOS lfs lua luat)

target_link_libraries(luat lua port cjson FreeRTOS)

target_link_libraries(pico-luatos FreeRTOS luat)
add_custom_command(TARGET pico-luatos
        POST_BUILD
        COMMAND arm-none-eabi-size pico-luatos.elf
        )
# rest of your project
