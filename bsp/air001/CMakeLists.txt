cmake_minimum_required (VERSION 3.0)

PROJECT(air001)


INCLUDE_DIRECTORIES(
    "include"
    "../../lua/include"
    "../../luat/include"
    "../../luat/packages/vsprintf"
    "../../luat/packages/lua-cjson"
    "../../luat/packages/minmea"
    "../../luat/packages/u8g2"
    "../../luat/packages/heap"
)

AUX_SOURCE_DIRECTORY(src DIR_SRCS)
AUX_SOURCE_DIRECTORY(impl DIR_SRCS)
AUX_SOURCE_DIRECTORY(../../lua/src LUA_SRCS)
AUX_SOURCE_DIRECTORY(../../luat/modules LUAT_MODULES_SRCS)

AUX_SOURCE_DIRECTORY(../../luat/packages/vsprintf PRINTF_SRCS)
AUX_SOURCE_DIRECTORY(../../luat/packages/lua-cjson CJSON_SRCS)
AUX_SOURCE_DIRECTORY(../../luat/packages/minmea MINMEA_SRCS)
AUX_SOURCE_DIRECTORY(../../luat/packages/u8g2 U8G2_SRCS)
AUX_SOURCE_DIRECTORY(../../luat/packages/heap BGET_SRCS)

add_library(lua SHARED ${LUA_SRCS})
add_library(luatm SHARED ${LUAT_MODULES_SRCS})
add_library(printf SHARED ${PRINTF_SRCS})
add_library(cjson SHARED ${CJSON_SRCS})
add_library(minmea SHARED ${MINMEA_SRCS})
add_library(bget SHARED ${BGET_SRCS})
#add_library(u8g2 SHARED ${U8G2_SRCS})

target_link_libraries(lua m)

target_link_libraries(luatm lua)

#add_executable(air001 ${DIR_SRCS} ${LUA_SRCS} ${LUAT_MODULES_SRCS} ${PRINTF_SRCS} ${CJSON_SRCS} ${MINMEA_SRCS} ${U8G2_SRCS})
add_executable(air001 ${DIR_SRCS})
target_link_libraries(air001 m)
target_link_libraries(air001 lua)
target_link_libraries(air001 luatm)
target_link_libraries(air001 printf)
target_link_libraries(air001 cjson)
target_link_libraries(air001 minmea)
target_link_libraries(air001 bget)

target_link_libraries(air001 pthread)

#set_target_properties(air001 PROPERTIES COMPILE_FLAGS "-m32" LINK_FLAGS "-m32")
