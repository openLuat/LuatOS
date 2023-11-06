
/*
@module  lpmem
@summary 操作低功耗不掉电内存块
@version V0002
@date    2020.07.10
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_lpmem.h"

/*
读取内存块
@api    lpmem.read(offset, size)
@int 内存偏移量
@int 读取大小,单位字节
@return string 读取成功返回字符串,否则返回nil
@usage  
-- 读取1kb的内存
local data = lpmem.read(0, 1024)
*/
static int l_lpmem_read(lua_State *L) {
    size_t offset = luaL_checkinteger(L, 1);
    size_t size = luaL_checkinteger(L, 2);
    void* buff = luat_heap_malloc(size);
    int ret = luat_lpmem_read(offset, size, buff);
    if (ret == 0) {
        lua_pushlstring(L, (const char*)buff, size);
    }
    else {
        lua_pushliteral(L, "");
    }
    luat_heap_free(buff);
    return 1;
}

/*
写入内存块
@api    lpmem.write(offset, str)
@int 内存偏移量
@string 待写入的数据
@return boolean 成功返回true,否则返回false
@usage  
-- 往偏移量为512字节的位置, 写入数据
lpmem.write(512, data)
*/
static int l_lpmem_write(lua_State *L) {
    size_t size;
    size_t offset = luaL_checkinteger(L, 1);
    const char* str = luaL_checklstring(L, 2, &size);
    if (size > 0) {
        int ret = luat_lpmem_write(offset, size, (void*)str);
        if (ret == 0) {
            lua_pushboolean(L, 1);
            return 1;
        }
    }
    lua_pushboolean(L, 0);
    return 1;
}

/*
获取内存块的总大小
@api    lpmem.size()
@return int 内存块的大小
@usage  
lpmem.size()
*/
static int l_lpmem_size(lua_State *L) {
    lua_pushinteger(L, luat_lpmem_size());
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_lpmem[] =
{
    { "read" ,         ROREG_FUNC(l_lpmem_read)},
    { "write" ,        ROREG_FUNC(l_lpmem_write)},
    { "size",          ROREG_FUNC(l_lpmem_size)},
	{ NULL,            ROREG_INT(0) }
};

LUAMOD_API int luaopen_lpmem( lua_State *L ) {
    luat_newlib2(L, reg_lpmem);
    return 1;
}
