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

function(print arg)
    message(STATUS "${arg}: ${${arg}}")
endfunction()

function(target_include_targets target type)
    foreach(arg ${ARGN})
        target_include_directories(${target} ${type}
            $<TARGET_PROPERTY:${arg},INTERFACE_INCLUDE_DIRECTORIES>)
    endforeach()
endfunction()

function(include_targets)
    foreach(arg ${ARGN})
        include_directories($<TARGET_PROPERTY:${arg},INTERFACE_INCLUDE_DIRECTORIES>)
    endforeach()
endfunction()

macro(target_add_revision target)
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/${target}_revision.c "const char *${target}_build_revision = \"${BUILD_TARGET}-${BUILD_RELEASE_TYPE}-${BUILD_AUTO_REVISION}\";")
    target_sources(${target} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/${target}_revision.c)
endmacro()

# Link targets with --whole-archive. PUBLIC/PRIVATE is required as parameter,
# but PRIVATE will be used forcedly.
function(target_link_whole_archive target signature)
    target_link_libraries(${target} PRIVATE -Wl,--whole-archive)
    foreach(arg ${ARGN})
        target_link_libraries(${target} PRIVATE ${arg})
    endforeach()
    target_link_libraries(${target} PRIVATE -Wl,--no-whole-archive)
endfunction()

# Link targets with --start-group. PUBLIC/PRIVATE is required as parameter,
# but PRIVATE will be used forcedly.
function(target_link_group target signature)
    target_link_libraries(${target} PRIVATE -Wl,--start-group)
    foreach(arg ${ARGN})
        target_link_libraries(${target} PRIVATE ${arg})
    endforeach()
    target_link_libraries(${target} PRIVATE -Wl,--end-group)
endfunction()

function(add_subdirectory_if_exist dir)
    if(IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${dir})
        if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${dir}/CMakeLists.txt)
            add_subdirectory(${dir})
        endif()
    endif()
endfunction()

function(cpp_only target file)
    add_library(${target} OBJECT ${file})
    set_source_files_properties(${file} PROPERTIES LANGUAGE C)
    target_compile_options(${target} PRIVATE -E -P -x c)
    foreach(dep ${ARGN})
        target_include_directories(${target}
            PRIVATE $<TARGET_PROPERTY:${dep},INTERFACE_INCLUDE_DIRECTORIES>)
    endforeach()
    foreach(dep ${ARGN})
        target_compile_definitions(${target}
            PRIVATE $<TARGET_PROPERTY:${dep},INTERFACE_COMPILE_DEFINITIONS>)
    endforeach()
endfunction()

function(target_incbin target binfile sym)
    get_filename_component(binpath ${binfile} ABSOLUTE)
    get_filename_component(binfilename ${binfile} NAME)
    set(asmfile ${CMAKE_CURRENT_BINARY_DIR}/${binfilename}.S)
    file(WRITE ${asmfile}
        ".text\n\
        .align 2\n\
        .global ${sym}\n\
        ${sym}:\n\
        .incbin \"${binpath}\"\n"
    )
    target_sources(${target} PRIVATE ${asmfile})
    set_source_files_properties(${asmfile} PROPERTIES OBJECT_DEPENDS ${binfile})
endfunction()

function(target_incbin_size target binfile sym symsize)
    get_filename_component(binpath ${binfile} ABSOLUTE)
    get_filename_component(binfilename ${binfile} NAME)
    set(asmfile ${CMAKE_CURRENT_BINARY_DIR}/${binfilename}.S)
    file(WRITE ${asmfile}
        ".text\n\
        .align 2\n\
        .global ${sym}\n\
        ${sym}:\n\
        .incbin \"${binpath}\"\n\
        .global ${symsize}\n\
        ${symsize}:\n\
        .word .-${sym}\n"
    )
    target_sources(${target} PRIVATE ${asmfile})
    set_source_files_properties(${asmfile} PROPERTIES OBJECT_DEPENDS ${binfile})
endfunction()

