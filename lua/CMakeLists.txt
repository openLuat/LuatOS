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

file(GLOB SC_FILE src/*.c)
target_sources(${target} PRIVATE ${SC_FILE})


