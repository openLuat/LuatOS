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

# Configures CMake for using GCC

set(CMAKE_SYSTEM_NAME           Generic)
find_program(CMAKE_C_COMPILER   ${CROSS_COMPILE}gcc)
find_program(CMAKE_CXX_COMPILER ${CROSS_COMPILE}g++)
find_program(CMAKE_READELF      ${CROSS_COMPILE}readelf)

set(CMAKE_EXECUTABLE_SUFFIX_ASM .elf)
set(CMAKE_EXECUTABLE_SUFFIX_C .elf)
set(CMAKE_EXECUTABLE_SUFFIX_CXX .elf)

if(CONFIG_CPU_ARM_CA5)
    set(abi_options -mcpu=cortex-a5 -mtune=generic-armv7-a -mthumb -mfpu=neon-vfpv4
        -mfloat-abi=hard -mno-unaligned-access)
    set(partial_link_options)
    set(libc_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/armca5/libc.a)
    set(libm_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/armca5/libm.a)
endif()

if(CONFIG_CPU_ARM_CM4F)
    set(abi_options -mcpu=cortex-m4 -mtune=cortex-m4 -mthumb -mfpu=fpv4-sp-d16
        -mfloat-abi=hard -mno-unaligned-access)
    set(partial_link_options)
    set(libc_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/armcm4f/libc.a)
    set(libm_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/armcm4f/libm.a)
endif()

if(CONFIG_CPU_MIPS_XCPU)
    set(abi_options -march=xcpu -mtune=xcpu -EL -mips16 -msoft-float -mno-gpopt -G0
        -mdisable-save-restore)
    set(partial_link_options -EL)
    set(libc_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/xcpu/libc.a)
    set(libm_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/xcpu/libm.a)
endif()

if(CONFIG_CPU_MIPS_XCPU2)
    set(abi_options -march=xcpu2 -mtune=xcpu2 -EL -mips16 -msoft-float -mno-gpopt -G0)
    set(partial_link_options -EL)
    set(libc_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/xcpu2/libc.a)
    set(libm_file_name ${CMAKE_CURRENT_SOURCE_DIR}/components/newlib/xcpu2/libm.a)
endif()

function(add_subdirectory_if_exist dir)
    if(IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${dir})
        if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${dir}/CMakeLists.txt)
            add_subdirectory(${dir})
		endif()
    endif()
endfunction()

add_compile_options(${abi_options} -g -Os
    -Wall
    -fno-strict-aliasing
    -ffunction-sections -fdata-sections
)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11 -fno-exceptions -fno-rtti -fno-threadsafe-statics")

# GNU ar will alreay create index
set(CMAKE_C_ARCHIVE_FINISH "")
set(CMAKE_CXX_ARCHIVE_FINISH "")

if(WITH_WERROR)
    add_compile_options(-Werror)
endif()

if(WITH_LINK_CREF)
    set(link_cref_option -Wl,-cref)
endif()

execute_process(COMMAND ${CMAKE_C_COMPILER} ${abi_options} --print-file-name libgcc.a
    OUTPUT_VARIABLE libgcc_file_name
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
