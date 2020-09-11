set(target ril)
add_library(${target} STATIC)
set_target_properties(${target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY ${out_hex_dir})
target_link_libraries(${target} PRIVATE ${libc_file_name} ${libm_file_name} ${libgcc_file_name})
#target_link_libraries(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../components/lib/libopenat.a)


#čŽžç˝ŽĺĺŤĺ¤´ćäť?
target_include_directories(${target} PUBLIC inc)
target_include_directories(${target} PRIVATE ../components/include)
target_include_directories(${target} PRIVATE ../components/newlib/include)
target_include_directories(${target} PRIVATE ../components/openat_inc)

target_sources(${target} PUBLIC
	src/at_process.c
	src/at_tok.c
	src/ril_pal.c
)



