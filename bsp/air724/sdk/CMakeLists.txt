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

cmake_minimum_required(VERSION 3.13)

set(SOURCE_TOP_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(BINARY_TOP_DIR ${CMAKE_CURRENT_BINARY_DIR})
set(CMAKE_C_COMPILER_FORCED   1)
set(CMAKE_CXX_COMPILER_FORCED 1)

add_definitions(-D_WINSOCKAPI_)

#DEFINED BUILD_TARGET
if(DEFINED ENV{BUILD_TARGET})
	set(BUILD_TARGET $ENV{BUILD_TARGET})
	message("BUILD_TARGET: ${BUILD_TARGET}")
else()
	message(FATAL_ERROR "BUILD_TARGET: UNDEFINED")
endif()

#DEFINED CSDK_PRO
if(DEFINED ENV{CSDK_PRO})
	set(CSDK_PRO $ENV{CSDK_PRO})
	add_definitions(-DCSDK_PRO="${CSDK_PRO}")
	message("CSDK_PRO: ${CSDK_PRO}")
else()
	message(FATAL_ERROR "CSDK_PRO: UNDEFINED")
endif()

#DEFINED CSDK_VER
if(DEFINED ENV{CSDK_VER})
	set(CSDK_VER $ENV{CSDK_VER})
	add_definitions(-DCSDK_VER="${CSDK_VER}")
	message("CSDK_VER: ${CSDK_VER} ")
else()
	message(FATAL_ERROR "CSDK_VER: UNDEFINED")
endif()



#select FOTA_FLAG app or core or all
if(DEFINED ENV{FOTA_FLAG})
	set(FOTA_FLAG $ENV{FOTA_FLAG})
	set(FOTA_TYPE $ENV{FOTA_TYPE})
	
	if (NOT (${FOTA_FLAG} STREQUAL  "fota"))
		message(FATAL_ERROR "FOTA_FLAG: ${FOTA_FLAG} != fota")
	endif()
	
	if (NOT ((${FOTA_TYPE} STREQUAL  "app") OR (${FOTA_TYPE} STREQUAL  "core") OR (${FOTA_TYPE} STREQUAL "all")))
		message(FATAL_ERROR "FOTA_TYPE: ${FOTA_TYPE} != app or core or all")
	endif()
	
	message("${FOTA_FLAG}=${FOTA_TYPE}")
endif()

#select core_type  0=iot_SDK_720U 1:iot_SDK_720U_TTS
if(DEFINED ENV{AM_MODEL})
	set(AM_MODEL $ENV{AM_MODEL})
	if ((${AM_MODEL} STREQUAL  "iot_SDK_720U"))
		message("core/iot_SDK_720U")
		set(core_type 0)
		include(${CMAKE_SOURCE_DIR}/core/${AM_MODEL}/memd/version.cmake)
		set(core_name CSDK_RDA8910)
		set(core_vername CSDK_${CORE_VER}_RDA8910)
		set(core_bin_dir ${CMAKE_SOURCE_DIR}/core/iot_SDK_720U)
		set(core_stub_o ${core_bin_dir}/lib/core_stub.o)
		include(${core_bin_dir}/memd/core_config.cmake)
		include(${core_bin_dir}/memd/partinfo.cmake)
		include_directories(${core_bin_dir}/memd)
		
        
        if(CONFIG_BUILD_LUA)
            set(csdk_target Air720U_CSDK_app_${CSDK_PRO})
        else()
            set(csdk_target Air720U_CSDK_demo_${CSDK_PRO})
        endif(CONFIG_BUILD_LUA)

		set(APP_IMG_NAME "8915DM_cat1_CSDK")
	elseif((${AM_MODEL} STREQUAL  "iot_SDK_720U_TTS"))
		message("core/iot_SDK_720U_TTS")
		set(core_type 1)
		add_definitions(-DTTS_ENABLE)
		include(${CMAKE_SOURCE_DIR}/core/${AM_MODEL}/memd/version.cmake)
		set(core_name CSDK_RDA8910_TTS)
		set(core_vername CSDK_${CORE_VER}_RDA8910_TTS)
		set(core_bin_dir ${CMAKE_SOURCE_DIR}/core/iot_SDK_720U_TTS)
		set(core_stub_o ${core_bin_dir}/lib/core_stub.o)
		include(${core_bin_dir}/memd/core_config.cmake)
		include(${core_bin_dir}/memd/partinfo.cmake)
		include_directories(${core_bin_dir}/memd)
        set(csdk_target Air720U_CSDK_TTS_demo_${CSDK_PRO})
		set(APP_IMG_NAME "8915DM_cat1_CSDK_TTS")

	else()
		message(FATAL_ERROR "AM_MODEL: ${AM_MODEL} != iot_SDK_720U_TTS or iot_SDK_720U")
	endif()
endif()

set(out_hex_dir ${CMAKE_CURRENT_BINARY_DIR}/hex)
set(out_lib_dir ${CMAKE_CURRENT_BINARY_DIR}/lib)
set(out_rel_dir ${CMAKE_CURRENT_BINARY_DIR}/rel)
set(out_inc_dir ${CMAKE_CURRENT_BINARY_DIR}/include)
set(tools_dir ${CMAKE_CURRENT_SOURCE_DIR}/tools)

set(flash_ldscript ${SOURCE_TOP_DIR}/ldscripts/app_flashimg.ld)
set(file_ldscript ${SOURCE_TOP_DIR}/ldscripts/app_fileimg.ld)
set(cmd_mkappimg dtools mkappimg)
set(pacgen_py ${tools_dir}/pacgen.py)
set(gdbComGen_py ${tools_dir}/gdbComGen.py)
#/*+\DEL\chenzhimin\2020.07.8\ */
# set(pacgen_core_py ${tools_dir}/combine_core.py)
#/*-\DEL\chenzhimin\2020.07.8\ */


include(cmake/toolchain-gcc.cmake)

#/*+\NEW\chenzhimin\2020.07.8\ */

include(cmake/extension.cmake)
include(config.cmake)

if( NOT CONFIG_BOOT_FLASH_ADDRESS )
math(EXPR CONFIG_BOOT_FLASH_ADDRESS "${CONFIG_NOR_PHY_ADDRESS}+${CONFIG_BOOT_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR CONFIG_APP_FLASH_ADDRESS "${CONFIG_NOR_PHY_ADDRESS}+${CONFIG_APP_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR CONFIG_FS_MODEM_FLASH_ADDRESS "${CONFIG_NOR_PHY_ADDRESS}+${CONFIG_FS_MODEM_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)


math(EXPR CONFIG_FS_SYS_FLASH_ADDRESS "${CONFIG_NOR_PHY_ADDRESS}+${CONFIG_FS_SYS_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
endif()
set(CONFIG_NVBIN_FIXED_SIZE 0x20000)
#/*-\NEW\chenzhimin\2020.07.8\ */


set(BUILD_SHARED_LIBS OFF)

project(core C CXX ASM)


#/*+\NEW\chenzhimin\2020.07.8\ add elua*/
if(CONFIG_BUILD_LUA)
    include_directories(components/kernel_inc)
    add_definitions(-DAM_LUA_SUPPORT)
    math(EXPR CONFIG_LUA_FLASH_ADDRESS "${CONFIG_NOR_PHY_ADDRESS}+${CONFIG_LUA_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
    math(EXPR CONFIG_APPIMG_FLASH_SIZE "${CONFIG_LUA_FLASH_OFFSET}-${CONFIG_APPIMG_FLASH_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
    add_subdirectory_if_exist(app/elua)
endif(CONFIG_BUILD_LUA)
#/*-\NEW\chenzhimin\2020.07.8\ add elua*/

include_directories(components/include components/openat_inc)

include_directories(components/newlib/include)

function(cpp_only target file)
    add_library(${target} OBJECT ${file})
    set_source_files_properties(${file} PROPERTIES LANGUAGE C)
    target_compile_options(${target} PRIVATE -E -P -x c)
endfunction()

function(add_appimg target ldscript)
    set(gen_ldscript ${target}_ldscript)
    set(target_map_file ${out_hex_dir}/${target}.map)
    set(target_img_file ${out_hex_dir}/${target}.img)
    cpp_only(${gen_ldscript} ${ldscript})
    add_executable(${target} ${ARGN} ${core_stub_o})
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${out_hex_dir})
    target_link_libraries(${target} PRIVATE -T $<TARGET_OBJECTS:${gen_ldscript}>)
    target_link_libraries(${target} PRIVATE -Wl,-Map=${target_map_file} -nostdlib -Wl,--gc-sections)

    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${cmd_mkappimg} $<TARGET_FILE:${target}> ${target_img_file}
        BYPRODUCTS ${target_img_file} ${target_map_file}
    )
endfunction()

#/*+\DEL\chenzhimin\2020.07.8\*/
# configure_file(${SOURCE_TOP_DIR}/components/lib/fdl1.img ${out_hex_dir}/fdl1.img COPYONLY)
# configure_file(${SOURCE_TOP_DIR}/components/lib/fdl2.img ${out_hex_dir}/fdl2.img COPYONLY)
#/*-\DEL\chenzhimin\2020.07.8\*/

#/*+\ADD\chenzhimin\2020.07.8\*/
configure_file(${SOURCE_TOP_DIR}/components/lib/lua.img ${out_hex_dir}/lua.img COPYONLY)
#/*-\ADD\chenzhimin\2020.07.8\*/

#/*+\ADD\chenzhimin\2020.07.8\ add dtools*/
set(dtoolspath ${SOURCE_TOP_DIR}/tools/win32/dtools.exe)
execute_process(
    COMMAND ${dtoolspath} pacdump ${core_bin_dir}/${core_name}.pac ${out_hex_dir}/oldpac
    OUTPUT_STRIP_TRAILING_WHITESPACE
    WORKING_DIRECTORY ${SOURCE_TOP_DIR}
)
#/*-\ADD\chenzhimin\2020.07.8\ add dtools*/

#/*+\DEL\chenzhimin\2020.07.8\*/
# macro(pac_init_fdl cmd pac_config)
#     set(${cmd}
#         cfg-init --pname UIX8910_MODEM --palias "APPIMG"
#             --pversion "8910 MODULE" --version "BP_R1.0.0"
#             --flashtype 1 ${pac_config}
#         cfg-host-fdl -a ${CONFIG_FDL1_IMAGE_START} -s ${CONFIG_FDL1_IMAGE_SIZE}
#             -p ${out_hex_dir}/fdl1.img ${pac_config}
#         cfg-fdl2 -a ${CONFIG_FDL2_IMAGE_START} -s ${CONFIG_FDL2_IMAGE_SIZE}
#             -p ${out_hex_dir}/fdl2.img ${pac_config}
#     )
# endmacro()
#/*-\DEL\chenzhimin\2020.07.8\*/

#/*+\ADD\chenzhimin\2020.07.8\*/
macro(pac_init_fdl cmd pac_config)
    set(${cmd}
        cfg-init --pname UIX8910_MODEM --palias "APPIMG"
            --pversion "8910 MODULE" --version "BP_R1.0.0"
            --flashtype 1 ${pac_config}
        cfg-host-fdl -a ${CONFIG_FDL1_IMAGE_START} -s ${CONFIG_FDL1_IMAGE_SIZE}
            -p ${out_hex_dir}/oldpac/fdl1.sign.img ${pac_config}
        cfg-fdl2 -a ${CONFIG_FDL2_IMAGE_START} -s ${CONFIG_FDL2_IMAGE_SIZE}
            -p ${out_hex_dir}/oldpac/fdl2.sign.img ${pac_config}
    )
endmacro()
#/*-\ADD\chenzhimin\2020.07.8\*/

if(CONFIG_APPIMG_LOAD_FLASH)
    set(target appimg_flash_delete)
    set(pac_config ${out_hex_dir}/${target}.json)
    set(pac_file ${out_hex_dir}/${target}.pac)
    pac_init_fdl(init_fdl ${pac_config})
    execute_process(
        COMMAND python3 ${pacgen_py} ${init_fdl}
            cfg-erase-flash -i ERASE_APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS}
                -s ${CONFIG_APPIMG_FLASH_SIZE} ${pac_config}
            dep-gen --base ${SOURCE_TOP_DIR} ${pac_config}
        OUTPUT_VARIABLE pac_dep
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )

    add_custom_command(OUTPUT ${pac_file}
        COMMAND python3 ${pacgen_py} pac-gen ${pac_config} ${pac_file}
        DEPENDS ${pacgen_py} ${pac_config} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
    add_custom_target(${target}_pacgen ALL DEPENDS ${pac_file})
endif()

if(CONFIG_APPIMG_LOAD_FILE)
    set(target appimg_file_delete)
    set(pac_config ${out_hex_dir}/${target}.json)
    set(pac_file ${out_hex_dir}/${target}.pac)
    pac_init_fdl(init_fdl ${pac_config})
    execute_process(
        COMMAND python3 ${pacgen_py} ${init_fdl}
            cfg-del-appimg -i DEL_APPIMG ${pac_config}
            dep-gen --base ${SOURCE_TOP_DIR} ${pac_config}
        OUTPUT_VARIABLE pac_dep
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )

    add_custom_command(OUTPUT ${pac_file}
        COMMAND python3 ${pacgen_py} pac-gen ${pac_config} ${pac_file}
        DEPENDS ${pacgen_py} ${pac_config} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
    add_custom_target(${target}_pacgen ALL DEPENDS ${pac_file})
endif()

add_subdirectory_if_exist(components/ril)
add_subdirectory_if_exist(api)
add_subdirectory_if_exist(../../../lua, lua)
add_subdirectory_if_exist(../../../luat, luat)
#/*+\ADD\chenzhimin\2020.07.9\*/
if( CONFIG_BUILD_APP_SSL OR 
CONFIG_BUILD_APP_FTP OR
CONFIG_BUILD_APP_HTTP OR
CONFIG_BUILD_APP_LITTLEVGL OR
CONFIG_BUILD_APP_MQTT OR
CONFIG_BUILD_APP_OLED_SSD1306 OR
CONFIG_BUILD_APP_OneWire)
    add_subdirectory_if_exist(app)
endif()
#/*-\ADD\chenzhimin\2020.07.9\*/

set(target ${csdk_target})
set(hex_bin_dir ${CMAKE_SOURCE_DIR}/hex/${target})
set(hex_map_dir ${CMAKE_SOURCE_DIR}/hex/${target}_map)

set(core_map_dir ${core_bin_dir}_map)
set(hex_app_file ${hex_bin_dir}/${target}_APP.pac)
if(CONFIG_APPIMG_LOAD_FILE)
set(pac_delete_file ${out_hex_dir}/appimg_file_delete.pac) 
set(hex_delete_file ${hex_bin_dir}/appimg_file_delete.pac)
elseif(CONFIG_APPIMG_LOAD_FLASH)
set(pac_delete_file ${out_hex_dir}/appimg_flash_delete.pac) 
set(hex_delete_file ${hex_bin_dir}/appimg_flash_delete.pac)
endif()
set(hex_app_with_core_file ${hex_bin_dir}/${target}.pac)
set(hex_map_file ${hex_map_dir}/${core_name}.map)
set(hex_elf_file ${hex_map_dir}/${core_name}.elf)

if(CONFIG_APPIMG_LOAD_FLASH)
    
    if(CONFIG_BUILD_LUA)
        add_subdirectory_if_exist(app/elua/user)
    else()
        add_subdirectory_if_exist(demo/${BUILD_TARGET})
    endif(CONFIG_BUILD_LUA)    
    add_subdirectory_if_exist(app/${BUILD_TARGET})
    target_link_libraries(${target} PRIVATE api)
	target_link_libraries(${target} PRIVATE ../../../lua)
	target_link_libraries(${target} PRIVATE ../../../luat)
    #/*+\ADD\chenzhimin\2020.07.9\*/
    if( CONFIG_BUILD_APP_SSL OR 
    CONFIG_BUILD_APP_FTP OR
    CONFIG_BUILD_APP_HTTP OR
    CONFIG_BUILD_APP_LITTLEVGL OR
    CONFIG_BUILD_APP_MQTT OR
    CONFIG_BUILD_APP_OLED_SSD1306 OR
    CONFIG_BUILD_APP_OneWire)
        target_link_libraries(${target} PRIVATE app)
    endif()
    #/*-\ADD\chenzhimin\2020.07.9\*/

    target_link_libraries(${target} PRIVATE ${libc_file_name} ${libm_file_name} ${libgcc_file_name})
    #/*+\DEL\chenzhimin\2020.07.8\*/
    # set(pac_config ${out_hex_dir}/${target}.json)
    #/*-\DEL\chenzhimin\2020.07.8\*/ 

    #/*+\ADD\chenzhimin\2020.07.8\*/
    set(pac_config ${out_hex_dir}/${target}_APP.json)
    set(pac_all_config ${out_hex_dir}/${target}.json)
    #/*-\ADD\chenzhimin\2020.07.8\*/

    set(pac_file ${out_hex_dir}/${target}_APP.pac)
	set(pac_file_with_core ${out_hex_dir}/${target}.pac)
    pac_init_fdl(init_fdl ${pac_config})
    #/*+\ADD\chenzhimin\2020.07.8\*/
    pac_init_fdl(init_all_fdl ${pac_all_config})
    if(CONFIG_BUILD_LUA)
        set(pac_app_8910
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_config}
                cfg-image -i LUA -a ${CONFIG_LUA_FLASH_ADDRESS} -s ${CONFIG_LUA_FLASH_SIZE}
                    -p ${out_hex_dir}/lua.img ${pac_config}
        )
        set(pac_all_8910
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_all_config}
                cfg-image -i LUA -a ${CONFIG_LUA_FLASH_ADDRESS} -s ${CONFIG_LUA_FLASH_SIZE}
                    -p ${out_hex_dir}/lua.img ${pac_all_config}
        )
    else()
         set(pac_app_8910
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_config}
        )   
        set(pac_all_8910
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_all_config}
        )   
    endif(CONFIG_BUILD_LUA)
    execute_process(
        COMMAND python3 ${pacgen_py}
            ${init_fdl}
            ${pac_app_8910}
            dep-gen --base ${SOURCE_TOP_DIR} ${pac_config}
        OUTPUT_VARIABLE pac_dep
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )       
    #/*-\ADD\chenzhimin\2020.07.8\*/

    #/*+\DEL\chenzhimin\2020.07.8\*/
    # execute_process(
    #     COMMAND python3 ${pacgen_py} ${init_fdl}
    #         cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
    #             -p ${out_hex_dir}/${target}.img ${pac_config}
    #         dep-gen --base ${SOURCE_TOP_DIR} ${pac_config}
    #     OUTPUT_VARIABLE pac_dep
    #     OUTPUT_STRIP_TRAILING_WHITESPACE
    #     WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    # )
    #/*-\DEL\chenzhimin\2020.07.8\*/

    add_custom_command(OUTPUT ${pac_file}
        COMMAND python3 ${pacgen_py} pac-gen ${pac_config} ${pac_file}
        DEPENDS ${pacgen_py} ${pac_config} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
	message(!!!!!!!!!!!!!!!!!!!!!!${pac_file_with_core})
    
    #/*+\DEL\chenzhimin\2020.07.8\*/
	# ##+ zhuwangbin 2020-6-30 add sffs.img
	# if (EXISTS ${out_hex_dir}/sffs.img)
	# 	add_custom_command(OUTPUT ${pac_file_with_core}
	# 		COMMAND python3 ${pacgen_core_py} ${out_hex_dir}/${target}.img ${pac_file_with_core} ${TTS_ENABLE} ${out_hex_dir}/sffs.img
	# 		DEPENDS ${pacgen_core_py} ${pac_dep}
	# 		WORKING_DIRECTORY ${SOURCE_TOP_DIR})
	# else()
	# 	add_custom_command(OUTPUT ${pac_file_with_core}
	# 		COMMAND python3 ${pacgen_core_py} ${out_hex_dir}/${target}.img ${pac_file_with_core} ${TTS_ENABLE} NULL
	# 		DEPENDS ${pacgen_core_py} ${pac_dep}
	# 		WORKING_DIRECTORY ${SOURCE_TOP_DIR})
	# endif()
	# ##- zhuwangbin 2020-6-30 add sffs.img
    #/*-\DEL\chenzhimin\2020.07.8\*/
  
    #/*+\ADD\chenzhimin\2020.07.8\*/
    pac_nvitem_8910(nvitem_all_8910 ${pac_all_config})
    set(pac_other_8910
            cfg-phase-check ${pac_all_config}
            cfg-image -i BOOTLOADER -a ${CONFIG_BOOT_FLASH_ADDRESS} -s ${CONFIG_BOOT_FLASH_SIZE}
                -p ${out_hex_dir}/oldpac/boot.sign.img ${pac_all_config}
            cfg-image -i AP -a ${CONFIG_APP_FLASH_ADDRESS} -s ${CONFIG_APP_FLASH_SIZE}
                -p ${out_hex_dir}/oldpac/${APP_IMG_NAME}.sign.img ${pac_all_config}
            cfg-image -i PS -a ${CONFIG_FS_MODEM_FLASH_ADDRESS} -s ${CONFIG_FS_MODEM_FLASH_SIZE}
                -p ${out_hex_dir}/oldpac/cat1_64X128_UIS8915DM_BB_RF_SingleSim.img ${pac_all_config}
            ${pac_all_8910}
            cfg-image -i SFFS -a ${CONFIG_FS_SYS_FLASH_ADDRESS} -s ${CONFIG_FS_SYS_FLASH_SIZE}
                -p ${out_hex_dir}/oldpac/sffs.img ${pac_all_config}
            cfg-erase-flash -i FLASH -a 0xFE000001 -s 0 ${pac_all_config}
            cfg-nv -s ${CONFIG_NVBIN_FIXED_SIZE} 
                -p ${out_hex_dir}/oldpac/cat1_64X128_UIS8915DM_BB_RF_SingleSim_nvitem.bin ${pac_all_config}
        )
    execute_process(
        COMMAND python3 ${pacgen_py}
            ${init_all_fdl}
            ${nvitem_all_8910}
            ${pac_other_8910}
            dep-gen --base ${SOURCE_TOP_DIR} ${pac_all_config}
        OUTPUT_VARIABLE pac_dep
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
    add_custom_command(OUTPUT ${pac_file_with_core}
        COMMAND python3 ${pacgen_py} pac-gen ${pac_all_config} ${pac_file_with_core}
        DEPENDS ${pacgen_py} ${pac_all_config} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
    #/*-\ADD\chenzhimin\2020.07.8\*/

	add_custom_target(${target}_pacgen ALL DEPENDS ${pac_file} ${pac_file_with_core})
endif()

if(CONFIG_APPIMG_LOAD_FILE)
    
    if(CONFIG_BUILD_LUA)
        add_subdirectory_if_exist(app/elua/user)
    else()
        add_subdirectory_if_exist(demo/${BUILD_TARGET})
    endif(CONFIG_BUILD_LUA)    

    target_link_libraries(${target} PRIVATE ${libc_file_name} ${libm_file_name} ${libgcc_file_name})
    set(pac_config ${out_hex_dir}/${target}.json)
    set(pac_file ${out_hex_dir}/${target}_APP.pac)
	set(pac_file_with_core ${out_hex_dir}/${target}.pac)
	
    pac_init_fdl(init_fdl ${pac_config})
    execute_process(
        COMMAND python3 ${pacgen_py} ${init_fdl}
            cfg-pack-file -i APPIMG -p ${out_hex_dir}/${target}.img
                -n ${CONFIG_APPIMG_LOAD_FILE_NAME} ${pac_config}
            dep-gen --base ${SOURCE_TOP_DIR} ${pac_config}
        OUTPUT_VARIABLE pac_dep
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )

    add_custom_command(OUTPUT ${pac_file}
        COMMAND python3 ${pacgen_py} pac-gen ${pac_config} ${pac_file}
        DEPENDS ${pacgen_py} ${pac_config} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )

	add_custom_command(OUTPUT ${pac_file_with_core}
		COMMAND python3 ${pacgen_core_py} ${out_hex_dir}/${target}.img ${pac_file_with_core} TTS_ENABLE
		DEPENDS ${pacgen_core_py} ${pac_dep}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
	)
    add_custom_target(${target}_pacgen ALL DEPENDS ${pac_file} ${pac_file_with_core})
endif()

add_custom_command(OUTPUT ${hex_app_file} ${hex_app_with_core_file} ${hex_delete_file} ${hex_map_file} ${hex_elf_file}
	COMMAND ${CMAKE_COMMAND} -E make_directory ${hex_bin_dir}
	COMMAND ${CMAKE_COMMAND} -E copy ${pac_file} ${hex_app_file}
	COMMAND ${CMAKE_COMMAND} -E copy ${pac_file_with_core} ${hex_app_with_core_file}
	COMMAND ${CMAKE_COMMAND} -E make_directory ${hex_map_dir}
	COMMAND ${CMAKE_COMMAND} -E copy ${core_map_dir}/${core_name}.map ${hex_map_file}
    COMMAND ${CMAKE_COMMAND} -E copy ${core_map_dir}/${core_name}.elf ${hex_elf_file}
    COMMAND ${CMAKE_COMMAND} -E copy ${out_hex_dir}/${target}.elf ${hex_map_dir}/app.elf
    COMMAND ${CMAKE_COMMAND} -E copy ${out_hex_dir}/${target}.map ${hex_map_dir}/app.map
    COMMAND python3 ${gdbComGen_py} ${CMAKE_SOURCE_DIR} /hex/${target}_map/app.elf
	DEPENDS ${pac_file} ${pac_file_with_core} 
	WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
	
#/*+\NEW\zhuwangbin\2020.07.1\add dofta.bin */
if(DEFINED ENV{FOTA_TYPE})
		set(hex_fota_file ${CSDK_PRO}_${CSDK_VER}_${core_vername}.dfota.bin)
		
		if (${FOTA_TYPE} STREQUAL  "all")
			add_custom_command(OUTPUT ${hex_fota_file}
				COMMAND ${CMAKE_COMMAND} -E copy ${out_hex_dir}/${target}.img ${target}.img
				COMMAND ${CMAKE_COMMAND} -E copy ${core_bin_dir}/${core_name}.pac  ${core_name}.pac
				COMMAND ${CMAKE_COMMAND} -E rename ${target}.img app.bin
				COMMAND ${CMAKE_COMMAND} -E rename ${core_name}.pac ${core_name}.bin
				COMMAND ${CMAKE_COMMAND} -E tar "cfv" "${hex_bin_dir}.zip" "--format=zip" "${core_name}.bin" "app.bin"
				COMMAND ${CMAKE_COMMAND} -E rename ${hex_bin_dir}.zip ${hex_fota_file}
				COMMAND ${CMAKE_COMMAND} -E remove [-f] ${core_name}.bin app.bin
				DEPENDS ${out_hex_dir}/${target}.img ${hex_app_file} ${hex_app_with_core_file}
				WORKING_DIRECTORY ${hex_bin_dir})
				add_custom_target(${target}_release ALL DEPENDS ${hex_app_file} ${hex_app_with_core_file} ${hex_map_file} ${hex_elf_file} ${hex_fota_file})
		endif()
		
		if (${FOTA_TYPE} STREQUAL  "core")
			add_custom_command(OUTPUT ${hex_fota_file}
			COMMAND ${CMAKE_COMMAND} -E copy ${core_bin_dir}/${core_name}.pac  ${core_name}.pac
			COMMAND ${CMAKE_COMMAND} -E rename ${core_name}.pac ${core_name}.bin
			COMMAND ${CMAKE_COMMAND} -E tar "cfv" "${hex_bin_dir}.zip" "--format=zip" "${core_name}.bin" 
			COMMAND ${CMAKE_COMMAND} -E rename ${hex_bin_dir}.zip ${hex_fota_file}
			COMMAND ${CMAKE_COMMAND} -E remove [-f] ${core_name}.bin
			DEPENDS ${out_hex_dir}/${target}.img ${hex_app_file} ${hex_app_with_core_file}
			WORKING_DIRECTORY ${hex_bin_dir})
			add_custom_target(${target}_release ALL DEPENDS ${hex_app_file} ${hex_app_with_core_file} ${hex_map_file} ${hex_elf_file} ${hex_fota_file})

		endif()
		
		if (${FOTA_TYPE} STREQUAL  "app")
			add_custom_command(OUTPUT ${hex_fota_file}
			COMMAND ${CMAKE_COMMAND} -E copy ${out_hex_dir}/${target}.img ${target}.img
			COMMAND ${CMAKE_COMMAND} -E rename ${target}.img app.bin
			COMMAND ${CMAKE_COMMAND} -E tar "cfv" "${hex_bin_dir}.zip" "--format=zip" "app.bin" 
			COMMAND ${CMAKE_COMMAND} -E rename ${hex_bin_dir}.zip ${hex_fota_file}
			COMMAND ${CMAKE_COMMAND} -E remove [-f] app.bin
			DEPENDS ${out_hex_dir}/${target}.img ${hex_app_file} ${hex_app_with_core_file}
			WORKING_DIRECTORY ${hex_bin_dir})
			add_custom_target(${target}_release ALL DEPENDS ${hex_app_file} ${hex_app_with_core_file} ${hex_map_file} ${hex_elf_file} ${hex_fota_file})
		endif()
else()
	add_custom_target(${target}_release ALL DEPENDS ${hex_app_file} ${hex_app_with_core_file} ${hex_map_file} ${hex_elf_file})
endif()
#/*-\NEW\zhuwangbin\2020.07.1\add dofta.bin */

