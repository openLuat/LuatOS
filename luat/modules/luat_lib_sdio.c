
/*
@module  sdio
@summary sdio
@version 1.0
@date    2021.09.02
*/
#include "luat_base.h"
#include "luat_sdio.h"

#define SDIO_COUNT 2
static luat_sdio_t sdio_t[SDIO_COUNT];

/**
初始化sdio
@api sdio.init(id)
@int 通道id,与具体设备有关,通常从0开始
@return boolean 打开结果
 */
static int l_sdio_init(lua_State *L) {
    if (luat_sdio_init(luaL_checkinteger(L, 1)) == 0) {
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

static int l_sdio_read(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int len = luaL_checkinteger(L, 2);
    int offset = luaL_checkinteger(L, 3);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_sdio_sd_read(id, sdio_t[id].rca, recv_buff, offset, len);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}

static int l_sdio_write(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len;
    const char* send_buff;
    send_buff = lua_tolstring(L, 2, &len);
    int offset = luaL_checkinteger(L, 3);
    int ret = luat_sdio_sd_write(id, sdio_t[id].rca, send_buff, offset, len);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}


static int l_sdio_sd_mount(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    sdio_t[id].id=id;
    int auto_format = luaL_checkinteger(L, 2);
    luat_sdio_sd_mount(id, sdio_t[id].rca, auto_format);
    return 0;
}


#include "rotable.h"
static const rotable_Reg reg_sdio[] =
{
    { "init" ,       l_sdio_init , 0},
    { "read" ,       l_sdio_read , 0},
    { "write" ,      l_sdio_write, 0},
    { "mount" ,      l_sdio_sd_mount, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_sdio( lua_State *L ) {
    luat_newlib(L, reg_sdio);
    return 1;
}
