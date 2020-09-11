# Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
# All rights reserved.
#
# This software is supplied "AS IS" without any warranties.
# RDA assumes no responsibility or liability for the use of the software,
# conveys no license or title under any patent, copyright, or mask work
# right to the product. RDA reserves the right to make changes in the
# software without notification.  RDA also make no representation or
# warranty that such application will be suitable for the specified use
# without further testing or modification.



#configure_file(include/fota_config.h.in ${BINARY_TOP_DIR}/include/fota_config.h)


set(target api)
add_library(${target} STATIC)
set_target_properties(${target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY ${out_hex_dir})
target_link_libraries(${target} PRIVATE ${libc_file_name} ${libm_file_name} ${libgcc_file_name})
#target_link_libraries(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../components/lib/libopenat.a)


#设置包含头文�?
target_include_directories(${target} PUBLIC include)
target_include_directories(${target} PRIVATE ../components/include)
target_include_directories(${target} PRIVATE ../components/newlib/include)
target_include_directories(${target} PRIVATE ../components/openat_inc)
target_include_directories(${target} PRIVATE ../components/ril/inc)

target_link_libraries(${target} PRIVATE ril)

target_sources(${target} PRIVATE
    src/iot_os.c
	src/iot_debug.c
	src/iot_gpio.c
	src/iot_fs.c
	src/iot_uart.c
	src/iot_flash.c
	src/iot_adc.c
	src/iot_i2c.c
	src/iot_pmd.c
	src/iot_keypad.c
	src/iot_network.c
	src/iot_spi.c
	src/iot_sys.c
	src/iot_vat.c
	src/iot_socket.c
	src/iot_lcd.c
	src/iot_zbar.c
	src/iot_camera.c
	src/iot_tts.c
	src/iot_audio.c
)


