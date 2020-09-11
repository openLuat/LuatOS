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


set(target lua)
add_library(${target} STATIC)
set_target_properties(${target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY ${out_hex_dir})
target_link_libraries(${target} PRIVATE ${libc_file_name} ${libm_file_name} ${libgcc_file_name})
#target_link_libraries(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../components/lib/libopenat.a)


#设置包含头文
target_include_directories(${target} PUBLIC include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/newlib/include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/openat_inc)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/ril/inc)

target_link_libraries(${target} PRIVATE lua)
file(GLOB SC_FILE src/*.c)
target_sources(${target} PRIVATE ${SC_FILE})