function(add_uimage target ldscript)
    set(gen_ldscript ${target}_ldscript)
    set(target_map_file ${out_hex_dir}/${target}.map)
    set(target_img_file ${out_hex_dir}/${target}.img)
    cpp_only(${gen_ldscript} ${ldscript} hal)
    add_executable(${target} ${ARGN})
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${out_hex_dir})
    target_link_libraries(${target} PRIVATE -T $<TARGET_OBJECTS:${gen_ldscript}>)
    target_link_libraries(${target} PRIVATE -Wl,-Map=${target_map_file} -nostdlib -Wl,--gc-sections ${link_cref_option})

    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${cmd_mkuimage} --name "${BUILD_REVISION}-${BUILD_AUTO_REVISION}"
            $<TARGET_FILE:${target}> ${target_img_file}
        BYPRODUCTS ${target_img_file} ${target_map_file}
    )
endfunction()

macro(pac_init_fdl cmd pac_config)
    if(CONFIG_SOC_8910)
        set(${cmd}
            cfg-init --pname "UIX8910_MODEM" --palias ${BUILD_TARGET}
                --pversion "8910 MODULE" --version "BP_R1.0.0"
                --flashtype 1 ${pac_config}
            cfg-host-fdl -a ${CONFIG_FDL1_IMAGE_START} -s ${CONFIG_FDL1_IMAGE_SIZE}
                -p ${out_hex_dir}/fdl1.sign.img ${pac_config}
            cfg-fdl2 -a ${CONFIG_FDL2_IMAGE_START} -s ${CONFIG_FDL2_IMAGE_SIZE}
                -p ${out_hex_dir}/fdl2.sign.img ${pac_config}
        )
    endif()
    if(CONFIG_SOC_8811)
        set(${cmd}
            cfg-init --pname "8811_MODEM" --palias ${BUILD_TARGET}
                --pversion "8811 MODULE" --version "BP_R1.0.0"
                --flashtype 0 ${pac_config}
            cfg-fdl -a ${CONFIG_NORFDL_IMAGE_START} -s ${CONFIG_NORFDL_IMAGE_SIZE}
                -p ${out_hex_dir}/norfdl.img ${pac_config}
        )
    endif()
endmacro()

macro(pac_nvitem_8910 cmd pac_config)
    set(${cmd}
        cfg-nvitem -n "Calibration" -i 0xFFFFFFFF --use 1 --replace 0 --continue 0 --backup 1 ${pac_config}
        cfg-nvitem -n "GSM Calibration" -i 0x26d --use 1 --replace 0 --continue 1 --backup 1 ${pac_config}
        cfg-nvitem -n "LTE Calibration" -i 0x26e --use 1 --replace 0 --continue 0 --backup 1 ${pac_config}
        cfg-nvitem -n "IMEI" -i 0xFFFFFFFF --use 1 --replace 0 --continue 0 --backup 1 ${pac_config}
    )
endmacro()

# Build unittest target. Parameters are source files.
# When PAC is supported, PAC is create with unittest only.
function(add_unittest target)
    if((CONFIG_SOC_8910) OR (CONFIG_SOC_6760))
        add_uimage(${target} ${unittest_ldscript} EXCLUDE_FROM_ALL ${ARGN})
        add_dependencies(unittests ${target})

        if((CONFIG_SOC_8910) OR (CONFIG_SOC_8811))
            set(build_target ${target})
            set(pac_config ${out_hex_dir}/${target}.json)
            set(pac_file ${out_hex_dir}/${target}.pac)
            pac_init_fdl(init_fdl ${pac_config})

            execute_process(
                COMMAND python3 ${pacgen_py} ${init_fdl}
                    cfg-image -i UNITTEST -a ${CONFIG_APP_FLASH_ADDRESS} -s ${CONFIG_APP_FLASH_SIZE}
                        -p ${out_hex_dir}/${target}.img ${pac_config}
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
            add_custom_target(${target}_pacgen DEPENDS ${pac_file})
            add_dependencies(unittests ${target}_pacgen)
        endif()
    endif()
    if ((CONFIG_SOC_8955) OR (CONFIG_SOC_8909))
        add_flash_lod(${target} ${SOURCE_TOP_DIR}/components/hal/ldscripts/xcpu_flashrun.ld
            EXCLUDE_FROM_ALL ${ARGN})
        add_dependencies(${target}_ldscript ${BUILD_TARGET}_bcpu sysrom_for_xcpu)
        target_include_directories(${target}_ldscript PRIVATE ${out_hex_dir})
        add_dependencies(unittests ${target})
    endif()
endfunction()

function(add_flash_lod target ldscript)
    set(gen_ldscript ${target}_ldscript)
    set(target_map_file ${out_hex_dir}/${target}.map)
    set(target_hex_file ${out_hex_dir}/${target}.hex)
    set(target_lod_file ${out_hex_dir}/${target}.lod)
    cpp_only(${gen_ldscript} ${ldscript} hal)
    add_executable(${target} ${ARGN})
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${out_hex_dir})
    target_link_libraries(${target} PRIVATE -T $<TARGET_OBJECTS:${gen_ldscript}>)
    target_link_libraries(${target} PRIVATE -Wl,-Map=${target_map_file} -nostdlib -Wl,--gc-sections ${link_cref_option})

    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${cmd_elf2lod} $<TARGET_FILE:${target}> ${target_lod_file}
            --boot --mips
            --param FLSH_MODEL=${CONFIG_FLASH_MODEL}
            --param FLASH_SIZE=${CONFIG_FLASH_SIZE}
            --param RAM_PHY_SIZE=${CONFIG_RAM_SIZE}
            --param CALIB_BASE=${CONFIG_CALIB_FLASH_OFFSET}
            --param FACT_SETTINGS_BASE=${CONFIG_FACTORY_FLASH_OFFSET}
            --param USER_DATA_BASE=${CONFIG_CALIB_FLASH_OFFSET}
            --param USER_DATA_SIZE=0x0
        BYPRODUCTS ${target_lod_file} ${target_map_file}
    )
