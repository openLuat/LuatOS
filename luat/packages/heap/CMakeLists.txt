target_include_directories(${target} PUBLIC ../../include)
target_include_directories(${target} PUBLIC ../../../lua/include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/newlib/include)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/openat_inc)
target_include_directories(${target} PRIVATE ${PROJECT_ROOT}/components/ril/inc)

file(GLOB SC_FILE *.c)
target_sources(${target} PRIVATE ${SC_FILE})


