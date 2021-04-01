/*
@module  zbuff
@summary 直接指向一块内存区域,提供一系列API操作这块内存
@version 0.1
@date    2021.03.31
*/
#include "luat_base.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "luat.zbuff"
#include "luat_log.h"

#define LUAT_ZBUFF_TYPE "ZBUFF*"

#define tozbuff(L) ((luat_zbuff *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE))

/* Fill memory block */
static void mem_set(void *dst, int val, uint32_t cnt)
{
    uint8_t *d = (uint8_t *)dst;

    do
    {
        *d++ = (uint8_t)val;
    } while (--cnt);
}

/**
创建zbuff
@api zbuff.create()
@int 字节数
@string 可选参数，填充字符串
@return object zbuff对象，如果创建失败会返回nil
@usage
-- 创建zbuff
local buff = zbuff.create(1024) -- 空白的
local buff = zbuff.create(1024, "123321456654") -- 创建，并填充一个已有字符串的内容
 */
static int l_zbuff_create(lua_State *L)
{

    int len = luaL_checkinteger(L, 1);
    if (len <= 0)
    {
        return 0;
    }

    luat_zbuff *buff = (luat_zbuff *)lua_newuserdata(L, sizeof(luat_zbuff));

    if (buff == NULL)
    {
        return 0;
    }
    buff->addr = (uint8_t *)luat_heap_malloc(len);
    if (buff->addr == NULL)
    {
        return 0;
    }

    mem_set(buff->addr, 0, len);
    buff->len = len;
    buff->cursor = 0;

    if (lua_isstring(L, 2))
    {
        char *data = luaL_optlstring(L, 2, "", &len);

        memcpy(buff->addr, data, len);

        buff->cursor = len;
    }

    luaL_setmetatable(L, LUAT_ZBUFF_TYPE);
    return 1;
}

/**
zbuff写数据
@api buff:write()
@string 写入buff的数据
@return boolean 写入结果，成功返回true，失败返回false
@usage
-- 类file的读写操作
buff:write("123") -- 写入数据, 指针相应地往后移动
 */
static int l_zbuff_write(lua_State *L)
{
    int len;
    char *data = luaL_checklstring(L, 2, &len);
    luat_zbuff *buff = tozbuff(L);
    if (buff == NULL)
    {
        lua_pushboolean(L, 0);
        return 1;
    }

    memcpy(&(buff->addr[buff->cursor]), data, len);

    buff->cursor = buff->cursor + len;

    lua_pushboolean(L, 1);
    return 1;
}

/**
zbuff读数据
@api buff:read()
@int 读取buff中的字节数
@return string 读取结果
@usage
-- 类file的读写操作
local str = buff:read(3)
 */
static int l_zbuff_read(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);

    int read_num = luaL_optinteger(L, 2, 0);
    char *return_str = (char *)luat_heap_malloc(read_num);
    memcpy(return_str, &(buff->addr[buff->cursor]), read_num);
    lua_pushlstring(L, return_str, read_num);
    buff->cursor = buff->cursor + read_num;
    return 1;
}

/**
zbuff设置光标位置
@api buff:seek()
@int whence, 基点，基点可以是"zbuff.SEEK_SET": 基点为 0 （文件开头）；"zbuff.SEEK_CUR": 基点为当前位置；"zbuff.SEEK_END": 基点为文件尾；
@return int 设置光标后从buff开头计算起的光标的位置
@usage
buff:seek(zbuff.SEEK_SET, 0) -- 把光标设置到指定位置
 */
static int l_zbuff_seek(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);

    int whence = luaL_optinteger(L, 2, 0);
    int offset = luaL_optinteger(L, 3, 0);
    switch (whence)
    {
    case 0:
        buff->cursor = 0 + offset;
        break;
    case 1:
        buff->cursor = buff->cursor + offset;
        break;
    case 2:
        buff->cursor = buff->len + offset;
        break;
    default:
        return 0;
    }
    lua_pushinteger(L, buff->cursor);
    return 1;
}

// __gc
static int l_zbuff_gc(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);
    luat_heap_free(buff->addr);
    LLOGD("GC");
    return 0;
}

static const luaL_Reg lib_zbuff[] = {
    {"write", l_zbuff_write},
    {"read", l_zbuff_read},
    {"seek", l_zbuff_seek},
    {"__gc", l_zbuff_gc},
    {NULL, NULL}};

static void createmeta(lua_State *L)
{
    luaL_newmetatable(L, LUAT_ZBUFF_TYPE); /* create metatable for file handles */
    lua_pushvalue(L, -1);                  /* push metatable */
    lua_setfield(L, -2, "__index");        /* metatable.__index = metatable */
    luaL_setfuncs(L, lib_zbuff, 0);        /* add file methods to new metatable */
    lua_pop(L, 1);                         /* pop new metatable */
}

#include "rotable.h"
static const rotable_Reg reg_zbuff[] =
    {
        {"create", l_zbuff_create, 0},
        {"SEEK_SET", NULL, 0},
        {"SEEK_CUR", NULL, 1},
        {"SEEK_END", NULL, 2},
        {NULL, NULL, 0}};

LUAMOD_API int luaopen_zbuff(lua_State *L)
{
    rotable_newlib(L, reg_zbuff);
    createmeta(L);
    return 1;
}