endfunction()

function(add_elf target ldscript)
    set(gen_ldscript ${target}_ldscript)
    set(target_map_file ${out_hex_dir}/${target}.map)
    cpp_only(${gen_ldscript} ${ldscript} hal)
    add_executable(${target} ${ARGN})
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${out_hex_dir})
    target_link_libraries(${target} PRIVATE -T $<TARGET_OBJECTS:${gen_ldscript}>)
    target_link_libraries(${target} PRIVATE -Wl,-Map=${target_map_file} -nostdlib -Wl,--gc-sections ${link_cref_option})
endfunction()

# Build appimg with specified link script.
function(add_appimg target ldscript) # <sources> LINK_LIBRARIES <libs>
    cmake_parse_arguments(MY "" "" "LINK_LIBRARIES" ${ARGN})
    set(MY_SOURCES ${MY_UNPARSED_ARGUMENTS} ${core_stub_o})
    set(MY_LINK_LIBRARIES ${MY_LINK_LIBRARIES} ${libc_file_name} ${libm_file_name} ${libgcc_file_name})

    set(gen_ldscript ${target}_ldscript)
    set(target_map_file ${out_hex_dir}/${target}.map)
    set(target_img_file ${out_hex_dir}/${target}.img)
    cpp_only(${gen_ldscript} ${ldscript})
    add_executable(${target} ${MY_SOURCES})
    set_source_files_properties(${core_stub_o} PROPERTIES GENERATED on)
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${out_hex_dir})
    target_link_libraries(${target} PRIVATE -T $<TARGET_OBJECTS:${gen_ldscript}>)
    target_link_libraries(${target} PRIVATE -Wl,-Map=${target_map_file} -nostdlib -Wl,--gc-sections ${link_cref_option})
    target_link_libraries(${target} PRIVATE ${MY_LINK_LIBRARIES})

    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${cmd_mkappimg} $<TARGET_FILE:${target}> ${target_img_file}
        BYPRODUCTS ${target_img_file} ${target_map_file}
    )
endfunction()

# Build unittest appimg (linked in flash).
function(add_appimg_unittest target) # <sources> LINK_LIBRARIES <libs>
    cmake_parse_arguments(MY "" "" "LINK_LIBRARIES" ${ARGN})
    set(MY_SOURCES EXCLUDE_FROM_ALL ${MY_UNPARSED_ARGUMENTS})
    set(MY_LINK_LIBRARIES unity ${MY_LINK_LIBRARIES})

    set(ldscript ${SOURCE_TOP_DIR}/components/apploader/pack/app_flashimg.ld)
    add_appimg(${target} ${ldscript} ${MY_SOURCES} LINK_LIBRARIES ${MY_LINK_LIBRARIES})
    add_dependencies(unittests ${target})

    if((CONFIG_SOC_8910) OR (CONFIG_SOC_8811))
        set(pac_config ${out_hex_dir}/${target}.json)
        set(pac_file ${out_hex_dir}/${target}.pac)
        pac_init_fdl(init_fdl ${pac_config})
        execute_process(
            COMMAND python3 ${pacgen_py} ${init_fdl}
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_config}
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
        add_custom_target(${target}_pacgen DEPENDS ${pac_file})
        add_dependencies(unittests ${target}_pacgen)
    endif()
