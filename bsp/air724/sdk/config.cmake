
#/*+\NEW\chenzhimin\2020.07.21\ elua工程专用*/
if(CONFIG_BUILD_LUA)
    set(CONFIG_LUA_FLASH_OFFSET 0x2D8000)
    set(CONFIG_LUA_FLASH_SIZE 0x68000)
else()
    set(CONFIG_BUILD_LUA OFF)
endif(CONFIG_BUILD_LUA)

message("BUILD_LUA:" ${CONFIG_BUILD_LUA})
#/*-\NEW\chenzhimin\2020.07.21\ elua工程专用*/

