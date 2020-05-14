/**
 * EC616特有的库, 读写sleep状态下的6k不掉电内存
 */

#include <stdio.h>
#include <string.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

// 0x00001000~0x00002800

static int l_lpmem_read(lua_State *L) {
    size_t offset = luaL_checkinteger(L, 1);
    size_t size = luaL_checkinteger(L, 2);
    if (offset < 0 || size < 0 || offset > 6*1024 || size > 6*1024 || (offset+size) > 6*1024) {
        lua_pushnil(L);
        return 1;
    }
    void* ptr = (void*)(0x00001000 + offset);
    lua_pushlstring(L, (const char*)ptr, size);
    return 1;
}

static int l_lpmem_write(lua_State *L) {
    size_t size;
    size_t offset = luaL_checkinteger(L, 1);
    const char* str = luaL_checklstring(L, 2, &size);
    if (offset < 0 || size < 0 || offset > 6*1024 || size > 6*1024 || (offset+size) > 6*1024) {
        lua_pushnil(L);
        return 1;
    }
    void* ptr = (void*)(0x00001000 + offset);
    memcpy((void*)str, ptr, size);
    lua_pushinteger(L, 1);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_lpmem[] =
{
    { "read" ,         l_lpmem_read , 0},
    { "write" ,        l_lpmem_write, 0},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_lpmem( lua_State *L ) {
    rotable_newlib(L, reg_lpmem);
    return 1;
}