endfunction()

# Build example appimg (linked in flash). Parameters are source files.
function(add_appimg_flash_example target)
    set(ldscript ${SOURCE_TOP_DIR}/components/apploader/pack/app_flashimg.ld)
    add_appimg(${target} ${ldscript} EXCLUDE_FROM_ALL ${ARGN})
    add_dependencies(examples ${target})

    if((CONFIG_SOC_8910) OR (CONFIG_SOC_8811))
        set(pac_config ${out_hex_dir}/${target}.json)
        set(pac_file ${out_hex_dir}/${target}.pac)
        pac_init_fdl(init_fdl ${pac_config})
        execute_process(
            COMMAND python3 ${pacgen_py} ${init_fdl}
                cfg-image -i APPIMG -a ${CONFIG_APPIMG_FLASH_ADDRESS} -s ${CONFIG_APPIMG_FLASH_SIZE}
                    -p ${out_hex_dir}/${target}.img ${pac_config}
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
        add_custom_target(${target}_pacgen DEPENDS ${pac_file})
        add_dependencies(examples ${target}_pacgen)
    endif()
endfunction()

# Build example appimg (linked in file). Parameters are source files.
function(add_appimg_file_example target)
    set(ldscript ${SOURCE_TOP_DIR}/components/apploader/pack/app_fileimg.ld)
    add_appimg(${target} ${ldscript} EXCLUDE_FROM_ALL ${ARGN})
    add_dependencies(examples ${target})

    if((CONFIG_SOC_8910) OR (CONFIG_SOC_8811))
        set(pac_config ${out_hex_dir}/${target}.json)
        set(pac_file ${out_hex_dir}/${target}.pac)
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
        add_custom_target(${target}_pacgen DEPENDS ${pac_file})
        add_dependencies(examples ${target}_pacgen)
    endif()
endfunction()

# Build appimg (flash and file) pac to delete appimg.
function(add_appimg_delete)
    if((CONFIG_SOC_8910) OR (CONFIG_SOC_8811))
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
    endif()
endfunction()

macro(relative_glob var)
    file(GLOB ${var} RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${ARGN})
endmacro()

function(beautify_c_code target)
    if(ARGN)
        set(beautify_target beautify_${target})
        if(NOT TARGET ${beautify_target})
            add_custom_target(${beautify_target})
            add_dependencies(beautify ${beautify_target})
        endif()
        add_custom_command(TARGET ${beautify_target} POST_BUILD
            COMMAND clang-format -i ${ARGN}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
    endif()
endfunction()

function(rpcstubgen xml sender receiver)
    get_filename_component(name ${xml} NAME_WE)
    configure_file(${xml} ${out_rpc_dir}/${name}.xml)
    set(gen ${out_rpc_dir}/${name}_${sender}.c
        ${out_rpc_dir}/${name}_${receiver}.c
        ${out_rpc_dir}/${name}_api.h
        ${out_rpc_dir}/${name}_par.h)
    add_custom_command(
        OUTPUT ${gen}
        COMMAND python3 ${tools_dir}/rpcgen.py stubgen ${xml}
        DEPENDS ${xml} ${tools_dir}/rpcgen.py
        WORKING_DIRECTORY ${out_rpc_dir}
    )
    add_custom_target(${name}_rpcgen DEPENDS ${gen})
    add_dependencies(rpcgen ${name}_rpcgen)
endfunction()

function(rpcdispatchgen cfile side)
    get_filename_component(name ${cfile} NAME_WE)
    set(xmls)
    foreach(xml ${ARGN})
        list(APPEND xmls ${out_rpc_dir}/${xml})
    endforeach()
    add_custom_command(
        OUTPUT ${out_rpc_dir}/${cfile}
        COMMAND python3 ${tools_dir}/rpcgen.py dispatchgen ${cfile} ${side} ${xmls}
        DEPENDS ${tools_dir}/rpcgen.py ${xmls}
        WORKING_DIRECTORY ${out_rpc_dir}
    )
    add_custom_target(${name}_rpcgen DEPENDS ${out_rpc_dir}/${cfile})
    add_dependencies(rpcgen ${name}_rpcgen)
endfunction()

function(nanopbgen)
    foreach(file ${ARGN})
        get_filename_component(name ${file} NAME_WE)
        get_filename_component(fpath ${file} DIRECTORY)
        add_custom_command(
            OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${name}.pb.h ${CMAKE_CURRENT_BINARY_DIR}/${name}.pb.c
            COMMAND protoc --proto_path=${fpath} --nanopb_out=${CMAKE_CURRENT_BINARY_DIR} ${file}
            DEPENDS ${file}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        )
    endforeach(file ${ARGN})
endfunction()

macro(config_nvm_variant_8910 nvmvariant modembin_dir nvmprj)
    set(NVM_VARIANT_${nvmvariant}_MODEMBIN_DIR ${modembin_dir})
    set(NVM_VARIANT_${nvmvariant}_NVMITEM ${nvmprj})
    set(NVM_VARIANT_${nvmvariant}_NVMPRJ ${modembin_dir}/${nvmprj}/nvitem_modem.prj)
endmacro()

function(build_modem_image nvmvariant)
    set(modembin_dir ${NVM_VARIANT_${nvmvariant}_MODEMBIN_DIR})
    set(modemgen_dir ${BINARY_TOP_DIR}/modemgen/${nvmvariant})
    set(modem_img ${out_hex_dir}/${nvmvariant}.img)
    set(nvitem_bin ${out_hex_dir}/${nvmvariant}_nvitem.bin)
    file(GLOB modembins ${modembin_dir}/*.bin)

    add_custom_command(OUTPUT ${modem_img}
        COMMAND python3 ${modemgen_py} --config ${CONFIG_MODEM_CONFIG_JSON_PATH}
            --partinfo ${CONFIG_PARTINFO_JSON_PATH}
            --bindir ${modembin_dir}
            --gendir ${modemgen_dir}
            --nvbin ${nvitem_bin}
            --img ${modem_img}
        DEPENDS ${modemgen_py} ${modembins} ${nvitem_bin}
        WORKING_DIRECTORY ${SOURCE_TOP_DIR}
    )
    add_custom_target(${nvmvariant}_gen ALL DEPENDS ${modem_img})
endfunction()

function(release_lib target)
    add_custom_command(OUTPUT ${out_rel_dir}/${target}.o
        COMMAND ${CMAKE_LINKER} ${partial_link_options} -r --whole-archive
            $<TARGET_FILE:${target}> -o ${out_rel_dir}/${target}.o
        DEPENDS $<TARGET_FILE:${target}>
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )
endfunction()

function(release_lib_with_symbols target symbols)
    add_custom_command(OUTPUT ${out_rel_dir}/${target}.o
        COMMAND ${CMAKE_LINKER} ${partial_link_options} -r --whole-archive
            $<TARGET_FILE:${target}> -o ${target}_rel.o
        COMMAND ${CMAKE_OBJCOPY} --keep-global-symbols=${CMAKE_CURRENT_SOURCE_DIR}/${symbols} ${target}_rel.o ${out_rel_dir}/${target}.o
        DEPENDS $<TARGET_FILE:${target}> ${CMAKE_CURRENT_SOURCE_DIR}/${symbols}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )
endfunction()

function(rom_for_xcpu_gen rom_elf rom_sym_rename rom_sym_global)
    set(rom_for_xcpu_elf ${out_hex_dir}/sysrom_for_xcpu.elf)
    set(rom_for_xcpu_ld ${out_hex_dir}/sysrom_for_xcpu.ld)
    add_custom_command(OUTPUT ${rom_for_xcpu_elf}
        COMMAND ${CMAKE_OBJCOPY} --redefine-syms ${rom_sym_rename}
            --keep-global-symbols ${rom_sym_global}
            ${rom_elf} ${rom_for_xcpu_elf}
        DEPENDS ${rom_elf} ${rom_sym_rename} ${rom_sym_global}
    )
    add_custom_command(OUTPUT ${rom_for_xcpu_ld}
        COMMAND python3 ${elf2incld_py} --cross ${CROSS_COMPILE}
            ${rom_for_xcpu_elf} ${rom_for_xcpu_ld}
        DEPENDS ${elf2incld_py} ${rom_for_xcpu_elf}
    )
    add_custom_target(sysrom_for_xcpu DEPENDS ${rom_for_xcpu_elf} ${rom_for_xcpu_ld})
endfunction()
